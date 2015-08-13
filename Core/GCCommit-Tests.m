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

@implementation GCSingleCommitRepositoryTests (GCCommit)

- (void)testCommits {
  // Make a commit
  GCCommit* commit = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Bonjour le monde!\n" message:@"Test"];
  XCTAssertEqualObjects([self.repository findCommitWithSHA1:commit.SHA1 error:NULL], commit);
  XCTAssertNil([self.repository findCommitWithSHA1:@"123456" error:NULL]);
  XCTAssertEqualObjects([self.repository findCommitWithSHA1Prefix:commit.shortSHA1 error:NULL], commit);
  XCTAssertEqualObjects([self.repository lookupParentsForCommit:commit error:NULL], @[self.initialCommit]);
  
  // Check short-SHA computation
  [self assertGitCLTOutputEqualsString:[NSString stringWithFormat:@"%@\n", [self.repository computeUniqueShortSHA1ForCommit:commit error:NULL]] withRepository:self.repository command:@"rev-parse", @"--short", @"HEAD", nil];
  
  // Check file in commmit
  XCTAssertNotNil([self.repository checkTreeForCommit:commit containsFile:@"hello_world.txt" error:NULL]);
  XCTAssertNil([self.repository checkTreeForCommit:commit containsFile:@"missing.txt" error:NULL]);
}

@end
