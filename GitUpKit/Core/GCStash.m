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

@interface GCStash ()
@property(nonatomic, strong) GCCommit* baseCommit;
@property(nonatomic, strong) GCCommit* indexCommit;
@property(nonatomic, strong) GCCommit* untrackedCommit;
@end

@implementation GCStashState {
  git_oid _target;
  git_reflog* _reflog;
}

- (id)initWithRepository:(git_repository*)repository error:(NSError**)error {
  if ((self = [super init])) {
    git_reference* reference;
    int status = git_reference_lookup(&reference, repository, kStashReferenceFullName);
    if (status != GIT_ENOTFOUND) {
      CHECK_LIBGIT2_FUNCTION_CALL(return nil, status, == GIT_OK);
      if (git_reference_type(reference) == GIT_REF_OID) {
        git_oid_cpy(&_target, git_reference_target(reference));
      }
      git_reference_free(reference);
      if (git_oid_iszero(&_target)) {
        XLOG_DEBUG_UNREACHABLE();
        GC_SET_GENERIC_ERROR(@"Invalid stash reference");
        return nil;
      }
      CALL_LIBGIT2_FUNCTION_RETURN(nil, git_reflog_read, &_reflog, repository, kStashReferenceFullName);
    }
  }
  return self;
}

- (void)dealloc {
  git_reflog_free(_reflog);
}

- (BOOL)restoreWithRepository:(git_repository*)repository error:(NSError**)error {
  if (_reflog) {
    git_reference* reference;
    CALL_LIBGIT2_FUNCTION_RETURN(NO, git_reference_create, &reference, repository, kStashReferenceFullName, &_target, 1, NULL);  // Reflog message doesn't matter
    git_reference_free(reference);
    CALL_LIBGIT2_FUNCTION_RETURN(NO, git_reflog_write, _reflog);
  } else {
    CALL_LIBGIT2_FUNCTION_RETURN(NO, git_reference_remove, repository, kStashReferenceFullName);  // TODO: Should we delete the reflog too?
  }
  return YES;
}

@end

@implementation GCStash
@end

// TODO: Handle submodules
@implementation GCRepository (GCStash)

- (GCStash*)_newStashFromOID:(const git_oid*)oid error:(NSError**)error {
  git_commit* commit;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_lookup, &commit, self.private, oid);
  GCStash* stash = [[GCStash alloc] initWithRepository:self commit:commit];
  
  git_commit* baseCommit;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_parent, &baseCommit, commit, 0);
  stash.baseCommit = [[GCCommit alloc] initWithRepository:self commit:baseCommit];
  
  git_commit* indexCommit;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_parent, &indexCommit, commit, 1);
  stash.indexCommit = [[GCCommit alloc] initWithRepository:self commit:indexCommit];
  
  if (git_commit_parentcount(commit) == 3) {
    git_commit* untrackedCommit;
    CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_parent, &untrackedCommit, commit, 2);
    stash.untrackedCommit = [[GCCommit alloc] initWithRepository:self commit:untrackedCommit];
  }
  
  return stash;
}

/* Git stash does the following and in this order:
 - Retrieve the HEAD as the "base commit"
 - Create a new commit from the current index tree
  - This commit has the base commit as its only parent
 - If requested, create a new commit with a special tree that contains only the files present in the working directory but not in the current index tree (i.e. "untracked files")
  - This commit has no parent
 - Create a new commit with the deleted or modified files between the base commit and the working directory
  - This commit has the base commit as its first parent, the index commit as the second parent and the optional untracked commit as the third parent
*/
- (GCStash*)saveStashWithMessage:(NSString*)message keepIndex:(BOOL)keepIndex includeUntracked:(BOOL)includeUntracked error:(NSError**)error {
  GCStash* stash = nil;
  git_index* index = NULL;
  git_signature* signature = NULL;
  
  index = [self reloadRepositoryIndex:error];  // git_stash_save() doesn't reload the repository index
  if (index == NULL) {
    goto cleanup;
  }
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_signature_default, &signature, self.private);
  int flags = 0;
  if (keepIndex) {
    flags |= GIT_STASH_KEEP_INDEX;
  }
  if (includeUntracked) {
    flags |= GIT_STASH_INCLUDE_UNTRACKED;
  }
  git_oid oid;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_stash_save, &oid, self.private, signature, GCCleanedUpCommitMessage(message).bytes, flags);
  stash = [self _newStashFromOID:&oid error:error];
  
