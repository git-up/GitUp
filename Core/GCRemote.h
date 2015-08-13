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

#import "GCRepository.h"

typedef NS_ENUM(NSUInteger, GCFetchTagMode) {
  kGCFetchTagMode_Automatic = 0,
  kGCFetchTagMode_None,
  kGCFetchTagMode_All
};

typedef NS_OPTIONS(NSUInteger, GCRemoteCheckOptions) {
  kGCRemoteCheckOption_IncludeBranches = (1 << 0),
  kGCRemoteCheckOption_IncludeTags = (1 << 1)
};

@interface GCRemote : NSObject
@property(nonatomic, readonly) GCRepository* repository;  // NOT RETAINED
@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) NSURL* URL;  // May be nil
@property(nonatomic, readonly) NSURL* pushURL;  // May be nil (if so libgit2 falls back to using URL)
@end

@interface GCRemote (Extensions)
- (BOOL)isEqualToRemote:(GCRemote*)remote;
- (NSComparisonResult)nameCompare:(GCRemote*)remote;
@end

@interface GCRepository (GCRemote)
- (NSArray*)listRemotes:(NSError**)error;  // git remote -v
- (GCRemote*)lookupRemoteWithName:(NSString*)name error:(NSError**)error;  // git remote -v

- (GCRemote*)addRemoteWithName:(NSString*)name url:(NSURL*)url error:(NSError**)error;  // git remote add {name} {url}
- (BOOL)setName:(NSString*)name forRemote:(GCRemote*)remote error:(NSError**)error;  // git remote rename {remote} {new name}
- (BOOL)setURL:(NSURL*)url forRemote:(GCRemote*)remote error:(NSError**)error;  // git remote set-url {remote} {new URL}
- (BOOL)setPushURL:(NSURL*)url forRemote:(GCRemote*)remote error:(NSError**)error;  // git remote set-url --push {remote} {new URL} - Pass nil to clear
- (BOOL)removeRemote:(GCRemote*)remote error:(NSError**)error;  // git remote remove {remote}

- (BOOL)checkForChangesInRemote:(GCRemote*)remote
                    withOptions:(GCRemoteCheckOptions)options
                addedReferences:(NSDictionary**)addedReferences  // Full-names / SHA1s
             modifiedReferences:(NSDictionary**)modifiedReferences  // Full-names / SHA1s
              deletedReferences:(NSDictionary**)deletedReferences  // Full-names / SHA1s
                          error:(NSError**)error;

- (BOOL)fetchRemoteBranch:(GCRemoteBranch*)branch tagMode:(GCFetchTagMode)mode updatedTips:(NSUInteger*)updatedTips error:(NSError**)error;  // git fetch {-n|-t} {-p} {remote} 'refs/heads/{branch}:refs/remotes/{remote}/{branch}'
- (BOOL)fetchDefaultRemoteBranchesFromRemote:(GCRemote*)remote tagMode:(GCFetchTagMode)mode prune:(BOOL)prune updatedTips:(NSUInteger*)updatedTips error:(NSError**)error;  // git fetch {-n|-t} {-p} {remote}
- (NSArray*)fetchTagsFromRemote:(GCRemote*)remote prune:(BOOL)prune updatedTips:(NSUInteger*)updatedTips error:(NSError**)error;  // git fetch {remote} 'refs/tags/*:refs/tags/*' - Returns the tags in the remote

- (BOOL)pushLocalBranchToUpstream:(GCLocalBranch*)branch force:(BOOL)force usedRemote:(GCRemote**)usedRemote error:(NSError**)error;  // git push
- (BOOL)pushLocalBranch:(GCLocalBranch*)branch toRemote:(GCRemote*)remote force:(BOOL)force setUpstream:(BOOL)setUpstream error:(NSError**)error;  // git push {-f} {-u} {remote} 'refs/heads/{branch}:refs/heads/{branch}'
- (BOOL)pushTag:(GCTag*)tag toRemote:(GCRemote*)remote force:(BOOL)force error:(NSError**)error;  // git push {-f} {remote} 'refs/tags/{tag}:refs/tags/{tag}'
- (BOOL)pushAllLocalBranchesToRemote:(GCRemote*)remote force:(BOOL)force setUpstream:(BOOL)setUpstream error:(NSError**)error;  // git push {-f} {-u} {remote} 'refs/heads/*:refs/heads/*'
- (BOOL)pushAllTagsToRemote:(GCRemote*)remote force:(BOOL)force error:(NSError**)error;  // git push {-f} {remote} 'refs/tags/*:refs/tags/*'

- (BOOL)deleteRemoteBranchFromRemote:(GCRemoteBranch*)branch error:(NSError**)error;  // git push {remote} ':refs/heads/{branch}'
- (BOOL)deleteTag:(GCTag*)tag fromRemote:(GCRemote*)remote error:(NSError**)error;  // git push {remote} ':refs/tags/{tag}'

- (GCRemote*)lookupRemoteForRemoteBranch:(GCRemoteBranch*)branch sourceBranchName:(NSString**)name error:(NSError**)error;  // git branch -avv

- (BOOL)cloneUsingRemote:(GCRemote*)remote recursive:(BOOL)recursive error:(NSError**)error;  // (?) - Requires repository to be empty
@end
