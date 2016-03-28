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

#import "GIMapViewController+Operations.h"

#import "GIWindowController.h"
#import "GCRepository+Utilities.h"
#import "GCHistory+Rewrite.h"
#import "XLFacilityMacros.h"

#define kUserDefaultsPrefix @"GIMapViewController_"
#define kUserDefaultsKey_SkipPushTagWarning kUserDefaultsPrefix "SkipPushTagWarning"
#define kUserDefaultsKey_SkipFetchRemoteBranchWarning kUserDefaultsPrefix "SkipFetchRemoteBranchWarning"
#define kUserDefaultsKey_SkipPullBranchWarning kUserDefaultsPrefix "SkipPullBranchWarning"
#define kUserDefaultsKey_SkipPushBranchWarning kUserDefaultsPrefix "SkipPushBranchWarning"
#define kUserDefaultsKey_SkipPushLocalBranchToRemoteWarning kUserDefaultsPrefix "SkipPushLocalBranchToRemoteWarning"
#define kUserDefaultsKey_SkipFetchRemoteBranchesWarning kUserDefaultsPrefix "SkipFetchRemoteBranchesWarning"
#define kUserDefaultsKey_AllowReturnKeyForDangerousRemoteOperations kUserDefaultsPrefix "AllowReturnKeyForDangerousRemoteOperations"

@interface GIMapViewController (Internal)
- (void)_promptForCommitMessage:(NSString*)message withTitle:(NSString*)title button:(NSString*)button block:(void (^)(NSString* message))block;
@end

static inline NSString* _CleanedUpCommitMessage(NSString* message) {
  return [message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

static inline GIAlertType _AlertTypeForDangerousRemoteOperations() {
  return ([[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsKey_AllowReturnKeyForDangerousRemoteOperations] ? kGIAlertType_Stop : kGIAlertType_Danger);
}

@implementation GIMapViewController (Operations)

- (BOOL)_checkClean {
  NSError* error;
  if (![self.repository checkClean:kGCCleanCheckOption_IgnoreUntrackedFiles error:&error]) {
    if ([error.domain isEqualToString:GCErrorDomain] && (error.code == kGCErrorCode_RepositoryDirty)) {
      [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning message:error.localizedDescription];
    } else {
      [self presentError:error];
    }
    return NO;
  }
  return YES;
}

- (BOOL)checkCleanRepositoryForOperationOnCommit:(GCCommit*)commit {
  if (!self.repository.history.HEADBranch || !self.repository.history.HEADCommit) {  // Check if HEAD is attached and not unborn
    return YES;
  }
  NSError* error;
  GCCommitRelation relation = [self.repository findRelationOfCommit:commit relativeToCommit:self.repository.history.HEADCommit error:&error];
  switch (relation) {
    
    case kGCCommitRelation_Unknown:
      [self presentError:error];
      return NO;
    
    case kGCCommitRelation_Descendant:
    case kGCCommitRelation_Cousin:
    case kGCCommitRelation_Unrelated:
      return YES;
    
    case kGCCommitRelation_Identical:
    case kGCCommitRelation_Ancestor:
      return [self _checkClean];
    
  }
  XLOG_DEBUG_UNREACHABLE();
  return NO;
}

- (BOOL)checkCleanRepositoryForOperationOnBranch:(GCLocalBranch*)branch {
  if (![self.repository.history.HEADBranch isEqualToBranch:branch]) {  // Check if HEAD is attached to the same branch
    return YES;
  }
  return [self _checkClean];
}

- (GCMergeAnalysisResult)_analyzeMergingCommit:(GCCommit*)mergeCommit intoCommit:(GCCommit*)intoCommit ancestorCommit:(GCHistoryCommit**)ancestorCommit error:(NSError**)error {
  GCCommit* commit;
  GCMergeAnalysisResult result = [self.repository analyzeMergingCommit:mergeCommit intoCommit:intoCommit ancestorCommit:&commit error:error];
  if (result != kGCMergeAnalysisResult_Unknown) {
    *ancestorCommit = [self.repository.history historyCommitForCommit:commit];
    if (*ancestorCommit == nil) {
      XLOG_DEBUG_UNREACHABLE();
      *error = GCNewError(kGCErrorCode_Generic, @"Missing history commit");
      result = kGCMergeAnalysisResult_Unknown;
    }
  }
  return result;
}

#pragma mark - Checkout

// This will preemptively abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)checkoutCommit:(GCHistoryCommit*)commit {
  NSError* error;
  [self.repository setUndoActionName:NSLocalizedString(@"Checkout Commit", nil)];
  if (![self.repository performOperationWithReason:@"checkout_commit"
                                          argument:commit.SHA1
                                skipCheckoutOnUndo:NO
                                             error:&error
                                        usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    return [repository checkoutCommit:commit options:kGCCheckoutOption_UpdateSubmodulesRecursively error:outError];
    
  }]) {
    [self presentError:error];
  }
}

// This will preemptively abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)checkoutLocalBranch:(GCHistoryLocalBranch*)branch {
  NSError* error;
  [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Checkout Branch \"%@\"", nil), branch.name]];
  if (![self.repository performOperationWithReason:@"checkout_branch"
                                          argument:branch.name
                                skipCheckoutOnUndo:NO
                                             error:&error
                                        usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    return [repository checkoutLocalBranch:branch options:kGCCheckoutOption_UpdateSubmodulesRecursively error:outError];
    
  }]) {
    [self presentError:error];
  }
}

// This will abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)checkoutRemoteBranch:(GCHistoryRemoteBranch*)remoteBranch {
  NSError* error;
  [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Checkout Remote Branch \"%@\"", nil), remoteBranch.name]];
  if (![self.repository performOperationWithReason:@"checkout_remote_branch"
                                          argument:remoteBranch.name
                                skipCheckoutOnUndo:NO
                                             error:&error
                                        usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    GCLocalBranch* localBranch = [repository createLocalBranchFromCommit:remoteBranch.tipCommit withName:remoteBranch.branchName force:NO error:outError];
    if (localBranch == nil) {
      return NO;
    }
    if (![repository setUpstream:remoteBranch forLocalBranch:localBranch error:outError]) {
      return NO;
    }
    if (![repository checkoutLocalBranch:localBranch options:kGCCheckoutOption_UpdateSubmodulesRecursively error:outError]) {
      [repository deleteLocalBranch:localBranch error:NULL];  // Ignore errors
      return NO;
    }
    return YES;
    
  }]) {
    [self presentError:error];
  }
}

