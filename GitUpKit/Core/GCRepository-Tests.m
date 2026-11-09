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

#import <git2/sys/credential.h>

// Stands in for the application: counts the requests for credentials and answers with fixed ones, or declines
@interface GCCredentialsTestDelegate : NSObject <GCRepositoryDelegate>
@property(nonatomic) BOOL providesCredentials;
@property(nonatomic) NSUInteger requestCount;
@end

@implementation GCCredentialsTestDelegate

- (BOOL)repository:(GCRepository*)repository requiresPlainTextAuthenticationForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password {
  _requestCount += 1;
  if (!_providesCredentials) {
    return NO;
  }
  *username = @"delegate";
  *password = @"dialog";
  return YES;
}

@end

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

// Installs a fake credential helper that logs every request it gets and answers "get" ones - Returns the directory holding the helper and its "log"
- (NSString*)_installCredentialHelperInRepository:(GCRepository*)repository {
  NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]);
  NSString* logPath = [directory stringByAppendingPathComponent:@"log"];
  NSString* helperPath = [directory stringByAppendingPathComponent:@"helper"];
  NSString* helperScript = [NSString stringWithFormat:@"#!/bin/sh\n"
                                                       "echo \"[$1] interactive=${GCM_INTERACTIVE:-default}\" >> \"%@\"\n"
                                                       "cat >> \"%@\"\n"
                                                       "if [ \"$1\" = \"get\" ]; then\n"
                                                       "  printf 'username=bot\\npassword=s3cret\\npassword_expiry_utc=4102444800\\n'\n"
                                                       "fi\n",
                                                      logPath, logPath];
  XCTAssertTrue([helperScript writeToFile:helperPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @(0755)} ofItemAtPath:helperPath error:NULL]);

  // Isolate from the developer's own configuration: reset inherited helpers, never send "path=" nor use an askpass program
  // Note: git only runs helpers as "git credential-<name>" unless given an absolute path or a "!" command
  XCTAssertNotNil(([self runGitCLTWithRepository:repository command:@"config", @"--add", @"credential.helper", @"", nil]));  // Commas must be shielded from the macro
  XCTAssertNotNil(([self runGitCLTWithRepository:repository command:@"config", @"--add", @"credential.helper", helperPath, nil]));
  XCTAssertNotNil(([self runGitCLTWithRepository:repository command:@"config", @"credential.useHttpPath", @"false", nil]));
  return directory;
}

// Returns what the fake credential helper logged since the last call, or nil if it wasn't run
- (NSString*)_takeCredentialHelperLog:(NSString*)directory {
  NSString* logPath = [directory stringByAppendingPathComponent:@"log"];
  NSString* log = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:NULL];
  [[NSFileManager defaultManager] removeItemAtPath:logPath error:NULL];
  return log;
}

static NSUInteger _CountOccurrences(NSString* string, NSString* substring) {
  return string ? [string componentsSeparatedByString:substring].count - 1 : 0;
}

