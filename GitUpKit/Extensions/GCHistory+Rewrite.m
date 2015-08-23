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

#import "GCHistory+Rewrite.h"

#import "XLFacilityMacros.h"

typedef NS_ENUM(NSUInteger, ReplayMode) {
  kReplayMode_CopyTrees = 0,
  kReplayMode_ApplyPatches,
  kReplayMode_ApplyNewPatchesOnly
};

@implementation GCHistory (GCRewrite)

- (BOOL)isCommitOnAnyLocalBranch:(GCHistoryCommit*)commit {
  if (commit.localBranches.count) {
    return YES;
  }
  __block BOOL result = NO;
  [self walkDescendantsOfCommits:@[commit] usingBlock:^(GCHistoryCommit* descendantCommit, BOOL* stop) {
    if (descendantCommit.localBranches.count) {
      result = YES;
      *stop = YES;
    }
  }];
  return result;
}

- (GCReferenceTransform*)revertCommit:(GCHistoryCommit*)commit
                        againstBranch:(GCHistoryLocalBranch*)branch
                          withMessage:(NSString*)message
                      conflictHandler:(GCConflictHandler)handler
                            newCommit:(GCCommit**)newCommit
                                error:(NSError**)error {
  GCCommit* revertedCommit = [self.repository revertCommit:commit againstCommit:branch.tipCommit withAncestorCommit:commit.parents.firstObject message:message conflictHandler:handler error:error];
  if (revertedCommit == nil) {
    return nil;
  }
  
  NSString* reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_GitUp_Revert, commit.shortSHA1];
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self.repository reflogMessage:reflogMessage];
  [transform setDirectTarget:revertedCommit forReference:branch];
  if (newCommit) {
    *newCommit = revertedCommit;
  }
  return transform;
}

- (GCReferenceTransform*)cherryPickCommit:(GCHistoryCommit*)commit
                            againstBranch:(GCHistoryLocalBranch*)branch
                              withMessage:(NSString*)message
                          conflictHandler:(GCConflictHandler)handler
                                newCommit:(GCCommit**)newCommit
                                    error:(NSError**)error {
  GCCommit* pickedCommit = [self.repository cherryPickCommit:commit againstCommit:branch.tipCommit withAncestorCommit:commit.parents.firstObject message:message conflictHandler:handler error:error];
  if (pickedCommit == nil) {
    return nil;
  }
  
  NSString* reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_GitUp_CherryPick, commit.shortSHA1];
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self.repository reflogMessage:reflogMessage];
  [transform setDirectTarget:pickedCommit forReference:branch];
  if (newCommit) {
    *newCommit = pickedCommit;
  }
  return transform;
}

- (GCReferenceTransform*)fastForwardBranch:(GCHistoryLocalBranch*)branch
                                  toCommit:(GCHistoryCommit*)commit
                                     error:(NSError**)error {
  NSString* reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_GitUp_Merge_FastForward, commit.shortSHA1];
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self.repository reflogMessage:reflogMessage];
  [transform setDirectTarget:commit forReference:branch];
  return transform;
}

- (GCReferenceTransform*)mergeCommit:(GCHistoryCommit*)commit
                          intoBranch:(GCHistoryLocalBranch*)branch
                  withAncestorCommit:(GCHistoryCommit*)ancestorCommit
                             message:(NSString*)message
                     conflictHandler:(GCConflictHandler)handler
                           newCommit:(GCCommit**)newCommit
                               error:(NSError**)error {
  GCCommit* mergedCommit = [self.repository mergeCommit:commit intoCommit:branch.tipCommit withAncestorCommit:ancestorCommit message:message conflictHandler:handler error:error];
  if (mergedCommit == nil) {
    return nil;
  }
  
  NSString* reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_GitUp_Merge, commit.shortSHA1];
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self.repository reflogMessage:reflogMessage];
  [transform setDirectTarget:mergedCommit forReference:branch];
  if (newCommit) {
    *newCommit = mergedCommit;
  }
  return transform;
}

