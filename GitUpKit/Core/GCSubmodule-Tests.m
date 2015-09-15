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
#import "GCRepository+Index.h"

@implementation GCTests (GCSubmodule)

// TODO: Test -checkAllSubmodulesInitialized:error:
// TODO: Test -initializeAllSubmodules:error:
- (void)testInitializeSubmodule {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  
  NSURL* url = [NSURL URLWithString:@"https://github.com/git-up/test-repo-submodules.git"];
  GCRepository* repository = [[GCRepository alloc] initWithClonedRepositoryFromURL:url toPath:path usingDelegate:nil recursive:NO error:NULL];
  XCTAssertNotNil(repository);
  
  NSArray* submodules = [repository listSubmodules:NULL];
  XCTAssertEqual(submodules.count, 1);
  GCSubmodule* submodule = submodules[0];
  XCTAssertFalse([repository checkSubmoduleInitialized:submodule error:NULL]);
  XCTAssertTrue([repository initializeSubmodule:submodule recursive:NO error:NULL]);
  XCTAssertTrue([repository checkSubmoduleInitialized:submodule error:NULL]);
  
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

@end

@implementation GCSingleCommitRepositoryTests (GCSubmodule)

- (void)testAddSubmodule {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  
  // Create submodule repo with dummy commit
  GCRepository* repository = [self createLocalRepositoryAtPath:path bare:NO];
  XCTAssertTrue([@"Hello World!\n" writeToFile:[path stringByAppendingPathComponent:@"file.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  XCTAssertTrue([repository addAllFilesToIndex:NULL]);
  XCTAssertNotNil([repository createCommitFromHEADWithMessage:@"0" error:NULL]);
  
  // Add submodule
  GCSubmodule* submodule = [self.repository addSubmoduleWithURL:[NSURL fileURLWithPath:path] atPath:@"submodule" recursive:NO error:NULL];
  XCTAssertNotNil(submodule);
  
  // Commit
  XCTAssertNotNil([self.repository createCommitFromHEADWithMessage:@"Test" error:NULL]);
  
  // Check submodule
  XCTAssertNotNil([self.repository lookupSubmoduleWithName:@"submodule" error:NULL]);
  
  // Destroy submodule repo
  [self destroyLocalRepository:repository];
}

- (void)testSubmodules {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  
  // Create submodule repo with dummy commit
  GCRepository* repository = [self createLocalRepositoryAtPath:path bare:NO];
  XCTAssertTrue([@"Hello World!\n" writeToFile:[path stringByAppendingPathComponent:@"file.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  XCTAssertTrue([repository addAllFilesToIndex:NULL]);
  XCTAssertNotNil([repository createCommitFromHEADWithMessage:@"0" error:NULL]);
  
  // Add submodule
  NSString* output = [self runGitCLTWithRepository:self.repository command:@"submodule", @"add", path, @"submodule", nil];
  XCTAssertNotNil(output);
  
  // Check status
  XCTAssertTrue([self.repository checkRepositoryDirty:NO]);
  GCDiff* indexStatus1 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus1);
  XCTAssertEqual([indexStatus1 changeForFile:@"submodule"], kGCFileDiffChange_Added);
  GCDiff* workdirStatus1 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus1);
  XCTAssertEqual([workdirStatus1 changeForFile:@"submodule"], NSNotFound);
  
  // Commit submodule
  GCCommit* commit1 = [self.repository createCommitFromHEADWithMessage:@"Added submodule" error:NULL];
  XCTAssertNotNil(commit1);
  XCTAssertFalse([self.repository checkRepositoryDirty:NO]);

  // List submodules
  NSArray* submodules = [self.repository listSubmodules:NULL];
  XCTAssertEqual(submodules.count, 1);
  GCSubmodule* submodule = submodules[0];
  XCTAssertEqualObjects(submodule.name, @"submodule");
  XCTAssertEqualObjects(submodule.path, @"submodule");
  XCTAssertEqualObjects(submodule.URL, GCURLFromGitURL(path));
  XCTAssertNil(submodule.remoteBranchName);
  XCTAssertEqual(submodule.ignoreMode, kGCSubmoduleIgnoreMode_None);
  XCTAssertEqual(submodule.fetchRecurseMode, kGCSubmoduleFetchRecurseMode_No);
  XCTAssertEqual(submodule.updateMode, kGCSubmoduleUpdateMode_Checkout);

  // Open submodule
  GCRepository* subRepo = [[GCRepository alloc] initWithSubmodule:submodule error:NULL];
  XCTAssertNotNil(subRepo);
  XCTAssertFalse([subRepo checkRepositoryDirty:YES]);
  if (1) {
    git_config* config;
    XCTAssertEqual(git_repository_config(&config, subRepo.private), GIT_OK);
    XCTAssertEqual(git_config_set_string(config, "user.name", "Bot"), GIT_OK);
    XCTAssertEqual(git_config_set_string(config, "user.email", "bot@example.com"), GIT_OK);
    git_config_free(config);
  }
  
  // Make commit in submodule
  XCTAssertTrue([@"Bonjour le Monde!\n" writeToFile:[subRepo.workingDirectoryPath stringByAppendingPathComponent:@"file.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  XCTAssertTrue([subRepo addAllFilesToIndex:NULL]);
  XCTAssertNotNil([subRepo createCommitFromHEADWithMessage:@"1" error:NULL]);
  
  // Check status
  XCTAssertTrue([self.repository checkRepositoryDirty:NO]);
  GCDiff* indexStatus2 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus2);
  XCTAssertEqual([indexStatus2 changeForFile:@"submodule"], NSNotFound);
  GCDiff* workdirStatus2 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus2);
  XCTAssertEqual([workdirStatus2 changeForFile:@"submodule"], kGCFileDiffChange_Modified);
  
  // Add submodule to index
  XCTAssertTrue([self.repository addSubmoduleToRepositoryIndex:submodule error:NULL]);
  GCDiff* indexStatus3 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus3);
  XCTAssertEqual([indexStatus3 changeForFile:@"submodule"], kGCFileDiffChange_Modified);
  GCDiff* workdirStatus3 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus3);
  XCTAssertEqual([workdirStatus3 changeForFile:@"submodule"], NSNotFound);
  
  // Unstage submodule from index
  XCTAssertTrue([self.repository resetFileInIndexToHEAD:@"submodule" error:NULL]);
  GCDiff* indexStatus4 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus4);
  XCTAssertEqual([indexStatus4 changeForFile:@"submodule"], NSNotFound);
  GCDiff* workdirStatus4 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus4);
  XCTAssertEqual([workdirStatus4 changeForFile:@"submodule"], kGCFileDiffChange_Modified);
  
  // Re-stage submodule into index
  XCTAssertTrue([self.repository addSubmoduleToRepositoryIndex:submodule error:NULL]);
  
  // Commit submodule again
  GCCommit* commit2 = [self.repository createCommitFromHEADWithMessage:@"Updated submodule" error:NULL];
  XCTAssertNotNil(commit2);
  XCTAssertFalse([self.repository checkRepositoryDirty:NO]);
  
  // Checkout previous commit
  XCTAssertTrue([self.repository checkoutCommit:commit1 options:kGCCheckoutOption_Force error:NULL]);
  GCDiff* indexStatus5 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus5);
  XCTAssertEqual([indexStatus5 changeForFile:@"submodule"], NSNotFound);
  GCDiff* workdirStatus5 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus5);
  XCTAssertEqual([workdirStatus5 changeForFile:@"submodule"], kGCFileDiffChange_Modified);
  
  // Update submodule
  XCTAssertTrue([self.repository updateSubmodule:submodule force:NO error:NULL]);
  GCDiff* indexStatus6 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus6);
  XCTAssertEqual([indexStatus6 changeForFile:@"submodule"], NSNotFound);
  GCDiff* workdirStatus6 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus6);
  XCTAssertEqual([workdirStatus6 changeForFile:@"submodule"], NSNotFound);
  
  // Reset to latest commit
  XCTAssertTrue([self.repository resetToCommit:commit2 mode:kGCResetMode_Hard error:NULL]);
  GCDiff* indexStatus7 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus7);
  XCTAssertEqual([indexStatus7 changeForFile:@"submodule"], NSNotFound);
  GCDiff* workdirStatus7 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus7);
  XCTAssertEqual([workdirStatus7 changeForFile:@"submodule"], kGCFileDiffChange_Modified);
  
  // Destroy submodule repo
  [self destroyLocalRepository:repository];
}