#pragma mark - Commits

- (void)swapCommitWithParent:(GCHistoryCommit*)commit {
  if ([self checkCleanRepositoryForOperationOnCommit:commit]) {
    [self.repository suspendHistoryUpdates];  // We need to suspend history updates to prevent history to change during replay if conflict handler is called
    NSError* error;
    __block GCCommit* newCommit = nil;
    [self.repository setUndoActionName:NSLocalizedString(@"Swap Commit With Parent", nil)];
    BOOL success = [self.repository performReferenceTransformWithReason:@"swap_commits"
                                                               argument:commit.SHA1
                                                                  error:&error
                                                             usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
      
      return [repository.history swapCommitWithItsParent:commit conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError2) {
        
        return [self resolveConflictsWithResolver:self.delegate index:index ourCommit:ourCommit theirCommit:theirCommit parentCommits:parentCommits message:message error:outError2];
          
      } newChildCommit:NULL newParentCommit:&newCommit error:outError1];
      
    }];
    [self.repository resumeHistoryUpdates];
    if (success) {
      [self selectCommit:newCommit];
    } else {
      [self presentError:error];
    }
  }
}

- (void)swapCommitWithChild:(GCHistoryCommit*)commit {
  if ([self checkCleanRepositoryForOperationOnCommit:commit]) {
    GCHistoryCommit* child = commit.children[0];
    [self.repository suspendHistoryUpdates];  // We need to suspend history updates to prevent history to change during replay if conflict handler is called
    NSError* error;
    __block GCCommit* newCommit = nil;
    [self.repository setUndoActionName:NSLocalizedString(@"Swap Commit With Child", nil)];
    BOOL success = [self.repository performReferenceTransformWithReason:@"swap_commits"
                                                               argument:child.SHA1
                                                                  error:&error
                                                             usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
      
      return [repository.history swapCommitWithItsParent:child conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError2) {
        
        return [self resolveConflictsWithResolver:self.delegate index:index ourCommit:ourCommit theirCommit:theirCommit parentCommits:parentCommits message:message error:outError2];
        
      } newChildCommit:&newCommit newParentCommit:NULL error:outError1];
      
    }];
    [self.repository resumeHistoryUpdates];
    if (success) {
      [self selectCommit:newCommit];
    } else {
      [self presentError:error];
    }
  }
}

- (void)squashCommitWithParent:(GCHistoryCommit*)commit {
  if ([self checkCleanRepositoryForOperationOnCommit:commit]) {
    GCHistoryCommit* parentCommit = commit.parents.firstObject;
    NSString* mergedMessage = [NSString stringWithFormat:NSLocalizedString(@"%@\n\n%@", nil), _CleanedUpCommitMessage(parentCommit.message), _CleanedUpCommitMessage(commit.message)];
    [self _promptForCommitMessage:mergedMessage
                        withTitle:NSLocalizedString(@"Squashed commit message:", nil)
                           button:NSLocalizedString(@"Squash", nil)
                            block:^(NSString* message) {
      
      NSError* error;
      __block GCCommit* newCommit = nil;
      [self.repository setUndoActionName:NSLocalizedString(@"Squash Commit", nil)];
      if ([self.repository performReferenceTransformWithReason:@"squash_commit"
                                                      argument:commit.SHA1
                                                         error:&error
                                                    usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError) {
        
        return [repository.history squashCommit:commit withMessage:message newCommit:&newCommit error:outError];
        
      }]) {
        [self selectCommit:newCommit];
      } else {
        [self presentError:error];
      }
      
    }];
  }
}

- (void)fixupCommitWithParent:(GCHistoryCommit*)commit {
  if ([self checkCleanRepositoryForOperationOnCommit:commit]) {
    NSError* error;
    __block GCCommit* newCommit = nil;
    [self.repository setUndoActionName:NSLocalizedString(@"Fixup Commit", nil)];
    if ([self.repository performReferenceTransformWithReason:@"fixup_commit"
                                                    argument:commit.SHA1
                                                       error:&error
                                                  usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError) {
      
      return [repository.history fixupCommit:commit newCommit:&newCommit error:outError];
      
    }]) {
      [self selectCommit:newCommit];
    } else {
      [self presentError:error];
    }
  }
}

- (void)deleteCommit:(GCHistoryCommit*)commit {
  if ([self checkCleanRepositoryForOperationOnCommit:commit]) {
    [self.repository suspendHistoryUpdates];  // We need to suspend history updates to prevent history to change during replay if conflict handler is called
    NSError* error;
    [self.repository setUndoActionName:NSLocalizedString(@"Delete Commit", nil)];
    if (![self.repository performReferenceTransformWithReason:@"delete_commit"
                                                     argument:commit.SHA1
                                                        error:&error
                                                   usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
      
      return [repository.history deleteCommit:commit withConflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError2) {
        
        return [self resolveConflictsWithResolver:self.delegate index:index ourCommit:ourCommit theirCommit:theirCommit parentCommits:parentCommits message:message error:outError2];
        
      } error:outError1];
      
    }]) {
      [self presentError:error];
    }
    [self.repository resumeHistoryUpdates];
  }
}

// We don't need to suspend history updates as there is no replay by definition
- (void)cherryPickCommit:(GCHistoryCommit*)commit againstLocalBranch:(GCHistoryLocalBranch*)branch {
  if ([self checkCleanRepositoryForOperationOnBranch:branch]) {
    [self _promptForCommitMessage:_CleanedUpCommitMessage(commit.message)
                        withTitle:NSLocalizedString(@"Cherry-picked commit message:", nil)
                           button:NSLocalizedString(@"Cherry-Pick", nil)
                            block:^(NSString* message) {
      
      NSError* error;
      __block GCCommit* newCommit = nil;
      [self.repository setUndoActionName:NSLocalizedString(@"Cherry-Pick Commit", nil)];
      if ([self.repository performReferenceTransformWithReason:@"cherry_pick_commit"
                                                      argument:commit.SHA1
                                                         error:&error
                                                    usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
        
        return [repository.history cherryPickCommit:commit againstBranch:branch withMessage:message conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message2, NSError** outError2) {
          
          return [self resolveConflictsWithResolver:self.delegate index:index ourCommit:ourCommit theirCommit:theirCommit parentCommits:parentCommits message:message2 error:outError2];
          
        } newCommit:&newCommit error:outError1];
        
      }]) {
        [self selectCommit:newCommit];
      } else {
        [self presentError:error];
      }
    
    }];
  }
}

