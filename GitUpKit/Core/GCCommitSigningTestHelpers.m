//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
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

#import "GCCommitSigningTestHelpers.h"
#import "GCTestCase.h"

NSString* GCCommitSignature(GCCommit* commit) {
  git_buf buffer = {0};
  int status = git_commit_header_field(&buffer, commit.private, "gpgsig");
  if (status != GIT_OK) {
    git_buf_free(&buffer);
    return nil;
  }
  NSString* signature = [[NSString alloc] initWithBytes:buffer.ptr length:buffer.size encoding:NSUTF8StringEncoding];
  git_buf_free(&buffer);
  return signature;
}

BOOL GCCommitHasSSHSignature(GCCommit* commit) {
  return [GCCommitSignature(commit) containsString:@"BEGIN SSH SIGNATURE"];
}

BOOL GCConfigureSSHSigningWithKeyPath(GCRepository* repository, NSString* keyPath) {
  return [repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"commit.gpgsign" withValue:@"true" error:NULL] &&
         [repository writeConfigOptionForLevel:kGCConfigLevel_Local
                                      variable:@"gpg.format"
                                     withValue:@"ssh"
                                         error:NULL] &&
         [repository writeConfigOptionForLevel:kGCConfigLevel_Local
                                      variable:@"user.signingkey"
                                     withValue:keyPath
                                         error:NULL];
}
