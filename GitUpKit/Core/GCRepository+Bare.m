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

#import "GCPrivate.h"

@implementation GCRepository (Bare)

- (GCCommit*)squashCommitOntoParent:(GCCommit*)squashCommit withUpdatedMessage:(NSString*)message error:(NSError**)error {
  GCCommit* newCommit = nil;
  git_commit* parentCommit = NULL;
  git_tree* tree = NULL;
  
  if (git_commit_parentcount(squashCommit.private) != 1) {
    GC_SET_GENERIC_ERROR(@"Commit to squash must have a single parent");
    goto cleanup;
  }
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_parent, &parentCommit, squashCommit.private, 0);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &tree, squashCommit.private);
  newCommit = [self createCommitFromCommit:parentCommit withTree:tree updatedMessage:message updatedParents:nil updateCommitter:YES error:error];
  
cleanup:
  git_tree_free(tree);
  git_commit_free(parentCommit);
  return newCommit;
}

static inline GCCommit* _CopyCommit(GCRepository* repository, git_commit* commit) {
  git_commit* copy;
  git_object_dup((git_object**)&copy, (git_object*)commit);  // This just increases the retain count and cannot fail
  return [[GCCommit alloc] initWithRepository:repository commit:copy];
}

- (GCCommit*)_mergeTheirCommit:(git_commit*)theirCommit
                 intoOurCommit:(git_commit*)ourCommit
            withAncestorCommit:(git_commit*)ancestorCommit
                       parents:(const git_commit**)parents
                         count:(NSUInteger)count
                        author:(const git_signature*)author
                       message:(NSString*)message
               conflictHandler:(GCConflictHandler)handler
                         error:(NSError**)error {
  GCCommit* commit = nil;
  git_tree* ancestorTree = NULL;
  git_tree* ourTree = NULL;
  git_tree* theirTree = NULL;
  git_index* index = NULL;
  
  if (ancestorCommit) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &ancestorTree, ancestorCommit);
  }
  if (ourCommit) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &ourTree, ourCommit);
  }
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &theirTree, theirCommit);
  git_merge_options mergeOptions = GIT_MERGE_OPTIONS_INIT;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_merge_trees, &index, self.private, ancestorTree, ourTree, theirTree, &mergeOptions);
  if (git_index_has_conflicts(index) && handler) {
    NSMutableArray* array = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < count; ++i) {
      [array addObject:_CopyCommit(self, (git_commit*)parents[i])];
    }
    commit = handler([[GCIndex alloc] initWithRepository:nil index:index], _CopyCommit(self, ourCommit), _CopyCommit(self, theirCommit), array, message, error);  // Doesn't make sense to specify a custom author on conflict anyway
    index = NULL;  // Ownership has been transferred to GCIndex instance
  } else {
    commit = [self createCommitFromIndex:index withParents:parents count:count author:author message:message error:error];
  }
  
cleanup:
  git_index_free(index);
  git_tree_free(theirTree);
  git_tree_free(ourTree);
  git_tree_free(ancestorTree);
  return commit;
}

- (GCCommit*)cherryPickCommit:(GCCommit*)pickCommit
                againstCommit:(GCCommit*)againstCommit
           withAncestorCommit:(GCCommit*)ancestorCommit
                      message:(NSString*)message
              conflictHandler:(GCConflictHandler)handler
                        error:(NSError**)error {
  const git_commit* parents[] = {againstCommit.private};
  return [self _mergeTheirCommit:pickCommit.private
                   intoOurCommit:againstCommit.private
              withAncestorCommit:ancestorCommit.private
                         parents:parents
                           count:1
                          author:git_commit_author(pickCommit.private)
                         message:message
                 conflictHandler:handler
                           error:error];
}

- (GCCommit*)revertCommit:(GCCommit*)revertCommit
            againstCommit:(GCCommit*)againstCommit
       withAncestorCommit:(GCCommit*)ancestorCommit
                  message:(NSString*)message
          conflictHandler:(GCConflictHandler)handler
                    error:(NSError**)error {
  const git_commit* parents[] = {againstCommit.private};
  return [self _mergeTheirCommit:ancestorCommit.private
                   intoOurCommit:againstCommit.private
              withAncestorCommit:revertCommit.private
                         parents:parents
                           count:1
                          author:NULL
                         message:message
                 conflictHandler:handler
                           error:error];
}

