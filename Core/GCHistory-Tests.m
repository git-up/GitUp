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

@implementation GCSQLiteRepositoryTests (GCHistory)

/*
  0---1----2----4----7 (master)
       \         \
        3----5----6----8 (topic)
*/
- (void)testHistory_Snapshots {
  // Create commit history
  NSArray* commits = [self.repository createMockCommitHierarchyFromNotation:@"0 1(0) 2(1) 3(1) 4(2) 5(3) 6(5,4) 7(4)<master> 8(6)<topic>" force:NO error:NULL];
  XCTAssertNotNil(commits);
  
  // Take snapshot
  GCSnapshot* snapshot = [self.repository takeSnapshot:NULL];
  XCTAssertNotNil(snapshot);
  
  // Check history in reverse chronological order
  GCHistory* historyTime = [self.repository loadHistoryFromSnapshot:snapshot usingSorting:kGCHistorySorting_ReverseChronological error:NULL];
  XCTAssertNotNil(historyTime);
  NSMutableArray* commitsTime = [NSMutableArray array];
  for (GCCommit* commit in commits) {
    [commitsTime insertObject:commit atIndex:0];
  }
  XCTAssertEqualObjects(historyTime.allCommits, commitsTime);
  NSArray* roots = @[commits[0]];
  XCTAssertEqualObjects(historyTime.rootCommits, roots);
  NSArray* leaves = @[commits[8], commits[7]];
  XCTAssertEqualObjects(historyTime.leafCommits, leaves);
}

/*
  0---1----2----4----7 (master)
       \         \
        3----5----6----8 (topic)
*/
- (void)testHistory_Order {
  // Create commit history
  NSArray* commits = [self.repository createMockCommitHierarchyFromNotation:@"0 1(0) 2(1) 3(1) 4(2) 5(3) 6(5,4) 7(4)<master> 8(6)<topic>" force:NO error:NULL];
  XCTAssertNotNil(commits);
  
  // Check history in reverse chronological order
  GCHistory* historyTime = [self.repository loadHistoryUsingSorting:kGCHistorySorting_ReverseChronological error:NULL];
  XCTAssertNotNil(historyTime);
  NSMutableArray* commitsTime = [NSMutableArray array];
  for (GCCommit* commit in commits) {
    [commitsTime insertObject:commit atIndex:0];
  }
  XCTAssertEqualObjects(historyTime.allCommits, commitsTime);
  NSArray* roots = @[commits[0]];
  XCTAssertEqualObjects(historyTime.rootCommits, roots);
  NSArray* leaves = @[commits[8], commits[7]];
  XCTAssertEqualObjects(historyTime.leafCommits, leaves);
}