// We don't need to suspend history updates as there is no replay by definition
- (void)revertCommit:(GCHistoryCommit*)commit againstLocalBranch:(GCHistoryLocalBranch*)branch {
  NSError* localError;
  GCCommitRelation relation = [self.repository findRelationOfCommit:commit relativeToCommit:branch.tipCommit error:&localError];
  switch (relation) {
    
    case kGCCommitRelation_Unknown:
      [self presentError:localError];
      break;
    
    case kGCCommitRelation_Descendant:
    case kGCCommitRelation_Cousin:
    case kGCCommitRelation_Unrelated:
      [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning format:NSLocalizedString(@"The commit is not on the \"%@\" branch", nil), branch.name];
      break;
    
    case kGCCommitRelation_Identical:
    case kGCCommitRelation_Ancestor: {
      if ([self checkCleanRepositoryForOperationOnBranch:branch]) {
        [self _promptForCommitMessage:[NSString stringWithFormat:NSLocalizedString(@"Revert \"%@\"\n\n%@", nil), commit.summary, commit.SHA1]
                            withTitle:NSLocalizedString(@"Reverted commit message:", nil)
                               button:NSLocalizedString(@"Revert", nil)
                                block:^(NSString* message) {
          
          NSError* error;
          __block GCCommit* newCommit = nil;
          [self.repository setUndoActionName:NSLocalizedString(@"Revert Commit", nil)];
          if ([self.repository performReferenceTransformWithReason:@"revert_commit"
                                                          argument:commit.SHA1
                                                             error:&error
                                                        usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
            
            return [repository.history revertCommit:commit againstBranch:branch withMessage:message conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message2, NSError** outError2) {
              
              return [self resolveConflictsWithResolver:self.delegate index:index ourCommit:ourCommit theirCommit:theirCommit parentCommits:parentCommits message:message2 error:outError2];
              
            } newCommit:&newCommit error:outError1];
            
          }]) {
            [self selectCommit:newCommit];
          } else {
            [self presentError:error];
          }
          
        }];
      }
      break;
    }
    
  }
}

// No checkout should happen here as HEAD tree should not change so there's no need to require a clean repo
- (void)editCommitMessage:(GCHistoryCommit*)commit {
  NSString* originalMessage = _CleanedUpCommitMessage(commit.message);
  [self _promptForCommitMessage:originalMessage
                      withTitle:NSLocalizedString(@"New commit message:", nil)
                         button:NSLocalizedString(@"Save", nil)
                          block:^(NSString* message) {
    
    if (![message isEqualToString:originalMessage]) {
      NSError* error;
      __block GCCommit* newCommit = nil;
      [self.repository setUndoActionName:NSLocalizedString(@"Edit Commit Message", nil)];
      if ([self.repository performReferenceTransformWithReason:@"edit_commit_message"
                                                      argument:commit.SHA1
                                                         error:&error
                                                    usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError) {
        
        newCommit = [repository copyCommit:commit withUpdatedMessage:message updatedParents:nil updatedTreeFromIndex:nil updateCommitter:YES error:outError];
        if (newCommit == nil) {
          return nil;
        }
        return [repository.history rewriteCommit:commit withUpdatedCommit:newCommit copyTrees:YES conflictHandler:NULL error:outError];  // No need for a conflict handler as editing a message should not result in conflicts
        
      }]) {
        [self selectCommit:newCommit];
      } else {
        [self presentError:error];
      }
    } else {
      NSBeep();
    }
    
  }];
}

#pragma mark - Local Branches

// This will abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)createLocalBranchAtCommit:(GCHistoryCommit*)commit withName:(NSString*)name checkOut:(BOOL)checkOut {
  NSError* error;
  [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Create Branch \"%@\"", nil), name]];
  if (![self.repository performOperationWithReason:@"create_branch"
                                          argument:name
                                skipCheckoutOnUndo:NO
                                             error:&error
                                        usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    GCLocalBranch* branch = [repository createLocalBranchFromCommit:commit withName:name force:NO error:outError];
    if (branch == nil) {
      return NO;
    }
    if (checkOut && ![repository checkoutLocalBranch:branch options:kGCCheckoutOption_UpdateSubmodulesRecursively error:outError]) {
      [repository deleteLocalBranch:branch error:NULL];  // Ignore errors
      return NO;
    }
    return YES;
    
  }]) {
    [self presentError:error];
  }
}

// No checkout should happen here as HEAD tree should not change so there's no need to require a clean repo
- (void)deleteLocalBranch:(GCHistoryLocalBranch*)branch {
  GCHistoryRemoteBranch* upstream = (GCHistoryRemoteBranch*)branch.upstream;  // Must be retained *before* deleting the local branch
  NSError* error;
  [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Delete Branch \"%@\"", nil), branch.name]];
  if ([self.repository performOperationWithReason:@"delete_branch"
                                         argument:branch.name
                               skipCheckoutOnUndo:YES
                                            error:&error
                                       usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    return [repository deleteLocalBranch:branch error:outError];
    
  }]) {
    if ([upstream isKindOfClass:[GCHistoryRemoteBranch class]]) {
      [self confirmUserActionWithAlertType:_AlertTypeForDangerousRemoteOperations()
                                     title:[NSString stringWithFormat:NSLocalizedString(@"Do you also want to delete the upstream remote branch \"%@\" from its remote?", nil), upstream.name]
                                   message:NSLocalizedString(@"This action cannot be undone.", nil)
                                    button:NSLocalizedString(@"Delete Remote Branch", nil)
                 suppressionUserDefaultKey:nil
                                     block:^{
        
        [self _deleteRemoteBranchFromRemote:upstream];
        
      }];
    }
  } else {
    [self presentError:error];
  }
}