- (GCReferenceTransform*)rebaseBranch:(GCHistoryLocalBranch*)branch
                           fromCommit:(GCHistoryCommit*)fromCommit
                           ontoCommit:(GCHistoryCommit*)commit
                      conflictHandler:(GCConflictHandler)handler
                         newTipCommit:(GCCommit**)newTipCommit
                                error:(NSError**)error {
  GCCommit* tipCommit = [self.repository replayMainLineParentsFromCommit:branch.tipCommit uptoCommit:fromCommit ontoCommit:commit preserveMerges:YES updateCommitter:YES skipIdentical:YES conflictHandler:handler error:error];
  if (tipCommit == nil) {
    return nil;
  }
  
  NSString* reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_GitUp_Rebase, commit.shortSHA1, branch.name];
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self.repository reflogMessage:reflogMessage];
  [transform setDirectTarget:tipCommit forReference:branch];
  if (newTipCommit) {
    *newTipCommit = tipCommit;
  }
  return transform;
}

- (void)_updateTransform:(GCReferenceTransform*)transform forNewCommit:(GCCommit*)newCommit withBaseCommit:(GCHistoryCommit*)baseCommit {
  if (self.HEADDetached && [baseCommit isEqualToCommit:self.HEADCommit]) {
    if (newCommit) {
      [transform setDirectTargetForHEAD:newCommit];
    } else {
      [transform setSymbolicTargetForHEAD:@"refs/heads/master"];  // Make HEAD unborn
    }
  }
  
  if (newCommit) {
    for (GCHistoryLocalBranch* branch in baseCommit.localBranches) {
      [transform setDirectTarget:newCommit forReference:branch];
    }
  } else {
    for (GCHistoryLocalBranch* branch in baseCommit.localBranches) {
      [transform deleteReference:branch];
    }
  }
}

// This will only replay descendants leading to local branch tips
- (BOOL)_replayDescendantsFromCommit:(GCHistoryCommit*)fromCommit
                          ontoCommit:(GCCommit*)ontoCommit
                  withInitialMapping:(NSDictionary*)initialMapping
                      usingTransform:(GCReferenceTransform*)transform
                          replayMode:(ReplayMode)replayMode
                     conflictHandler:(GCConflictHandler)handler
                               error:(NSError**)error {
  CFMutableDictionaryRef mapping = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(mapping, (__bridge const void*)fromCommit, ontoCommit ? (__bridge const void*)ontoCommit : kCFNull);
  for (GCHistoryCommit* commit in initialMapping) {
    CFDictionarySetValue(mapping, (__bridge const void*)commit, (__bridge const void*)initialMapping[commit]);
  }
  __block BOOL success = YES;
  [self walkDescendantsOfCommits:@[fromCommit] usingBlock:^(GCHistoryCommit* commit, BOOL* stop) {
    
    if ([self isCommitOnAnyLocalBranch:commit]) {
      if (CFDictionaryContainsKey(mapping, (__bridge const void*)commit)) {
        return;
      }
      
      NSMutableArray* parents = [[NSMutableArray alloc] init];
      GCHistoryCommit* ancestorCommit = nil;
      GCCommit* tipCommit = nil;
      for (GCHistoryCommit* parent in commit.parents) {
        GCCommit* newParent = CFDictionaryGetValue(mapping, (__bridge const void*)parent);
        if ((__bridge void*)newParent != kCFNull) {
          if (newParent) {
            if (ancestorCommit == nil) {  // Replay on top of first found replayed parent
              ancestorCommit = parent;
              tipCommit = newParent;
            }
            [parents addObject:newParent];
          } else {
            [parents addObject:parent];
          }
        }
      }
      GCCommit* newCommit;
      if (replayMode == kReplayMode_CopyTrees) {
        newCommit = [self.repository copyCommit:commit
                             withUpdatedMessage:nil
                                 updatedParents:parents
                           updatedTreeFromIndex:nil
                                updateCommitter:YES
                                          error:error];
      } else {
        newCommit = [self.repository replayCommit:commit
                                       ontoCommit:tipCommit
                               withAncestorCommit:ancestorCommit
                                   updatedMessage:nil
                                   updatedParents:parents
                                  updateCommitter:YES
                                    skipIdentical:(replayMode == kReplayMode_ApplyNewPatchesOnly)
                                  conflictHandler:handler
                                            error:error];
      }
      if (newCommit == nil) {
        success = NO;
        *stop = YES;
        return;
      }
      [self _updateTransform:transform forNewCommit:newCommit withBaseCommit:commit];
      CFDictionarySetValue(mapping, (__bridge const void*)commit, (__bridge const void*)newCommit);
    } else {
      XLOG_DEBUG(@"Skipping replay of commit \"%@\" (%@) not on local branch", commit.summary, commit.shortSHA1);
    }
    
  }];
  CFRelease(mapping);
  return success;
}

