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

#import "GCCore.h"

typedef NS_ENUM(NSUInteger, GCHostingService) {
  kGCHostingService_Unknown = 0,
  kGCHostingService_GitHub,
  kGCHostingService_BitBucket,
  kGCHostingService_GitLab
};

extern NSString* GCNameFromHostingService(GCHostingService service);

@interface GCRepository (Utilities)
- (BOOL)fetchDefaultRemoteBranchesFromAllRemotes:(GCFetchTagMode)mode recursive:(BOOL)recursive prune:(BOOL)prune updatedTips:(NSUInteger*)updatedTips error:(NSError**)error;  // git fetch --all --recurse-submodules=yes
- (BOOL)fetchAllTagsFromAllRemotes:(BOOL)recursive prune:(BOOL)prune updatedTips:(NSUInteger*)updatedTips error:(NSError**)error;  // git fetch -f --all --recurse-submodules=yes 'refs/tags/*:refs/tags/*'

- (BOOL)moveFileFromPath:(NSString*)fromPath toPath:(NSString*)toPath force:(BOOL)force error:(NSError**)error;  // git mv {-f} {from_file} {to_file}
- (BOOL)removeFile:(NSString*)path error:(NSError**)error;  // git rm {file}

- (BOOL)syncIndexWithWorkingDirectory:(NSError**)error;  // git add -A
- (BOOL)cleanWorkingDirectory:(NSError**)error;  // git clean -f -d
- (BOOL)syncWorkingDirectoryWithIndex:(NSError**)error;  // git checkout -- .

- (BOOL)forceCheckoutHEAD:(BOOL)recursive error:(NSError**)error;  // (?) - Equivalent to "git reset --hard" but without the resetting the repository state and updating the reflog

- (NSURL*)hostingURLForProject:(GCHostingService*)service error:(NSError**)error;  // This only looks at the "origin" remote
- (NSURL*)hostingURLForCommit:(GCCommit*)commit service:(GCHostingService*)service error:(NSError**)error;  // This only looks at the "origin" remote
- (NSURL*)hostingURLForRemoteBranch:(GCRemoteBranch*)branch service:(GCHostingService*)service error:(NSError**)error;
- (NSURL*)hostingURLForPullRequestFromRemoteBranch:(GCRemoteBranch*)fromBranch toBranch:(GCRemoteBranch*)toBranch service:(GCHostingService*)service error:(NSError**)error;

- (BOOL)safeDeleteFileIfExists:(NSString*)path error:(NSError**)error;

- (void)setUserInfo:(id)info forKey:(NSString*)key;  // Persistent on disk in the private app directory - Pass nil to delete a key
- (id)userInfoForKey:(NSString*)key;
@end
