//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GCTestCase.h"
#import "GCCommitSigningTestHelpers.h"
#import "GCRepository+Index.h"

static BOOL _WriteLocalConfigOption(GCRepository* repository, NSString* variable, NSString* value) {
  return [repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:variable withValue:value error:NULL];
}

static BOOL _WriteExecutable(NSString* path, NSString* contents) {
  if (![contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
    return NO;
  }
  return [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @(0755)} ofItemAtPath:path error:NULL];
}

static NSString* _CreateFakeSSHSigner(NSString* directory, int exitStatus) {
  NSString* path = [directory stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString* contents;

  if (exitStatus == 0) {
    NSArray* lines = @[
      @"#!/bin/sh",
      @"cat >/dev/null",
      @"printf '%s\\n' '-----BEGIN SSH SIGNATURE-----' 'fake-signature' '-----END SSH SIGNATURE-----'",
      @""
    ];
    contents = [lines componentsJoinedByString:@"\n"];
  } else {
    NSArray* lines = @[
      @"#!/bin/sh",
      @"cat >/dev/null",
      @"echo signer failed >&2",
      [NSString stringWithFormat:@"exit %i", exitStatus],
      @""
    ];
    contents = [lines componentsJoinedByString:@"\n"];
  }

  return _WriteExecutable(path, contents) ? path : nil;
}

static GCCommit* _CreateCommitFromRepositoryIndex(GCRepository* repository, NSString* message, NSError** error) {
  GCCommit* commit = nil;
  git_index* index = NULL;
  git_tree* tree = NULL;

  index = [repository reloadRepositoryIndex:error];
  if (!index) {
    goto cleanup;
  }

  git_oid oid;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_write_tree_to, &oid, index, repository.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_tree_lookup, &tree, repository.private, &oid);
  commit = GCCreateCommitFromTreeWithOptionalSignature(repository,
                                                       tree,
                                                       NULL,
                                                       0,
                                                       NULL,
                                                       message,
                                                       error);

cleanup:
  git_tree_free(tree);
  git_index_free(index);
  return commit;
}

@implementation GCEmptyRepositoryTests (GCCommitSigning)

- (void)testCommitSigningLeavesCommitsUnsignedWhenDisabledOrUnsupported {
  [self updateFileAtPath:@"unsigned.txt" withString:@"unsigned\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"unsigned.txt" error:NULL]);

  GCCommit* unsignedCommit = _CreateCommitFromRepositoryIndex(self.repository, @"Unsigned", NULL);
  XCTAssertNotNil(unsignedCommit);
  XCTAssertNil(GCCommitSignature(unsignedCommit));

  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"commit.gpgsign", @"true"));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.format", @"openpgp"));
  [self updateFileAtPath:@"openpgp.txt" withString:@"openpgp\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"openpgp.txt" error:NULL]);

  GCCommit* openPGPCommit = _CreateCommitFromRepositoryIndex(self.repository, @"OpenPGP config remains unsigned", NULL);
  XCTAssertNotNil(openPGPCommit);
  XCTAssertNil(GCCommitSignature(openPGPCommit));
}

- (void)testCommitSigningRequiresSSHKey {
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"commit.gpgsign", @"true"));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.format", @"ssh"));
  [self updateFileAtPath:@"missing-key.txt" withString:@"missing key\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"missing-key.txt" error:NULL]);

  NSError* error;
  XCTAssertNil(_CreateCommitFromRepositoryIndex(self.repository, @"Missing key", &error));
  XCTAssertTrue([error.localizedDescription containsString:@"user.signingkey"]);
}

