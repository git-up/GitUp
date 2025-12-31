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
#import "GCRepository+Utilities.h"
#import "GCRepository+Index.h"

@implementation GCEmptyRepositoryTests (GCRepository_HEAD)

- (void)testUnbornHEAD {
  // Check unborn
  XCTAssertTrue(self.repository.HEADUnborn);

  // Make commit
  XCTAssertNotNil([self.repository createCommitFromHEADWithMessage:@"Initial commit" error:NULL]);

  // Check unborn again
  XCTAssertFalse(self.repository.HEADUnborn);
}

@end

@implementation GCMultipleCommitsRepositoryTests (GCRepository_HEAD)

// -checkoutIndex:withOptions:error: is tested in GCRepository+Bare
- (void)testHEAD {
  // Load HEAD reference
  GCReference* headReference = [self.repository lookupHEADReference:NULL];
  XCTAssertNotNil(headReference);
  XCTAssertTrue(headReference.symbolic);

  // Checkout topic branch
  XCTAssertTrue([self.repository checkoutLocalBranch:self.topicBranch options:kGCCheckoutOption_Force error:NULL]);
  GCLocalBranch* branch1;
  GCCommit* commit1 = [self.repository lookupHEAD:&branch1 error:NULL];
  XCTAssertEqualObjects(commit1, self.commitA);
  XCTAssertEqualObjects(branch1, self.topicBranch);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Goodbye World!\n"];

  // Checkout detached HEAD
  XCTAssertTrue([self.repository checkoutCommit:self.commit2 options:kGCCheckoutOption_Force error:NULL]);
  GCLocalBranch* branch2;
  GCCommit* commit2 = [self.repository lookupHEAD:&branch2 error:NULL];
  XCTAssertEqualObjects(commit2, self.commit2);
  XCTAssertNil(branch2);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Gutentag Welt!\n"];

  // Move HEAD to reference
  XCTAssertTrue([self.repository setHEADToReference:self.topicBranch error:NULL]);
  GCLocalBranch* branch3;
  GCCommit* commit3 = [self.repository lookupHEAD:&branch3 error:NULL];
  XCTAssertEqualObjects(commit3, self.commitA);
  XCTAssertEqualObjects(branch3, self.topicBranch);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Gutentag Welt!\n"];

  // Move HEAD to commit
  XCTAssertTrue([self.repository setDetachedHEADToCommit:self.commit1 error:NULL]);
  GCLocalBranch* branch4;
  GCCommit* commit4 = [self.repository lookupHEAD:&branch4 error:NULL];
  XCTAssertEqualObjects(commit4, self.commit1);
  XCTAssertNil(branch4);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Gutentag Welt!\n"];

  // Checkout HEAD
  XCTAssertTrue([self.repository forceCheckoutHEAD:NO error:NULL]);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Bonjour Monde!\n"];

  // Checkout master branch
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:kGCCheckoutOption_Force error:NULL]);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Hola Mundo!\n"];

  // Create empty commit
  GCCommit* emptyCommit = [self.repository createCommitFromHEADWithMessage:@"Empty" error:NULL];
  XCTAssertNotNil(emptyCommit);
  XCTAssertEqualObjects([self.repository lookupParentsForCommit:emptyCommit error:NULL], @[ self.commit3 ]);

  // Create merge commit
  GCCommit* mergeCommit = [self.repository createCommitFromHEADAndOtherParent:self.commitA withMessage:@"Merge" error:NULL];
  XCTAssertNotNil(mergeCommit);
  NSArray* parents = @[ emptyCommit, self.commitA ];
  XCTAssertEqualObjects([self.repository lookupParentsForCommit:mergeCommit error:NULL], parents);

  // Amend HEAD commit
  [self updateFileAtPath:@"hello_world.txt" withString:@"BONJOUR!"];
  XCTAssertTrue([self.repository addFileToIndex:@"hello_world.txt" error:NULL]);
  GCCommit* amendCommit = [self.repository createCommitByAmendingHEADWithMessage:@"TEST" error:NULL];
  XCTAssertNotNil(amendCommit);
  GCCommit* newHEAD = [self.repository lookupHEAD:NULL error:NULL];
  XCTAssertEqualObjects(newHEAD.message, @"TEST");
  XCTAssertEqualObjects([self.repository lookupParentsForCommit:amendCommit error:NULL], parents);

  // Move HEAD
  XCTAssertTrue([self.repository checkClean:0 error:NULL]);
  XCTAssertTrue([self.repository moveHEADToCommit:self.commit2 reflogMessage:nil error:NULL]);
  XCTAssertFalse([self.repository checkClean:0 error:NULL]);
}

