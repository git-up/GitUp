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

// TODO: Test -fetchDefaultRemoteBranchesFromAllRemotes:
// TODO: Test -fetchAllTagsFromAllRemotes:
// TODO: Test -hostingURLForCommit:
// TODO: Test -hostingURLForRemoteBranch:
// TODO: Test -hostingURLForPullRequestFromRemoteBranch:
@implementation GCSingleCommitRepositoryTests (GCRepository_Utilities)

- (void)testUtilities {
  // Move file
  XCTAssertTrue([self.repository moveFileFromPath:@"hello_world.txt" toPath:@"goodbye_world.txt" force:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@"R  hello_world.txt -> goodbye_world.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Remove file
  XCTAssertTrue([self.repository removeFile:@"goodbye_world.txt" error:NULL]);
  [self assertGitCLTOutputEqualsString:@"D  hello_world.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Hosting service URLs
  GCHostingService service;
  XCTAssertNil([self.repository hostingURLForProject:&service error:NULL]);
  
  XCTAssertTrue([self.repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"remote.origin.url" withValue:@"git@github.com:git-up/GitUp-Mac.git" error:NULL]);
  XCTAssertEqualObjects([self.repository hostingURLForProject:&service error:NULL], [NSURL URLWithString:@"https://github.com/git-up/GitUp-Mac"]);
  XCTAssertEqual(service, kGCHostingService_GitHub);
  XCTAssertTrue([self.repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"remote.origin.url" withValue:@"https://github.com/git-up/GitUp-Mac.git" error:NULL]);
  XCTAssertEqualObjects([self.repository hostingURLForProject:&service error:NULL], [NSURL URLWithString:@"https://github.com/git-up/GitUp-Mac"]);
  XCTAssertEqual(service, kGCHostingService_GitHub);
  
  XCTAssertTrue([self.repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"remote.origin.url" withValue:@"ssh://git@bitbucket.org:gitup/test.git" error:NULL]);
  XCTAssertEqualObjects([self.repository hostingURLForProject:&service error:NULL], [NSURL URLWithString:@"https://bitbucket.org/gitup/test"]);
  XCTAssertEqual(service, kGCHostingService_BitBucket);
  XCTAssertTrue([self.repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"remote.origin.url" withValue:@"https://user@bitbucket.org/gitup/test.git" error:NULL]);
  XCTAssertEqualObjects([self.repository hostingURLForProject:&service error:NULL], [NSURL URLWithString:@"https://bitbucket.org/gitup/test"]);
  XCTAssertEqual(service, kGCHostingService_BitBucket);
  
  XCTAssertTrue([self.repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"remote.origin.url" withValue:@"git@gitlab.com:gitup/GitUp-Mac.git" error:NULL]);
  XCTAssertEqualObjects([self.repository hostingURLForProject:&service error:NULL], [NSURL URLWithString:@"https://gitlab.com/gitup/GitUp-Mac"]);
  XCTAssertEqual(service, kGCHostingService_GitLab);
  XCTAssertTrue([self.repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"remote.origin.url" withValue:@"https://gitlab.com/gitup/GitUp-Mac.git" error:NULL]);
  XCTAssertEqualObjects([self.repository hostingURLForProject:&service error:NULL], [NSURL URLWithString:@"https://gitlab.com/gitup/GitUp-Mac"]);
  XCTAssertEqual(service, kGCHostingService_GitLab);
}

- (void)testSyncIndexWithWorkdir {
  [self updateFileAtPath:@"temp.txt" withString:@"temp"];
  XCTAssertTrue([self.repository addFileToIndex:@"temp.txt" error:NULL]);
  XCTAssertTrue([self.repository createCommitFromHEADWithMessage:@"temp" error:NULL]);
  
  [self updateFileAtPath:@"new.txt" withString:@"new"];
  [self deleteFileAtPath:@"temp.txt"];
  [self updateFileAtPath:@"hello_world.txt" withString:@"COUCOU"];
  [self assertGitCLTOutputEqualsString:@" M hello_world.txt\n D temp.txt\n?? new.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  XCTAssertTrue([self.repository syncIndexWithWorkingDirectory:NULL]);
  [self assertGitCLTOutputEqualsString:@"M  hello_world.txt\nA  new.txt\nD  temp.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
}

- (void)testSyncWorkdirWithIndex {
  [self updateFileAtPath:@"temp.txt" withString:@"temp"];
  XCTAssertTrue([self.repository addFileToIndex:@"temp.txt" error:NULL]);
  XCTAssertTrue([self.repository createCommitFromHEADWithMessage:@"temp" error:NULL]);
  
  [self updateFileAtPath:@"new.txt" withString:@"new"];
  [self deleteFileAtPath:@"temp.txt"];
  [self updateFileAtPath:@"hello_world.txt" withString:@"COUCOU"];
  [self assertGitCLTOutputEqualsString:@" M hello_world.txt\n D temp.txt\n?? new.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  XCTAssertTrue([self.repository syncWorkingDirectoryWithIndex:NULL]);
  [self assertGitCLTOutputEqualsString:@"" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
}

- (void)testCleanWorkingDirectory {
  [self updateFileAtPath:@"file1" withString:@"1"];
  XCTAssertTrue([self.repository addFileToIndex:@"file1" error:NULL]);
  [self updateFileAtPath:@"file2" withString:@"2"];
  XCTAssertTrue([self.repository cleanWorkingDirectory:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"file1"]]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"file2"]]);
}

@end
