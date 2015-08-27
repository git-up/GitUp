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

@implementation GCEmptyRepositoryTests (GCRepository_Mock)

- (void)testNotation {
  // Create mock commits
  NSString* notation = @"\
m0 - m1<master> - m2 - m3[origin/master] \n\
 \\ \n\
  \\ \n\
  t0(m0) - t1 - t2{temp} - t3 - t4<topic>";
  XCTAssertNotNil([self.repository createMockCommitHierarchyFromNotation:notation force:NO error:NULL]);
  
  // Load history
  GCHistory* history = [self.repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history);
  
  // Dump notation
  XCTAssertEqualObjects([history notationFromMockCommitHierarchy], @"m0 m1(m0)<master> m2(m1) m3(m2)[origin/master] t0(m0) t1(t0) t2(t1){temp} t3(t2) t4(t3)<topic>");
  
  // Check commits
  NSMutableSet* messages = [[NSMutableSet alloc] init];
  for (GCHistoryCommit* commit in history.allCommits) {
    [messages addObject:commit.summary];
  }
  NSSet* set = [NSSet setWithObjects:@"m0", @"m1", @"m2", @"m3", @"t0", @"t1", @"t2", @"t3", @"t4", nil];
  XCTAssertEqualObjects(messages, set);
  
  // Check tags
  XCTAssertEqual(history.tags.count, 1);
  GCHistoryTag* tag = history.tags[0];
  XCTAssertEqualObjects(tag.name, @"temp");
  XCTAssertEqualObjects(tag.commit.message, @"t2");
  
  // Check local branches
  XCTAssertEqual(history.localBranches.count, 2);
  GCHistoryLocalBranch* masterBranch = history.localBranches[0];
  XCTAssertEqualObjects(masterBranch.name, @"master");
  XCTAssertEqualObjects(masterBranch.tipCommit.message, @"m1");
  GCHistoryLocalBranch* topicBranch = history.localBranches[1];
  XCTAssertEqualObjects(topicBranch.name, @"topic");
  XCTAssertEqualObjects(topicBranch.tipCommit.message, @"t4");
  
  // Check remote branches
  XCTAssertEqual(history.remoteBranches.count, 1);
  GCHistoryRemoteBranch* originBranch = history.remoteBranches[0];
  XCTAssertEqualObjects(originBranch.name, @"origin/master");
  XCTAssertEqualObjects(originBranch.tipCommit.message, @"m3");
  
  // Attempt to re-create mock commits again
  XCTAssertNil([self.repository createMockCommitHierarchyFromNotation:notation force:NO error:NULL]);
  XCTAssertNotNil([self.repository createMockCommitHierarchyFromNotation:notation force:YES error:NULL]);
}

@end