- (void)testCredentialHelpers {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  GCRepository* repository = [self createLocalRepositoryAtPath:path bare:NO];

  // No helper configured: no credentials
  XCTAssertNotNil(([self runGitCLTWithRepository:repository command:@"config", @"--add", @"credential.helper", @"", nil]));
  NSURL* url = [NSURL URLWithString:@"https://example.invalid/some/repo.git"];
  NSString* username = nil;
  NSString* password = nil;
  NSString* description = nil;
  NSError* error = nil;
  XCTAssertFalse([repository fillCredentialsForURL:url user:nil allowInteraction:NO username:&username password:&password description:&description error:&error]);
  XCTAssertNotNil(error);
  XCTAssertNil(username);
  XCTAssertNil(password);
  XCTAssertNil(description);

  // ...and Git must not fall back to asking by itself through an askpass program, even when the helpers are allowed to interact
  NSString* askpassDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:askpassDirectory withIntermediateDirectories:YES attributes:nil error:NULL]);
  NSString* askpassPath = [askpassDirectory stringByAppendingPathComponent:@"askpass"];
  NSString* askpassMarkerPath = [askpassDirectory stringByAppendingPathComponent:@"asked"];
  NSString* askpassScript = [NSString stringWithFormat:@"#!/bin/sh\ntouch \"%@\"\necho answer\n", askpassMarkerPath];
  XCTAssertTrue([askpassScript writeToFile:askpassPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @(0755)} ofItemAtPath:askpassPath error:NULL]);
  XCTAssertNotNil(([self runGitCLTWithRepository:repository command:@"config", @"core.askPass", askpassPath, nil]));
  XCTAssertFalse([repository fillCredentialsForURL:url user:nil allowInteraction:YES username:&username password:&password description:&description error:&error]);
  XCTAssertFalse([repository fillCredentialsForURL:url user:nil allowInteraction:NO username:&username password:&password description:&description error:&error]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:askpassMarkerPath]);
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:askpassDirectory error:NULL]);

  // URLs credentials can't be described for are refused instead of raising
  NSURL* nilURL = nil;
  XCTAssertFalse([repository fillCredentialsForURL:nilURL user:nil allowInteraction:NO username:&username password:&password description:&description error:&error]);
  XCTAssertFalse([repository fillCredentialsForURL:[NSURL fileURLWithPath:@"/some/repo.git"] user:nil allowInteraction:NO username:&username password:&password description:&description error:&error]);
  XCTAssertFalse([repository approveCredentialsWithDescription:@"" error:&error]);

  // Fake helper configured: fill in both modes
  NSString* helperDirectory = [self _installCredentialHelperInRepository:repository];
  XCTAssertTrue([repository fillCredentialsForURL:url user:@"hint" allowInteraction:NO username:&username password:&password description:&description error:&error]);
  XCTAssertEqualObjects(username, @"bot");
  XCTAssertEqualObjects(password, @"s3cret");
  XCTAssertTrue([description containsString:@"host=example.invalid\n"]);
  XCTAssertTrue([description containsString:@"password=s3cret\n"]);
  NSString* log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqualObjects(log, @"[get] interactive=never\nprotocol=https\nhost=example.invalid\nusername=hint\n");  // Told not to prompt, and no "path=" as credential.useHttpPath is off
  XCTAssertTrue([repository fillCredentialsForURL:url user:@"hint" allowInteraction:YES username:&username password:&password description:&description error:&error]);
  XCTAssertEqualObjects(username, @"bot");
  XCTAssertEqualObjects(password, @"s3cret");
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqualObjects(log, @"[get] interactive=default\nprotocol=https\nhost=example.invalid\nusername=hint\n");

  // Approve and reject hand the complete description back, including attributes other than the username and password
  BOOL hasExpiry = [description containsString:@"password_expiry_utc=4102444800\n"];  // Only passed along by Git 2.40 and later
  XCTAssertTrue([repository approveCredentialsWithDescription:description error:&error]);
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertTrue([log hasPrefix:@"[store] interactive=never\nprotocol=https\nhost=example.invalid\nusername=bot\npassword=s3cret\n"], @"%@", log);
  XCTAssertEqual([log containsString:@"password_expiry_utc=4102444800\n"], hasExpiry);
  XCTAssertTrue([repository rejectCredentialsWithDescription:description error:&error]);
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertTrue([log hasPrefix:@"[erase] interactive=never\nprotocol=https\nhost=example.invalid\nusername=bot\npassword=s3cret\n"], @"%@", log);
  XCTAssertEqual([log containsString:@"password_expiry_utc=4102444800\n"], hasExpiry);

  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:helperDirectory error:NULL]);
  [self destroyLocalRepository:repository];
}

// Ask for credentials the way libgit2 does during a transfer
- (int)_requestCredentialsForURL:(NSString*)url withCallbacks:(git_remote_callbacks*)callbacks username:(NSString**)username password:(NSString**)password {
  git_credential* credential = NULL;
  int status = callbacks->credentials(&credential, url.UTF8String, NULL, GIT_CREDENTIAL_USERPASS_PLAINTEXT, callbacks->payload);
  *username = nil;
  *password = nil;
  if (status == GIT_OK) {
    git_credential_userpass_plaintext* plaintext = (git_credential_userpass_plaintext*)credential;
    *username = [NSString stringWithUTF8String:plaintext->username];
    *password = [NSString stringWithUTF8String:plaintext->password];
    git_credential_free(credential);
  }
  return status;
}