/*
  0---1----2----4----7 (master)
       \   |     \
        3----5----6----8 (topic)
           |            \
           |-------------9 (test)
*/
- (void)testHistory_Enumeration {
  // Create commit history
  NSArray* commits = [self.repository createMockCommitHierarchyFromNotation:@"0 1(0) 2(1) 3(1) 4(2) 5(3) 6(5,4) 7(4)<master> 8(6)<topic> 9(8,2)<test>" force:NO error:NULL];
  XCTAssertNotNil(commits);
  
  // Load history
  GCHistory* history = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history);
  
  // Check walking entire history through children
  NSMutableArray* walk2 = [NSMutableArray array];
  [history walkAllCommitsFromRootsUsingBlock:^(GCHistoryCommit* commit, BOOL* stop) {
    [walk2 addObject:commit];
  }];
  NSArray* array2 = @[commits[0], commits[1], commits[2], commits[3], commits[4], commits[5], commits[6], commits[7], commits[8], commits[9]];
  XCTAssertTrue([walk2 isEqualToArray:array2]);
  
  // Check walking history through children from commit #2
  NSMutableArray* walk3 = [NSMutableArray array];
  [history walkDescendantsOfCommits:@[[history historyCommitForCommit:commits[2]]] usingBlock:^(GCHistoryCommit* commit, BOOL* stop) {
    [walk3 addObject:commit];
  }];
  NSArray* array3 = @[commits[4], commits[7], commits[6], commits[8], commits[9]];
  XCTAssertEqualObjects(walk3, array3);
  
  // Check walking entire history through parents
  NSMutableArray* walk4 = [NSMutableArray array];
  [history walkAllCommitsFromLeavesUsingBlock:^(GCHistoryCommit* commit, BOOL* stop) {
    [walk4 addObject:commit];
  }];
  NSArray* array4 = @[commits[7], commits[9], commits[8], commits[6], commits[4], commits[5], commits[2], commits[3], commits[1], commits[0]];
  XCTAssertTrue([walk4 isEqualToArray:array4]);
  
  // Check walking history through parents from commit #8
  NSMutableArray* walk5 = [NSMutableArray array];
  [history walkAncestorsOfCommits:@[[history historyCommitForCommit:commits[8]]] usingBlock:^(GCHistoryCommit* commit, BOOL* stop) {
    [walk5 addObject:commit];
  }];
  NSArray* array5 = @[commits[6], commits[5], commits[3], commits[4], commits[2], commits[1], commits[0]];
  XCTAssertEqualObjects(walk5, array5);
  
  // Check walking history through children from commit #6
  NSMutableArray* walk6 = [NSMutableArray array];
  [history walkDescendantsOfCommits:@[[history historyCommitForCommit:commits[6]]] usingBlock:^(GCHistoryCommit* commit, BOOL* stop) {
    [walk6 addObject:commit];
  }];
  NSArray* array6 = @[commits[8], commits[9]];
  XCTAssertEqualObjects(walk6, array6);
  
  // Check counting ancestors
  XCTAssertEqual([history countAncestorCommitsFromCommit:[history historyCommitForCommit:commits[9]] toCommit:[history historyCommitForCommit:commits[6]]], 2);
  XCTAssertEqual([history countAncestorCommitsFromCommit:[history historyCommitForCommit:commits[9]] toCommit:[history historyCommitForCommit:commits[2]]], 6);
}

@end

@implementation GCSingleCommitRepositoryTests (GCHistory)

