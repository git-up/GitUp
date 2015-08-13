//  Copyright (C) 2015 Pierre-Olivier Latour <info@pol-online.net>
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
  XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0500)} ofItemAtPath:[path stringByAppendingPathComponent:@".git"] error:NULL]);
  GCRepository* repo2 = [[GCRepository alloc] initWithExistingLocalRepository:path error:NULL];
  XCTAssertNotNil(repo2);
  XCTAssertTrue(repo2.readOnly);
  repo2 = nil;
  XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0700)} ofItemAtPath:[path stringByAppendingPathComponent:@".git"] error:NULL]);
  
  // Destroy repository
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
}

@end

@implementation GCEmptyRepositoryTests (GCRepository)

// -initWithNewLocalRepository:bare:error: is called in -setUp
- (void)testInitialization {
  // Check initialization result
  [self assertGitCLTOutputContainsString:@"On branch master\n\nInitial commit\n" withRepository:self.repository command:@"status", nil];
  
  // Check properties
  XCTAssertEqualObjects([self.repository.repositoryPath stringByStandardizingPath], [self.temporaryPath stringByAppendingPathComponent:@".git"]);
  XCTAssertEqualObjects([self.repository.workingDirectoryPath stringByStandardizingPath], self.temporaryPath);
  XCTAssertFalse(self.repository.bare);
  XCTAssertTrue(self.repository.empty);
  XCTAssertEqual(self.repository.state, kGCRepositoryState_None);
  
  // Test re-initializing
  XCTAssertFalse([[GCRepository alloc] initWithNewLocalRepository:self.repository.workingDirectoryPath bare:NO error:NULL]);
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

@end