cleanup:
  git_signature_free(signature);
  git_index_free(index);
  return stash;
}

- (NSArray*)listStashes:(NSError**)error {
  NSMutableArray* array = [[NSMutableArray alloc] init];
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_stash_foreach_block, self.private, ^int(size_t index, const char* message, const git_oid* stash_id) {
    
    XLOG_DEBUG_CHECK(array.count == index);
    GCStash* stash = [self _newStashFromOID:stash_id error:error];
    if (stash == nil) {
      return GIT_ERROR;
    }
    [array addObject:stash];
    return GIT_OK;
    
  });
  return array;
}

- (NSUInteger)_indexOfStash:(GCStash*)stash error:(NSError**)error {
  const git_oid* oid = git_commit_id(stash.private);
  __block NSUInteger stashIndex = NSNotFound;
  CALL_LIBGIT2_FUNCTION_RETURN(NSNotFound, git_stash_foreach_block, self.private, ^int(size_t index, const char* message, const git_oid* stash_id) {
    
    if (git_oid_equal(stash_id, oid)) {
      XLOG_DEBUG_CHECK(stashIndex == NSNotFound);
      stashIndex = index;
    }
    return GIT_OK;
    
  });
  if (stashIndex == NSNotFound) {
    GC_SET_GENERIC_ERROR(@"Stash does not exist");
  }
  return stashIndex;
}

- (BOOL)applyStash:(GCStash*)stash restoreIndex:(BOOL)restoreIndex error:(NSError**)error {
  git_index* index = [self reloadRepositoryIndex:error];  // git_stash_apply() doesn't reload the repository index
  if (index == NULL) {
    return NO;
  }
  git_index_free(index);
  
  NSUInteger i = [self _indexOfStash:stash error:error];
  if (i == NSNotFound) {
    return NO;
  }
  
  git_stash_apply_options options = GIT_STASH_APPLY_OPTIONS_INIT;
  if (restoreIndex) {
    options.flags |= GIT_STASH_APPLY_REINSTATE_INDEX;
  }
  options.checkout_options.checkout_strategy = GIT_CHECKOUT_SAFE;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_stash_apply, self.private, i, &options);
  return YES;
}

- (BOOL)dropStash:(GCStash*)stash error:(NSError**)error {
  NSUInteger i = [self _indexOfStash:stash error:error];
  if (i == NSNotFound) {
    return NO;
  }
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_stash_drop, self.private, i);
  return YES;
}

- (BOOL)popStash:(GCStash*)stash restoreIndex:(BOOL)restoreIndex error:(NSError**)error {
  git_index* index = [self reloadRepositoryIndex:error];  // git_stash_pop() doesn't reload the repository index
  if (index == NULL) {
    return NO;
  }
  git_index_free(index);
  
  NSUInteger i = [self _indexOfStash:stash error:error];
  if (i == NSNotFound) {
    return NO;
  }
  
  git_stash_apply_options options = GIT_STASH_APPLY_OPTIONS_INIT;
  if (restoreIndex) {
    options.flags |= GIT_STASH_APPLY_REINSTATE_INDEX;
  }
  options.checkout_options.checkout_strategy = GIT_CHECKOUT_SAFE;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_stash_pop, self.private, i, &options);
  return YES;
}

- (GCStashState*)saveStashState:(NSError**)error {
  return [[GCStashState alloc] initWithRepository:self.private error:error];
}

- (BOOL)restoreStashState:(GCStashState*)state error:(NSError**)error {
  return [state restoreWithRepository:self.private error:error];
}

@end
