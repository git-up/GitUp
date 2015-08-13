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

// TODO: Test -checkoutFileToWorkingDirectory:fromCommit:skipIndex:error:
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
  XCTAssertEqualObjects([self.repository lookupParentsForCommit:emptyCommit error:NULL], @[self.commit3]);
  
  // Create merge commit
  GCCommit* mergeCommit = [self.repository createCommitFromHEADAndOtherParent:self.commitA withMessage:@"Merge" error:NULL];
  XCTAssertNotNil(mergeCommit);
  NSArray* parents = @[emptyCommit, self.commitA];
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

@end
