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

@implementation GCMultipleCommitsRepositoryTests (GCBranch)

- (void)testBranches {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  
  // Test branch names
  XCTAssertFalse([GCRepository isValidBranchName:@"my^branch"]);
  XCTAssertTrue([GCRepository isValidBranchName:@"my_branch"]);
  
  // Create bare local repo with empty commit
  GCRepository* bare = [self createLocalRepositoryAtPath:path bare:YES];
  XCTAssertNotNil(bare);
  GCCommit* emptyCommit = [bare createCommitFromHEADWithMessage:@"Empty" error:NULL];
  XCTAssertNotNil(emptyCommit);
  
  // Add remote from bare and fetch
  GCRemote* remote = [self.repository addRemoteWithName:@"origin" url:[NSURL fileURLWithPath:path] error:NULL];
  XCTAssertNotNil(remote);
  NSUInteger updatedTips;
  XCTAssertTrue([self.repository fetchDefaultRemoteBranchesFromRemote:remote tagMode:kGCFetchTagMode_None prune:NO updatedTips:&updatedTips error:NULL]);
  XCTAssertEqual(updatedTips, 1);
  
  // Find branches
  GCLocalBranch* localMaster = [self.repository findLocalBranchWithName:@"master" error:NULL];
  XCTAssertEqualObjects(localMaster, self.masterBranch);
  GCRemoteBranch* remoteMaster = [self.repository findRemoteBranchWithName:@"origin/master" error:NULL];
  XCTAssertNotNil(remoteMaster);
  
  // List branches
  NSArray* branches1 = @[self.masterBranch, self.topicBranch];
  XCTAssertEqualObjects([self.repository listLocalBranches:NULL], branches1);
  XCTAssertEqualObjects([self.repository listRemoteBranches:NULL], @[remoteMaster]);
  NSArray* branches2 = @[self.masterBranch, self.topicBranch, remoteMaster];
  XCTAssertEqualObjects([self.repository listAllBranches:NULL], branches2);
  
  // Configure upstream
  XCTAssertTrue([self.repository setUpstream:remoteMaster forLocalBranch:localMaster error:NULL]);
  XCTAssertEqualObjects([self.repository lookupUpstreamForLocalBranch:localMaster error:NULL], remoteMaster);
  XCTAssertTrue([self.repository unsetUpstreamForLocalBranch:localMaster error:NULL]);
  XCTAssertNil([self.repository lookupUpstreamForLocalBranch:localMaster error:NULL]);
  
  // Check branch tip
  GCCommit* tipCommit = [self.repository lookupTipCommitForBranch:self.masterBranch error:NULL];
  XCTAssertEqualObjects(tipCommit, self.commit3);
  
  // Set branch tip
  XCTAssertTrue([self.repository setTipCommit:self.commit2 forBranch:self.topicBranch reflogMessage:nil error:NULL]);
  XCTAssertEqualObjects([self.repository lookupTipCommitForBranch:self.topicBranch error:NULL], self.commit2);
  
  // Create temp branch
  GCLocalBranch* tempBranch = [self.repository createLocalBranchFromCommit:self.commit1 withName:@"temp" force:NO error:NULL];
  XCTAssertNotNil(tempBranch);
  XCTAssertTrue([self.repository setName:@"test" forLocalBranch:tempBranch force:NO error:NULL]);
  XCTAssertEqualObjects([self.repository findLocalBranchWithName:@"test" error:NULL], tempBranch);
  XCTAssertTrue([self.repository deleteLocalBranch:tempBranch error:NULL]);
  
  // Destroy bare local repo
  [self destroyLocalRepository:bare];
}

@end
