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

@implementation GCSingleCommitRepositoryTests (GCTag)

- (void)testTags {
  // Test valid names
  XCTAssertTrue([GCRepository isValidTagName:@"My_Tag"]);
  XCTAssertFalse([GCRepository isValidTagName:@"^Tag%"]);
  
  // Create lightweight tag (should fail)
  XCTAssertNil([self.repository createLightweightTagWithCommit:self.initialCommit name:@"^Tag%" force:NO error:NULL]);
  
  // Create lightweight tag (should pass)
  GCTag* tag1 = [self.repository createLightweightTagWithCommit:self.initialCommit name:@"Mark" force:NO error:NULL];
  XCTAssertNotNil(tag1);
  XCTAssertEqualObjects([self.repository lookupCommitForTag:tag1 annotation:NULL error:NULL], self.initialCommit);
  XCTAssertEqualObjects([self.repository findTagWithName:@"Mark" error:NULL], tag1);
  
  // Create annotated tag
  GCTag* tag2 = [self.repository createAnnotatedTagWithCommit:self.initialCommit name:@"Demo" message:@"This is a test" force:NO annotation:NULL error:NULL];
  GCTagAnnotation* annotation;
  XCTAssertEqualObjects([self.repository lookupCommitForTag:tag2 annotation:&annotation error:NULL], self.initialCommit);
  XCTAssertEqualObjects(annotation.message, @"This is a test\n");
  XCTAssertEqualObjects([self.repository findTagWithName:@"Demo" error:NULL], tag2);
  
  // Delete tag
  XCTAssertTrue([self.repository deleteTag:tag2 error:NULL]);
  
  // Re-create annotated tag
  GCTag* tag3 = [self.repository createAnnotatedTagWithAnnotation:annotation force:NO error:NULL];
  XCTAssertNotNil(tag3);
  
  // Check tags
  [self assertGitCLTOutputEqualsString:@"Demo\nMark\n" withRepository:self.repository command:@"tag", nil];
  NSArray* tags1 = @[tag3, tag1];
  XCTAssertEqualObjects([self.repository listTags:NULL], tags1);
  
  // Rename tag
  XCTAssertTrue([self.repository setName:@"TEST" forTag:tag1 force:NO error:NULL]);
  XCTAssertEqualObjects([self.repository findTagWithName:@"TEST" error:NULL], tag1);
  
  // Check tags
  [self assertGitCLTOutputEqualsString:@"Demo\nTEST\n" withRepository:self.repository command:@"tag", nil];
  NSArray* tags2 = @[tag3, tag1];
  XCTAssertEqualObjects([self.repository listTags:NULL], tags2);
}

@end
