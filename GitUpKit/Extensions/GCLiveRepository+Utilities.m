//
//  GCLiveRepository+Utilities.m
//  GitUpKit (OSX)
//
//  Created by Lucas Derraugh on 8/2/19.
//

#import "GCLiveRepository+Utilities.h"

@implementation GCLiveRepository (Utilities)

- (void)smartCheckoutCommit:(GCHistoryCommit*)commit window:(NSWindow*)window {
  if (![self validateCheckoutCommit:commit]) {
    NSBeep();
    return;
  }
  id target = [self smartCheckoutTarget:commit];
  if ([target isKindOfClass:[GCLocalBranch class]]) {
    [self _checkoutLocalBranch:target window:window];
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
                        [self _checkoutCommit:target window:window];
                      }
                    }];
    } else {
      [self _checkoutCommit:target window:window];
    }
  }
}

// This will abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)checkoutRemoteBranch:(GCHistoryRemoteBranch*)remoteBranch window:(NSWindow*)window {
  NSError* error;
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
                               if (![repository checkoutLocalBranch:localBranch options:kGCCheckoutOption_UpdateSubmodulesRecursively error:outError]) {
                                 [repository deleteLocalBranch:localBranch error:NULL];  // Ignore errors
                                 return NO;
                               }
                               return YES;
                             }]) {
    [window presentError:error];
  }
}

// This will preemptively abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)_checkoutLocalBranch:(GCHistoryLocalBranch*)branch window:(NSWindow*)window {
  NSError* error;
  [self setUndoActionName:[NSString stringWithFormat:NSLocalizedString(@"Checkout Branch \"%@\"", nil), branch.name]];
  if (![self performOperationWithReason:@"checkout_branch"
                               argument:branch.name
                     skipCheckoutOnUndo:NO
                                  error:&error
                             usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
                               return [repository checkoutLocalBranch:branch options:kGCCheckoutOption_UpdateSubmodulesRecursively error:outError];
                             }]) {
    [window presentError:error];
  }
}

// This will preemptively abort on conflicts in workdir or index so there's no need to require a clean repo
- (void)_checkoutCommit:(GCHistoryCommit*)commit window:(NSWindow*)window {
  NSError* error;
  [self setUndoActionName:NSLocalizedString(@"Checkout Commit", nil)];
  if (![self performOperationWithReason:@"checkout_commit"
                               argument:commit.SHA1
                     skipCheckoutOnUndo:NO
                                  error:&error
                             usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
                               return [repository checkoutCommit:commit options:kGCCheckoutOption_UpdateSubmodulesRecursively error:outError];
                             }]) {
    [window presentError:error];
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