// No checkout should happen here as HEAD tree should not change so there's no need to require a clean repo
- (void)setName:(NSString*)name forLocalBranch:(GCHistoryLocalBranch*)branch {
  NSError* error;
  [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Rename Branch \"%@\"", nil), branch.name]];
  if (![self.repository performOperationWithReason:@"rename_branch"
                                          argument:branch.name
                                skipCheckoutOnUndo:YES
                                             error:&error
                                        usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    return [repository setName:name forLocalBranch:branch force:NO error:outError];
    
  }]) {
    [self presentError:error];
  }
}

- (void)setTipCommit:(GCHistoryCommit*)commit forLocalBranch:(GCHistoryLocalBranch*)branch {
  if ([self checkCleanRepositoryForOperationOnBranch:branch]) {
    NSError* error;
    [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Set \"%@\" Branch Tip", nil), branch.name]];
    if (![self.repository performReferenceTransformWithReason:@"set_branch_tip"
                                                     argument:branch.name
                                                        error:&error
                                                   usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError) {
      
      GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:repository reflogMessage:kGCReflogMessageFormat_GitUp_SetTip];
      [transform setDirectTarget:commit forReference:branch];
      return transform;
      
    }]) {
      [self presentError:error];
    }
  }
}

// No checkout happens here so there's no need to require a clean repo
- (void)moveTipCommit:(GCHistoryCommit*)commit forLocalBranch:(GCHistoryLocalBranch*)branch {
  NSError* error;
  [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Move \"%@\" Branch Tip", nil), branch.name]];
  if (![self.repository performOperationWithReason:@"move_branch_tip"
                                          argument:branch.name
                                skipCheckoutOnUndo:YES
                                             error:&error
                                        usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:repository reflogMessage:kGCReflogMessageFormat_GitUp_MoveTip];
    [transform setDirectTarget:commit forReference:branch];
    return [repository applyReferenceTransform:transform error:outError];
    
  }]) {
    [self presentError:error];
  }
}

// No checkout should happen here as HEAD tree should not change so there's no need to require a clean repo
- (void)setUpstream:(GCBranch*)upstream forLocalBranch:(GCLocalBranch*)branch {
  NSError* error;
  if (upstream) {
    [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Set Upstream For \"%@\"", nil), branch.name]];
    if (![self.repository performOperationWithReason:@"set_branch_upstream"
                                            argument:branch.name
                                  skipCheckoutOnUndo:YES
                                               error:&error
                                          usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
      
      return [repository setUpstream:upstream forLocalBranch:branch error:outError];
      
    }]) {
      [self presentError:error];
    }
  } else {
    [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Unset Upstream For \"%@\"", nil), branch.name]];
    if (![self.repository performOperationWithReason:@"unset_branch_upstream"
                                            argument:branch.name
                                  skipCheckoutOnUndo:YES
                                               error:&error
                                          usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
      
      return [self.repository unsetUpstreamForLocalBranch:branch error:outError];
      
    }]) {
      [self presentError:error];
    }
  }
}

#pragma mark - Tags

// No checkout should happen here as HEAD tree should not change so there's no need to require a clean repo
- (void)createTagAtCommit:(GCHistoryCommit*)commit withName:(NSString*)name message:(NSString*)message {
  NSError* error;
  [self.repository setUndoActionName:NSLocalizedString(@"Create Tag", nil)];
  __block GCTag* tag = nil;
  if (![self.repository performOperationWithReason:@"create_tag"
                                          argument:name
                                skipCheckoutOnUndo:YES
                                             error:&error
                                        usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    if (message.length) {
      tag = [repository createAnnotatedTagWithCommit:commit name:name message:message force:NO annotation:NULL error:outError];
    } else {
      tag = [repository createLightweightTagWithCommit:commit name:name force:NO error:outError];
    }
    return tag ? YES : NO;
    
  }]) {
    [self presentError:error];
  }
}

// No checkout should happen here as HEAD tree should not change so there's no need to require a clean repo
- (void)setName:(NSString*)name forTag:(GCHistoryTag*)tag {
  NSError* error;
  [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Rename Tag \"%@\"", nil), tag.name]];
  if (![self.repository performOperationWithReason:@"rename_tag"
                                          argument:tag.name
                                skipCheckoutOnUndo:YES
                                             error:&error
                                        usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    return [repository setName:name forTag:tag force:NO error:outError];
    
  }]) {
    [self presentError:error];
  }
}

// No checkout should happen here as HEAD tree should not change so there's no need to require a clean repo
- (void)deleteTag:(GCHistoryTag*)tag {
  NSError* error;
  [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Delete Tag \"%@\"", nil), tag.name]];
  if (![self.repository performOperationWithReason:@"delete_tag"
                                          argument:tag.name
                                skipCheckoutOnUndo:YES
                                             error:&error
                                        usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    return [repository deleteTag:tag error:outError];
    
  }]) {
    [self presentError:error];
  }
}

#pragma mark - Merging

- (void)fastForwardLocalBranch:(GCHistoryLocalBranch*)branch toCommitOrBranch:(id)commitOrBranch withUserMessage:(NSString*)userMessage {
  if ([self checkCleanRepositoryForOperationOnBranch:branch]) {
    BOOL isBranch = [commitOrBranch isKindOfClass:[GCBranch class]];
    GCHistoryCommit* commit = isBranch ? [commitOrBranch tipCommit] : commitOrBranch;
    NSError* error;
    if (isBranch) {
      [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Fast-Forward \"%@\" Branch to \"%@\" Branch", nil), branch.name, [commitOrBranch name]]];
    } else {
      [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Fast-Forward \"%@\" Branch to Commit", nil), branch.name]];
    }
    if ([self.repository performReferenceTransformWithReason:(isBranch ? @"fast_forward_merge_branch" : @"fast_forward_merge_commit")
                                                    argument:(isBranch ? [commitOrBranch name] : [commitOrBranch SHA1])
                                                       error:&error
                                                  usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError) {
      
      return [repository.history fastForwardBranch:branch toCommit:commit error:outError];
      
    }]) {
      [self selectCommit:commit];
      if (userMessage) {
        [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:userMessage];
      }
    } else {
      [self presentError:error];
    }
  }
}

