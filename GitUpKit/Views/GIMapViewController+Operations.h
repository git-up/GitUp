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

#import "GIMapViewController.h"

@class GCBranch, GCLocalBranch, GCHistoryLocalBranch, GCHistoryRemoteBranch, GCHistoryTag, GCRemote;

@interface GIMapViewController (Operations)
- (BOOL)checkCleanRepositoryForOperationOnCommit:(GCCommit*)commit;
- (BOOL)checkCleanRepositoryForOperationOnBranch:(GCLocalBranch*)branch;

- (void)checkoutCommit:(GCHistoryCommit*)commit;
- (void)checkoutLocalBranch:(GCHistoryLocalBranch*)branch;
- (void)checkoutRemoteBranch:(GCHistoryRemoteBranch*)remoteBranch;

- (void)swapCommitWithParent:(GCHistoryCommit*)commit;
- (void)swapCommitWithChild:(GCHistoryCommit*)commit;
- (void)squashCommitWithParent:(GCHistoryCommit*)commit;
- (void)fixupCommitWithParent:(GCHistoryCommit*)commit;
- (void)deleteCommit:(GCHistoryCommit*)commit;
- (void)cherryPickCommit:(GCHistoryCommit*)commit againstLocalBranch:(GCHistoryLocalBranch*)branch;
- (void)revertCommit:(GCHistoryCommit*)commit againstLocalBranch:(GCHistoryLocalBranch*)branch;
- (void)editCommitMessage:(GCHistoryCommit*)commit;

- (void)createLocalBranchAtCommit:(GCHistoryCommit*)commit withName:(NSString*)name checkOut:(BOOL)checkOut;
- (void)deleteLocalBranch:(GCHistoryLocalBranch*)branch;
- (void)setName:(NSString*)name forLocalBranch:(GCHistoryLocalBranch*)branch;
- (void)setTipCommit:(GCHistoryCommit*)commit forLocalBranch:(GCHistoryLocalBranch*)branch;
- (void)moveTipCommit:(GCHistoryCommit*)commit forLocalBranch:(GCHistoryLocalBranch*)branch;
- (void)setUpstream:(GCBranch*)upstream forLocalBranch:(GCLocalBranch*)branch;

- (void)createTagAtCommit:(GCHistoryCommit*)commit withName:(NSString*)name message:(NSString*)message;
- (void)setName:(NSString*)name forTag:(GCHistoryTag*)tag;
- (void)deleteTag:(GCHistoryTag*)tag;

- (void)fastForwardLocalBranch:(GCHistoryLocalBranch*)branch toCommitOrBranch:(id)commitOrBranch withUserMessage:(NSString*)userMessage;
- (void)mergeCommitOrBranch:(id)commitOrBranch intoLocalBranch:(GCHistoryLocalBranch*)branch withAncestorCommit:(GCHistoryCommit*)ancestorCommit userMessage:(NSString*)userMessage;
- (void)rebaseLocalBranch:(GCHistoryLocalBranch*)branch fromCommit:(GCHistoryCommit*)fromCommit ontoCommit:(GCHistoryCommit*)commit withUserMessage:(NSString*)userMessage;
- (void)smartMergeCommitOrBranch:(id)commitOrBranch intoLocalBranch:(GCHistoryLocalBranch*)intoBranch withUserMessage:(NSString*)userMessage;
- (void)smartRebaseLocalBranch:(GCHistoryLocalBranch*)branch ontoCommit:(GCHistoryCommit*)commit withUserMessage:(NSString*)userMessage;

- (void)fetchRemoteBranch:(GCHistoryRemoteBranch*)branch;
- (void)deleteRemoteBranch:(GCHistoryRemoteBranch*)branch;
- (void)deleteTagFromAllRemotes:(GCHistoryTag*)tag;
- (void)fetchDefaultRemoteBranchesFromAllRemotes;
- (void)fetchAllTagsFromAllRemotes:(BOOL)prune;

- (void)pushLocalBranch:(GCHistoryLocalBranch*)branch toRemote:(GCRemote*)remote;
- (void)pushLocalBranchToUpstream:(GCHistoryLocalBranch*)branch;
- (void)pushAllLocalBranchesToAllRemotes;
- (void)pushTag:(GCHistoryTag*)tag toRemote:(GCRemote*)remote;
- (void)pushAllTagsToAllRemotes;

- (void)pullLocalBranchFromUpstream:(GCHistoryLocalBranch*)branch;
@end
