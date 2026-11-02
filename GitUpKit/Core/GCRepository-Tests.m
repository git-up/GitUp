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

@implementation GCTests (GCRepository)

- (void)testPrecompose {
  NSString* string = @"héllo Wôrld";
  const char* composed = "héllo Wôrld";
  const char* decomposed = "héllo Wôrld";
  XCTAssertNotEqual(strcmp(composed, decomposed), 0);
  XCTAssertEqual(strcmp(string.UTF8String, composed), 0);
  XCTAssertEqual(strcmp(string.fileSystemRepresentation, decomposed), 0);
}

- (void)testOpen {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];

  // Create repository
  NSString* output = [self runGitCLTWithRepository:nil command:@"init", path, nil];
  XCTAssertNotNil(output);

  // Open repository
  GCRepository* repo1 = [[GCRepository alloc] initWithExistingLocalRepository:path error:NULL];
  XCTAssertNotNil(repo1);
  XCTAssertFalse(repo1.readOnly);
  repo1 = nil;

  // Test read-only
  XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @(0500)} ofItemAtPath:[path stringByAppendingPathComponent:@".git"] error:NULL]);
  GCRepository* repo2 = [[GCRepository alloc] initWithExistingLocalRepository:path error:NULL];
  XCTAssertNotNil(repo2);
  XCTAssertTrue(repo2.readOnly);
  repo2 = nil;
  XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @(0700)} ofItemAtPath:[path stringByAppendingPathComponent:@".git"] error:NULL]);

  // Destroy repository
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
}

- (void)testRepositoryURLContainingURL {
  NSString* parentPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:parentPath withIntermediateDirectories:NO attributes:nil error:NULL]);

  NSString* repositoryPath = [parentPath stringByAppendingPathComponent:@"repository"];
  GCRepository* repository = [self createLocalRepositoryAtPath:repositoryPath bare:NO];
  NSURL* expectedURL = [NSURL fileURLWithPath:repository.workingDirectoryPath];

  NSError* error = nil;
  NSURL* sameDirectoryURL = [GCRepository repositoryURLContainingURL:expectedURL error:&error];
  XCTAssertEqualObjects(sameDirectoryURL.path.stringByStandardizingPath, expectedURL.path.stringByStandardizingPath);
  XCTAssertNil(error);

  NSString* subdirectoryPath = [repository.workingDirectoryPath stringByAppendingPathComponent:@"subdirectory"];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:subdirectoryPath withIntermediateDirectories:NO attributes:nil error:NULL]);
  error = nil;
  NSURL* subdirectoryURL = [GCRepository repositoryURLContainingURL:[NSURL fileURLWithPath:subdirectoryPath] error:&error];
  XCTAssertEqualObjects(subdirectoryURL.path.stringByStandardizingPath, expectedURL.path.stringByStandardizingPath);
  XCTAssertNil(error);

  error = nil;
  XCTAssertNil([GCRepository repositoryURLContainingURL:[NSURL fileURLWithPath:parentPath] error:&error]);
  XCTAssertEqual(error.code, kGCErrorCode_NotFound);

  [self destroyLocalRepository:repository];
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:parentPath error:NULL]);
}

@end

@implementation GCEmptyRepositoryTests (GCRepository)

// -initWithNewLocalRepository:bare:error: is called in -setUp
- (void)testInitialization {
  // Check initialization result
  NSString* result = [self runGitCLTWithRepository:self.repository command:@"status", nil];
  XCTAssertTrue([result hasPrefix:@"On branch master"]);
  XCTAssertTrue([result containsString:@"Initial commit"] || [result containsString:@"No commits yet"]);

  // Check properties
  XCTAssertEqualObjects([self.repository.repositoryPath stringByStandardizingPath], [self.temporaryPath stringByAppendingPathComponent:@".git"]);
  XCTAssertEqualObjects([self.repository.workingDirectoryPath stringByStandardizingPath], self.temporaryPath);
  XCTAssertFalse(self.repository.bare);
  XCTAssertTrue(self.repository.empty);
  XCTAssertEqual(self.repository.state, kGCRepositoryState_None);

  // Test re-initializing
  XCTAssertFalse([[GCRepository alloc] initWithNewLocalRepository:self.repository.workingDirectoryPath bare:NO error:NULL]);
}