// We don't need to suspend history updates as there is no replay by definition
- (void)mergeCommitOrBranch:(id)commitOrBranch intoLocalBranch:(GCHistoryLocalBranch*)branch withAncestorCommit:(GCHistoryCommit*)ancestorCommit userMessage:(NSString*)userMessage {
  if ([self checkCleanRepositoryForOperationOnBranch:branch]) {
    BOOL isBranch = [commitOrBranch isKindOfClass:[GCBranch class]];
    GCHistoryCommit* commit = isBranch ? [commitOrBranch tipCommit] : commitOrBranch;
    [self _promptForCommitMessage:[NSString stringWithFormat:NSLocalizedString(@"Merge %@ into %@", nil), isBranch ? [commitOrBranch name] : [commitOrBranch SHA1], branch.name]
                        withTitle:NSLocalizedString(@"Merged commit message:", nil)
                           button:NSLocalizedString(@"Merge", nil)
                            block:^(NSString* message) {
      
      NSError* error;
      __block GCCommit* newCommit = nil;
      if (isBranch) {
        [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Merge Branch \"%@\" Into \"%@\" Branch", nil), [commitOrBranch name], branch.name]];
      } else {
        [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Merge Commit Into \"%@\" Branch", nil), branch.name]];
      }
      if ([self.repository performReferenceTransformWithReason:(isBranch ? @"merge_branch" : @"merge_commit")
                                                      argument:(isBranch ? [commitOrBranch name] : [commitOrBranch SHA1])
                                                         error:&error
                                                    usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
        
        return [repository.history mergeCommit:commit intoBranch:branch withAncestorCommit:ancestorCommit message:message conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message2, NSError** outError2) {
          
          return [self resolveConflictsWithResolver:self.delegate index:index ourCommit:ourCommit theirCommit:theirCommit parentCommits:parentCommits message:message2 error:outError2];
          
        } newCommit:&newCommit error:outError1];
        
      }]) {
        [self selectCommit:newCommit];
        if (userMessage) {
          [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:userMessage];
        }
      } else {
        [self presentError:error];
      }
      
    }];
  }
}

- (void)rebaseLocalBranch:(GCHistoryLocalBranch*)branch fromCommit:(GCHistoryCommit*)fromCommit ontoCommit:(GCHistoryCommit*)commit withUserMessage:(NSString*)userMessage {
  NSError* error;
  if ([self checkCleanRepositoryForOperationOnBranch:branch]) {
    [self.repository suspendHistoryUpdates];  // We need to suspend history updates to prevent history to change during replay if conflict handler is called
    __block GCCommit* newCommit = nil;
    [self.repository setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Rebase \"%@\" Branch", nil), branch.name]];
    BOOL success = [self.repository performReferenceTransformWithReason:@"rebase_branch"
                                                               argument:branch.name
                                                                  error:&error
                                                             usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
      
      return [repository.history rebaseBranch:branch fromCommit:fromCommit ontoCommit:commit conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError2) {
        
        return [self resolveConflictsWithResolver:self.delegate index:index ourCommit:ourCommit theirCommit:theirCommit parentCommits:parentCommits message:message error:outError2];
        
      } newTipCommit:&newCommit error:outError1];
      
    }];
    [self.repository resumeHistoryUpdates];
    if (success) {
      [self selectCommit:newCommit];
      if (userMessage) {
        [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:userMessage];
      }
    } else {
      [self presentError:error];
    }
  }
}

- (void)smartMergeCommitOrBranch:(id)commitOrBranch intoLocalBranch:(GCHistoryLocalBranch*)intoBranch withUserMessage:(NSString*)userMessage {
  BOOL isBranch = [commitOrBranch isKindOfClass:[GCBranch class]];
  NSError* analyzeError;
  GCHistoryCommit* ancestorCommit;
  GCMergeAnalysisResult result = [self _analyzeMergingCommit:(isBranch ? [commitOrBranch tipCommit] : commitOrBranch) intoCommit:intoBranch.tipCommit ancestorCommit:&ancestorCommit error:&analyzeError];
  switch (result) {
    
    case kGCMergeAnalysisResult_Unknown:
      [self presentError:analyzeError];
      break;
    
    case kGCMergeAnalysisResult_UpToDate: {
      if (isBranch) {
        [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning format:NSLocalizedString(@"The \"%@\" branch was already merged into the \"%@\" branch", nil), [commitOrBranch name], intoBranch.name];
      } else {
        [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning format:NSLocalizedString(@"The commit is already on the \"%@\" branch", nil), intoBranch.name];
      }
      break;
    }
  
    case kGCMergeAnalysisResult_FastForward: {
      if (result == kGCMergeAnalysisResult_FastForward) {
        NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedString(@"This merge can be fast-forwarded!", nil)
                                         defaultButton:NSLocalizedString(@"Fast Forward", nil)
                                       alternateButton:NSLocalizedString(@"Cancel", nil)
                                           otherButton:NSLocalizedString(@"Merge", nil)
                             informativeTextWithFormat:NSLocalizedString(@"Do you want to still create a merge or just fast-forward?", nil)];
        alert.type = kGIAlertType_Note;
        [self presentAlert:alert completionHandler:^(NSInteger returnCode) {
          
          if (returnCode == NSAlertDefaultReturn) {
            [self fastForwardLocalBranch:intoBranch toCommitOrBranch:commitOrBranch withUserMessage:userMessage];
          } else if (returnCode == NSAlertOtherReturn) {
            [self mergeCommitOrBranch:commitOrBranch intoLocalBranch:intoBranch withAncestorCommit:ancestorCommit userMessage:userMessage];
          }
          
        }];
      }
      break;
    }
    
    case kGCMergeAnalysisResult_Normal:
      [self mergeCommitOrBranch:commitOrBranch intoLocalBranch:intoBranch withAncestorCommit:ancestorCommit userMessage:userMessage];
      break;
    
  }
}

