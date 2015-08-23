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

@implementation GCEmptyRepositoryTests (GCSnapshot)

- (void)testEmptySnapshots {
  // Create snapshot
  GCSnapshot* snapshot = [self.repository takeSnapshot:NULL];
  XCTAssertNotNil(snapshot);
  
  // Make commit
  XCTAssertNotNil([self.repository createCommitFromHEADWithMessage:@"Initial" error:NULL]);
  
  // Restore snapshot
  XCTAssertTrue([self.repository restoreSnapshot:snapshot withOptions:kGCSnapshotOption_IncludeAll reflogMessage:nil didUpdateReferences:NULL error:NULL]);
}

/*
  m0 - m1<master> - m2[origin/master] - m3
    \
    t4(m0) - t5{temp} - t6<topic>
*/
- (void)testRegularSnapshots {
  BOOL didUpdateReferences;
  
  // Create commits
  NSArray* commits = [self.repository createMockCommitHierarchyFromNotation:@"m0 - m1<master> - m2 - m3[origin/master]\nt4(m0) - t5{temp} - t6<topic>" force:NO error:NULL];
  XCTAssertNotNil(commits);
  
  // Save references
  NSString* output1 = [self runGitCLTWithRepository:self.repository command:@"show-ref", @"--head", nil];
  XCTAssertNotNil(output1);
  
  // Create snapshot
  GCSnapshot* snapshot1 = [self.repository takeSnapshot:NULL];
  XCTAssertNotNil(snapshot1);
  
  // Create tag
  XCTAssertTrue([self.repository createLightweightTagWithCommit:commits[0] name:@"test" force:NO error:NULL]);
  
  // Create snapshot
  GCSnapshot* snapshot2 = [self.repository takeSnapshot:NULL];
  XCTAssertNotNil(snapshot2);
  
  // Compare snapshots
  XCTAssertFalse([snapshot1 isEqual:snapshot2]);
  XCTAssertFalse([snapshot2 isEqual:snapshot1]);
  XCTAssertTrue([snapshot1 isEqualToSnapshot:snapshot2 usingOptions:0]);
  XCTAssertTrue([snapshot2 isEqualToSnapshot:snapshot1 usingOptions:0]);
  XCTAssertFalse([snapshot1 isEqualToSnapshot:snapshot2 usingOptions:kGCSnapshotOption_IncludeTags]);
  XCTAssertFalse([snapshot2 isEqualToSnapshot:snapshot1 usingOptions:kGCSnapshotOption_IncludeTags]);
  
  // Switch branch
  XCTAssertTrue([self.repository setHEADToReference:[self.repository findLocalBranchWithName:@"topic" error:NULL] error:NULL]);
  
  // Delete tag
  XCTAssertTrue([self.repository deleteTag:[self.repository findTagWithName:@"temp" error:NULL] error:NULL]);
  
  // Move remote branch
  XCTAssertTrue([self.repository setTipCommit:commits[3] forBranch:[self.repository findRemoteBranchWithName:@"origin/master" error:nil] reflogMessage:nil error:NULL]);
  
  // Verify expected references
  NSString* output2 = [self runGitCLTWithRepository:self.repository command:@"show-ref", @"--head", nil];
  NSString* string1 = [NSString stringWithFormat:@"\
%@ HEAD\n\
%@ refs/heads/master\n\
%@ refs/heads/topic\n\
%@ refs/remotes/origin/master\n\
%@ refs/tags/test\n\
", [commits[6] SHA1], [commits[1] SHA1], [commits[6] SHA1], [commits[3] SHA1], [commits[0] SHA1]];
  XCTAssertEqualObjects(output2, string1);
  
  // Create snapshot
  GCSnapshot* snapshot3 = [self.repository takeSnapshot:NULL];
  XCTAssertNotNil(snapshot3);
  
  // Restore snapshot with all references
  XCTAssertTrue([self.repository restoreSnapshot:snapshot1 withOptions:kGCSnapshotOption_IncludeAll reflogMessage:nil didUpdateReferences:&didUpdateReferences error:NULL]);
  XCTAssertTrue(didUpdateReferences);
  
  // Verify restored references
  NSString* output3 = [self runGitCLTWithRepository:self.repository command:@"show-ref", @"--head", nil];
  XCTAssertEqualObjects(output3, output1);
  
  // Rollback
  XCTAssertTrue([self.repository restoreSnapshot:snapshot3 withOptions:kGCSnapshotOption_IncludeAll reflogMessage:nil didUpdateReferences:NULL error:NULL]);
  
  // Restore snapshot with tags only
  XCTAssertTrue([self.repository restoreSnapshot:snapshot1 withOptions:kGCSnapshotOption_IncludeTags reflogMessage:nil didUpdateReferences:&didUpdateReferences error:NULL]);
  XCTAssertTrue(didUpdateReferences);
  
  // Verify restored references
  NSString* output4 = [self runGitCLTWithRepository:self.repository command:@"show-ref", @"--head", nil];
  NSString* string2 = [NSString stringWithFormat:@"\
%@ HEAD\n\
%@ refs/heads/master\n\
%@ refs/heads/topic\n\
%@ refs/remotes/origin/master\n\
%@ refs/tags/temp\n\
", [commits[6] SHA1], [commits[1] SHA1], [commits[6] SHA1], [commits[3] SHA1], [commits[5] SHA1]];
  XCTAssertEqualObjects(output4, string2);
}

@end

@implementation GCSingleCommitRepositoryTests (GCSnapshot)

- (void)testDeltaSnapshots {
  // Take "from" snapshot
  GCSnapshot* fromSnaphot = [self.repository takeSnapshot:NULL];
  XCTAssertNotNil(fromSnaphot);
  
  // Create topic branch
  GCLocalBranch* branch1 = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"topic1" force:NO error:NULL];
  XCTAssertNotNil(branch1);
  
  // Take "to" snapshot
  GCSnapshot* toSnaphot = [self.repository takeSnapshot:NULL];
  XCTAssertNotNil(toSnaphot);
  
  // Create other topic branch
  GCLocalBranch* branch2 = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"topic2" force:NO error:NULL];
  XCTAssertNotNil(branch2);
  
  // Apply reverse delta
  NSArray* array1 = @[self.masterBranch, branch1, branch2];
  XCTAssertEqualObjects([self.repository listAllBranches:NULL], array1  );
  XCTAssertTrue([self.repository applyDeltaFromSnapshot:toSnaphot toSnapshot:fromSnaphot withOptions:(kGCSnapshotOption_IncludeHEAD | kGCSnapshotOption_IncludeLocalBranches | kGCSnapshotOption_IncludeTags) reflogMessage:nil didUpdateReferences:NULL error:NULL]);
  NSArray* array2 = @[self.masterBranch, branch2];
  XCTAssertEqualObjects([self.repository listAllBranches:NULL], array2);
}

@end