- (GCCommitRelation)findRelationOfCommit:(GCCommit*)ofCommit relativeToCommit:(GCCommit*)toCommit error:(NSError**)error {
  const git_oid* ofOID = git_commit_id(ofCommit.private);
  const git_oid* toOID = git_commit_id(toCommit.private);
  if (!git_oid_equal(ofOID, toOID)) {
    git_oid bases[] = {*ofOID, *toOID};
    git_oid oid;
    int status = git_merge_base_many(&oid, self.private, 2, bases);
    if (status == GIT_ENOTFOUND) {
      return kGCCommitRelation_Unrelated;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(return kGCCommitRelation_Unknown, status, == GIT_OK);
    if (git_oid_equal(&oid, ofOID)) {
      return kGCCommitRelation_Ancestor;
    }
    if (git_oid_equal(&oid, toOID)) {
      return kGCCommitRelation_Descendant;
    }
    return kGCCommitRelation_Cousin;
  }
  return kGCCommitRelation_Identical;
}

- (GCCommit*)findMergeBaseForCommits:(NSArray*)commits error:(NSError**)error {
  git_commit* commit = NULL;
  size_t count = commits.count;
  git_oid* bases = malloc(count * sizeof(git_oid));
  
  for (size_t i = 0; i < count; ++i) {
    bases[i] = *git_commit_id([(GCCommit*)commits[i] private]);
  }
  git_oid oid;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_merge_base_many, &oid, self.private, count, bases);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &commit, self.private, &oid);
  
cleanup:
  free(bases);
  return commit ? [[GCCommit alloc] initWithRepository:self commit:commit] : nil;
}

// Generic re-implementation of git_merge_analysis()
- (GCMergeAnalysisResult)analyzeMergingCommit:(GCCommit*)mergeCommit intoCommit:(GCCommit*)intoCommit ancestorCommit:(GCCommit**)ancestorCommit error:(NSError**)error {
  GCCommit* ancestor = [self findMergeBaseForCommits:@[intoCommit, mergeCommit] error:error];
  if (ancestor == nil) {
    return kGCMergeAnalysisResult_Unknown;
  }
  GCMergeAnalysisResult result;
  if ([ancestor isEqualToCommit:mergeCommit]) {
    result = kGCMergeAnalysisResult_UpToDate;
  } else if ([ancestor isEqualToCommit:intoCommit]) {
    result = kGCMergeAnalysisResult_FastForward;
  } else {
    result = kGCMergeAnalysisResult_Normal;
  }
  if (ancestorCommit) {
    *ancestorCommit = ancestor;
  }
  return result;
}

- (GCCommit*)mergeCommit:(GCCommit*)mergeCommit
              intoCommit:(GCCommit*)intoCommit
      withAncestorCommit:(GCCommit*)ancestorCommit
                 message:(NSString*)message
         conflictHandler:(GCConflictHandler)handler
                   error:(NSError**)error {
  const git_commit* parents[] = {intoCommit.private, mergeCommit.private};
  return [self _mergeTheirCommit:mergeCommit.private
                   intoOurCommit:intoCommit.private
              withAncestorCommit:ancestorCommit.private
                         parents:parents
                           count:2
                          author:NULL
                         message:message
                 conflictHandler:handler
                           error:error];
}

- (GCCommit*)createCommitFromIndex:(GCIndex*)index
                       withParents:(NSArray*)parents
                           message:(NSString*)message
                             error:(NSError**)error {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wvla"
  const git_commit* commits[parents.count];
#pragma clang diagnostic pop
  NSUInteger count = 0;
  for (GCCommit* parent in parents) {
    commits[count++] = parent.private;
  }
  return [self createCommitFromIndex:index.private withParents:commits count:count author:NULL message:message error:error];
}

- (GCCommit*)copyCommit:(GCCommit*)copyCommit
     withUpdatedMessage:(NSString*)message
         updatedParents:(NSArray*)parents
   updatedTreeFromIndex:(GCIndex*)index
        updateCommitter:(BOOL)updateCommitter
                  error:(NSError**)error {
  GCCommit* newCommit = nil;
  git_commit* commit = copyCommit.private;
  git_tree* tree = NULL;
  git_oid oid;
  
  if (index) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_write_tree_to, &oid, index.private, self.private);
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_tree_lookup, &tree, self.private, &oid);
  } else {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &tree, commit);
  }
  newCommit = [self createCommitFromCommit:commit withTree:tree updatedMessage:message updatedParents:parents updateCommitter:updateCommitter error:error];
  
cleanup:
  git_tree_free(tree);
  return newCommit;
}

