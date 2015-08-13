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

@implementation GCMultipleCommitsRepositoryTests (GCCommitDatabase)

// TODO: Test users table
- (void)testCommitDatabase {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"db"]];
  
  // Create database
  GCCommitDatabase* database = [[GCCommitDatabase alloc] initWithRepository:self.repository databasePath:path options:0 error:NULL];
  XCTAssertNotNil(database);
  XCTAssertEqual([database countTips], 0);
  XCTAssertEqual([database countCommits], 0);
  XCTAssertEqual([database countRelations], 0);
  XCTAssertEqual([database totalCommitRetainCount], 0);
  
  // Re-open database in read-write
  GCCommitDatabase* database2 = [[GCCommitDatabase alloc] initWithRepository:self.repository databasePath:path options:0 error:NULL];
  XCTAssertNotNil(database2);
  database2 = nil;
  
  // Re-open database in read-only
  GCCommitDatabase* database3 = [[GCCommitDatabase alloc] initWithRepository:self.repository databasePath:path options:kGCCommitDatabaseOptions_QueryOnly error:NULL];
  XCTAssertNotNil(database3);
  database3 = nil;
  
  // Populate database
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 2);
  XCTAssertEqual([database countCommits], 5);
  XCTAssertEqual([database countRelations], 4);
  XCTAssertEqual([database totalCommitRetainCount], 6);  // 5 commits with 1 common
  
  // Re-populate database (should be no-op)
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 2);
  XCTAssertEqual([database countCommits], 5);
  XCTAssertEqual([database countRelations], 4);
  XCTAssertEqual([database totalCommitRetainCount], 5 + 1);
  
  // Create a new branch that does NOT create a new tip
  GCLocalBranch* otherBranch1 = [self.repository createLocalBranchFromCommit:[self.repository lookupTipCommitForBranch:self.topicBranch error:NULL] withName:@"other1" force:NO error:NULL];
  XCTAssertNotNil(otherBranch1);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 2);
  XCTAssertEqual([database countCommits], 5);
  XCTAssertEqual([database countRelations], 4);
  XCTAssertEqual([database totalCommitRetainCount], 5 + 1);
  
  // Delete branch
  XCTAssertTrue([self.repository deleteLocalBranch:otherBranch1 error:NULL]);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 2);
  XCTAssertEqual([database countCommits], 5);
  XCTAssertEqual([database countRelations], 4);
  XCTAssertEqual([database totalCommitRetainCount], 5 + 1);
  
  // Create a new branch that creates a new tip
  GCLocalBranch* otherBranch2 = [self.repository createLocalBranchFromCommit:self.commit2 withName:@"other2" force:NO error:NULL];
  XCTAssertNotNil(otherBranch2);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 3);
  XCTAssertEqual([database countCommits], 5);
  XCTAssertEqual([database countRelations], 4);
  XCTAssertEqual([database totalCommitRetainCount], 5 + 1 + 1);
  
  // Delete branch
  XCTAssertTrue([self.repository deleteLocalBranch:otherBranch2 error:NULL]);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 2);
  XCTAssertEqual([database countCommits], 5);
  XCTAssertEqual([database countRelations], 4);
  XCTAssertEqual([database totalCommitRetainCount], 5 + 1);
  
  // Create commit on topic branch
  XCTAssertTrue([self.repository checkoutLocalBranch:self.topicBranch options:0 error:NULL]);
  XCTAssertNotNil([self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"" message:@"Nothing"]);
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 2);
  XCTAssertEqual([database countCommits], 6);
  XCTAssertEqual([database countRelations], 5);
  XCTAssertEqual([database totalCommitRetainCount], 6 + 1);
  
  // Delete topic branch
  XCTAssertTrue([self.repository deleteLocalBranch:self.topicBranch error:NULL]);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 1);
  XCTAssertEqual([database countCommits], 4);
  XCTAssertEqual([database countRelations], 3);
  XCTAssertEqual([database totalCommitRetainCount], 4 + 0);
  
  // Create and merge branch
  GCLocalBranch* mergeBranch = [self.repository createLocalBranchFromCommit:self.commit1 withName:@"merge" force:NO error:NULL];
  XCTAssertNotNil(mergeBranch);
  XCTAssertTrue([self.repository checkoutLocalBranch:mergeBranch options:0 error:NULL]);
  GCCommit* mergeCommit = [self makeCommitWithUpdatedFileAtPath:@"merge.txt" string:@"" message:@"MERGE"];
  XCTAssertNotNil(mergeCommit);
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
  XCTAssertTrue([self.repository mergeCommitToHEAD:mergeCommit error:NULL]);
  XCTAssertNotNil([self.repository createCommitFromHEADAndOtherParent:mergeCommit withMessage:@"merged" error:NULL]);
  XCTAssertTrue([self.repository deleteLocalBranch:mergeBranch error:NULL]);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 1);
  XCTAssertEqual([database countCommits], 6);
  XCTAssertEqual([database countRelations], 6);
  XCTAssertEqual([database totalCommitRetainCount], 6 + 1);
  
  // Create degenerated commit with duplicated parents
  GCCommit* tempCommit = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"TEMP" message:@"TEMP"];
  XCTAssertNotNil(tempCommit);
  XCTAssertNotNil([self.repository createCommitFromHEADAndOtherParent:tempCommit withMessage:@"merged" error:NULL]);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 1);
  XCTAssertEqual([database countCommits], 8);
  XCTAssertEqual([database countRelations], 8);
  XCTAssertEqual([database totalCommitRetainCount], 8 + 1);
  
  // Delete database
  database = nil;
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
}