- (void)smartRebaseLocalBranch:(GCHistoryLocalBranch*)branch ontoCommit:(GCHistoryCommit*)commit withUserMessage:(NSString*)userMessage {
  NSError* error;
  GCCommit* baseCommit = [self.repository findMergeBaseForCommits:@[branch.tipCommit, commit] error:&error];
  if (baseCommit) {
    GCHistoryCommit* fromCommit = [self.repository.history historyCommitForCommit:baseCommit];
    XLOG_DEBUG_CHECK(fromCommit);
    if ([fromCommit isEqualToCommit:commit]) {  // We are trying to rebase onto an ancestor so use branch point instead of common ancestor to rebase from
      GCHistoryCommit* parentCommit = branch.tipCommit.parents.firstObject;
      while (parentCommit) {
        if ([parentCommit isEqualToCommit:commit]) {
          [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning format:NSLocalizedString(@"The \"%@\" branch cannot be rebased onto one of its commits", nil), branch.name];
          return;
        }
        if (parentCommit.children.count > 1) {
          fromCommit = parentCommit;
          break;
        }
        parentCommit = parentCommit.parents.firstObject;
      }
    } else {
      XLOG_DEBUG_CHECK(![fromCommit isEqualToCommit:branch.tipCommit]);
    }
    [self rebaseLocalBranch:branch fromCommit:fromCommit ontoCommit:commit withUserMessage:userMessage];
  } else {
    [self presentError:error];
  }
}

#pragma mark - Remote Fetch

- (void)fetchRemoteBranch:(GCHistoryRemoteBranch*)branch {
  __block NSUInteger updatedTips;
  [self confirmUserActionWithAlertType:kGIAlertType_Caution
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to fetch the remote branch \"%@\"?", nil), branch.name]
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Fetch Branch", nil)
             suppressionUserDefaultKey:kUserDefaultsKey_SkipFetchRemoteBranchWarning
                                 block:^{
    
    [self.repository performOperationInBackgroundWithReason:nil argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** error) {
      
      return [repository fetchRemoteBranch:branch tagMode:kGCFetchTagMode_None updatedTips:&updatedTips error:error];  // Don't fetch any tags to not mess up with undo
      
    } completionBlock:^(BOOL success, NSError* error) {
      
      if (success) {
        if (updatedTips) {
          [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"Remote branch was updated", nil)];
        } else {
          [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"Remote branch is already up-to-date with its remote", nil)];
        }
      } else {
        [self presentError:error];
      }
      
    }];
    
  }];
}

- (void)fetchDefaultRemoteBranchesFromAllRemotes {
  [self confirmUserActionWithAlertType:kGIAlertType_Caution
                                 title:NSLocalizedString(@"Are you sure you want to fetch remote branches?", nil)
                               message:NSLocalizedString(@"This will fetch branches from all remotes in this repository and its submodules, then update the corresponding remote branches in this repository.\n\nRemote branches in this repository that do not exist anymore on their remotes will also be pruned.\n\nThis action cannot be undone.", nil)
                                button:NSLocalizedString(@"Fetch Remote Branches", nil)
             suppressionUserDefaultKey:kUserDefaultsKey_SkipFetchRemoteBranchesWarning
                                 block:^{
    
    __block NSUInteger updatedTips;
    [self.repository performOperationInBackgroundWithReason:nil argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** error) {
      
      return [repository fetchDefaultRemoteBranchesFromAllRemotes:kGCFetchTagMode_None recursive:YES prune:YES updatedTips:&updatedTips error:error];  // Don't fetch any tags to avoid messing with undo (pruning is OK as it only affects remote branches)
      
    } completionBlock:^(BOOL success, NSError* error) {
      
      if (success) {
        if (updatedTips > 1) {
          [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational format:NSLocalizedString(@"%lu remote branches have been updated", nil), updatedTips];
        } else if (updatedTips) {
          [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"1 remote branch has been updated", nil)];
        } else {
          [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"Remote branches are already up-to-date with their remotes", nil)];
        }
      } else {
        [self presentError:error];
      }
      
    }];
    
  }];
}

- (void)fetchAllTagsFromAllRemotes:(BOOL)prune {
  __block NSUInteger updatedTips;
  [self.repository setUndoActionName:NSLocalizedString(@"Fetch Remote Tags", nil)];
  [self.repository performOperationInBackgroundWithReason:@"fetch_remote_tags" argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** error) {
    
    return [repository fetchAllTagsFromAllRemotes:NO prune:prune updatedTips:&updatedTips error:error];  // Don't fetch recursively as we can't undo changes in submodules
    
  } completionBlock:^(BOOL success, NSError* error) {
    
    if (success) {
      if (updatedTips > 1) {
        [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational format:NSLocalizedString(@"%lu tags have been updated", nil), updatedTips];
      } else if (updatedTips) {
        [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"1 tag has been updated", nil)];
      } else {
        [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"Tags are already up-to-date with the remotes", nil)];
      }
    } else {
      [self presentError:error];
    }
    
  }];
}

#pragma mark - Remote Push

- (void)_pushLocalBranch:(GCHistoryLocalBranch*)branch toRemote:(GCRemote*)remote force:(BOOL)force {
  __block GCRemote* upstreamRemote = nil;
  [self.repository performOperationInBackgroundWithReason:nil argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** outError) {
    
    if (remote) {
      return [repository pushLocalBranch:branch toRemote:remote force:force setUpstream:NO error:outError];
    } else {
      return [repository pushLocalBranchToUpstream:branch force:force usedRemote:&upstreamRemote error:outError];
    }
    
  } completionBlock:^(BOOL success, NSError* error) {
    
    if (success) {
      
      if (remote) {
        NSError* localError;
        GCHistoryLocalBranch* updatedBranch = [self.repository.history historyLocalBranchForLocalBranch:branch];  // Reload branch to check upstream!
        GCRemoteBranch* remoteBranch = [self.repository findRemoteBranchWithName:[NSString stringWithFormat:@"%@/%@", remote.name, branch.name] error:&localError];
        if (updatedBranch && remoteBranch) {
          if (![updatedBranch.upstream isEqualToBranch:remoteBranch]) {
            [self confirmUserActionWithAlertType:kGIAlertType_Note
                                           title:[NSString stringWithFormat:NSLocalizedString(@"Do you want to set the upstream for \"%@\"?", nil), updatedBranch.name]
                                         message:[NSString stringWithFormat:NSLocalizedString(@"This will configure the local branch \"%@\" to track the remote branch \"%@\" you just pushed to.", nil), updatedBranch.name, remoteBranch.name]
                                          button:NSLocalizedString(@"Set Upstream", nil)
                       suppressionUserDefaultKey:nil
                                           block:^{
              
              [self setUpstream:remoteBranch forLocalBranch:branch];
              
            }];
          }
        } else {
          [self presentError:localError];
        }
      } else {
        [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational format:NSLocalizedString(@"The branch \"%@\" was pushed to the remote \"%@\" successfully!", nil), branch.name, remote ? remote.name : upstreamRemote.name];
      }
      
    } else if (!force && [error.domain isEqualToString:GCErrorDomain] && (error.code == kGCErrorCode_NonFastForward)) {
      [self confirmUserActionWithAlertType:_AlertTypeForDangerousRemoteOperations()
                                     title:[NSString stringWithFormat:NSLocalizedString(@"The branch \"%@\" could not be fast-forwarded on the remote \"%@\". Do you want to attempt to force push?", nil), branch.name, remote ? remote.name : upstreamRemote.name]
                                   message:NSLocalizedString(@"This action cannot be undone.", nil)
                                    button:NSLocalizedString(@"Force Push", nil)
                 suppressionUserDefaultKey:nil
                                     block:^{
        
        [self _pushLocalBranch:branch toRemote:remote force:YES];
        
      }];
    } else {
      [self presentError:error];
    }
    
  }];
}