- (GCCommit*)replayCommit:(GCCommit*)replayCommit
               ontoCommit:(GCCommit*)ontoCommit
       withAncestorCommit:(GCCommit*)ancestorCommit
           updatedMessage:(NSString*)message
           updatedParents:(NSArray*)parents
          updateCommitter:(BOOL)updateCommitter
            skipIdentical:(BOOL)skipIdentical
          conflictHandler:(GCConflictHandler)handler
                    error:(NSError**)error {
  GCCommit* newCommit = nil;
  git_tree* replayTree = NULL;
  git_tree* ontoTree = NULL;
  git_tree* ancestorTree = NULL;
  git_index* mergeIndex = NULL;
  git_tree* mergeTree = NULL;
  git_diff* diff = NULL;
  git_oid oid;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &replayTree, replayCommit.private);
  if (ontoCommit) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &ontoTree, ontoCommit.private);
  }
  if (ancestorCommit) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &ancestorTree, ancestorCommit.private);
  }
  git_merge_options mergeOptions = GIT_MERGE_OPTIONS_INIT;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_merge_trees, &mergeIndex, self.private, ancestorTree, ontoTree, replayTree, &mergeOptions);
  if (git_index_has_conflicts(mergeIndex) && handler) {
    if (parents == nil) {
      parents = [[NSMutableArray alloc] init];
      for (unsigned int i = 0, count = git_commit_parentcount(replayCommit.private); i < count; ++i) {
        git_commit* commit;
        CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_parent, &commit, replayCommit.private, i);
        [(NSMutableArray*)parents addObject:[[GCCommit alloc] initWithRepository:self commit:commit]];
      }
    }
    if (message == nil) {
      message = replayCommit.message;
    }
    newCommit = handler([[GCIndex alloc] initWithRepository:nil index:mergeIndex], ontoCommit, replayCommit, parents, message, error);  // TODO: This ignores "updateCommitter" and "skipIdentical"
    mergeIndex = NULL;  // Ownership has been transferred to GCIndex instance
  } else {
    if (skipIdentical) {
      git_diff_options diffOptions = GIT_DIFF_OPTIONS_INIT;
      diffOptions.flags = GIT_DIFF_SKIP_BINARY_CHECK;  // This should not be needed since not generating patches anyway
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_diff_tree_to_index, &diff, self.private, ontoTree, mergeIndex, &diffOptions);
    }
    if (!diff || git_diff_num_deltas(diff)) {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_write_tree_to, &oid, mergeIndex, self.private);
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_tree_lookup, &mergeTree, self.private, &oid);
      newCommit = [self createCommitFromCommit:replayCommit.private withTree:mergeTree updatedMessage:message updatedParents:parents updateCommitter:updateCommitter error:error];
    } else {
      newCommit = ontoCommit;
      XLOG_VERBOSE(@"Skipping replay of already applied commit \"%@\" (%@) onto commit \"%@\" (%@)", replayCommit.summary, replayCommit.shortSHA1, ontoCommit.summary, ontoCommit.shortSHA1);
    }
  }
  
cleanup:
  git_diff_free(diff);
  git_tree_free(mergeTree);
  git_index_free(mergeIndex);
  git_tree_free(ancestorTree);
  git_tree_free(ontoTree);
  git_tree_free(replayTree);
  return newCommit;
}

- (GCCommit*)replayMainLineParentsFromCommit:(GCCommit*)fromCommit
                                  uptoCommit:(GCCommit*)uptoCommit
                                  ontoCommit:(GCCommit*)ontoCommit
                              preserveMerges:(BOOL)preserveMerges
                             updateCommitter:(BOOL)updateCommitter
                               skipIdentical:(BOOL)skipIdentical
                             conflictHandler:(GCConflictHandler)handler
                                       error:(NSError**)error {
  NSMutableArray* stack = [[NSMutableArray alloc] init];
  GCCommit* walkCommit = fromCommit;
  while (1) {
    NSArray* parents = [self lookupParentsForCommit:walkCommit error:error];
    if (parents == nil) {
      return nil;
    }
    [stack insertObject:@[walkCommit, parents] atIndex:0];
    walkCommit = parents.firstObject;  // Follow main line
    if (walkCommit == nil) {
      XLOG_DEBUG_UNREACHABLE();
      GC_SET_GENERIC_ERROR(@"Unable to reach ancestor commit");
      return nil;
    }
    if ([walkCommit isEqualToCommit:uptoCommit]) {
      break;
    }
  }
  
  GCCommit* tipCommit = ontoCommit;
  for (NSArray* array in stack) {
    GCCommit* replayCommit = array[0];
    NSArray* replayParents = array[1];
    GCCommit* ancestor = replayParents[0];  // Use main line
    NSMutableArray* parents = nil;
    if (preserveMerges) {
      parents = [[NSMutableArray alloc] initWithArray:replayParents];
      [parents replaceObjectAtIndex:0 withObject:tipCommit];  // Only replace first parent and preserve others
    }
    tipCommit = [self replayCommit:replayCommit ontoCommit:tipCommit withAncestorCommit:ancestor updatedMessage:nil updatedParents:(parents ? parents : @[tipCommit]) updateCommitter:updateCommitter skipIdentical:skipIdentical conflictHandler:handler error:error];
    if (tipCommit == nil) {
      return nil;
    }
  }
  return tipCommit;
}