@end

@implementation GCEmptyRepositoryTests (GCCommitDatabase)

/*
  0---1----2----3----5 (master)
       \            /
        4-----------
*/
- (void)testCommitDatabase {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"db"]];
  
  // Create mock hierarchy
  NSArray* commits = [self.repository createMockCommitHierarchyFromNotation:@"0 1(0) 2(1) 3(2) 4(1) 5(3,4)<master>" force:NO error:NULL];
  XCTAssertNotNil(commits);
  
  // Create and populate database
  GCCommitDatabase* database = [[GCCommitDatabase alloc] initWithRepository:self.repository databasePath:path options:0 error:NULL];
  XCTAssertNotNil(database);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  XCTAssertEqual([database countTips], 1);
  XCTAssertEqual([database countCommits], 6);
  XCTAssertEqual([database countRelations], 6);
  XCTAssertEqual([database totalCommitRetainCount], 6 + 1);
  
  // Delete database
  database = nil;
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
}

@end

@implementation GCSingleCommitRepositoryTests (GCCommitDatabase)

// TODO: Test diff search
- (void)testCommitDatabase {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"db"]];
  
  // Make commits
  GCCommit* commit1 = [self.repository createCommitFromHEADWithMessage:@"This is a test" error:NULL];
  XCTAssertNotNil(commit1);
  GCCommit* commit2 = [self.repository createCommitFromHEADWithMessage:@"This is\n\nanother TEST" error:NULL];
  XCTAssertNotNil(commit2);
  GCCommit* commit3 = [self.repository createCommitFromHEADWithMessage:@"ThisTESTishere" error:NULL];
  XCTAssertNotNil(commit3);
  GCCommit* commit4 = [self.repository createCommitFromHEADWithMessage:@"Merge pull request #60 from pvblivs/master" error:NULL];
  XCTAssertNotNil(commit4);
  GCCommit* commit5 = [self.repository createCommitFromHEADWithMessage:@"Un essai en français les amis!" error:NULL];
  XCTAssertNotNil(commit5);
  GCCommit* commit6 = [self.repository createCommitFromHEADWithMessage:@"Hey test_this" error:NULL];
  XCTAssertNotNil(commit6);
  
  // Create and populate database
  GCCommitDatabase* database = [[GCCommitDatabase alloc] initWithRepository:self.repository databasePath:path options:0 error:NULL];
  XCTAssertNotNil(database);
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  
  // Test search
  XCTAssertEqualObjects([database findCommitsMatching:@"nothing" error:NULL], @[]);
  NSSet* results1 = [NSSet setWithObjects:commit1, commit2, nil];
  XCTAssertEqualObjects([NSSet setWithArray:[database findCommitsMatching:@"Test" error:NULL]], results1);
  XCTAssertEqualObjects([database findCommitsMatching:@"#60" error:NULL], @[commit4]);
  XCTAssertEqualObjects([database findCommitsMatching:@"pvblivs/master" error:NULL], @[commit4]);
  XCTAssertEqualObjects([database findCommitsMatching:@"essai français" error:NULL], @[commit5]);
  XCTAssertEqualObjects([database findCommitsMatching:@"test_this" error:NULL], @[commit6]);
  
  // Make more commits
  GCCommit* commit7 = [self.repository createCommitFromHEADWithMessage:@"Un autre essai" error:NULL];
  XCTAssertNotNil(commit7);
  
  // Update database
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  
  // Test search again
  NSSet* results2 = [NSSet setWithObjects:commit5, commit7, nil];
  XCTAssertEqualObjects([NSSet setWithArray:[database findCommitsMatching:@"essai" error:NULL]], results2);
  
  // Delete last commit
  XCTAssertTrue([self.repository setTipCommit:commit6 forBranch:self.masterBranch reflogMessage:nil error:NULL]);
  
  // Update database
  XCTAssertTrue([database updateWithProgressHandler:NULL error:NULL]);
  
  // Test search again
  XCTAssertEqualObjects([database findCommitsMatching:@"essai" error:NULL], @[commit5]);
  
  // Delete database
  database = nil;
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
}

@end