- (void)pushLocalBranch:(GCHistoryLocalBranch*)branch toRemote:(GCRemote*)remote {
  [self confirmUserActionWithAlertType:kGIAlertType_Caution
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to push \"%@\" to the remote \"%@\"?", nil), branch.name, remote.name]
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Push Branch", nil)
             suppressionUserDefaultKey:kUserDefaultsKey_SkipPushLocalBranchToRemoteWarning
                                 block:^{
    
    [self _pushLocalBranch:branch toRemote:remote force:NO];
    
  }];
}

- (void)pushLocalBranchToUpstream:(GCHistoryLocalBranch*)branch {
  GCHistoryRemoteBranch* upstream = (GCHistoryRemoteBranch*)branch.upstream;
  [self confirmUserActionWithAlertType:kGIAlertType_Caution
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to push the branch \"%@\" to its upstream?", nil), branch.name]
                               message:[NSString stringWithFormat:NSLocalizedString(@"This will push to the remote branch \"%@\" which cannot be undone.", nil), upstream.name]
                                button:NSLocalizedString(@"Push Branch", nil)
             suppressionUserDefaultKey:kUserDefaultsKey_SkipPushBranchWarning
                                 block:^{
    
    [self _pushLocalBranch:branch toRemote:nil force:NO];
    
  }];
}

- (void)_pushAllLocalBranchesToRemote:(GCRemote*)remote force:(BOOL)force {
  [self.repository performOperationInBackgroundWithReason:nil argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** error) {
    
    return [self.repository pushAllLocalBranchesToRemote:remote force:force setUpstream:NO error:error];
    
  } completionBlock:^(BOOL success, NSError* error) {
    
    if (success) {
      [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational format:NSLocalizedString(@"All branches were pushed to the remote \"%@\" successfully!", nil), remote.name];
    } else if ([error.domain isEqualToString:GCErrorDomain] && (error.code == kGCErrorCode_NonFastForward)) {
      [self confirmUserActionWithAlertType:_AlertTypeForDangerousRemoteOperations()
                                     title:[NSString stringWithFormat:NSLocalizedString(@"Some branches could not be fast-forwarded on the remote \"%@\". Do you want to attempt to force push?", nil), remote.name]
                                   message:NSLocalizedString(@"This action cannot be undone.", nil)
                                    button:NSLocalizedString(@"Force Push", nil)
                 suppressionUserDefaultKey:nil
                                     block:^{
        
        [self _pushAllLocalBranchesToRemote:remote force:YES];
        
      }];
    } else {
      [self presentError:error];
    }
    
  }];
}

- (void)pushAllLocalBranchesToAllRemotes {
  NSError* localError;
  NSArray* remotes = [self.repository listRemotes:&localError];
  if (remotes.count <= 1) {
    GCRemote* remote = remotes[0];
    [self confirmUserActionWithAlertType:_AlertTypeForDangerousRemoteOperations()
                                   title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to push all branches to the remote \"%@\"?", nil), remote.name]
                                 message:NSLocalizedString(@"This action cannot be undone.", nil)
                                  button:NSLocalizedString(@"Push All Branches", nil)
               suppressionUserDefaultKey:nil
                                   block:^{
      
      [self _pushAllLocalBranchesToRemote:remote force:NO];
      
    }];
  } else if (remotes == nil) {
    [self presentError:localError];
  } else {
    [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning message:NSLocalizedString(@"Pushing all branches is only allowed for repositories with a single remote!", nil)];
  }
}

// In Git tags behave like branches and can be moved forward but not backward.
// This is non-intuitive as one would expect tags to either move freely in either direction or not move at all.
// To work around this issue, tags are always forced-pushed.
- (void)_pushTag:(GCTag*)tag toRemote:(GCRemote*)remote {
  [self.repository performOperationInBackgroundWithReason:nil argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** error) {
    
    return [repository pushTag:tag toRemote:remote force:YES error:error];
    
  } completionBlock:^(BOOL success, NSError* error) {
    
    if (success) {
      [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational format:NSLocalizedString(@"The tag \"%@\" was pushed to the remote \"%@\" successfully!", nil), tag.name, remote.name];
    } else {
      [self presentError:error];
    }
    
  }];
}

// IMPORTANT: See comment above
- (void)pushTag:(GCHistoryTag*)tag toRemote:(GCRemote*)remote {
  [self confirmUserActionWithAlertType:kGIAlertType_Caution
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to push the tag \"%@\" to the remote \"%@\"?", nil), tag.name, remote.name]
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Push Tag", nil)
             suppressionUserDefaultKey:kUserDefaultsKey_SkipPushTagWarning
                                 block:^{
    
    [self _pushTag:tag toRemote:remote];
    
  }];
}