@end

@implementation GCRepository (Bare_Private)

- (GCCommit*)createCommitFromTree:(git_tree*)tree
                      withParents:(const git_commit**)parents
                            count:(NSUInteger)count
                           author:(const git_signature*)author
                          message:(NSString*)message
                            error:(NSError**)error {
  GCCommit* commit = nil;
  git_signature* signature = NULL;
  
  git_oid oid;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_signature_default, &signature, self.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_create, &oid, self.private, NULL, author ? author : signature, signature, NULL, GCCleanedUpCommitMessage(message).bytes, tree, count, parents);
  git_commit* newCommit = NULL;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &newCommit, self.private, &oid);
  commit = [[GCCommit alloc] initWithRepository:self commit:newCommit];
  
cleanup:
  git_signature_free(signature);
  return commit;
}

- (GCCommit*)createCommitFromIndex:(git_index*)index
                       withParents:(const git_commit**)parents
                             count:(NSUInteger)count
                            author:(const git_signature*)author
                           message:(NSString*)message
                             error:(NSError**)error {
  GCCommit* commit = nil;
  git_tree* tree = NULL;
  
  git_oid oid;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_write_tree_to, &oid, index, self.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_tree_lookup, &tree, self.private, &oid);
  
  commit = [self createCommitFromTree:tree withParents:parents count:count author:author message:message error:error];
  
cleanup:
  git_tree_free(tree);
  return commit;
}

static const git_oid* _CommitParentCallback_Parents(size_t idx, void* payload) {
  NSArray* parents = (__bridge NSArray*)payload;
  if (idx < parents.count) {
    return git_commit_id([(GCCommit*)parents[idx] private]);
  }
  return NULL;
}

static const git_oid* _CommitParentCallback_Commit(size_t idx, void* payload) {
  git_commit* commit = (git_commit*)payload;
  if (idx < git_commit_parentcount(commit)) {
    return git_commit_parent_id(commit, (unsigned int)idx);
  }
  return NULL;
}

- (GCCommit*)createCommitFromCommit:(git_commit*)commit
                          withIndex:(git_index*)index
                     updatedMessage:(NSString*)message
                     updatedParents:(NSArray*)parents
                    updateCommitter:(BOOL)updateCommitter
                              error:(NSError**)error {
  git_oid oid;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_index_write_tree_to, &oid, index, self.private);
  git_tree* tree;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_tree_lookup, &tree, self.private, &oid);
  GCCommit* newCommit = [self createCommitFromCommit:commit withTree:tree updatedMessage:message updatedParents:parents updateCommitter:updateCommitter error:error];
  git_tree_free(tree);
  return newCommit;
}

- (GCCommit*)createCommitFromCommit:(git_commit*)commit
                           withTree:(git_tree*)tree
                     updatedMessage:(NSString*)message
                     updatedParents:(NSArray*)parents
                    updateCommitter:(BOOL)updateCommitter
                              error:(NSError**)error {
  git_commit* newCommit = NULL;
  git_signature* signature = NULL;
  git_oid oid;
  
  if (updateCommitter) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_signature_default, &signature, self.private);
  }
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_create_from_callback, &oid, self.private, NULL,
                             git_commit_author(commit),
                             updateCommitter ? signature : git_commit_committer(commit),
                             message ? NULL : git_commit_message_encoding(commit), message ? GCCleanedUpCommitMessage(message).bytes : git_commit_message(commit),
                             git_tree_id(tree),
                             parents ? _CommitParentCallback_Parents : _CommitParentCallback_Commit, parents ? (__bridge void*)parents : (void*)commit);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &newCommit, self.private, &oid);
  XLOG_DEBUG_CHECK(!git_oid_equal(git_commit_id(newCommit), git_commit_id(commit)));
  
cleanup:
  git_signature_free(signature);
  return newCommit ? [[GCCommit alloc] initWithRepository:self commit:newCommit] : nil;
}

@end
