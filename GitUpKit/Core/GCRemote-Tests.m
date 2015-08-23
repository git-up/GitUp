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

@implementation GCSingleCommitRepositoryTests (GCRemote)

// TODO: Test -setPushURL:forRemote:error:
// TODO: Test -fetchRemoteBranch:tagMode:force:error:
// TODO: Test -fetchDefaultRemoteBranchesFromRemote:tagMode:prune:error:
// -cloneUsingRemote:error: is tested elsewhere
- (void)testRemotes {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  
  // Create bare local repo
  GCRepository* bare = [self createLocalRepositoryAtPath:path bare:YES];
  XCTAssertNotNil(bare);
  
  // Check remotes
  XCTAssertEqualObjects([self.repository listRemotes:NULL], @[]);
  
  // Add a fake remote
  GCRemote* remote = [self.repository addRemoteWithName:@"origin" url:GCURLFromGitURL(@"git@github.com:swisspol/SANDBOX.git") error:NULL];
  XCTAssertNotNil(remote);
  XCTAssertEqualObjects(remote.name, @"origin");
  XCTAssertEqualObjects(remote.URL, GCURLFromGitURL(@"git@github.com:swisspol/SANDBOX.git"));
  XCTAssertNil(remote.pushURL);
  XCTAssertEqualObjects([self.repository lookupRemoteWithName:@"origin" error:NULL], remote);
  XCTAssertEqualObjects([self.repository listRemotes:NULL], @[remote]);
  NSString* output1 = [NSString stringWithFormat:@"origin\t%@ (fetch)\norigin\t%@ (push)\n", @"git@github.com:swisspol/SANDBOX.git", @"git@github.com:swisspol/SANDBOX.git"];
  [self assertGitCLTOutputEqualsString:output1 withRepository:self.repository command:@"remote", @"-v", nil];
  
  // Reconfigure remote to point to local bare repo
  XCTAssertTrue([self.repository setURL:[NSURL fileURLWithPath:path] forRemote:remote error:NULL]);
  XCTAssertTrue([self.repository setName:@"backup" forRemote:remote error:NULL]);
  XCTAssertNil(remote.pushURL);
  
  // Fetch from remote
  XCTAssertTrue([self.repository fetchDefaultRemoteBranchesFromRemote:remote tagMode:kGCFetchTagMode_None prune:NO updatedTips:NULL error:NULL]);
  XCTAssertEqualObjects([self.repository listRemoteBranches:NULL], @[]);
  XCTAssertNil([self.repository findRemoteBranchWithName:@"backup/master" error:NULL]);
  
  // Push to remote
  XCTAssertTrue([self.repository pushAllLocalBranchesToRemote:remote force:NO setUpstream:NO error:NULL]);
  NSString* string1 = [self runGitCLTWithRepository:bare command:@"branch", @"-avv", nil];
  NSString* string2 = [NSString stringWithFormat:@"* master %@ Initial commit\n", [self.repository computeUniqueShortSHA1ForCommit:self.initialCommit error:NULL]];
  XCTAssertEqualObjects(string1, string2);
  GCRemoteBranch* remoteMasterBranch = [self.repository findRemoteBranchWithName:@"backup/master" error:NULL];
  XCTAssertNotNil(remoteMasterBranch);
  XCTAssertEqualObjects([self.repository listRemoteBranches:NULL], @[remoteMasterBranch]);
  NSString* name;
  XCTAssertEqualObjects([self.repository lookupRemoteForRemoteBranch:remoteMasterBranch sourceBranchName:&name error:NULL], remote);
  XCTAssertEqualObjects(name, @"master");
  XCTAssertNil([self.repository lookupUpstreamForLocalBranch:self.masterBranch error:NULL]);
  
  // Configure local branch to track remote one
  XCTAssertTrue([self.repository setUpstream:remoteMasterBranch forLocalBranch:self.masterBranch error:NULL]);
  XCTAssertEqualObjects([self.repository lookupUpstreamForLocalBranch:self.masterBranch error:NULL], remoteMasterBranch);
  NSString* output2 = [NSString stringWithFormat:@"* master                %@ [backup/master] Initial commit\n  remotes/backup/master %@ Initial commit\n",
                       [self.repository computeUniqueShortSHA1ForCommit:self.initialCommit error:NULL],
                       [self.repository computeUniqueShortSHA1ForCommit:self.initialCommit error:NULL]];
  [self assertGitCLTOutputEqualsString:output2 withRepository:self.repository command:@"branch", @"-avv", nil];
  
  // Make a commit
  GCCommit* commit1 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Bonjour le monde!\n" message:@"French"];
  
  // Unset upstream on master branch
  XCTAssertTrue([self.repository unsetUpstreamForLocalBranch:self.masterBranch error:NULL]);
  XCTAssertNil([self.repository lookupUpstreamForLocalBranch:self.masterBranch error:NULL]);
  
  // Create topic branch and check it out
  GCLocalBranch* topicBranch = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"topic" force:NO error:NULL];
  XCTAssertNotNil(topicBranch);
  XCTAssertTrue([self.repository checkoutLocalBranch:topicBranch options:0 error:NULL]);
  
  // Make a commit
  GCCommit* commit2 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Guten Tag Welt!\n" message:@"German"];
  
  // Push topic branch and set upstream automatically
  XCTAssertNil([self.repository lookupUpstreamForLocalBranch:topicBranch error:NULL]);
  XCTAssertTrue([self.repository pushLocalBranch:topicBranch toRemote:remote force:NO setUpstream:YES error:NULL]);
  XCTAssertNotNil([self.repository lookupUpstreamForLocalBranch:topicBranch error:NULL]);
  
  // Push all branches and set all upstreams automatically
  XCTAssertTrue([self.repository pushAllLocalBranchesToRemote:remote force:NO setUpstream:YES error:NULL]);
  XCTAssertNotNil([self.repository lookupUpstreamForLocalBranch:self.masterBranch error:NULL]);
  NSString* output3 = [NSString stringWithFormat:@"\
  master                %@ [backup/master] French\n\
* topic                 %@ [backup/topic] German\n\
  remotes/backup/master %@ French\n\
  remotes/backup/topic  %@ German\n\
",
                       [self.repository computeUniqueShortSHA1ForCommit:commit1 error:NULL],
                       [self.repository computeUniqueShortSHA1ForCommit:commit2 error:NULL],
                       [self.repository computeUniqueShortSHA1ForCommit:commit1 error:NULL],
                       [self.repository computeUniqueShortSHA1ForCommit:commit2 error:NULL]];
  [self assertGitCLTOutputEqualsString:output3 withRepository:self.repository command:@"branch", @"-avv", nil];
  
  // Checkout master branch
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
  
  // Delete topic branch
  XCTAssertTrue([self.repository deleteLocalBranch:topicBranch error:NULL]);
  XCTAssertEqualObjects([self.repository listLocalBranches:NULL], @[self.masterBranch]);
  XCTAssertNil([self.repository findLocalBranchWithName:@"topic" error:NULL]);
  
  // Remove remote
  XCTAssertTrue([self.repository removeRemote:remote error:NULL]);
  XCTAssertEqualObjects([self.repository listRemotes:NULL], @[]);
  NSString* output4 = [NSString stringWithFormat:@"* master %@ French\n", [self.repository computeUniqueShortSHA1ForCommit:commit1 error:NULL]];
  [self assertGitCLTOutputEqualsString:output4 withRepository:self.repository command:@"branch", @"-avv", nil];
  XCTAssertNil([self.repository lookupUpstreamForLocalBranch:self.masterBranch error:NULL]);
  
  // Re-add remote and fetch again
  remote = [self.repository addRemoteWithName:@"backup" url:[NSURL fileURLWithPath:path] error:NULL];
  XCTAssertNotNil(remote);
  XCTAssertTrue([self.repository fetchDefaultRemoteBranchesFromRemote:remote tagMode:kGCFetchTagMode_None prune:NO updatedTips:NULL error:NULL]);
  
  // Verify topic branch is back
  GCRemoteBranch* remoteTopicBranch = [self.repository findRemoteBranchWithName:@"backup/topic" error:NULL];
  XCTAssertNotNil(remoteTopicBranch);
  topicBranch = [self.repository createLocalBranchFromCommit:[self.repository lookupTipCommitForBranch:remoteTopicBranch error:NULL] withName:remoteTopicBranch.branchName force:NO error:NULL];
  XCTAssertNotNil(topicBranch);
  XCTAssertTrue([self.repository setUpstream:remoteTopicBranch forLocalBranch:topicBranch error:NULL]);
  XCTAssertTrue([self.repository checkoutLocalBranch:topicBranch options:0 error:NULL]);
  NSString* output5 = [NSString stringWithFormat:@"\
  master                %@ French\n\
* topic                 %@ [backup/topic] German\n\
  remotes/backup/master %@ French\n\
  remotes/backup/topic  %@ German\n\
",
                       [self.repository computeUniqueShortSHA1ForCommit:commit1 error:NULL],
                       [self.repository computeUniqueShortSHA1ForCommit:commit2 error:NULL],
                       [self.repository computeUniqueShortSHA1ForCommit:commit1 error:NULL],
                       [self.repository computeUniqueShortSHA1ForCommit:commit2 error:NULL]];
  [self assertGitCLTOutputEqualsString:output5 withRepository:self.repository command:@"branch", @"-avv", nil];
  
  // Checkout master branch
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
  
  // Delete topic branch on the remote
  XCTAssertNotNil([bare findLocalBranchWithName:@"topic" error:NULL]);
  XCTAssertNotNil([self.repository findRemoteBranchWithName:@"backup/topic" error:NULL]);
  XCTAssertTrue([self.repository deleteRemoteBranchFromRemote:remoteTopicBranch error:NULL]);
  XCTAssertNil([bare findRemoteBranchWithName:@"topic" error:NULL]);
  XCTAssertNil([self.repository findRemoteBranchWithName:@"backup/topic" error:NULL]);
  
  // Push again to recreate branch
  XCTAssertTrue([self.repository pushAllLocalBranchesToRemote:remote force:NO setUpstream:YES error:NULL]);
  
  // Delete topic branch directly on remote repo
  NSString* output6 = [self runGitCLTWithRepository:bare command:@"branch", @"-D", @"topic", nil];
  XCTAssertNotNil(output6);
  
  // Fetch again
  XCTAssertTrue([self.repository fetchDefaultRemoteBranchesFromRemote:remote tagMode:kGCFetchTagMode_None prune:YES updatedTips:NULL error:NULL]);
  XCTAssertNil([self.repository findRemoteBranchWithName:@"backup/topic" error:NULL]);
  
  // Make another commit
  GCCommit* commit3 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Gutten Tag Welt!\n" message:@"German"];
  
  // Create tags and push to remote
  XCTAssertTrue([self.repository createLightweightTagWithCommit:self.initialCommit name:@"FIRST" force:NO error:NULL]);
  XCTAssertTrue([self.repository createLightweightTagWithCommit:commit3 name:@"LAST" force:NO error:NULL]);
  XCTAssertTrue([self.repository pushAllTagsToRemote:remote force:NO error:NULL]);
  NSString* output7 = [self runGitCLTWithRepository:bare command:@"tag", nil];
  XCTAssertEqualObjects(output7, @"FIRST\nLAST\n");
  
  // Delete tag in remote
  XCTAssertTrue([self.repository deleteTag:[self.repository findTagWithName:@"FIRST" error:NULL] fromRemote:remote error:NULL]);
  NSString* output8 = [self runGitCLTWithRepository:bare command:@"tag", nil];
  XCTAssertEqualObjects(output8, @"LAST\n");
  
  // Delete tags locally
  XCTAssertTrue([self.repository deleteTag:[self.repository findTagWithName:@"FIRST" error:NULL] error:NULL]);
  XCTAssertTrue([self.repository deleteTag:[self.repository findTagWithName:@"LAST" error:NULL] error:NULL]);
  XCTAssertEqualObjects([self.repository listTags:NULL], @[]);
  
  // Fetch again
  XCTAssertTrue([self.repository fetchDefaultRemoteBranchesFromRemote:remote tagMode:kGCFetchTagMode_All prune:NO updatedTips:NULL error:NULL]);
  XCTAssertNotNil([self.repository findTagWithName:@"LAST" error:NULL]);
  
  // Delete tag locally
  XCTAssertTrue([self.repository deleteTag:[self.repository findTagWithName:@"LAST" error:NULL] error:NULL]);
  
  // Fetch again but tags only this time
  XCTAssertNotNil([self.repository fetchTagsFromRemote:remote prune:NO updatedTips:NULL error:NULL]);
  XCTAssertNotNil([self.repository findTagWithName:@"LAST" error:NULL]);
  
  // Force push overriden tag
  GCTag* tag1 = [self.repository createLightweightTagWithCommit:self.initialCommit name:@"LAST" force:YES error:NULL];
  XCTAssertNotNil(tag1);
  XCTAssertFalse([self.repository pushTag:tag1 toRemote:remote force:NO error:NULL]);
  XCTAssertTrue([self.repository pushTag:tag1 toRemote:remote force:YES error:NULL]);
  
  // Push single annotated tag
  GCTag* tag2 = [self.repository createAnnotatedTagWithCommit:commit2 name:@"ANNOTATED" message:@"Nothing to see here" force:NO annotation:NULL error:NULL];
  XCTAssertNotNil(tag2);
  XCTAssertTrue([self.repository pushTag:tag2 toRemote:remote force:NO error:NULL]);
  NSString* output9 = [self runGitCLTWithRepository:bare command:@"tag", nil];
  XCTAssertEqualObjects(output9, @"ANNOTATED\nLAST\n");
  
  // Check for remote changes
  XCTAssertEqual([self.repository checkForChangesInRemote:remote withOptions:kGCRemoteCheckOption_IncludeBranches error:NULL], 0);
  
  // Make a commit directly on remote
  XCTAssertNotNil([bare createCommitFromHEADWithMessage:@"EMPTY" error:NULL]);
  
  // Check for remote changes
  XCTAssertEqual([self.repository checkForChangesInRemote:remote withOptions:kGCRemoteCheckOption_IncludeBranches error:NULL], 1);
  
  // Fetch again
  XCTAssertTrue([self.repository fetchDefaultRemoteBranchesFromRemote:remote tagMode:kGCFetchTagMode_None prune:YES updatedTips:NULL error:NULL]);
  
  // Check for remote changes
  XCTAssertEqual([self.repository checkForChangesInRemote:remote withOptions:kGCRemoteCheckOption_IncludeBranches error:NULL], 0);
  
  // Create branch directly on remote
  GCLocalBranch* remoteBranch = [bare createLocalBranchFromCommit:[bare lookupHEAD:NULL error:NULL] withName:@"remote" force:NO error:NULL];
  XCTAssertNotNil(remoteBranch);
  
  // Check for remote changes
  XCTAssertEqual([self.repository checkForChangesInRemote:remote withOptions:kGCRemoteCheckOption_IncludeBranches error:NULL], 1);
  
  // Fetch again
  XCTAssertTrue([self.repository fetchDefaultRemoteBranchesFromRemote:remote tagMode:kGCFetchTagMode_None prune:YES updatedTips:NULL error:NULL]);
  
  // Check for remote changes
  XCTAssertEqual([self.repository checkForChangesInRemote:remote withOptions:kGCRemoteCheckOption_IncludeBranches error:NULL], 0);
  
  // Delete branch directly on remote
  XCTAssertTrue([bare deleteLocalBranch:remoteBranch error:NULL]);
  
  // Check for remote changes
  XCTAssertEqual([self.repository checkForChangesInRemote:remote withOptions:kGCRemoteCheckOption_IncludeBranches error:NULL], 1);
  
  // Fetch again
  XCTAssertTrue([self.repository fetchDefaultRemoteBranchesFromRemote:remote tagMode:kGCFetchTagMode_None prune:YES updatedTips:NULL error:NULL]);
  
  // Check for remote changes
  XCTAssertEqual([self.repository checkForChangesInRemote:remote withOptions:kGCRemoteCheckOption_IncludeBranches error:NULL], 0);
  
  // Destroy bare local repo
  [self destroyLocalRepository:bare];
}

@end
