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

#import <GitUpKit/GitUpKit.h>

#import "ViewController.h"

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  NSString* path = [[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] stringByAppendingPathExtension:@"git"];
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  GCRepository* repo = [[GCRepository alloc] initWithNewLocalRepository:path bare:YES error:NULL];
  assert(repo);

  GCRemote* remote = [repo addRemoteWithName:@"origin" url:[NSURL URLWithString:@"https://github.com/git-up/test-repo-base.git"] error:NULL];
  assert(remote);
  assert([repo cloneUsingRemote:remote recursive:NO error:NULL]);

  assert([repo writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"user.name" withValue:@"User" error:NULL]);
  assert([repo writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"user.email" withValue:@"user@example.com" error:NULL]);

  GCIndex* index = [repo createInMemoryIndex:NULL];
  assert([repo addFile:@"empty.data" withContents:[NSData data] toIndex:index error:NULL]);
  GCCommit* commit = [repo createCommitFromIndex:index withParents:nil message:@"Initial commit" error:NULL];
  assert(commit);

  GCLocalBranch* branch = [repo createLocalBranchFromCommit:commit withName:@"empty" force:NO error:NULL];
  assert(branch);

  self.view.backgroundColor = [UIColor greenColor];
}

@end
