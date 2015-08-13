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

@implementation GCSQLiteRepositoryTests (GCSQLiteRepository)

// TODO: Test read_header() and foreach()
- (void)testSQLite_Objects {
  // Test exists(), write() and read()
  GCCommit* commit = [self.repository createCommitFromHEADWithMessage:@"0" error:NULL];
  XCTAssertNotNil(commit);
  
  // Test exists_prefix()
  XCTAssertNotNil([self.repository computeUniqueShortSHA1ForCommit:commit error:NULL]);
  
  // Test read_prefix()
  git_object* object;
  XCTAssertEqual(git_object_lookup_prefix(&object, self.repository.private, git_commit_id(commit.private), 10, GIT_OBJ_COMMIT), GIT_OK);
}

// TODO: libgit2 doesn't call exists() at all
- (void)testSQLite_References {
  // Test lookup()
  XCTAssertNil([self.repository lookupHEAD:NULL error:NULL]);
  
  // Test write() - Symbolic
  XCTAssertNotNil([self.repository createSymbolicReferenceWithFullName:@"HEAD" target:@"refs/heads/master" force:YES error:NULL]);
  
  // Test write() - Direct
  GCCommit* commit = [self.repository createCommitFromHEADWithMessage:@"0" error:NULL];
  XCTAssertNotNil(commit);
  GCLocalBranch* masterBranch;
  XCTAssertNotNil([self.repository lookupHEAD:&masterBranch error:NULL]);
  
  // Create topic branch
  GCLocalBranch* topicBranch = [self.repository createLocalBranchFromCommit:commit withName:@"topic" force:NO error:NULL];
  XCTAssertNotNil(topicBranch);
  
  // Test iterator()
  NSArray* branches = @[masterBranch, topicBranch];
  XCTAssertEqualObjects([self.repository listAllBranches:NULL], branches);
  
  // Test rename() (and indirectly exists())
  XCTAssertTrue([self.repository setName:@"temp" forLocalBranch:topicBranch force:NO error:NULL]);
  
  // Test del()
  XCTAssertTrue([self.repository deleteLocalBranch:topicBranch error:NULL]);
}

@end

@implementation GCMultipleCommitsRepositoryTests (GCSQLiteRepository)

- (void)testSQLite_Copy {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  
  // Copy repo from test repo
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  GCSQLiteRepository* repository = [[GCSQLiteRepository alloc] initWithDatabase:path config:nil localRepositoryContents:self.repository.repositoryPath error:NULL];
  XCTAssertNotNil(repository);
  XCTAssertNotNil([repository findCommitWithSHA1:self.commit2.SHA1 error:NULL]);
  XCTAssertNotNil([repository findCommitWithSHA1:self.commitA.SHA1 error:NULL]);
  XCTAssertNotNil([repository findLocalBranchWithName:@"topic" error:NULL]);
  GCLocalBranch* branch;
  XCTAssertNotNil([repository lookupHEAD:&branch error:NULL]);
  XCTAssertEqualObjects(branch.name, @"master");
  
  // Clean up
  repository = nil;
}

@end