- (GCReferenceTransform*)rewriteCommit:(GCHistoryCommit*)commit
                     withUpdatedCommit:(GCCommit*)updatedCommit
                             copyTrees:(BOOL)copyTrees
                       conflictHandler:(GCConflictHandler)handler
                                 error:(NSError**)error {
  NSString* reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_GitUp_Rewrite, commit.shortSHA1];
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self.repository reflogMessage:reflogMessage];
  [self _updateTransform:transform forNewCommit:updatedCommit withBaseCommit:commit];
  if (![self _replayDescendantsFromCommit:commit
                               ontoCommit:updatedCommit
                       withInitialMapping:nil
                           usingTransform:transform
                               replayMode:(copyTrees ? kReplayMode_CopyTrees : kReplayMode_ApplyPatches)
                          conflictHandler:handler
                                    error:error]) {
    return nil;
  }
  return transform;
}

- (GCReferenceTransform*)deleteCommit:(GCHistoryCommit*)commit
                  withConflictHandler:(GCConflictHandler)handler
                                error:(NSError**)error {
  GCHistoryCommit* newCommit = commit.parents.firstObject;
  NSString* reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_GitUp_Delete, commit.shortSHA1];
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self.repository reflogMessage:reflogMessage];
  [self _updateTransform:transform forNewCommit:newCommit withBaseCommit:commit];
  if (![self _replayDescendantsFromCommit:commit
                               ontoCommit:newCommit
                       withInitialMapping:nil
                           usingTransform:transform
                               replayMode:kReplayMode_ApplyPatches
                          conflictHandler:handler
                                    error:error]) {
    return nil;
  }
  return transform;
}

- (GCReferenceTransform*)_squashCommit:(GCHistoryCommit*)commit withMessage:(NSString*)message newCommit:(GCCommit**)newCommit error:(NSError**)error {
  GCCommit* squashedCommit = [self.repository squashCommitOntoParent:commit withUpdatedMessage:message error:error];
  if (squashedCommit == nil) {
    return nil;
  }
  NSString* reflogMessage = [NSString stringWithFormat:(message ? kGCReflogMessageFormat_GitUp_Squash : kGCReflogMessageFormat_GitUp_Fixup), commit.shortSHA1];
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self.repository reflogMessage:reflogMessage];
  [self _updateTransform:transform forNewCommit:squashedCommit withBaseCommit:commit];
  if (![self _replayDescendantsFromCommit:commit
                               ontoCommit:squashedCommit
                       withInitialMapping:nil
                           usingTransform:transform
                               replayMode:kReplayMode_CopyTrees  // Tree content should not have changed
                          conflictHandler:NULL  // Squashing should not generate conflicts
                                    error:error]) {
    return nil;
  }
  if (newCommit) {
    *newCommit = squashedCommit;
  }
  return transform;
}

- (GCReferenceTransform*)fixupCommit:(GCHistoryCommit*)commit
                           newCommit:(GCCommit**)newCommit
                               error:(NSError**)error {
  return [self _squashCommit:commit withMessage:nil newCommit:newCommit error:error];
}

