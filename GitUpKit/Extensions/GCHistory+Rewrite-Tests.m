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
#import "GCHistory+Rewrite.h"
#import "GCRepository+Utilities.h"

// TODO: Test updating detached HEAD and references
@implementation GCSingleCommitRepositoryTests (GCHistory_Rewrite)

/*
  c0 -> c1 -> c2 -> c3 (master)
   \
    \-> c4 (topic)
*/
- (void)testRewrite {
  GCReferenceTransform* transform;
  
  // Make a commit
  GCCommit* commit1 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"A\n\nB\n\nC\n" message:@"1"];
  
  // Make another commit
  GCCommit* commit2 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"A\n\nB'\n\nC\n" message:@"2"];
  
  // Make another commit
  GCCommit* commit3 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"A\n\nB'\n\nC'\n" message:@"3"];
  
  // Create topic branch with temp commit
  GCLocalBranch* topicBranch = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"topic" force:NO error:NULL];
  XCTAssertNotNil(topicBranch);
  XCTAssertTrue([self.repository checkoutLocalBranch:topicBranch options:0 error:NULL]);
  GCCommit* commit4 = [self makeCommitWithUpdatedFileAtPath:@"test.txt" string:@"TEST" message:@"T"];
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
  
  // Load history
  GCHistory* history = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history);
  
  // Edit commit message
  GCCommit* newCommit = [self.repository copyCommit:commit1 withUpdatedMessage:@"TEST" updatedParents:nil updatedTreeFromIndex:nil updateCommitter:YES error:NULL];
  XCTAssertNotNil(newCommit);
  transform = [history rewriteCommit:[history historyCommitForCommit:commit1] withUpdatedCommit:newCommit copyTrees:YES conflictHandler:NULL error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  [self assertGitCLTOutputEqualsString:@"3\n2\nTEST\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"A\n\nB'\n\nC'\n"];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit3 mode:kGCResetMode_Hard error:NULL]);
  
  // Delete commit
  transform = [history deleteCommit:[history historyCommitForCommit:commit2] withConflictHandler:NULL error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  XCTAssertTrue([self.repository forceCheckoutHEAD:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@"3\n1\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"A\n\nB\n\nC'\n"];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit3 mode:kGCResetMode_Hard error:NULL]);
  
  // Fixup commit
  transform = [history fixupCommit:[history historyCommitForCommit:commit2] newCommit:NULL error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  [self assertGitCLTOutputEqualsString:@"3\n1\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"A\n\nB'\n\nC'\n"];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit3 mode:kGCResetMode_Hard error:NULL]);
  
  // Squash commit
  transform = [history squashCommit:[history historyCommitForCommit:commit2] withMessage:@"TEST" newCommit:NULL error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  [self assertGitCLTOutputEqualsString:@"3\nTEST\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"A\n\nB'\n\nC'\n"];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit3 mode:kGCResetMode_Hard error:NULL]);
  
  // Swap commits
  GCCommit* commitA;
  GCCommit* commitB;
  transform = [history swapCommitWithItsParent:[history historyCommitForCommit:commit3] conflictHandler:NULL newChildCommit:&commitA newParentCommit:&commitB error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  XCTAssertNotNil(commitA);
  XCTAssertNotNil(commitB);
  [self assertGitCLTOutputEqualsString:@"2\n3\n1\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"A\n\nB'\n\nC'\n"];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit3 mode:kGCResetMode_Hard error:NULL]);
  
  // Revert commit
  transform = [history revertCommit:[history historyCommitForCommit:commit3] againstBranch:history.localBranches[0] withMessage:@"R" conflictHandler:NULL newCommit:NULL error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  XCTAssertTrue([self.repository forceCheckoutHEAD:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@"R\n3\n2\n1\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"A\n\nB'\n\nC\n"];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit3 mode:kGCResetMode_Hard error:NULL]);
  
  // Cherry-pick commit
  transform = [history cherryPickCommit:[history historyCommitForCommit:commit4] againstBranch:history.localBranches[0] withMessage:@"T" conflictHandler:NULL newCommit:NULL error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  XCTAssertTrue([self.repository forceCheckoutHEAD:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@"T\n3\n2\n1\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"A\n\nB'\n\nC'\n"];
  [self assertContentsOfFileAtPath:@"test.txt" equalsString:@"TEST"];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit3 mode:kGCResetMode_Hard error:NULL]);
  
  // Fast-forward
  transform = [history fastForwardBranch:history.localBranches[0] toCommit:[history historyCommitForCommit:commit4] error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  XCTAssertTrue([self.repository forceCheckoutHEAD:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@"T\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Hello World!\n"];
  [self assertContentsOfFileAtPath:@"test.txt" equalsString:@"TEST"];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit3 mode:kGCResetMode_Hard error:NULL]);
  
  // Merge commit
  GCCommit* ancestorCommit = [self.repository findMergeBaseForCommits:@[[history.localBranches[0] tipCommit], commit4] error:NULL];
  XCTAssertNotNil(ancestorCommit);
  transform = [history mergeCommit:[history historyCommitForCommit:commit4] intoBranch:history.localBranches[0] withAncestorCommit:[history historyCommitForCommit:ancestorCommit] message:@"M" conflictHandler:NULL newCommit:NULL error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  XCTAssertTrue([self.repository forceCheckoutHEAD:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@"M\nT\n3\n2\n1\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", @"--topo-order", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"A\n\nB'\n\nC'\n"];
  [self assertContentsOfFileAtPath:@"test.txt" equalsString:@"TEST"];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit3 mode:kGCResetMode_Hard error:NULL]);
  XCTAssertTrue([self.repository checkoutLocalBranch:topicBranch options:0 error:NULL]);
  
  // Rebase commit
  GCCommit* fromCommit = [self.repository findMergeBaseForCommits:@[[history.localBranches[1] tipCommit], commit3] error:NULL];
  XCTAssertNotNil(fromCommit);
  transform = [history rebaseBranch:history.localBranches[1] fromCommit:[history historyCommitForCommit:fromCommit] ontoCommit:[history historyCommitForCommit:commit3] conflictHandler:NULL newTipCommit:NULL error:NULL];
  XCTAssertNotNil(transform);
  XCTAssertTrue([self.repository applyReferenceTransform:transform error:NULL]);
  XCTAssertTrue([self.repository forceCheckoutHEAD:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@"T\n3\n2\n1\nInitial commit" withRepository:self.repository command:@"log", @"--pretty=format:%s", nil];
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"A\n\nB'\n\nC'\n"];
  [self assertContentsOfFileAtPath:@"test.txt" equalsString:@"TEST"];
}

@end

@implementation GCEmptyRepositoryTests (GCHistory_Rewrite)

/*
  0---1----2----4----7 (master)
       \         \
        3----5----6----8----9----10 (topic)
*/
- (void)testSwapCommits {
  // Create commit history
  NSArray* commits = [self.repository createMockCommitHierarchyFromNotation:@"0 1(0) 2(1) 3(1) 4(2) 5(3) 6(5,4) 7(4)<master> 8(6) 9(8) 10(9)<topic>" force:NO error:NULL];
  XCTAssertNotNil(commits);
  GCHistory* history0 = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history0);
  GCSnapshot* snapshot = [self.repository takeSnapshot:NULL];
  XCTAssertNotNil(snapshot);
  
  // Swap 0
  XCTAssertNil([history0 swapCommitWithItsParent:[history0 mockCommitWithName:@"0"] conflictHandler:NULL newChildCommit:NULL newParentCommit:NULL error:NULL]);
  
  // Swap 1
  XCTAssertNil([history0 swapCommitWithItsParent:[history0 mockCommitWithName:@"1"] conflictHandler:NULL newChildCommit:NULL newParentCommit:NULL error:NULL]);
  
  // Swap 9 and 8
  GCReferenceTransform* transform1 = [history0 swapCommitWithItsParent:[history0 mockCommitWithName:@"9"] conflictHandler:NULL newChildCommit:NULL newParentCommit:NULL error:NULL];
  XCTAssertNotNil(transform1);
  XCTAssertTrue([self.repository applyReferenceTransform:transform1 error:NULL]);
  GCHistory* history1 = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history1);
  XCTAssertEqualObjects([history1 notationFromMockCommitHierarchy], @"0 1(0) 2(1) 3(1) 4(2) 5(3) 6(5,4) 7(4)<master> 8(9) 9(6) 10(8)<topic>");
  
  // Reset
  XCTAssertTrue([self.repository restoreSnapshot:snapshot withOptions:kGCSnapshotOption_IncludeAll reflogMessage:nil didUpdateReferences:NULL error:NULL]);
  
  // Swap 10 and 9
  GCReferenceTransform* transform2 = [history0 swapCommitWithItsParent:[history0 mockCommitWithName:@"10"] conflictHandler:NULL newChildCommit:NULL newParentCommit:NULL error:NULL];
  XCTAssertNotNil(transform2);
  XCTAssertTrue([self.repository applyReferenceTransform:transform2 error:NULL]);
  GCHistory* history2 = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history2);
  XCTAssertEqualObjects([history2 notationFromMockCommitHierarchy], @"0 1(0) 2(1) 3(1) 4(2) 5(3) 6(5,4) 7(4)<master> 8(6) 9(10)<topic> 10(8)");
  
  // Reset
  XCTAssertTrue([self.repository restoreSnapshot:snapshot withOptions:kGCSnapshotOption_IncludeAll reflogMessage:nil didUpdateReferences:NULL error:NULL]);
  
  // Swap 7 and 4
  GCReferenceTransform* transform3 = [history0 swapCommitWithItsParent:[history0 mockCommitWithName:@"7"] conflictHandler:NULL newChildCommit:NULL newParentCommit:NULL error:NULL];
  XCTAssertNotNil(transform3);
  XCTAssertTrue([self.repository applyReferenceTransform:transform3 error:NULL]);
  GCHistory* history3 = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history3);
  XCTAssertEqualObjects([history3 notationFromMockCommitHierarchy], @"0 1(0) 2(1) 3(1) 4(7)<master> 5(3) 6(5,7) 7(2) 8(6) 9(8) 10(9)<topic>");
  
  // Reset
  XCTAssertTrue([self.repository restoreSnapshot:snapshot withOptions:kGCSnapshotOption_IncludeAll reflogMessage:nil didUpdateReferences:NULL error:NULL]);
  
  // Swap 2 and 1
  GCReferenceTransform* transform4 = [history0 swapCommitWithItsParent:[history0 mockCommitWithName:@"2"] conflictHandler:NULL newChildCommit:NULL newParentCommit:NULL error:NULL];
  XCTAssertNotNil(transform4);
  XCTAssertTrue([self.repository applyReferenceTransform:transform4 error:NULL]);
  GCHistory* history4 = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history4);
  XCTAssertEqualObjects([history4 notationFromMockCommitHierarchy], @"0 1(2) 2(0) 3(2) 4(1) 5(3) 6(5,4) 7(4)<master> 8(6) 9(8) 10(9)<topic>");
}

@end