// TODO: Test -historyRemoteBranchForLocalBranch:
- (void)testHistory_Reload {
  BOOL referencesDidChange;
  NSArray* addedCommits;
  NSArray* removedCommits;
  
  // Make a commit
  GCCommit* commit1 = [self.repository createCommitFromHEADWithMessage:@"1" error:NULL];
  XCTAssertNotNil(commit1);
  
  // Revert commit
  GCCommit* commit2 = [self.repository createCommitFromHEADWithMessage:@"2" error:NULL];
  XCTAssertNotNil(commit2);
  XCTAssertEqual(self.repository.state, kGCRepositoryState_None);
  
  // Create local branch and check it out
  GCLocalBranch* topicBranch = [self.repository createLocalBranchFromCommit:commit1 withName:@"topic" force:NO error:NULL];
  XCTAssertNotNil(topicBranch);
  XCTAssertTrue([self.repository checkoutLocalBranch:topicBranch options:0 error:NULL]);
  
  // Make a commit
  GCCommit* commit3 = [self.repository createCommitFromHEADWithMessage:@"3" error:NULL];
  XCTAssertNotNil(commit3);
  
  /*
    c0 -> c1 -> c2 (master)
           \
            \-> c3 (topic*)
  */
  
  // Check history
  GCHistory* history = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  NSSet* commits = [NSSet setWithObjects:commit3, commit1, commit2, self.initialCommit, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.allCommits], commits);
  XCTAssertEqualObjects(history.rootCommits, @[self.initialCommit]);
  NSSet* leaves = [NSSet setWithObjects:commit2, commit3, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.leafCommits], leaves);
  XCTAssertFalse([[history historyCommitForCommit:self.initialCommit] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:self.initialCommit] parents], @[]);
  XCTAssertEqualObjects([[history historyCommitForCommit:self.initialCommit] children], @[commit1]);
  XCTAssertFalse([[history historyCommitForCommit:commit1] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit1] parents], @[self.initialCommit]);
  NSSet* children = [NSSet setWithObjects:commit2, commit3, nil];
  XCTAssertEqualObjects([NSSet setWithArray:[[history historyCommitForCommit:commit1] children]], children);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] localBranches], @[self.masterBranch]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] parents], @[commit1]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] children], @[]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit3] localBranches], @[topicBranch]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit3] parents], @[commit1]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit3] children], @[]);
  XCTAssertEqualObjects([history historyLocalBranchForLocalBranch:topicBranch], topicBranch);
  
  // Check reloading history without changes
  XCTAssertTrue([self.repository reloadHistory:history referencesDidChange:&referencesDidChange addedCommits:&addedCommits removedCommits:&removedCommits error:NULL]);
  XCTAssertFalse(referencesDidChange);
  XCTAssertEqual(addedCommits.count, 0);
  XCTAssertEqual(removedCommits.count, 0);
  XCTAssertEqualObjects([NSSet setWithArray:history.allCommits], commits);
  
  // Make a couple commits
  GCCommit* commit4 = [self.repository createCommitFromHEADWithMessage:@"4" error:NULL];
  XCTAssertNotNil(commit4);
  GCCommit* commit5 = [self.repository createCommitFromHEADWithMessage:@"5" error:NULL];
  XCTAssertNotNil(commit5);
  
  /*
    c0 -> c1 -> c2 (master)
           \
            \-> c3 -> c4 -> c5 (topic*)
  */
  
  // Check reloading history with new commits
  XCTAssertTrue([self.repository reloadHistory:history referencesDidChange:&referencesDidChange addedCommits:&addedCommits removedCommits:&removedCommits error:NULL]);
  XCTAssertTrue(referencesDidChange);
  XCTAssertEqual(addedCommits.count, 2);
  XCTAssertEqual(removedCommits.count, 0);
  NSSet* commits3 = [NSSet setWithObjects:commit5, commit4, commit3, commit2, commit1, self.initialCommit, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.allCommits], commits3);
  XCTAssertEqualObjects(history.rootCommits, @[self.initialCommit]);
  NSSet* leafs2 = [NSSet setWithObjects:commit2, commit5, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.leafCommits], leafs2);
  XCTAssertFalse([[history historyCommitForCommit:self.initialCommit] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:self.initialCommit] parents], @[]);
  XCTAssertEqualObjects([[history historyCommitForCommit:self.initialCommit] children], @[commit1]);
  XCTAssertFalse([[history historyCommitForCommit:commit1] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit1] parents], @[self.initialCommit]);
  XCTAssertEqualObjects([NSSet setWithArray:[[history historyCommitForCommit:commit1] children]], children);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] localBranches], @[self.masterBranch]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] parents], @[commit1]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] children], @[]);
  XCTAssertFalse([[history historyCommitForCommit:commit3] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit3] parents], @[commit1]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit3] children], @[commit4]);
  XCTAssertFalse([[history historyCommitForCommit:commit4] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit4] parents], @[commit3]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit4] children], @[commit5]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit5] localBranches], @[topicBranch]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit5] parents], @[commit4]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit5] children], @[]);
  
  // Make a temp branch with a couple commits and fast-forward merge it on master
  GCLocalBranch* tempBranch = [self.repository createLocalBranchFromCommit:commit2 withName:@"temp" force:NO error:NULL];
  XCTAssertNotNil(tempBranch);
  XCTAssertTrue([self.repository checkoutLocalBranch:tempBranch options:0 error:NULL]);
  GCCommit* commit6 = [self.repository createCommitFromHEADWithMessage:@"6" error:NULL];
  XCTAssertNotNil(commit6);
  GCCommit* commit7 = [self.repository createCommitFromHEADWithMessage:@"7" error:NULL];
  XCTAssertNotNil(commit7);
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
  XCTAssertTrue([self.repository resetToCommit:commit7 mode:kGCResetMode_Hard error:NULL]);
  XCTAssertTrue([self.repository checkoutLocalBranch:topicBranch options:0 error:NULL]);
  
  /*
                  /-> c6 -> c7 (temp)
                 /            \
    c0 -> c1 -> c2 -> c6 ---> c7 (master)
           \
            \-> c3 -> c4 -> c5 (topic*)
  */
  
  // Check reloading history with merged branch
  XCTAssertTrue([self.repository reloadHistory:history referencesDidChange:&referencesDidChange addedCommits:&addedCommits removedCommits:&removedCommits error:NULL]);
  XCTAssertTrue(referencesDidChange);
  XCTAssertEqual(addedCommits.count, 2);
  XCTAssertEqual(removedCommits.count, 0);
  NSSet* commits4 = [NSSet setWithObjects:commit7, commit6, commit5, commit4, commit3, commit2, commit1, self.initialCommit, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.allCommits], commits4);
  XCTAssertEqualObjects(history.rootCommits, @[self.initialCommit]);
  NSSet* leafs4 = [NSSet setWithObjects:commit7, commit5, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.leafCommits], leafs4);
  
  // Amend commit
  commit5 = [self.repository copyCommit:commit5 withUpdatedMessage:@"5'" updatedParents:nil updatedTreeFromIndex:nil updateCommitter:YES error:NULL];
  XCTAssertNotNil(commit5);
  XCTAssertTrue([self.repository resetToCommit:commit5 mode:kGCResetMode_Soft error:NULL]);  // Required to update HEAD and branch
  
  /*
                  /-> c6 -> c7 (temp)
                 /            \
    c0 -> c1 -> c2 -> c6 ---> c7 (master)
           \
            \-> c3 -> c4 -> c5' (topic*)
  */
  
  // Check reloading history with rewritten commit
  XCTAssertTrue([self.repository reloadHistory:history referencesDidChange:&referencesDidChange addedCommits:&addedCommits removedCommits:&removedCommits error:NULL]);
  XCTAssertTrue(referencesDidChange);
  XCTAssertEqual(addedCommits.count, 1);
  XCTAssertEqual(removedCommits.count, 1);
  NSSet* commits5 = [NSSet setWithObjects:commit7, commit6, commit5, commit4, commit3, commit2, commit1, self.initialCommit, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.allCommits], commits5);
  XCTAssertEqualObjects(history.rootCommits, @[self.initialCommit]);
  NSSet* leafs5 = [NSSet setWithObjects:commit7, commit5, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.leafCommits], leafs5);
  XCTAssertFalse([[history historyCommitForCommit:self.initialCommit] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:self.initialCommit] parents], @[]);
  XCTAssertEqualObjects([[history historyCommitForCommit:self.initialCommit] children], @[commit1]);
  XCTAssertFalse([[history historyCommitForCommit:commit1] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit1] parents], @[self.initialCommit]);
  XCTAssertEqualObjects([NSSet setWithArray:[[history historyCommitForCommit:commit1] children]], children);
  XCTAssertFalse([[history historyCommitForCommit:commit2] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] parents], @[commit1]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] children], @[commit6]);
  XCTAssertFalse([[history historyCommitForCommit:commit3] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit3] parents], @[commit1]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit3] children], @[commit4]);
  XCTAssertFalse([[history historyCommitForCommit:commit4] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit4] parents], @[commit3]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit4] children], @[commit5]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit5] localBranches], @[topicBranch]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit5] parents], @[commit4]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit5] children], @[]);
  XCTAssertFalse([[history historyCommitForCommit:commit6] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit6] parents], @[commit2]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit6] children], @[commit7]);
  NSSet* references = [NSSet setWithObjects:self.masterBranch, tempBranch, nil];
  XCTAssertEqualObjects([NSSet setWithArray:[[history historyCommitForCommit:commit7] localBranches]], references);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit7] parents], @[commit6]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit7] children], @[]);
  
  /*
            c2 -> c6 -> c7 (temp)
           /
    c0 -> c1 (master)
  */
  
  // Switch back to master branch, reset to commit 1 and delete topic branch
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
  XCTAssertTrue([self.repository resetToCommit:commit1 mode:kGCResetMode_Hard error:NULL]);
  XCTAssertTrue([self.repository deleteLocalBranch:topicBranch error:NULL]);
  XCTAssertTrue([self.repository reloadHistory:history referencesDidChange:&referencesDidChange addedCommits:&addedCommits removedCommits:&removedCommits error:NULL]);
  XCTAssertTrue(referencesDidChange);
  XCTAssertEqual(addedCommits.count, 0);
  XCTAssertEqual(removedCommits.count, 3);
  NSSet* commits6 = [NSSet setWithObjects:commit7, commit6, commit2, commit1, self.initialCommit, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.allCommits], commits6);
  XCTAssertEqualObjects(history.rootCommits, @[self.initialCommit]);
  XCTAssertEqualObjects(history.leafCommits, @[commit7]);
  XCTAssertFalse([[history historyCommitForCommit:self.initialCommit] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:self.initialCommit] parents], @[]);
  XCTAssertEqualObjects([[history historyCommitForCommit:self.initialCommit] children], @[commit1]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit1] localBranches], @[self.masterBranch]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit1] parents], @[self.initialCommit]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit1] children], @[commit2]);
  XCTAssertFalse([[history historyCommitForCommit:commit2] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] parents], @[commit1]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] children], @[commit6]);
  XCTAssertFalse([[history historyCommitForCommit:commit6] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit6] parents], @[commit2]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit6] children], @[commit7]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit7] localBranches], @[tempBranch]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit7] parents], @[commit6]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit7] children], @[]);
  
  // Add a branch
  GCLocalBranch* test = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"test" force:NO error:NULL];
  XCTAssertNotNil(test);
  XCTAssertTrue([self.repository checkoutLocalBranch:test options:0 error:NULL]);
  GCCommit* commit8 = [self.repository createCommitFromHEADWithMessage:@"8" error:NULL];
  XCTAssertNotNil(commit8);
  
  /*
            c2 -> c6 -> c7 (temp)
           /
    c0 -> c1 (master)
     \
      c8 (test)
  */
  
  // Reload history with new branch
  XCTAssertTrue([self.repository reloadHistory:history referencesDidChange:&referencesDidChange addedCommits:&addedCommits removedCommits:&removedCommits error:NULL]);
  XCTAssertTrue(referencesDidChange);
  XCTAssertEqual(addedCommits.count, 1);
  XCTAssertEqual(removedCommits.count, 0);
  NSSet* commits7 = [NSSet setWithObjects:commit8, commit7, commit6, commit2, commit1, self.initialCommit, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.allCommits], commits7);
  XCTAssertEqualObjects(history.rootCommits, @[self.initialCommit]);
  NSSet* leafs6 = [NSSet setWithObjects:commit8, commit7, nil];
  XCTAssertEqualObjects([NSSet setWithArray:history.leafCommits], leafs6);
  XCTAssertFalse([[history historyCommitForCommit:self.initialCommit] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:self.initialCommit] parents], @[]);
  NSSet* children2 = [NSSet setWithObjects:commit8, commit1, nil];
  XCTAssertEqualObjects([NSSet setWithArray:[[history historyCommitForCommit:self.initialCommit] children]], children2);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit1] localBranches], @[self.masterBranch]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit1] parents], @[self.initialCommit]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit1] children], @[commit2]);
  XCTAssertFalse([[history historyCommitForCommit:commit2] hasReferences]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] parents], @[commit1]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit2] children], @[commit6]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit6] parents], @[commit2]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit6] children], @[commit7]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit7] parents], @[commit6]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit7] children], @[]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit8] parents], @[self.initialCommit]);
  XCTAssertEqualObjects([[history historyCommitForCommit:commit8] children], @[]);
}