- (void)testPathForHookWithName {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];

  // Create dummy local repo
  GCRepository* repository = [self createLocalRepositoryAtPath:path bare:NO];

  NSString* hookName = @"pre-commit";
  XCTAssertEqualObjects([repository pathForHookWithName:hookName], NULL);

  // Create dummy hook file
  NSString* hookFilePath = [[repository.repositoryPath stringByAppendingPathComponent:@"hooks"] stringByAppendingPathComponent:hookName];
  [self _createDummyHookFile:hookFilePath];

  XCTAssertEqualObjects([repository pathForHookWithName:hookName], hookFilePath);

  // Destroy dummy local repository
  [self destroyLocalRepository:repository];
}

- (void)testPathForHookWithName_AbsoluteCustomHooksPath {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];

  // Create dummy local repo
  GCRepository* repository = [self createLocalRepositoryAtPath:path bare:NO];

  // Set absolute path to core.hooksPath
  NSString* hooksPath = [path stringByAppendingPathComponent:@"custom-hooks-path"];
  XCTAssertTrue([repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"core.hooksPath" withValue:hooksPath error:NULL]);

  NSString* hookName = @"pre-commit";
  XCTAssertEqualObjects([repository pathForHookWithName:hookName], NULL);

  // Create dummy hook file
  NSString* hookFilePath = [hooksPath stringByAppendingPathComponent:hookName];
  [self _createDummyHookFile:hookFilePath];

  XCTAssertEqualObjects([repository pathForHookWithName:hookName], hookFilePath);

  // Destroy dummy local repository
  [self destroyLocalRepository:repository];
}

- (void)testPathForHookWithName_RelativeCustomHooksPath {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];

  // Create dummy local repo
  GCRepository* repository = [self createLocalRepositoryAtPath:path bare:NO];

  // Set relative path to core.hooksPath
  NSString* hooksPath = @"./custom-hooks-path";
  XCTAssertTrue([repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"core.hooksPath" withValue:hooksPath error:NULL]);

  NSString* hookName = @"pre-commit";
  XCTAssertEqualObjects([repository pathForHookWithName:hookName], NULL);

  // Create dummy hook file
  NSString* hookFilePath = [[repository.workingDirectoryPath stringByAppendingPathComponent:hooksPath] stringByAppendingPathComponent:hookName];
  [self _createDummyHookFile:hookFilePath];

  XCTAssertEqualObjects([repository pathForHookWithName:hookName], hookFilePath);

  // Destroy dummy local repository
  [self destroyLocalRepository:repository];
}

- (void)_createDummyHookFile:(NSString*)path {
  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                            withIntermediateDirectories:NO
                                             attributes:NULL
                                                  error:NULL];
  [[NSFileManager defaultManager] createFileAtPath:path
                                          contents:[@"echo 'Hello world'\n" dataUsingEncoding:NSUTF8StringEncoding]
                                        attributes:@{NSFilePosixPermissions : @0x755}];
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path]);
}

@end

@implementation GCSingleCommitRepositoryTests (GCRepository)