- (void)testCommitSigningRefreshesPATHOncePerOperation {
  NSString* firstDirectory = [self.temporaryPath stringByAppendingPathComponent:@"first"];
  NSString* secondDirectory = [self.temporaryPath stringByAppendingPathComponent:@"second"];
  NSString* pathOutput = [self.temporaryPath stringByAppendingPathComponent:@"signing-path"];
  NSString* pathLookups = [self.temporaryPath stringByAppendingPathComponent:@"path-lookups"];
  NSString* shell = [self.temporaryPath stringByAppendingPathComponent:@"path-shell"];
  NSString* program = @"test-ssh-signer";
  NSString* defaultKeyCommand = @"test-default-key";

  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:firstDirectory withIntermediateDirectories:NO attributes:nil error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:secondDirectory withIntermediateDirectories:NO attributes:nil error:NULL]);

  NSString* shellContents = [NSString stringWithFormat:@"#!/bin/sh\nprintf x >> '%@'\n/bin/cat '%@'\n", pathLookups, pathOutput];
  XCTAssertTrue(_WriteExecutable(shell, shellContents));

  for (NSString* directory in @[ firstDirectory, secondDirectory ]) {
    NSString* marker = [directory isEqualToString:firstDirectory] ? @"first-signature" : @"second-signature";
    NSString* signerContents = [NSString stringWithFormat:@"#!/bin/sh\n/bin/cat >/dev/null\nprintf '%%s\\n' '-----BEGIN SSH SIGNATURE-----' '%@' '-----END SSH SIGNATURE-----'\n", marker];
    XCTAssertTrue(_WriteExecutable([directory stringByAppendingPathComponent:program], signerContents));
    XCTAssertTrue(_WriteExecutable([directory stringByAppendingPathComponent:defaultKeyCommand],
                                   @"#!/bin/sh\nprintf 'key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPathRefreshKey test@example.com\\n'\n"));
  }

  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"commit.gpgsign", @"true"));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.format", @"ssh"));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.ssh.program", program));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.ssh.defaultKeyCommand", defaultKeyCommand));

  const char* previousShellValue = getenv("SHELL");
  NSString* previousShell = previousShellValue ? [NSString stringWithUTF8String:previousShellValue] : nil;
  setenv("SHELL", shell.fileSystemRepresentation, 1);
  @try {
    XCTAssertTrue([[firstDirectory stringByAppendingString:@"\n"] writeToFile:pathOutput atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    [self updateFileAtPath:@"first-path.txt" withString:@"first path\n"];
    XCTAssertTrue([self.repository addFileToIndex:@"first-path.txt" error:NULL]);
    GCCommit* firstCommit = _CreateCommitFromRepositoryIndex(self.repository, @"First PATH", NULL);
    XCTAssertNotNil(firstCommit);
    XCTAssertTrue([GCCommitSignature(firstCommit) containsString:@"first-signature"]);
    XCTAssertEqual([[NSString stringWithContentsOfFile:pathLookups encoding:NSUTF8StringEncoding error:NULL] length], 1);

    XCTAssertTrue([[secondDirectory stringByAppendingString:@"\n"] writeToFile:pathOutput atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    [self updateFileAtPath:@"second-path.txt" withString:@"second path\n"];
    XCTAssertTrue([self.repository addFileToIndex:@"second-path.txt" error:NULL]);
    GCCommit* secondCommit = _CreateCommitFromRepositoryIndex(self.repository, @"Second PATH", NULL);
    XCTAssertNotNil(secondCommit);
    XCTAssertTrue([GCCommitSignature(secondCommit) containsString:@"second-signature"]);
    XCTAssertEqual([[NSString stringWithContentsOfFile:pathLookups encoding:NSUTF8StringEncoding error:NULL] length], 2);
  } @finally {
    if (previousShell) {
      setenv("SHELL", previousShell.fileSystemRepresentation, 1);
    } else {
      unsetenv("SHELL");
    }
  }
}

- (void)testCommitSigningSupportsInlineKeyAndDefaultKeyCommand {
  NSString* signer = _CreateFakeSSHSigner(self.temporaryPath, 0);
  NSString* inlineKey = @"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeInlineKey test@example.com";
  NSString* defaultKeyCommand = @"printf 'key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDefaultCommandKey test@example.com\\n'";

  XCTAssertNotNil(signer);
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"commit.gpgsign", @"true"));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.format", @"ssh"));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.ssh.program", signer));

  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"user.signingkey", inlineKey));
  [self updateFileAtPath:@"inline-key.txt" withString:@"inline key\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"inline-key.txt" error:NULL]);

  GCCommit* inlineCommit = _CreateCommitFromRepositoryIndex(self.repository, @"Inline key", NULL);
  XCTAssertNotNil(inlineCommit);
  XCTAssertTrue(GCCommitHasSSHSignature(inlineCommit));

  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"user.signingkey", nil));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.ssh.defaultKeyCommand", defaultKeyCommand));
  [self updateFileAtPath:@"default-key-command.txt" withString:@"default key command\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"default-key-command.txt" error:NULL]);

  GCCommit* defaultCommandCommit = _CreateCommitFromRepositoryIndex(self.repository, @"Default key command", NULL);
  XCTAssertNotNil(defaultCommandCommit);
  XCTAssertTrue(GCCommitHasSSHSignature(defaultCommandCommit));
}