- (void)testHistory_Tags {
  // Make some commits
  GCCommit* commit1 = [self.repository createCommitFromHEADWithMessage:@"1" error:NULL];
  XCTAssertNotNil(commit1);
  GCCommit* commit2 = [self.repository createCommitFromHEADWithMessage:@"2" error:NULL];
  XCTAssertNotNil(commit2);
  
  // Create tags
  GCTag* tag1 = [self.repository createLightweightTagWithCommit:commit1 name:@"Lightweight_Tag" force:NO error:NULL];
  XCTAssertNotNil(tag1);
  GCTagAnnotation* annotation;
  GCTag* tag2 = [self.repository createAnnotatedTagWithCommit:commit2 name:@"Annotated_Tag" message:@"This is a test" force:NO annotation:&annotation error:NULL];
  XCTAssertNotNil(tag2);
  
  // Load history
  GCHistory* history = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history);
  
  // Check tags
  NSArray* tags = @[tag2, tag1];
  XCTAssertEqualObjects(history.tags, tags);
  XCTAssertEqualObjects([(GCHistoryTag*)history.tags[0] commit], commit2);
  XCTAssertEqualObjects([(GCHistoryTag*)history.tags[0] annotation], annotation);
  XCTAssertEqualObjects([(GCHistoryTag*)history.tags[1] commit], commit1);
  XCTAssertNil([(GCHistoryTag*)history.tags[1] annotation]);
}

