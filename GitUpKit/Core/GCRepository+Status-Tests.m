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

@implementation GCSingleCommitRepositoryTests (GCRepository_Status)

- (void)testStatus_Base {
  // Check clean
  XCTAssertTrue([self.repository checkClean:kGCCleanCheckOption_IgnoreUntrackedFiles error:NULL]);
  
  // Add some files & commit changes
  [self updateFileAtPath:@".gitignore" withString:@"ignored.txt\n"];
  XCTAssertTrue([self.repository addFileToIndex:@".gitignore" error:NULL]);
  [self updateFileAtPath:@"modified.txt" withString:@""];
  XCTAssertTrue([self.repository addFileToIndex:@"modified.txt" error:NULL]);
  [self updateFileAtPath:@"deleted.txt" withString:@""];
  XCTAssertTrue([self.repository addFileToIndex:@"deleted.txt" error:NULL]);
  [self updateFileAtPath:@"renamed1.txt" withString:@"Nothing to see here!"];
  XCTAssertTrue([self.repository addFileToIndex:@"renamed1.txt" error:NULL]);
  [self updateFileAtPath:@"type-changed.txt" withString:@""];
  XCTAssertTrue([self.repository addFileToIndex:@"type-changed.txt" error:NULL]);
  XCTAssertNotNil([self.repository createCommitFromHEADWithMessage:@"Update" error:NULL]);
  
  // Check clean
  XCTAssertTrue([self.repository checkClean:kGCCleanCheckOption_IgnoreUntrackedFiles error:NULL]);
  
  // Touch files
  [self updateFileAtPath:@"ignored.txt" withString:@""];
  [self updateFileAtPath:@"modified.txt" withString:@"Hi there!"];
  [self updateFileAtPath:@"added.txt" withString:@"This is a test"];
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"deleted.txt"] error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] moveItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"renamed1.txt"] toPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"renamed2.txt"] error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"type-changed.txt"] error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"type-changed.txt"] withDestinationPath:@"hello_world.txt" error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"hello_world.txt"] toPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"copied.txt"] error:NULL]);
  
  // Check clean
  XCTAssertFalse([self.repository checkClean:kGCCleanCheckOption_IgnoreUntrackedFiles error:NULL]);
  
  // Diff index
  GCDiff* indexStatus1 = [self.repository diffRepositoryIndexWithHEAD:nil
                                                              options:(kGCDiffOption_FindRenames | kGCDiffOption_FindCopies | kGCDiffOption_IncludeUnmodified)
                                                    maxInterHunkLines:0
                                                      maxContextLines:0
                                                                error:NULL];
  XCTAssertNotNil(indexStatus1);
  XCTAssertEqual([indexStatus1 changeForFile:@".gitignore"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([indexStatus1 changeForFile:@"added.txt"], NSNotFound);
  XCTAssertEqual([indexStatus1 changeForFile:@"copied.txt"], NSNotFound);
  XCTAssertEqual([indexStatus1 changeForFile:@"deleted.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([indexStatus1 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([indexStatus1 changeForFile:@"ignored.txt"], NSNotFound);
  XCTAssertEqual([indexStatus1 changeForFile:@"modified.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([indexStatus1 changeForFile:@"renamed1.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([indexStatus1 changeForFile:@"renamed2.txt"], NSNotFound);
  XCTAssertEqual([indexStatus1 changeForFile:@"type-changed.txt"], kGCFileDiffChange_Unmodified);
  
  // Diff workdir
  GCDiff* workdirStatus1 = [self.repository diffWorkingDirectoryWithRepositoryIndex:nil
                                                                            options:(kGCDiffOption_FindTypeChanges | kGCDiffOption_FindRenames | kGCDiffOption_FindCopies | kGCDiffOption_IncludeUnmodified | kGCDiffOption_IncludeUntracked | kGCDiffOption_IncludeIgnored)
                                                                  maxInterHunkLines:0
                                                                    maxContextLines:0
                                                                              error:NULL];
  XCTAssertNotNil(workdirStatus1);
  XCTAssertEqual([workdirStatus1 changeForFile:@".gitignore"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([workdirStatus1 changeForFile:@"added.txt"], kGCFileDiffChange_Untracked);
  XCTAssertEqual([workdirStatus1 changeForFile:@"copied.txt"], kGCFileDiffChange_Copied);  // TODO: Check source is "hello_world.txt"
  XCTAssertEqual([workdirStatus1 changeForFile:@"deleted.txt"], kGCFileDiffChange_Deleted);
  XCTAssertEqual([workdirStatus1 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([workdirStatus1 changeForFile:@"ignored.txt"], kGCFileDiffChange_Ignored);
  XCTAssertEqual([workdirStatus1 changeForFile:@"modified.txt"], kGCFileDiffChange_Modified);
  XCTAssertEqual([workdirStatus1 changeForFile:@"renamed2.txt"], kGCFileDiffChange_Renamed);  // TODO: Check source is "renamed1.txt"
  XCTAssertEqual([workdirStatus1 changeForFile:@"type-changed.txt"], kGCFileDiffChange_TypeChanged);
  
  // Check conflicts
  XCTAssertEqualObjects([self.repository checkConflicts:NULL], @{});
  
  // Update index
  XCTAssertTrue([self.repository addAllFilesToIndex:NULL]);
  
  // Check clean
  XCTAssertFalse([self.repository checkClean:kGCCleanCheckOption_IgnoreUntrackedFiles error:NULL]);
  
  // Diff index
  GCDiff* indexStatus2 = [self.repository diffRepositoryIndexWithHEAD:nil
                                                              options:(kGCDiffOption_FindTypeChanges | kGCDiffOption_FindRenames | kGCDiffOption_FindCopies | kGCDiffOption_IncludeUnmodified)
                                                    maxInterHunkLines:0
                                                      maxContextLines:0
                                                                error:NULL];
  XCTAssertNotNil(indexStatus2);
  XCTAssertEqual([indexStatus2 changeForFile:@".gitignore"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([indexStatus2 changeForFile:@"added.txt"], kGCFileDiffChange_Added);
  XCTAssertEqual([indexStatus2 changeForFile:@"copied.txt"], kGCFileDiffChange_Copied);  // TODO: Check source is "hello_world.txt"
  XCTAssertEqual([indexStatus2 changeForFile:@"deleted.txt"], kGCFileDiffChange_Deleted);
  XCTAssertEqual([indexStatus2 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([indexStatus2 changeForFile:@"ignored.txt"], NSNotFound);
  XCTAssertEqual([indexStatus2 changeForFile:@"modified.txt"], kGCFileDiffChange_Modified);
  XCTAssertEqual([indexStatus2 changeForFile:@"renamed1.txt"], NSNotFound);
  XCTAssertEqual([indexStatus2 changeForFile:@"renamed2.txt"], kGCFileDiffChange_Renamed);  // TODO: Check source is "renamed1.txt"
  XCTAssertEqual([indexStatus2 changeForFile:@"type-changed.txt"], kGCFileDiffChange_TypeChanged);
  
  // Diff workdir
  GCDiff* workdirStatus2 = [self.repository diffWorkingDirectoryWithRepositoryIndex:nil
                                                                            options:(kGCDiffOption_FindRenames | kGCDiffOption_FindCopies | kGCDiffOption_IncludeUnmodified | kGCDiffOption_IncludeUntracked | kGCDiffOption_IncludeIgnored)
                                                                  maxInterHunkLines:0
                                                                    maxContextLines:0
                                                                              error:NULL];
  XCTAssertNotNil(workdirStatus2);
  XCTAssertEqual([workdirStatus2 changeForFile:@".gitignore"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([workdirStatus2 changeForFile:@"added.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([workdirStatus2 changeForFile:@"copied.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([workdirStatus2 changeForFile:@"deleted.txt"], NSNotFound);
  XCTAssertEqual([workdirStatus2 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([workdirStatus2 changeForFile:@"ignored.txt"], kGCFileDiffChange_Ignored);
  XCTAssertEqual([workdirStatus2 changeForFile:@"modified.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([workdirStatus2 changeForFile:@"renamed2.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([workdirStatus2 changeForFile:@"type-changed.txt"], kGCFileDiffChange_Unmodified);
  
  // Check conflicts
  XCTAssertEqualObjects([self.repository checkConflicts:NULL], @{});
}

- (void)testStatus_Conflicts {
  // Check initial state
  XCTAssertEqualObjects([self.repository checkConflicts:NULL], @{});
  
  // Modify file
  GCCommit* newCommit = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Bonjour le monde!\n" message:@"Modified"];
  
  // Create test branch with commit
  GCLocalBranch* branch1 = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"b1" force:NO error:NULL];
  XCTAssertNotNil(branch1);
  XCTAssertTrue([self.repository checkoutLocalBranch:branch1 options:0 error:NULL]);
  [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Hola Mundo!\n" message:@"c1"];
  
  // Test "both modified"
  XCTAssertTrue([self.repository mergeCommitToHEAD:newCommit error:NULL]);
  [self assertGitCLTOutputEqualsString:@"UU hello_world.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  GCDiff* indexStatus1 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus1);
  XCTAssertEqual([indexStatus1 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Conflicted);
  GCDiff* workdirStatus1 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus1);
  XCTAssertEqual([workdirStatus1 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Conflicted);
  NSDictionary* conflicts1 = [self.repository checkConflicts:NULL];
  XCTAssertEqual(conflicts1.count, 1);
  XCTAssertEqual([(GCIndexConflict*)conflicts1[@"hello_world.txt"] status], kGCIndexConflictStatus_BothModified);
  
  // Reset
  XCTAssertTrue([self.repository resetToHEAD:kGCResetMode_Hard error:NULL]);
  
  // Create test branch with commit
  GCLocalBranch* branch2 = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"b2" force:NO error:NULL];
  XCTAssertNotNil(branch2);
  XCTAssertTrue([self.repository checkoutLocalBranch:branch2 options:0 error:NULL]);
  GCCommit* commit2 = [self makeCommitWithDeletedFileAtPath:@"hello_world.txt" message:@"c2"];
  
  // Test "deleted by us"
  XCTAssertTrue([self.repository mergeCommitToHEAD:newCommit error:NULL]);
  [self assertGitCLTOutputEqualsString:@"DU hello_world.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  GCDiff* indexStatus2 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus2);
  XCTAssertEqual([indexStatus2 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Conflicted);
  GCDiff* workdirStatus2 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus2);
  XCTAssertEqual([workdirStatus2 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Conflicted);
  NSDictionary* conflicts2 = [self.repository checkConflicts:NULL];
  XCTAssertEqual(conflicts2.count, 1);
  XCTAssertEqual([(GCIndexConflict*)conflicts2[@"hello_world.txt"] status], kGCIndexConflictStatus_DeletedByUs);
  
  // Reset
  XCTAssertTrue([self.repository resetToHEAD:kGCResetMode_Hard error:NULL]);
  
  // Test "deleted by them"
  XCTAssertTrue([self.repository checkoutLocalBranch:[self.repository findLocalBranchWithName:@"master" error:NULL] options:0 error:NULL]);
  XCTAssertTrue([self.repository mergeCommitToHEAD:commit2 error:NULL]);
  [self assertGitCLTOutputEqualsString:@"UD hello_world.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  GCDiff* indexStatus3 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus3);
  XCTAssertEqual([indexStatus3 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Conflicted);
  GCDiff* workdirStatus3 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus3);
  XCTAssertEqual([workdirStatus3 changeForFile:@"hello_world.txt"], kGCFileDiffChange_Conflicted);
  NSDictionary* conflicts3 = [self.repository checkConflicts:NULL];
  XCTAssertEqual(conflicts3.count, 1);
  XCTAssertEqual([(GCIndexConflict*)conflicts3[@"hello_world.txt"] status], kGCIndexConflictStatus_DeletedByThem);
  
  // Reset
  XCTAssertTrue([self.repository resetToHEAD:kGCResetMode_Hard error:NULL]);
  
  // Create test branch with commit
  GCLocalBranch* branch3 = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"b3" force:NO error:NULL];
  XCTAssertNotNil(branch3);
  XCTAssertTrue([self.repository checkoutLocalBranch:branch3 options:0 error:NULL]);
  GCCommit* commit3 = [self makeCommitWithUpdatedFileAtPath:@"test.txt" string:@"Hello\n" message:@"c3"];
  
  // Test "both added"
  XCTAssertTrue([self.repository checkoutLocalBranch:[self.repository findLocalBranchWithName:@"master" error:NULL] options:0 error:NULL]);
  [self makeCommitWithUpdatedFileAtPath:@"test.txt" string:@"Bonjour\n" message:@"c4"];
  XCTAssertTrue([self.repository mergeCommitToHEAD:commit3 error:NULL]);
  [self assertGitCLTOutputEqualsString:@"AA test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  GCDiff* indexStatus4 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus4);
  XCTAssertEqual([indexStatus4 changeForFile:@"hello_world.txt"], NSNotFound);
  XCTAssertEqual([indexStatus4 changeForFile:@"test.txt"], kGCFileDiffChange_Conflicted);
  GCDiff* workdirStatus4 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus4);
  XCTAssertEqual([workdirStatus4 changeForFile:@"hello_world.txt"], NSNotFound);
  XCTAssertEqual([workdirStatus4 changeForFile:@"test.txt"], kGCFileDiffChange_Conflicted);
  NSDictionary* conflicts4 = [self.repository checkConflicts:NULL];
  XCTAssertEqual(conflicts4.count, 1);
  XCTAssertEqual([(GCIndexConflict*)conflicts4[@"test.txt"] status], kGCIndexConflictStatus_BothAdded);
}

- (void)testStatus_Modified {
  // Check index
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  GCDiff* indexStatus1 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus1);
  XCTAssertFalse(indexStatus1.modified);
  GCDiff* workdirStatus1 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus1);
  XCTAssertFalse(workdirStatus1.modified);
  
  // Modify file in working directory
  [self updateFileAtPath:@"hello_world.txt" withString:@"Bonjour le monde!\n"];
  XCTAssertTrue([self.repository checkRepositoryDirty:YES]);
  GCDiff* indexStatus2 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus2);
  XCTAssertFalse(indexStatus2.modified);
  GCDiff* workdirStatus2 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus2);
  XCTAssertTrue(workdirStatus2.modified);
  
  // Add file to index
  XCTAssertTrue([self.repository addFileToIndex:@"hello_world.txt" error:NULL]);
  XCTAssertTrue([self.repository checkRepositoryDirty:YES]);
  GCDiff* indexStatus3 = [self.repository checkIndexStatus:NULL];
  XCTAssertNotNil(indexStatus3);
  XCTAssertTrue(indexStatus3.modified);
  GCDiff* workdirStatus3 = [self.repository checkWorkingDirectoryStatus:NULL];
  XCTAssertNotNil(workdirStatus3);
  XCTAssertFalse(workdirStatus3.modified);
}

@end