- (void)testCheckoutFileToWorkingDirectory {
  // Working directory should have content from commit3 (master)
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Hola Mundo!\n"];

  // Checkout file from commit1 (earlier version)
  XCTAssertTrue([self.repository checkoutFileToWorkingDirectory:@"hello_world.txt" fromCommit:self.commit1 skipIndex:YES error:NULL]);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Bonjour Monde!\n"];

  // Checkout file from initialCommit
  XCTAssertTrue([self.repository checkoutFileToWorkingDirectory:@"hello_world.txt" fromCommit:self.initialCommit skipIndex:YES error:NULL]);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Hello World!\n"];

  // Checkout file from commit2
  XCTAssertTrue([self.repository checkoutFileToWorkingDirectory:@"hello_world.txt" fromCommit:self.commit2 skipIndex:YES error:NULL]);
  [self assertContentsOfFileAtPath:@"hello_world.txt" equalsString:@"Gutentag Welt!\n"];
}

- (void)testLookupParentsForCommit {
  // Test parent of commit1 is initialCommit
  NSArray* parentsOfCommit1 = [self.repository lookupParentsForCommit:self.commit1 error:NULL];
  XCTAssertEqual(parentsOfCommit1.count, 1);
  XCTAssertEqualObjects(parentsOfCommit1.firstObject, self.initialCommit);

  // Test parent of commit2 is commit1
  NSArray* parentsOfCommit2 = [self.repository lookupParentsForCommit:self.commit2 error:NULL];
  XCTAssertEqual(parentsOfCommit2.count, 1);
  XCTAssertEqualObjects(parentsOfCommit2.firstObject, self.commit1);

  // Test parent of commit3 is commit2
  NSArray* parentsOfCommit3 = [self.repository lookupParentsForCommit:self.commit3 error:NULL];
  XCTAssertEqual(parentsOfCommit3.count, 1);
  XCTAssertEqualObjects(parentsOfCommit3.firstObject, self.commit2);

  // Test parent of commitA is initialCommit (branched from there)
  NSArray* parentsOfCommitA = [self.repository lookupParentsForCommit:self.commitA error:NULL];
  XCTAssertEqual(parentsOfCommitA.count, 1);
  XCTAssertEqualObjects(parentsOfCommitA.firstObject, self.initialCommit);

  // Test parent of initialCommit is empty (root commit)
  NSArray* parentsOfInitial = [self.repository lookupParentsForCommit:self.initialCommit error:NULL];
  XCTAssertEqual(parentsOfInitial.count, 0);
}

- (void)testCheckTreeForCommitContainsFile {
  // hello_world.txt should exist in all commits
  XCTAssertNotNil([self.repository checkTreeForCommit:self.initialCommit containsFile:@"hello_world.txt" error:NULL]);
  XCTAssertNotNil([self.repository checkTreeForCommit:self.commit1 containsFile:@"hello_world.txt" error:NULL]);
  XCTAssertNotNil([self.repository checkTreeForCommit:self.commit2 containsFile:@"hello_world.txt" error:NULL]);
  XCTAssertNotNil([self.repository checkTreeForCommit:self.commit3 containsFile:@"hello_world.txt" error:NULL]);
  XCTAssertNotNil([self.repository checkTreeForCommit:self.commitA containsFile:@"hello_world.txt" error:NULL]);

  // A non-existent file should return nil
  XCTAssertNil([self.repository checkTreeForCommit:self.commit1 containsFile:@"nonexistent.txt" error:NULL]);
}

- (void)testRestoreFileToParentVersion {
  // Create a new file in a new commit
  GCCommit* addCommit = [self makeCommitWithUpdatedFileAtPath:@"new_file.txt" string:@"New Content\n" message:@"Add new file"];
  XCTAssertNotNil(addCommit);
  [self assertContentsOfFileAtPath:@"new_file.txt" equalsString:@"New Content\n"];

  // Verify the file exists in addCommit
  XCTAssertNotNil([self.repository checkTreeForCommit:addCommit containsFile:@"new_file.txt" error:NULL]);

  // Verify the file doesn't exist in commit3 (before addCommit)
  XCTAssertNil([self.repository checkTreeForCommit:self.commit3 containsFile:@"new_file.txt" error:NULL]);

  // Make another commit modifying the file
  GCCommit* modifyCommit = [self makeCommitWithUpdatedFileAtPath:@"new_file.txt" string:@"Modified Content\n" message:@"Modify file"];
  XCTAssertNotNil(modifyCommit);
  [self assertContentsOfFileAtPath:@"new_file.txt" equalsString:@"Modified Content\n"];

  // Restore file to version before modifyCommit (should get addCommit's version)
  NSArray* parentsOfModify = [self.repository lookupParentsForCommit:modifyCommit error:NULL];
  GCCommit* parentCommit = parentsOfModify.firstObject;
  XCTAssertNotNil(parentCommit);
  XCTAssertEqualObjects(parentCommit, addCommit);

  // Checkout file from parent commit
  XCTAssertTrue([self.repository checkoutFileToWorkingDirectory:@"new_file.txt" fromCommit:parentCommit skipIndex:YES error:NULL]);
  [self assertContentsOfFileAtPath:@"new_file.txt" equalsString:@"New Content\n"];
}

@end