- (void)testHistory_Files {
  // Make a commit
  NSMutableArray* lines = [NSMutableArray array];
  for (NSUInteger i = 0; i < 100; ++i) {
    [lines addObject:[NSString stringWithFormat:@"GILine %lu", (unsigned long)i]];
  }
  GCCommit* commit1 = [self makeCommitWithUpdatedFileAtPath:@"lines.txt" string:[lines componentsJoinedByString:@"\n"] message:@"0) Added"];
  
  // Make a commit
  [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Bonjour le monde!\n" message:@"French"];
  
  // Make a commit
  [lines removeObjectAtIndex:50];
  GCCommit* commit3 = [self makeCommitWithUpdatedFileAtPath:@"lines.txt" string:[lines componentsJoinedByString:@"\n"] message:@"1) Modified"];
  
  // Make a commit
  [lines removeObjectAtIndex:10];
  [lines removeObjectAtIndex:90];
  [self updateFileAtPath:@"lines2.txt" withString:[lines componentsJoinedByString:@"\n" ]];
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"lines.txt"] error:NULL]);
  XCTAssertTrue([self.repository removeFileFromIndex:@"lines.txt" error:NULL]);
  XCTAssertTrue([self.repository addFileToIndex:@"lines2.txt" error:NULL]);
  GCCommit* commit4 = [self.repository createCommitFromHEADWithMessage:@"2) Modified and renamed" error:NULL];
  XCTAssertNotNil(commit4);
  
  // Make a commit
  [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Guten Tag Welt!\n" message:@"German"];
  
  // Make a commit
  [lines insertObject:@"Prelude" atIndex:0];
  [lines addObject:@"Postlude"];
  GCCommit* commit6 = [self makeCommitWithUpdatedFileAtPath:@"lines2.txt" string:[lines componentsJoinedByString:@"\n"] message:@"3) Modified"];
  
  // Check file history (no follow)
  NSArray* commits1 = [self.repository lookupCommitsForFile:@"lines2.txt" followRenames:NO error:NULL];
  NSArray* array1 = @[commit6, commit4];
  XCTAssertEqualObjects(commits1, array1);
  
  // Check file history (follow)
  NSArray* commits2 = [self.repository lookupCommitsForFile:@"lines2.txt" followRenames:YES error:NULL];
  NSArray* array2 = @[commit6, commit4, commit3, commit1];
  XCTAssertEqualObjects(commits2, array2);
}

@end

@implementation GCEmptyRepositoryTests (GCHistory)

- (void)testHistory_Empty {
  GCHistory* history = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history);
  XCTAssertTrue(history.empty);
}

@end