- (void)testClone {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];

  // Clone repo using HTTPS
  GCRepository* repo1 = [[GCRepository alloc] initWithClonedRepositoryFromURL:GCURLFromGitURL(@"https://github.com/git-up/test-repo-base.git") toPath:path usingDelegate:nil recursive:NO error:NULL];
  XCTAssertNotNil(repo1);
  XCTAssertFalse(repo1.empty);
  repo1 = nil;
  XCTAssert([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);

  // Clone repo using SSH (scp-like syntax)
  if (!self.botMode) {
    GCRepository* repo2 = [[GCRepository alloc] initWithClonedRepositoryFromURL:GCURLFromGitURL(@"git@github.com:git-up/test-repo-base.git") toPath:path usingDelegate:nil recursive:NO error:NULL];
    XCTAssertNotNil(repo2);
    XCTAssertFalse(repo2.empty);
    repo2 = nil;
    XCTAssert([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
  }

  // Clone repo using local path
  GCRepository* repo3 = [[GCRepository alloc] initWithClonedRepositoryFromURL:[NSURL fileURLWithPath:self.repository.workingDirectoryPath] toPath:path usingDelegate:nil recursive:NO error:NULL];
  XCTAssertNotNil(repo3);
  XCTAssertFalse(repo3.empty);
  repo3 = nil;
  XCTAssert([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);

  // Clone repo with submodules not recursively
  GCRepository* repo4 = [[GCRepository alloc] initWithClonedRepositoryFromURL:GCURLFromGitURL(@"https://github.com/git-up/test-repo-submodules.git") toPath:path usingDelegate:nil recursive:NO error:NULL];
  XCTAssertNotNil(repo4);
  XCTAssertFalse(repo4.empty);
  NSArray* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[path stringByAppendingPathComponent:@"base"] error:NULL];
  XCTAssertEqualObjects(contents, @[]);  // Submodule directory should be empty
  repo4 = nil;
  XCTAssert([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);

  // Clone repo with recursive submodules recursively
  GCRepository* repo5 = [[GCRepository alloc] initWithClonedRepositoryFromURL:GCURLFromGitURL(@"https://github.com/git-up/test-repo-recursive-submodules.git") toPath:path usingDelegate:nil recursive:YES error:NULL];
  XCTAssertNotNil(repo5);
  XCTAssertFalse(repo5.empty);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:@"rebase/.git"] isDirectory:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:@"rebase/base/.git"] isDirectory:NULL]);
  repo5 = nil;
  XCTAssert([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
}

@end

@implementation GCMultipleCommitsRepositoryTests (GCRepository)

- (void)testState {
  // Check initial state
  XCTAssertEqual(self.repository.state, kGCRepositoryState_None);

  // Merge topic branch and check state
  XCTAssertTrue([self.repository mergeCommitToHEAD:self.commitA error:NULL]);
  XCTAssertEqual(self.repository.state, kGCRepositoryState_Merge);

  // Reset state
  XCTAssertTrue([self.repository cleanupState:NULL]);
  XCTAssertEqual(self.repository.state, kGCRepositoryState_None);
}

// Regression test for issue #1053: hooks are shared from the repository's common
// directory, so they must be discoverable from a linked worktree. Previously
// -pathForHookWithName: looked up the default hooks directory in the per-worktree
// git directory, which never contains a hooks directory, so hooks were silently
// unavailable in worktrees.
- (void)testPathForHookWithName_FoundFromLinkedWorktree {
  // Create a linked worktree checked out on the topic branch.
  NSString* worktreePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString* output = [self runGitCLTWithRepository:self.repository command:@"worktree", @"add", worktreePath, @"topic", nil];
  XCTAssertNotNil(output);  // nil means git exited non-zero, i.e. the worktree wasn't created

  // Open the linked worktree as its own repository.
  GCRepository* worktreeRepository = [[GCRepository alloc] initWithExistingLocalRepository:worktreePath error:NULL];
  XCTAssertNotNil(worktreeRepository);

  NSString* hookName = @"pre-commit";

  // A linked worktree's git directory is separate from the common directory and
  // must not contain the hook.
  NSString* worktreeHookPath = [[worktreeRepository.repositoryPath stringByAppendingPathComponent:@"hooks"] stringByAppendingPathComponent:hookName];
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:worktreeHookPath]);

  // Install the hook in the main repository's common hooks directory, which is
  // shared with all linked worktrees.
  NSString* commonHookPath = [[self.repository.repositoryPath stringByAppendingPathComponent:@"hooks"] stringByAppendingPathComponent:hookName];
  [[NSFileManager defaultManager] createDirectoryAtPath:[commonHookPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:NULL error:NULL];
  XCTAssertTrue([[NSFileManager defaultManager] createFileAtPath:commonHookPath
                                                        contents:[@"#!/bin/sh\nexit 0\n" dataUsingEncoding:NSUTF8StringEncoding]
                                                      attributes:@{NSFilePosixPermissions : @0o755}]);

  // The worktree must resolve the hook from the shared common directory.
  XCTAssertEqualObjects([worktreeRepository pathForHookWithName:hookName], commonHookPath);

  worktreeRepository = nil;
  [[NSFileManager defaultManager] removeItemAtPath:worktreePath error:NULL];
}