- (void)testRecursiveSubmoduleUpdate {
  NSString* path1 = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString* path2 = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString* output;
  git_config* config;
  
  // Create submodule repo
  GCRepository* repo1 = [self createLocalRepositoryAtPath:path1 bare:NO];
  XCTAssertNotNil(repo1);
  NSArray* commits = [repo1 createMockCommitHierarchyFromNotation:@"m0 - m1 - m2<master>" force:NO error:NULL];
  XCTAssertNotNil(commits);
  XCTAssertTrue([repo1 setDetachedHEADToCommit:commits[1] error:NULL]);
  
  // Create wrapper repo
  GCRepository* repo2 = [self createLocalRepositoryAtPath:path2 bare:NO];
  XCTAssertNotNil(repo2);
  output = [self runGitCLTWithRepository:repo2 command:@"submodule", @"add", path1, @"repo1", nil];
  XCTAssertNotNil(output);
  XCTAssertNotNil([repo2 createCommitFromHEADWithMessage:@"Added submodule" error:NULL]);
  
  // Wrap the wrapper repo
  output = [self runGitCLTWithRepository:self.repository command:@"submodule", @"add", path2, @"repo2", nil];
  XCTAssertNotNil(output);
  output = [self runGitCLTWithRepository:self.repository command:@"submodule", @"update", @"--init", @"--recursive", nil];
  XCTAssertNotNil(output);
  GCCommit* commit1 = [self.repository createCommitFromHEADWithMessage:@"Added submodule" error:NULL];
  XCTAssertNotNil(commit1);
  
  // Load submodules and subrepos
  GCSubmodule* submodule2 = [[self.repository listSubmodules:NULL] firstObject];
  XCTAssertNotNil(submodule2);
  GCRepository* subrepo2 = [[GCRepository alloc] initWithSubmodule:submodule2 error:NULL];
  XCTAssertNotNil(subrepo2);
  XCTAssertEqual(git_repository_config(&config, subrepo2.private), GIT_OK);
  XCTAssertEqual(git_config_set_string(config, "user.name", "Bot"), GIT_OK);
  XCTAssertEqual(git_config_set_string(config, "user.email", "bot@example.com"), GIT_OK);
  git_config_free(config);
  GCSubmodule* submodule1 = [[subrepo2 listSubmodules:NULL] firstObject];
  XCTAssertNotNil(submodule1);
  GCRepository* subrepo1 = [[GCRepository alloc] initWithSubmodule:submodule1 error:NULL];
  XCTAssertNotNil(subrepo1);
  XCTAssertEqual(git_repository_config(&config, subrepo1.private), GIT_OK);
  XCTAssertEqual(git_config_set_string(config, "user.name", "Bot"), GIT_OK);
  XCTAssertEqual(git_config_set_string(config, "user.email", "bot@example.com"), GIT_OK);
  git_config_free(config);
  
  // Move HEAD in submodule repo
  XCTAssertTrue([subrepo1 setDetachedHEADToCommit:commits[2] error:NULL]);
  XCTAssertTrue([self.repository checkRepositoryDirty:NO]);
  XCTAssertTrue([subrepo2 addSubmoduleToRepositoryIndex:submodule1 error:NULL]);
  XCTAssertNotNil([subrepo2 createCommitFromHEADWithMessage:@"Updated submodule" error:NULL]);
  XCTAssertTrue([self.repository checkRepositoryDirty:NO]);
  XCTAssertTrue([self.repository addSubmoduleToRepositoryIndex:submodule2 error:NULL]);
  GCCommit* commit2 = [self.repository createCommitFromHEADWithMessage:@"Updated submodule" error:NULL];
  XCTAssertNotNil(commit2);
  XCTAssertFalse([self.repository checkRepositoryDirty:NO]);
  
  // Roll back commit
  XCTAssertTrue([self.repository resetToCommit:commit1 mode:kGCResetMode_Hard error:NULL]);
  XCTAssertTrue([self.repository checkRepositoryDirty:NO]);
  XCTAssertTrue([self.repository updateAllSubmodulesResursively:NO error:NULL]);
  XCTAssertFalse([self.repository checkRepositoryDirty:NO]);
  XCTAssertEqualObjects([subrepo1 lookupHEAD:NULL error:NULL], commits[1]);
  
  // Clean up
  [self destroyLocalRepository:repo2];
  [self destroyLocalRepository:repo1];
}

