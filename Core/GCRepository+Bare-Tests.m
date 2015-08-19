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

@implementation GCSingleCommitRepositoryTests (GCRepository_Bare)

/*
  c0 -> c1 -> c2(R) -> c3(P) (master)
   \
    \-> c4 (topic)
*/
- (void)testBare_Base {
  // Make commit
  GCCommit* commit1 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Bonjour le monde!\n\nHello World!\n" message:@"French"];
  
  // Revert commit
  GCCommit* commit2 = [self.repository revertCommit:commit1 againstCommit:commit1 withAncestorCommit:[[self.repository lookupParentsForCommit:commit1 error:NULL] firstObject] message:@"Revert" conflictHandler:NULL error:NULL];
  XCTAssertNotNil(commit2);
  
  // Cherry pick commit
  GCCommit* commit3 = [self.repository cherryPickCommit:commit1 againstCommit:commit2 withAncestorCommit:[[self.repository lookupParentsForCommit:commit1 error:NULL] firstObject] message:@"Pick" conflictHandler:NULL error:NULL];
  XCTAssertNotNil(commit3);
  
  // Update branch
  XCTAssertTrue([self.repository setTipCommit:commit3 forBranch:self.masterBranch reflogMessage:nil error:NULL]);
  
  // Check head is up-to-date
  XCTAssertEqualObjects([self.repository lookupHEAD:NULL error:NULL], commit3);
  
  // Create topic branch and switch to it
  GCLocalBranch* topicBranch = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"topic" force:NO error:NULL];
  XCTAssertNotNil(topicBranch);
  XCTAssertTrue([self.repository checkoutLocalBranch:topicBranch options:0 error:NULL]);
  
  // Make commit
  GCCommit* commit4 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Hello World!\n\nGutten Tag Welt!\n" message:@"German"];
  
  // Switch back to master
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
  
  // Analyze merge topic on master
  GCCommit* ancestor;
  GCMergeAnalysisResult result = [self.repository analyzeMergingCommit:commit4 intoCommit:commit3 ancestorCommit:&ancestor error:NULL];  // This calls -findMergeBaseForCommits:error:
  XCTAssertEqual(result, kGCMergeAnalysisResult_Normal);
  XCTAssertEqualObjects(ancestor, self.initialCommit);
  
  // Merge topic on master
  GCCommit* commit5 = [self.repository mergeCommit:commit4 intoCommit:commit3 withAncestorCommit:ancestor message:@"Merge" conflictHandler:NULL error:NULL];
  XCTAssertNotNil(commit5);
  
  // Replay commit
  GCCommit* commit6 = [self.repository replayCommit:commit4 ontoCommit:commit3 withAncestorCommit:[[self.repository lookupParentsForCommit:commit4 error:NULL] firstObject] updatedMessage:nil updatedParents:@[commit3] updateCommitter:YES skipIdentical:NO conflictHandler:NULL error:NULL];
  XCTAssertNotNil(commit6);
  
  // Copy commit
  GCCommit* commit7 = [self.repository copyCommit:commit5 withUpdatedMessage:@"Merge 2" updatedParents:nil updatedTreeFromIndex:nil updateCommitter:YES error:NULL];
  XCTAssertNotNil(commit7);
  
  // Squash commit
  GCCommit* commit8 = [self.repository squashCommitOntoParent:commit1 withUpdatedMessage:nil error:NULL];
  XCTAssertNotNil(commit8);
  
  // Replay mainline commits
  GCCommit* commit9 = [self.repository replayMainLineParentsFromCommit:commit3 uptoCommit:self.initialCommit ontoCommit:commit4 preserveMerges:NO updateCommitter:YES skipIdentical:NO conflictHandler:NULL error:NULL];
  XCTAssertEqualObjects(commit9.summary, @"Pick");
  NSArray* parents = [self.repository lookupParentsForCommit:commit9 error:NULL];
  XCTAssertEqual(parents.count, 1);
  XCTAssertEqualObjects([(GCCommit*)parents[0] summary], @"Revert");
  NSArray* grandParents = [self.repository lookupParentsForCommit:parents[0] error:NULL];
  XCTAssertEqual(grandParents.count, 1);
  XCTAssertEqualObjects([(GCCommit*)grandParents[0] summary], @"French");
  NSArray* grandGrandParents = [self.repository lookupParentsForCommit:grandParents[0] error:NULL];
  XCTAssertEqual(grandGrandParents.count, 1);
  XCTAssertEqualObjects(grandGrandParents[0], commit4);
}

