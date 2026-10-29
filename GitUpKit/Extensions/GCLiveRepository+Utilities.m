//
//  GCLiveRepository+Utilities.m
//  GitUpKit (OSX)
//
//  Created by Lucas Derraugh on 8/2/19.
//

#import <GitUpKit/GCLiveRepository+Utilities.h>

@implementation GCLiveRepository (Utilities)

- (void)smartCheckoutCommit:(GCHistoryCommit*)commit window:(NSWindow*)window {
  if (![self validateCheckoutCommit:commit]) {
    NSBeep();
    return;
  }
  id target = [self smartCheckoutTarget:commit];
  if ([target isKindOfClass:[GCLocalBranch class]]) {
    [self _checkoutLocalBranch:target force:NO window:window];
  } else {
    GCHistoryRemoteBranch* branch = commit.remoteBranches.firstObject;
    if (branch && ![self.history historyLocalBranchWithName:branch.branchName]) {
      NSAlert* alert = [[NSAlert alloc] init];
      alert.messageText = NSLocalizedString(@"Do you want to just checkout the commit or also create a new local branch?", nil);
      alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The selected commit is also the tip of the remote branch \"%@\".", nil), branch.name];
      [alert addButtonWithTitle:NSLocalizedString(@"Create Local Branch", nil)];
      [alert addButtonWithTitle:NSLocalizedString(@"Checkout Commit", nil)];
      [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
      alert.type = kGIAlertType_Note;
      [alert beginSheetModalForWindow:window
                    completionHandler:^(NSModalResponse returnCode) {
                      if (returnCode == NSAlertFirstButtonReturn) {
                        [self checkoutRemoteBranch:branch window:window];
                      } else if (returnCode == NSAlertSecondButtonReturn) {
                        [self _checkoutCommit:target force:NO window:window];
                      }
                    }];
    } else {
      [self _checkoutCommit:target force:NO window:window];
    }
  }
}

// Full name of the branch HEAD points to or SHA1 of the commit if HEAD is detached
- (NSString*)_HEADTarget {
  GCLocalBranch* branch;
  GCCommit* commit = [self lookupHEAD:&branch error:NULL];
  return branch ? branch.fullName : commit.SHA1;
}

// Checkout aborts when local changes would be overwritten so offer to discard them and checkout again like "git checkout -f", unless HEAD has moved: submodules are updated after moving it so the retry could not be undone back to the previous HEAD
- (void)_presentCheckoutError:(NSError*)error previousHEADTarget:(NSString*)previousHEADTarget window:(NSWindow*)window discardChangesBlock:(dispatch_block_t)block {
  if (!block || ![error.domain isEqualToString:GCErrorDomain] || (error.code != kGCErrorCode_CheckoutConflicts) || ![[self _HEADTarget] isEqualToString:previousHEADTarget]) {
    [window presentError:error];
    return;
  }
  NSAlert* alert = [[NSAlert alloc] init];
  alert.type = kGIAlertType_Danger;
  alert.messageText = NSLocalizedString(@"Local changes would be overwritten by checkout", nil);
  alert.informativeText = NSLocalizedString(@"Discarding them reverts every uncommitted change to tracked files, including in submodules, and overwrites untracked files that are in the way. Other untracked files are kept.\n\nThis action cannot be undone.", nil);
  NSButton* discardButton = [alert addButtonWithTitle:NSLocalizedString(@"Discard Changes and Continue", nil)];
  discardButton.keyEquivalent = @"";
  discardButton.hasDestructiveAction = YES;
  [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
  [alert beginSheetModalForWindow:window
                completionHandler:^(NSModalResponse returnCode) {
                  if (returnCode == NSAlertFirstButtonReturn) {
                    block();
                  }
                }];
}

- (void)checkoutRemoteBranch:(GCHistoryRemoteBranch*)remoteBranch window:(NSWindow*)window {
  [self _checkoutRemoteBranch:remoteBranch force:NO window:window];
}

// This will abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)_checkoutRemoteBranch:(GCHistoryRemoteBranch*)remoteBranch force:(BOOL)force window:(NSWindow*)window {
  NSError* error;
  GCCheckoutOptions options = kGCCheckoutOption_UpdateSubmodulesRecursively;
  if (force) {
    options |= kGCCheckoutOption_Force;
  }
  NSString* HEADTarget = [self _HEADTarget];
  [self setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Checkout Remote Branch \"%@\"", nil), remoteBranch.name]];
  if (![self performOperationWithReason:@"checkout_remote_branch"
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
                               if (![repository checkoutLocalBranch:localBranch options:options error:outError]) {
                                 [repository deleteLocalBranch:localBranch error:NULL];  // Ignore errors
                                 return NO;
                               }
                               return YES;
                             }]) {
    [self _presentCheckoutError:error
             previousHEADTarget:HEADTarget
                         window:window
            discardChangesBlock:(force ? nil : ^{
              [self _checkoutRemoteBranch:remoteBranch force:YES window:window];
            })];
  }
}