// The git-lfs tool used to be expected at /usr/local/bin/git-lfs only, so LFS files were
// silently left unfiltered when it was installed elsewhere e.g. /opt/homebrew/bin (issue #805).
- (void)testFindExecutableInPATH {
  NSFileManager* fileManager = [NSFileManager defaultManager];
  NSString* root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString* emptyDirectory = [root stringByAppendingPathComponent:@"empty"];
  NSString* firstDirectory = [root stringByAppendingPathComponent:@"first"];
  NSString* secondDirectory = [root stringByAppendingPathComponent:@"second"];
  NSString* fallbackDirectory = [root stringByAppendingPathComponent:@"fallback"];
  for (NSString* directory in @[ emptyDirectory, firstDirectory, secondDirectory, fallbackDirectory ]) {
    XCTAssertTrue([fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]);
  }
  NSData* script = [@"#!/bin/sh\nexit 0\n" dataUsingEncoding:NSUTF8StringEncoding];
  NSString* firstPath = [firstDirectory stringByAppendingPathComponent:@"git-lfs"];
  NSString* secondPath = [secondDirectory stringByAppendingPathComponent:@"git-lfs"];
  NSString* fallbackPath = [fallbackDirectory stringByAppendingPathComponent:@"git-lfs"];
  XCTAssertTrue([fileManager createFileAtPath:secondPath contents:script attributes:@{NSFilePosixPermissions : @0o755}]);
  XCTAssertTrue([fileManager createFileAtPath:fallbackPath contents:script attributes:@{NSFilePosixPermissions : @0o755}]);

  // Found in PATH, skipping empty components and directories without the tool
  NSString* PATH = [NSString stringWithFormat:@"::%@:%@:%@", emptyDirectory, firstDirectory, secondDirectory];
  XCTAssertEqualObjects(GCFindExecutableInPATH(@"git-lfs", PATH, @[ fallbackDirectory ]), secondPath);

  // PATH order wins over later PATH entries and fallbacks
  XCTAssertTrue([fileManager createFileAtPath:firstPath contents:script attributes:@{NSFilePosixPermissions : @0o755}]);
  XCTAssertEqualObjects(GCFindExecutableInPATH(@"git-lfs", PATH, @[ fallbackDirectory ]), firstPath);

  // Non-executable files are ignored
  XCTAssertTrue([fileManager setAttributes:@{NSFilePosixPermissions : @0o644} ofItemAtPath:firstPath error:NULL]);
  XCTAssertEqualObjects(GCFindExecutableInPATH(@"git-lfs", PATH, @[ fallbackDirectory ]), secondPath);

  // Falls back to the extra directories when not in PATH, or when PATH couldn't be determined
  XCTAssertEqualObjects(GCFindExecutableInPATH(@"git-lfs", emptyDirectory, @[ fallbackDirectory ]), fallbackPath);
  XCTAssertEqualObjects(GCFindExecutableInPATH(@"git-lfs", nil, @[ fallbackDirectory ]), fallbackPath);

  // Not found anywhere
  XCTAssertNil(GCFindExecutableInPATH(@"git-lfs", emptyDirectory, @[]));
  XCTAssertNil(GCFindExecutableInPATH(@"git-lfs", nil, @[ emptyDirectory ]));

  // Directories with the tool's name are ignored
  XCTAssertTrue([fileManager createDirectoryAtPath:[emptyDirectory stringByAppendingPathComponent:@"git-lfs"] withIntermediateDirectories:NO attributes:nil error:NULL]);
  XCTAssertEqualObjects(GCFindExecutableInPATH(@"git-lfs", emptyDirectory, @[ fallbackDirectory ]), fallbackPath);

  XCTAssertTrue([fileManager removeItemAtPath:root error:NULL]);
}