- (GCReferenceTransform*)squashCommit:(GCHistoryCommit*)commit
                          withMessage:(NSString*)message
                            newCommit:(GCCommit**)newCommit
                                error:(NSError**)error {
  return [self _squashCommit:commit withMessage:message newCommit:newCommit error:error];
}

- (GCReferenceTransform*)swapCommitWithItsParent:(GCHistoryCommit*)commit
                                 conflictHandler:(GCConflictHandler)handler
                                  newChildCommit:(GCCommit**)newChildCommit
                                 newParentCommit:(GCCommit**)newParentCommit
                                           error:(NSError**)error {
  if (commit.parents.count == 0) {
    GC_SET_GENERIC_ERROR(@"Commit cannot be a root commit");
    return nil;
  }
  GCHistoryCommit* parentCommit = commit.parents[0];
  if (parentCommit.parents.count == 0) {
    GC_SET_GENERIC_ERROR(@"Root parent commit is not currently supported");
    return nil;
  }
  GCHistoryCommit* grandParentCommit = parentCommit.parents[0];
  NSString* reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_GitUp_Swap, commit.shortSHA1, parentCommit.shortSHA1];
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self.repository reflogMessage:reflogMessage];
  
  // Replay commit on top of its grandparent preserving other parents
  NSMutableArray* parents = [[NSMutableArray alloc] initWithArray:commit.parents];
  [parents replaceObjectAtIndex:0 withObject:grandParentCommit];
  GCCommit* swappedParentCommit = [self.repository replayCommit:commit
                                                     ontoCommit:grandParentCommit
                                             withAncestorCommit:parentCommit
                                                 updatedMessage:nil
                                                 updatedParents:parents
                                                updateCommitter:YES
                                                  skipIdentical:NO
                                                conflictHandler:handler
                                                          error:error];
  if (swappedParentCommit == nil) {
    return nil;
  }
  [self _updateTransform:transform forNewCommit:swappedParentCommit withBaseCommit:commit];
  
  // Replay parent commit on top of just replayed commit preserving other parents
  NSMutableArray* grandParents = [[NSMutableArray alloc] initWithArray:parentCommit.parents];
  [grandParents replaceObjectAtIndex:0 withObject:swappedParentCommit];
  GCCommit* swappedCommit = [self.repository replayCommit:parentCommit
                                               ontoCommit:swappedParentCommit
                                       withAncestorCommit:grandParentCommit
                                           updatedMessage:nil
                                           updatedParents:grandParents
                                          updateCommitter:YES
                                            skipIdentical:NO
                                          conflictHandler:handler
                                                    error:error];
  if (swappedCommit == nil) {
    return nil;
  }
  [self _updateTransform:transform forNewCommit:swappedCommit withBaseCommit:parentCommit];
  
  // Replay descendants from parents onto replayed parent skipping commit
  if (![self _replayDescendantsFromCommit:parentCommit
                               ontoCommit:swappedParentCommit
                       withInitialMapping:@{commit: swappedCommit}
                           usingTransform:transform
                               replayMode:kReplayMode_ApplyPatches
                          conflictHandler:handler
                                    error:error]) {
    return nil;
  }
  
  // If the commit to swap was a leaf, move its references to the commit that replaces it
  if (commit.leaf) {
    for (GCHistoryLocalBranch* branch in commit.localBranches) {  // Force-update its branch references to point to the new tip instead of following their old commits so that new commits are reachable
      [transform setDirectTarget:swappedCommit forReference:branch];
    }
    if (self.HEADDetached && [self.HEADCommit isEqualToCommit:commit] && !commit.hasReferences) {  // Force-update the HEAD if detached and pointing to it and no other references point to the new tip
      [transform setDirectTargetForHEAD:swappedCommit];
    }
  }
  
  if (newChildCommit) {
    *newChildCommit = swappedCommit;
  }
  if (newParentCommit) {
    *newParentCommit = swappedParentCommit;
  }
  return transform;
}

@end