- (void)testBare_Replay {
  // Make commits
  GCCommit* commit1 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"1\n" message:@"1"];
  [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"2\n" message:@"2"];
  
  sleep(1);  // Make sure timestamp has changed and committer signature will be different
  
  // Copy commit
  GCCommit* commitA = [self.repository copyCommit:commit1 withUpdatedMessage:nil updatedParents:@[self.initialCommit] updatedTreeFromIndex:nil updateCommitter:YES error:NULL];
  XCTAssertNotNil(commitA);
  XCTAssertTrue([self.repository resetToCommit:commitA mode:kGCResetMode_Hard error:NULL]);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"1\n"];
  
  // Replay commit
  GCCommit* commitB = [self.repository replayCommit:commit1 ontoCommit:self.initialCommit withAncestorCommit:self.initialCommit updatedMessage:nil updatedParents:@[self.initialCommit] updateCommitter:YES skipIdentical:YES conflictHandler:NULL error:NULL];
  XCTAssertNotNil(commitB);
  XCTAssertNotEqual(commitB, commit1);  // Verify not skipped
  XCTAssertTrue([self.repository resetToCommit:commitB mode:kGCResetMode_Hard error:NULL]);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"1\n"];
  
  // Replay commit (skip)
  GCCommit* commit3 = [self.repository cherryPickCommit:commit1 againstCommit:self.initialCommit withAncestorCommit:self.initialCommit message:@"Pick" conflictHandler:NULL error:NULL];
  XCTAssertNotNil(commit3);
  GCCommit* commitC = [self.repository replayCommit:commit1 ontoCommit:commit3 withAncestorCommit:self.initialCommit updatedMessage:nil updatedParents:@[self.initialCommit] updateCommitter:YES skipIdentical:NO conflictHandler:NULL error:NULL];
  XCTAssertNotNil(commitC);
  XCTAssertNotEqual(commitC, commit3);  // Verify not skipped
  GCCommit* commitD = [self.repository replayCommit:commit1 ontoCommit:commit3 withAncestorCommit:self.initialCommit updatedMessage:nil updatedParents:@[self.initialCommit] updateCommitter:YES skipIdentical:YES conflictHandler:NULL error:NULL];
  XCTAssertNotNil(commitD);
  XCTAssertEqual(commitD, commit3);  // Verify skipped
  XCTAssertTrue([self.repository resetToCommit:commitD mode:kGCResetMode_Hard error:NULL]);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"1\n"];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"

- (void)testBare_ResolveConflicts {
  // Make commits
  GCCommit* commit1 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"1\n" message:@"1"];
  GCLocalBranch* topicBranch = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"topic" force:NO error:NULL];
  XCTAssertNotNil(topicBranch);
  XCTAssertTrue([self.repository checkoutLocalBranch:topicBranch options:0 error:NULL]);
  GCCommit* commit2 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"2\n" message:@"2"];
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
  
  // Merge topic branch (don't handle conflicts)
  XCTAssertNil([self.repository mergeCommit:commit2 intoCommit:commit1 withAncestorCommit:self.initialCommit message:@"MERGE" conflictHandler:NULL error:NULL]);
  
  // Merge topic branch (cancel conflict resolution)
  XCTAssertNil([self.repository mergeCommit:commit2 intoCommit:commit1 withAncestorCommit:self.initialCommit message:@"MERGE" conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError) {
    return nil;
  } error:NULL]);
  
  // Merge topic branch (don't resolve conflict)
  XCTAssertNil([self.repository mergeCommit:commit2 intoCommit:commit1 withAncestorCommit:self.initialCommit message:@"MERGE" conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError) {
    BOOL success = [self.repository checkoutIndex:index withOptions:0 error:NULL];
    XCTAssertEqual(success, YES);  // Why is XCTAssertTrue() not working here?
    return [self.repository createCommitFromHEADAndOtherParent:parentCommits[1] withMessage:message error:NULL];
  } error:NULL]);
  
  // Reset
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:kGCCheckoutOption_Force error:NULL]);
  
  // Merge topic branch (don't resolve conflict)
  XCTAssertNotNil([self.repository mergeCommit:commit2 intoCommit:commit1 withAncestorCommit:self.initialCommit message:@"MERGE" conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError) {
    XCTAssertEqual(parentCommits.count, 2);
    XCTAssertEqualObjects(parentCommits[0], commit1);
    XCTAssertEqualObjects(parentCommits[1], commit2);
    BOOL success = [self.repository checkoutCommit:parentCommits[0] options:0 error:NULL]
      && [self.repository checkoutIndex:index withOptions:0 error:NULL]
      && [self.repository addAllFilesToIndex:NULL];
    XCTAssertEqual(success, YES);  // Why is XCTAssertTrue() not working here?
    return [self.repository createCommitFromHEADAndOtherParent:parentCommits[1] withMessage:message error:NULL];
  } error:NULL]);
}

#pragma clang diagnostic pop

@end

@implementation GCMultipleCommitsRepositoryTests (GCRepository_Bare)

// TODO: Test kGCCommitRelation_Unrelated
- (void)testBare_Relations {
  XCTAssertEqual([self.repository findRelationOfCommit:self.initialCommit relativeToCommit:self.initialCommit error:NULL], kGCCommitRelation_Identical);
  XCTAssertEqual([self.repository findRelationOfCommit:self.commit3 relativeToCommit:self.commit1 error:NULL], kGCCommitRelation_Descendant);
  XCTAssertEqual([self.repository findRelationOfCommit:self.commit1 relativeToCommit:self.commit3 error:NULL], kGCCommitRelation_Ancestor);
  XCTAssertEqual([self.repository findRelationOfCommit:self.commitA relativeToCommit:self.commit2 error:NULL], kGCCommitRelation_Cousin);
}

@end