// Smoke test with the real git-lfs tool
- (void)testGitLFSCleanFilter {
  NSString* shell = NSProcessInfo.processInfo.environment[@"SHELL"] ?: @"/bin/sh";
  NSString* PATH = [self.repository getPATHUsingShell:shell error:NULL];
  if (!GCFindExecutableInPATH(@"git-lfs", PATH, GCDefaultExecutableDirectories())) {
    XCTSkip(@"git-lfs is not installed");
  }

  [self updateFileAtPath:@".gitattributes" withString:@"*.bin filter=lfs diff=lfs merge=lfs -text\n"];
  [self updateFileAtPath:@"large.bin" withString:@"Hello LFS\n"];

  GCIndex* index = [self.repository readRepositoryIndex:NULL];
  XCTAssertNotNil(index);
  XCTAssertTrue([self.repository addFileInWorkingDirectory:@"large.bin" toIndex:index error:NULL]);
  NSData* data = [self.repository readContentsForFile:@"large.bin" inIndex:index error:NULL];
  NSString* contents = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  XCTAssertTrue([contents hasPrefix:@"version https://git-lfs.github.com/spec/v1\n"], @"%@", contents);
}

// Smoke test with the real git-lfs tool: many files go through the same long-running filter process,
// including content spanning several protocol packets
- (void)testGitLFSFilterRoundTrip {
  NSString* shell = NSProcessInfo.processInfo.environment[@"SHELL"] ?: @"/bin/sh";
  NSString* PATH = [self.repository getPATHUsingShell:shell error:NULL];
  if (!GCFindExecutableInPATH(@"git-lfs", PATH, GCDefaultExecutableDirectories())) {
    XCTSkip(@"git-lfs is not installed");
  }

  [self updateFileAtPath:@".gitattributes" withString:@"*.bin filter=lfs diff=lfs merge=lfs -text\n"];
  NSMutableDictionary* files = [[NSMutableDictionary alloc] init];
  for (int i = 0; i < 20; ++i) {
    files[[NSString stringWithFormat:@"file-%i.bin", i]] = [@"" stringByPaddingToLength:(i * 10000 + 1) withString:[NSString stringWithFormat:@"Hello LFS %i\n", i] startingAtIndex:0];
  }
  GCIndex* index = [self.repository readRepositoryIndex:NULL];
  XCTAssertNotNil(index);
  for (NSString* path in files) {
    [self updateFileAtPath:path withString:files[path]];
    XCTAssertTrue([self.repository addFileInWorkingDirectory:path toIndex:index error:NULL]);
    NSString* contents = [[NSString alloc] initWithData:[self.repository readContentsForFile:path inIndex:index error:NULL] encoding:NSUTF8StringEncoding];
    XCTAssertTrue([contents hasPrefix:@"version https://git-lfs.github.com/spec/v1\n"], @"%@", contents);
  }

  for (NSString* path in files) {
    [self deleteFileAtPath:path];
    XCTAssertTrue([self.repository checkoutFileToWorkingDirectory:path fromIndex:index error:NULL]);
    [self assertContentsOfFileAtPath:path equalsString:files[path]];
  }
}

@end