- (void)testCommitSigningSupportsKeyPath {
  NSString* keyPath = [self.temporaryPath stringByAppendingPathComponent:@"signing_key"];
  GCTask* keygen = [[GCTask alloc] initWithExecutablePath:@"/usr/bin/ssh-keygen"];
  int status;
  NSArray* keygenArguments = @[ @"-t", @"ed25519", @"-f", keyPath, @"-N", @"", @"-q" ];
  BOOL keygenSuccess = [keygen runWithArguments:keygenArguments stdin:nil stdout:NULL stderr:NULL exitStatus:&status error:NULL];
  XCTAssertTrue(keygenSuccess);
  XCTAssertEqual(status, 0);
  XCTAssertTrue(GCConfigureSSHSigningWithKeyPath(self.repository, keyPath));

  [self updateFileAtPath:@"path-key.txt" withString:@"path key\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"path-key.txt" error:NULL]);

  GCCommit* commit = _CreateCommitFromRepositoryIndex(self.repository, @"Path key", NULL);
  XCTAssertNotNil(commit);
  XCTAssertTrue(GCCommitHasSSHSignature(commit));

  NSString* publicKey = [NSString stringWithContentsOfFile:[keyPath stringByAppendingString:@".pub"] encoding:NSUTF8StringEncoding error:NULL];
  NSString* allowedSignersPath = [self.temporaryPath stringByAppendingPathComponent:@"allowed_signers"];
  NSString* allowedSigners = [NSString stringWithFormat:@"bot@example.com %@", publicKey];
  XCTAssertTrue([allowedSigners writeToFile:allowedSignersPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

  NSString* allowedSignersConfig = [NSString stringWithFormat:@"gpg.ssh.allowedSignersFile=%@", allowedSignersPath];
  NSString* verifyOutput = [self runGitCLTWithRepository:self.repository command:@"-c", allowedSignersConfig, @"verify-commit", commit.SHA1, nil];
  XCTAssertNotNil(verifyOutput);
}

- (void)testCommitSigningFailsOnSignerFailure {
  NSString* signer = _CreateFakeSSHSigner(self.temporaryPath, 7);
  NSString* signingKey = @"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFailingSignerKey test@example.com";

  XCTAssertNotNil(signer);
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"commit.gpgsign", @"true"));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.format", @"ssh"));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"gpg.ssh.program", signer));
  XCTAssertTrue(_WriteLocalConfigOption(self.repository, @"user.signingkey", signingKey));
  [self updateFileAtPath:@"failing-signer.txt" withString:@"failing signer\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"failing-signer.txt" error:NULL]);

  NSError* error;
  XCTAssertNil(_CreateCommitFromRepositoryIndex(self.repository, @"Failing signer", &error));
  XCTAssertTrue([error.localizedDescription containsString:@"non-zero status"]);
}

@end
