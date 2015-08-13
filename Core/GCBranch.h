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

#import "GCReference.h"
#import "GCRepository.h"

@class GCCommit;

@interface GCBranch : GCReference
@end

@interface GCLocalBranch : GCBranch
@end

@interface GCRemoteBranch : GCBranch
@end

@interface GCBranch (Extensions)
- (BOOL)isEqualToBranch:(GCBranch*)branch;
@end

@interface GCRemoteBranch (Extensions)
@property(nonatomic, readonly) NSString* remoteName;  // "origin" in "origin/master"
@property(nonatomic, readonly) NSString* branchName;  // "master" in "origin/master"
@end

@interface GCRepository (GCBranch)
+ (BOOL)isValidBranchName:(NSString*)name;

- (GCLocalBranch*)findLocalBranchWithName:(NSString*)name error:(NSError**)error;
- (GCRemoteBranch*)findRemoteBranchWithName:(NSString*)name error:(NSError**)error;
- (NSArray*)listLocalBranches:(NSError**)error;  // git branch
- (NSArray*)listRemoteBranches:(NSError**)error;  // git branch -r
- (NSArray*)listAllBranches:(NSError**)error;  // git branch -a

- (GCCommit*)lookupTipCommitForBranch:(GCBranch*)branch error:(NSError**)error;  // git show-ref {branch}

- (GCLocalBranch*)createLocalBranchFromCommit:(GCCommit*)commit withName:(NSString*)name force:(BOOL)force error:(NSError**)error;  // git branch {name} {commit}
- (BOOL)setTipCommit:(GCCommit*)commit forBranch:(GCBranch*)branch reflogMessage:(NSString*)message error:(NSError**)error;  // git update-ref {branch} {commit}
- (BOOL)setName:(NSString*)name forLocalBranch:(GCLocalBranch*)branch force:(BOOL)force error:(NSError**)error;  // git branch -m {branch} {new_name}
- (BOOL)deleteLocalBranch:(GCLocalBranch*)branch error:(NSError**)error;  // git branch -D {branch}

- (GCBranch*)lookupUpstreamForLocalBranch:(GCLocalBranch*)branch error:(NSError**)error;
- (BOOL)setUpstream:(GCBranch*)upstreamBranch forLocalBranch:(GCLocalBranch*)branchBranch error:(NSError**)error;  // git branch -u {remote}/{branch} {branch}
- (BOOL)unsetUpstreamForLocalBranch:(GCLocalBranch*)branchBranch error:(NSError**)error;  // git branch --unset-upstream {branch}
@end
