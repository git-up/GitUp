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

#import "GCTestCase.h"
#import "GCOrderedSet.h"

@implementation GCMultipleCommitsRepositoryTests(GCOrderedSetTests)

- (void)testOrderedSetAddObject {
  GCOrderedSet* collection = [[GCOrderedSet alloc] init];
  [collection addObject:self.commit1];
  XCTAssertTrue([collection containsObject:self.commit1]);
  NSArray* commits = collection.objects;
  XCTAssertEqual(commits.count, 1);
  XCTAssertEqual(commits[0], self.commit1);
}

- (void)testOrderedSetAddDuplicateObject {
  GCOrderedSet* collection = [[GCOrderedSet alloc] init];
  [collection addObject:self.commit1];
  [collection addObject:self.commit1];
  [collection addObject:self.commit2];
  XCTAssertTrue([collection containsObject:self.commit1]);
  NSArray* commits = collection.objects;
  XCTAssertEqual(commits.count, 2);
  XCTAssertEqual(commits[0], self.commit1);
  XCTAssertEqual(commits[1], self.commit2);
}

- (void)testOrderedSetRemoveObject {
  GCOrderedSet* collection = [[GCOrderedSet alloc] init];
  [collection addObject:self.commit1];
  [collection addObject:self.commit2];
  XCTAssertTrue([collection containsObject:self.commit1]);
  XCTAssertTrue([collection containsObject:self.commit2]);
  [collection removeObject:self.commit1];
  XCTAssertFalse([collection containsObject:self.commit1]);
  XCTAssertTrue([collection containsObject:self.commit2]);
  NSArray* commits = collection.objects;
  XCTAssertEqual(commits.count, 1);
  XCTAssertEqual(commits[0], self.commit2);
}

- (void)testOrderedSetReAddObject {
  GCOrderedSet* collection = [[GCOrderedSet alloc] init];
  [collection addObject:self.commit1];
  [collection addObject:self.commit2];
  XCTAssertTrue([collection containsObject:self.commit1]);
  XCTAssertTrue([collection containsObject:self.commit2]);
  [collection removeObject:self.commit1];
  XCTAssertFalse([collection containsObject:self.commit1]);
  XCTAssertTrue([collection containsObject:self.commit2]);
  [collection addObject:self.commit1];
  XCTAssertTrue([collection containsObject:self.commit1]);
  XCTAssertTrue([collection containsObject:self.commit2]);
  // NOTE: this collection preserves the original place of commit if re-added
  NSArray* commits = collection.objects;
  XCTAssertEqual(commits.count, 2);
  XCTAssertEqual(commits[0], self.commit1);
  XCTAssertEqual(commits[1], self.commit2);
}

- (void)testOrderedSetObjectsOrdering {
  GCOrderedSet* collection = [[GCOrderedSet alloc] init];
  [collection addObject:self.commit1];
  [collection addObject:self.commit2];
  [collection addObject:self.commit3];
  NSArray* commits = collection.objects;
  XCTAssertEqual(commits.count, 3);
  XCTAssertEqual(commits[0], self.commit1);
  XCTAssertEqual(commits[1], self.commit2);
  XCTAssertEqual(commits[2], self.commit3);
}

@end