- (void)testCredentialHelpersDuringTransfers {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  GCRepository* repository = [self createLocalRepositoryAtPath:path bare:NO];
  NSString* helperDirectory = [self _installCredentialHelperInRepository:repository];
  GCCredentialsTestDelegate* delegate = [[GCCredentialsTestDelegate alloc] init];
  delegate.providesCredentials = YES;
  repository.delegate = delegate;
  // Unique hosts as the credentials approved so far are remembered for the lifetime of the process
  NSString* unique = [[NSUUID UUID].UUIDString lowercaseString];
  NSString* url = [NSString stringWithFormat:@"https://%@.example.invalid/some/repo.git", unique];
  NSString* automaticURL = [NSString stringWithFormat:@"https://automatic-%@.example.invalid/some/repo.git", unique];
  git_remote_callbacks callbacks = GIT_REMOTE_CALLBACKS_INIT;
  NSString* username;
  NSString* password;
  NSString* log;

  // Disabled, which is the default: only the delegate is asked
  XCTAssertEqual(repository.credentialHelperMode, kGCCredentialHelperMode_Disabled);
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:url withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"delegate");
  XCTAssertEqualObjects(password, @"dialog");
  XCTAssertEqual(delegate.requestCount, 1);
  [repository didFinishRemoteTransferWithURL:nil success:YES];
  XCTAssertNil([self _takeCredentialHelperLog:helperDirectory]);

  // Interactive: the helpers are asked first and their credentials approved once the transfer succeeds
  repository.credentialHelperMode = kGCCredentialHelperMode_Interactive;
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:url withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"bot");
  XCTAssertEqualObjects(password, @"s3cret");
  XCTAssertEqual(delegate.requestCount, 1);
  [repository didFinishRemoteTransferWithURL:nil success:YES];
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqual(_CountOccurrences(log, @"[get] interactive=default\n"), 1);
  XCTAssertEqual(_CountOccurrences(log, @"[store]"), 1);
  XCTAssertEqual(_CountOccurrences(log, @"[erase]"), 0);

  // ...and approved again after each successful transfer, like Git does
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:url withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  [repository didFinishRemoteTransferWithURL:nil success:YES];
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqual(_CountOccurrences(log, @"[store]"), 1);

  // Being asked again means the credentials were refused: the helpers are told, not asked a second time, and the delegate takes over
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:url withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"bot");
  XCTAssertEqual([self _requestCredentialsForURL:url withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"delegate");
  XCTAssertEqual(delegate.requestCount, 2);
  delegate.providesCredentials = NO;
  XCTAssertEqual([self _requestCredentialsForURL:url withCallbacks:&callbacks username:&username password:&password], GIT_EUSER);
  XCTAssertEqual(delegate.requestCount, 3);
  [repository didFinishRemoteTransferWithURL:nil success:YES];  // Whatever worked in the end didn't come from the helpers
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqual(_CountOccurrences(log, @"[get]"), 1);
  XCTAssertEqual(_CountOccurrences(log, @"[erase]"), 1);
  XCTAssertEqual(_CountOccurrences(log, @"[store]"), 0);
  delegate.providesCredentials = YES;

  // A transfer failing for another reason neither approves nor rejects
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:url withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"bot");
  [repository didFinishRemoteTransferWithURL:nil success:NO];
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqual(_CountOccurrences(log, @"[get]"), 1);
  XCTAssertEqual(_CountOccurrences(log, @"[store]"), 0);
  XCTAssertEqual(_CountOccurrences(log, @"[erase]"), 0);

  // Like Git, helpers aren't involved in password authentication over SSH
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:@"ssh://example.invalid/some/repo.git" withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"delegate");
  [repository didFinishRemoteTransferWithURL:nil success:YES];
  XCTAssertNil([self _takeCredentialHelperLog:helperDirectory]);

  // Non-interactive: the delegate is asked first and the helpers aren't run if it has credentials that work
  repository.credentialHelperMode = kGCCredentialHelperMode_NonInteractive;
  delegate.requestCount = 0;
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:automaticURL withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"delegate");
  [repository didFinishRemoteTransferWithURL:nil success:YES];
  XCTAssertNil([self _takeCredentialHelperLog:helperDirectory]);

  // ...the helpers come next if these are refused, and are told not to prompt
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:automaticURL withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"delegate");
  XCTAssertEqual([self _requestCredentialsForURL:automaticURL withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"bot");
  XCTAssertEqual(delegate.requestCount, 2);
  [repository didFinishRemoteTransferWithURL:nil success:YES];
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqual(_CountOccurrences(log, @"[get] interactive=never\n"), 1);
  XCTAssertEqual(_CountOccurrences(log, @"[store] interactive=never\n"), 1);

  // ...or if the delegate has none - This time the same credentials aren't approved again
  delegate.providesCredentials = NO;
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:automaticURL withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"bot");
  [repository didFinishRemoteTransferWithURL:nil success:YES];
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqual(_CountOccurrences(log, @"[get]"), 1);
  XCTAssertEqual(_CountOccurrences(log, @"[store]"), 0);

  // ...until they have been rejected in between
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:automaticURL withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqual([self _requestCredentialsForURL:automaticURL withCallbacks:&callbacks username:&username password:&password], GIT_EUSER);
  [repository didFinishRemoteTransferWithURL:nil success:NO];
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqual(_CountOccurrences(log, @"[erase]"), 1);
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:automaticURL withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  [repository didFinishRemoteTransferWithURL:nil success:YES];
  log = [self _takeCredentialHelperLog:helperDirectory];
  XCTAssertEqual(_CountOccurrences(log, @"[store]"), 1);

  // Without a delegate the helpers are all there is
  repository.delegate = nil;
  [repository setRemoteCallbacks:&callbacks];
  XCTAssertEqual([self _requestCredentialsForURL:automaticURL withCallbacks:&callbacks username:&username password:&password], GIT_OK);
  XCTAssertEqualObjects(username, @"bot");
  XCTAssertEqual([self _requestCredentialsForURL:automaticURL withCallbacks:&callbacks username:&username password:&password], GIT_PASSTHROUGH);
  [repository didFinishRemoteTransferWithURL:nil success:NO];
  [self _takeCredentialHelperLog:helperDirectory];

  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:helperDirectory error:NULL]);
  [self destroyLocalRepository:repository];
}

