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

@implementation GCMultipleCommitsRepositoryTests (GCRepository_Reflog)

- (void)testReflogs {
  // Load reflog entries for HEAD
  NSArray* entries0 = [self.repository loadReflogEntriesForReference:[self.repository lookupHEADReference:NULL] error:NULL];
  XCTAssertEqual(entries0.count, 7);
  XCTAssertEqualObjects([entries0.lastObject messages][0], @"commit (initial): Initial commit");
  
  // Load reflog entries for "master" branch
  NSArray* entries1 = [self.repository loadReflogEntriesForReference:self.masterBranch error:NULL];
  XCTAssertEqual(entries1.count, 4);
  
  // Load reflog entries for "topic" branch
  NSArray* entries2 = [self.repository loadReflogEntriesForReference:self.topicBranch error:NULL];
  XCTAssertEqual(entries2.count, 2);
  
  // Load unified reflog
  NSArray* entries3 = [self.repository loadAllReflogEntries:NULL];
  XCTAssertNotNil(entries3);
  XCTAssertGreaterThanOrEqual(entries3.count, 6);
  XCTAssertEqualObjects([entries3.lastObject messages][0], @"commit (initial): Initial commit");
}

@end