// IMPORTANT: See comment above
- (void)pushAllTagsToAllRemotes {
  NSError* localError;
  NSArray* remotes = [self.repository listRemotes:&localError];
  if (remotes.count <= 1) {
    GCRemote* remote = remotes[0];
    [self confirmUserActionWithAlertType:_AlertTypeForDangerousRemoteOperations()
                                   title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to push all tags to the remote \"%@\"?", nil), remote.name]
                                 message:NSLocalizedString(@"This action cannot be undone.", nil)
                                  button:NSLocalizedString(@"Push All Tags", nil)
               suppressionUserDefaultKey:nil
                                   block:^{
      
      [self.repository performOperationInBackgroundWithReason:nil argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** error) {
        
        return [self.repository pushAllTagsToRemote:remote force:YES error:error];
        
      } completionBlock:^(BOOL success, NSError* error) {
        
        if (success) {
          [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational format:NSLocalizedString(@"All tags were pushed to the remote \"%@\" successfully!", nil), remote.name];
        } else {
          [self presentError:error];
        }
        
      }];
      
    }];
  } else if (remotes == nil) {
    [self presentError:localError];
  } else {
    [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning message:NSLocalizedString(@"Pushing all tags is only allowed for repositories with a single remote!", nil)];
  }
}

#pragma mark - Remote Delete

- (void)_deleteRemoteBranchFromRemote:(GCHistoryRemoteBranch*)branch {
  [self.repository performOperationInBackgroundWithReason:nil argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** error) {
    
    return [repository deleteRemoteBranchFromRemote:branch error:error];
    
  } completionBlock:^(BOOL success, NSError* error) {
    
    if (!success) {
      [self presentError:error];
    }
    
  }];
}

// TODO: Delete upstream(s) in config if needed and put on undo stack
- (void)deleteRemoteBranch:(GCHistoryRemoteBranch*)branch {
  [self confirmUserActionWithAlertType:_AlertTypeForDangerousRemoteOperations()
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the remote branch \"%@\" from its remote?", nil), branch.name]
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Delete Branch", nil)
             suppressionUserDefaultKey:nil
                                 block:^{
    
    [self _deleteRemoteBranchFromRemote:branch];
    
  }];
}

- (void)deleteTagFromAllRemotes:(GCHistoryTag*)tag {
  [self confirmUserActionWithAlertType:_AlertTypeForDangerousRemoteOperations()
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the tag \"%@\" from all remotes?", nil), tag.name]
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Delete Tag", nil)
             suppressionUserDefaultKey:nil
                                 block:^{
    
    NSError* localError;
    NSArray* remotes = [self.repository listRemotes:&localError];
    if (remotes == nil) {
      [self presentError:localError];
      return;
    }
    if (remotes.count) {
      [self.repository performOperationInBackgroundWithReason:nil argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** error) {
        
        for (GCRemote* remote in remotes) {
          if (![repository deleteTag:tag fromRemote:remote error:error]) {
            return NO;
          }
        }
        return YES;
        
      } completionBlock:^(BOOL success, NSError* error) {
        
        if (!success) {
          [self presentError:error];
        }
        
      }];
    }
    
  }];
}

#pragma mark - Remote Pull

- (void)pullLocalBranchFromUpstream:(GCHistoryLocalBranch*)branch {
  __block GCHistoryRemoteBranch* upstream = (GCHistoryRemoteBranch*)branch.upstream;
  [self confirmUserActionWithAlertType:kGIAlertType_Caution
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to pull the branch \"%@\" from its upstream?", nil), branch.name]
                               message:[NSString stringWithFormat:NSLocalizedString(@"This will first fetch the remote branch \"%@\" which cannot be undone.", nil), upstream.name]
                                button:NSLocalizedString(@"Pull Branch", nil)
             suppressionUserDefaultKey:kUserDefaultsKey_SkipPullBranchWarning
                                 block:^{
    
    [self.repository performOperationInBackgroundWithReason:nil argument:nil usingOperationBlock:^BOOL(GCRepository* repository, NSError** error) {
      
      return [repository fetchRemoteBranch:upstream tagMode:kGCFetchTagMode_None updatedTips:NULL error:error];  // Don't fetch any tags to not mess up with undo
      
    } completionBlock:^(BOOL success, NSError* error) {
      
      if (success) {
        GCHistoryCommit* branchCommit = branch.tipCommit;
        upstream = [self.repository.history historyRemoteBranchForRemoteBranch:upstream];  // We must refetch the branch from history as it has changed
        XLOG_DEBUG_CHECK(upstream);
        GCHistoryCommit* ancestorCommit;
        GCMergeAnalysisResult result = [self _analyzeMergingCommit:upstream.tipCommit intoCommit:branchCommit ancestorCommit:&ancestorCommit error:&error];
        switch (result) {
          
          case kGCMergeAnalysisResult_Unknown:
            [self presentError:error];
            break;
          
          case kGCMergeAnalysisResult_UpToDate:
            [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational format:NSLocalizedString(@"The branch \"%@\" is already up-to-date with its upstream!", nil), branch.name];
            break;
          
          case kGCMergeAnalysisResult_FastForward:
            [self fastForwardLocalBranch:branch toCommitOrBranch:upstream withUserMessage:[NSString stringWithFormat:NSLocalizedString(@"The branch \"%@\" was fast-forwarded to its upstream!", nil), branch.name]];
            break;
          
          case kGCMergeAnalysisResult_Normal: {
            NSAlert* alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:NSLocalizedString(@"Do you want to merge or rebase the branch \"%@\"?", nil), branch.name]
                                             defaultButton:NSLocalizedString(@"Rebase", nil)
                                           alternateButton:NSLocalizedString(@"Cancel", nil)
                                               otherButton:NSLocalizedString(@"Merge", nil)
                                 informativeTextWithFormat:NSLocalizedString(@"The branch \"%@\" has diverged from its upstream and cannot be fast-forwarded.", nil), branch.name];
            alert.type = kGIAlertType_Note;
            [self presentAlert:alert completionHandler:^(NSInteger returnCode) {
              
              if (returnCode == NSAlertDefaultReturn) {
                [self rebaseLocalBranch:branch fromCommit:ancestorCommit ontoCommit:upstream.tipCommit withUserMessage:nil];
              } else if (returnCode == NSAlertOtherReturn) {
                [self mergeCommitOrBranch:upstream intoLocalBranch:branch withAncestorCommit:ancestorCommit userMessage:nil];
              }
              
            }];
            break;
          }
          
        }
      } else {
        [self presentError:error];
      }
      
    }];
    
  }];
}

@end