- (void)testInheritRemoteSettings {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  GCRepository* repository = [self createLocalRepositoryAtPath:path bare:NO];
  GCCredentialsTestDelegate* delegate = [[GCCredentialsTestDelegate alloc] init];
  repository.delegate = delegate;
  repository.credentialHelperMode = kGCCredentialHelperMode_Interactive;

  GCRepository* other = [[GCRepository alloc] initWithExistingLocalRepository:path error:NULL];
  XCTAssertNotNil(other);
  XCTAssertNil(other.delegate);
  XCTAssertEqual(other.credentialHelperMode, kGCCredentialHelperMode_Disabled);
  [other inheritRemoteSettingsFromRepository:repository];
  XCTAssertEqual(other.delegate, delegate);
  XCTAssertEqual(other.credentialHelperMode, kGCCredentialHelperMode_Interactive);

  [self destroyLocalRepository:repository];
}

// A timed out task must not keep waiting on a process it started that survived and still holds its pipes (e.g. a credential helper started by git)
- (void)_testTaskTimeout {
  GCTask* task = [[GCTask alloc] initWithExecutablePath:@"/bin/sh"];
  task.executionTimeOut = 1.0;
  int status = 0;
  NSData* stdoutData;
  NSData* stderrData;
  CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
  NSArray* arguments = @[ @"-c", @"(trap '' TERM INT; exec sleep 15) & wait" ];  // The background process ignores the signals ending the shell and holds on to its pipes
  XCTAssertTrue([task runWithArguments:arguments stdin:nil stdout:&stdoutData stderr:&stderrData exitStatus:&status error:NULL]);
  XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - time, 10.0);
  XCTAssertTrue(task.timedOut);
  XCTAssertNotEqual(status, 0);

  // Not timing out leaves everything as before
  arguments = @[ @"-c", @"echo done" ];
  XCTAssertTrue([task runWithArguments:arguments stdin:nil stdout:&stdoutData stderr:&stderrData exitStatus:&status error:NULL]);
  XCTAssertFalse(task.timedOut);
  XCTAssertEqual(status, 0);
  XCTAssertEqualObjects([[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding], @"done\n");
}

- (void)testTaskTimeout {
  [self _testTaskTimeout];

  // Same from a background thread, which is where transfers run
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [self _testTaskTimeout];
    dispatch_semaphore_signal(semaphore);
  });
  XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0);
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

@end