- (void)testSubmoduleEdgeCases {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString* output;
  
  // Create submodule repo
  GCRepository* repo = [self createLocalRepositoryAtPath:path bare:NO];
  XCTAssertNotNil(repo);
  XCTAssertNotNil([repo createMockCommitHierarchyFromNotation:@"m0 - m1 - m2<master>" force:NO error:NULL]);
  
  // Add submodule and commit
  output = [self runGitCLTWithRepository:self.repository command:@"submodule", @"add", path, @"repo", nil];
  XCTAssertNotNil(output);
  output = [self runGitCLTWithRepository:self.repository command:@"submodule", @"update", @"--init", nil];
  XCTAssertNotNil(output);
  GCCommit* commit1 = [self.repository createCommitFromHEADWithMessage:@"Added submodule" error:NULL];
  XCTAssertNotNil(commit1);
  
  // Checkout commit before submodule was added
  XCTAssertTrue([self.repository checkoutCommit:self.initialCommit options:kGCCheckoutOption_UpdateSubmodulesRecursively error:NULL]);
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  XCTAssertEqualObjects([self.repository listSubmodules:NULL], @[]);
  
  // Checkout commit when submodule was added
  XCTAssertTrue([self.repository checkoutLocalBranch:[self.repository findLocalBranchWithName:@"master" error:NULL] options:kGCCheckoutOption_UpdateSubmodulesRecursively error:NULL]);
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  XCTAssertEqual([[self.repository listSubmodules:NULL] count], 1);
  
  // Delete submodule and commit
  output = [self runGitCLTWithRepository:self.repository command:@"submodule", @"deinit", @"repo", nil];
  XCTAssertNotNil(output);
  output = [self runGitCLTWithRepository:self.repository command:@"rm", @"repo", nil];
  XCTAssertNotNil(output);
  GCCommit* commit2 = [self.repository createCommitFromHEADWithMessage:@"Removed submodule" error:NULL];
  XCTAssertNotNil(commit2);
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  XCTAssertEqualObjects([self.repository listSubmodules:NULL], @[]);
  
  // Checkout commit when submodule was added
  XCTAssertTrue([self.repository checkoutCommit:commit1 options:kGCCheckoutOption_UpdateSubmodulesRecursively error:NULL]);
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  XCTAssertEqual([[self.repository listSubmodules:NULL] count], 1);
  
  // Checkout commit when submodule was deleted
  XCTAssertTrue([self.repository checkoutLocalBranch:[self.repository findLocalBranchWithName:@"master" error:NULL] options:kGCCheckoutOption_UpdateSubmodulesRecursively error:NULL]);
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  XCTAssertEqualObjects([self.repository listSubmodules:NULL], @[]);
  
  // Checkin file where submodule was
  [self makeCommitWithUpdatedFileAtPath:@"repo" string:@"nothing" message:@"NOTHING"];
  
  // Checkout commit when submodule was added
  XCTAssertTrue([self.repository checkoutCommit:commit1 options:kGCCheckoutOption_UpdateSubmodulesRecursively error:NULL]);
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  XCTAssertEqual([[self.repository listSubmodules:NULL] count], 1);
  
  // Destroy submodule repo
  [self destroyLocalRepository:repo];
}

