//
//  GCLiveRepository+Conflicts.m
//  GitUpKit (macOS)
//
//  Created by Felix Lapalme on 2024-04-13.
//

#import "GCLiveRepository+Conflicts.h"

#import "GCRepository+Utilities.h"
#import "GCRepository+HEAD.h"

@implementation GCLiveRepository (Conflicts)

- (GCCommit*)resolveConflictsWithResolver:(id<GCMergeConflictResolver>)resolver
                                    index:(GCIndex*)index
                                ourCommit:(GCCommit*)ourCommit
                              theirCommit:(GCCommit*)theirCommit
                            parentCommits:(NSArray*)parentCommits
                                  message:(NSString*)message
                                    error:(NSError**)error {


  // Save HEAD
  GCCommit* headCommit;
  GCLocalBranch* headBranch;
  if (![self lookupHEADCurrentCommit:&headCommit branch:&headBranch error:error]) {
    return nil;
  }

  // Detach HEAD to "ours" commit
  if (![self checkoutCommit:parentCommits[0] options:0 error:error]) {
    return nil;
  }

  // Check out index with conflicts
  if (![self checkoutIndex:index withOptions:kGCCheckoutOption_UpdateSubmodulesRecursively error:error]) {
    return nil;
  }

  // Have user resolve conflicts
  BOOL resolved = [resolver resolveMergeConflictsWithOurCommit:ourCommit theirCommit:theirCommit];

  // Unless user cancelled, create commit with "ours" and "theirs" parent commits (if applicable)
  GCCommit* commit = nil;
  if (resolved) {
    if (![self syncIndexWithWorkingDirectory:error]) {
      return nil;
    }
    commit = [self createCommitFromHEADAndOtherParent:(parentCommits.count > 1 ? parentCommits[1] : nil) withMessage:message error:error];
    if (commit == nil) {
      return nil;
    }
  }

  // Restore HEAD
  if ((headBranch && ![self setHEADToReference:headBranch error:error]) || (!headBranch && ![self setDetachedHEADToCommit:headCommit error:error])) {
    return nil;
  }
  if (![self forceCheckoutHEAD:YES error:error]) {
    return nil;
  }

  // Check if user cancelled
  if (!resolved) {
    GC_SET_USER_CANCELLED_ERROR();
    return nil;
  }

  return commit;
}

@end