// This will preemptively abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)_checkoutLocalBranch:(GCHistoryLocalBranch*)branch force:(BOOL)force window:(NSWindow*)window {
  NSError* error;
  GCCheckoutOptions options = kGCCheckoutOption_UpdateSubmodulesRecursively;
  if (force) {
    options |= kGCCheckoutOption_Force;
  }
  NSString* HEADTarget = [self _HEADTarget];
  [self setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Checkout Branch \"%@\"", nil), branch.name]];
  if (![self performOperationWithReason:@"checkout_branch"
                               argument:branch.name
                     skipCheckoutOnUndo:NO
                                  error:&error
                             usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
                               return [repository checkoutLocalBranch:branch options:options error:outError];
                             }]) {
    [self _presentCheckoutError:error
             previousHEADTarget:HEADTarget
                         window:window
            discardChangesBlock:(force ? nil : ^{
              [self _checkoutLocalBranch:branch force:YES window:window];
            })];
  }
}

// This will preemptively abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)_checkoutCommit:(GCHistoryCommit*)commit force:(BOOL)force window:(NSWindow*)window {
  NSError* error;
  GCCheckoutOptions options = kGCCheckoutOption_UpdateSubmodulesRecursively;
  if (force) {
    options |= kGCCheckoutOption_Force;
  }
  NSString* HEADTarget = [self _HEADTarget];
  [self setUndoActionName:NSLocalizedString(@"Checkout Commit", nil)];
  if (![self performOperationWithReason:@"checkout_commit"
                               argument:commit.SHA1
                     skipCheckoutOnUndo:NO
                                  error:&error
                             usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
                               return [repository checkoutCommit:commit options:options error:outError];
                             }]) {
    [self _presentCheckoutError:error
             previousHEADTarget:HEADTarget
                         window:window
            discardChangesBlock:(force ? nil : ^{
              [self _checkoutCommit:commit force:YES window:window];
            })];
  }
}

- (id)smartCheckoutTarget:(GCHistoryCommit*)commit {
  NSArray* branches = commit.localBranches;
  if (branches.count > 1) {
    GCHistoryLocalBranch* headBranch = self.history.HEADBranch;
    NSUInteger index = [branches indexOfObject:headBranch];
    if (index != NSNotFound) {
      return [branches objectAtIndex:((index + 1) % branches.count)];
    }
  }
  GCHistoryLocalBranch* branch = branches.firstObject;
  return branch ? branch : commit;
}

- (BOOL)validateCheckoutCommit:(GCHistoryCommit*)commit {
  id target = [self smartCheckoutTarget:commit];
  if ([target isKindOfClass:[GCLocalBranch class]]) {
    return ![self.history.HEADBranch isEqualToBranch:target];
  } else {
    return ![self.history.HEADCommit isEqualToCommit:target];
  }
}

@end