- (void)testRenameSubmodule {
  NSArray* submodules;
  GCSubmodule* submodule;
  
  // Add submodule
  NSString* output1 = [self runGitCLTWithRepository:self.repository command:@"submodule", @"add", @"https://github.com/git-up/test-repo-base.git", nil];
  XCTAssertNotNil(output1);
  
  // Verify name & path
  submodules = [self.repository listSubmodules:NULL];
  XCTAssertEqual(submodules.count, 1);
  submodule = submodules.firstObject;
  XCTAssertEqualObjects(submodule.name, @"test-repo-base");
  XCTAssertEqualObjects(submodule.path, @"test-repo-base");
  
  // Commit submodule
  GCCommit* commit1 = [self.repository createCommitFromHEADWithMessage:@"Added submodule" error:NULL];
  XCTAssertNotNil(commit1);
  XCTAssertFalse([self.repository checkRepositoryDirty:NO]);
  
  // Verify name & path
  submodules = [self.repository listSubmodules:NULL];
  XCTAssertEqual(submodules.count, 1);
  submodule = submodules.firstObject;
  XCTAssertEqualObjects(submodule.name, @"test-repo-base");
  XCTAssertEqualObjects(submodule.path, @"test-repo-base");
  
  // Move submodule
  NSString* output2 = [self runGitCLTWithRepository:self.repository command:@"mv", @"test-repo-base", @"base", nil];
  XCTAssertNotNil(output2);
  
  // Verify name & path
  submodules = [self.repository listSubmodules:NULL];
  XCTAssertEqual(submodules.count, 1);
  submodule = submodules.firstObject;
  XCTAssertEqualObjects(submodule.name, @"test-repo-base");
  XCTAssertEqualObjects(submodule.path, @"base");
  
  // Commit submodule
  GCCommit* commit2 = [self.repository createCommitFromHEADWithMessage:@"Moved submodule" error:NULL];
  XCTAssertNotNil(commit2);
  XCTAssertFalse([self.repository checkRepositoryDirty:NO]);
  
  // Verify name & path
  submodules = [self.repository listSubmodules:NULL];
  XCTAssertEqual(submodules.count, 1);
  submodule = submodules.firstObject;
  XCTAssertEqualObjects(submodule.name, @"test-repo-base");
  XCTAssertEqualObjects(submodule.path, @"base");
}

@end
