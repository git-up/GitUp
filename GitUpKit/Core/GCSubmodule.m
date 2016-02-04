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

extern int git_path_make_relative(git_buf *path, const char *parent);  // SPI

@implementation GCSubmodule {
  __unsafe_unretained GCRepository* _repository;
}

- (instancetype)initWithRepository:(GCRepository*)repository submodule:(git_submodule*)submodule {
  if ((self = [super init])) {
    _repository = repository;
    _private = submodule;
    [self _reload];
  }
  return self;
}

- (void)dealloc {
  git_submodule_free(_private);
}

- (void)_reload {
  _name = [NSString stringWithUTF8String:git_submodule_name(_private)];
  const char* path = git_submodule_path(_private);
  _path = GCFileSystemPathFromGitPath(path);
  const char* url = git_submodule_url(_private);
  _URL = url ? GCURLFromGitURL([NSString stringWithUTF8String:url]) : nil;
  const char* branch = git_submodule_branch(_private);
  _remoteBranchName = branch ? [NSString stringWithUTF8String:branch] : nil;
  switch (git_submodule_ignore(_private)) {
    case GIT_SUBMODULE_IGNORE_NONE: _ignoreMode = kGCSubmoduleIgnoreMode_None; break;
    case GIT_SUBMODULE_IGNORE_UNTRACKED: _ignoreMode = kGCSubmoduleIgnoreMode_Untracked; break;
    case GIT_SUBMODULE_IGNORE_DIRTY: _ignoreMode = kGCSubmoduleIgnoreMode_Dirty; break;
    case GIT_SUBMODULE_IGNORE_ALL: _ignoreMode = kGCSubmoduleIgnoreMode_All; break;
    case GIT_SUBMODULE_IGNORE_UNSPECIFIED: XLOG_DEBUG_UNREACHABLE();
  }
  switch (git_submodule_fetch_recurse_submodules(_private)) {
    case GIT_SUBMODULE_RECURSE_NO: _fetchRecurseMode = kGCSubmoduleFetchRecurseMode_No; break;
    case GIT_SUBMODULE_RECURSE_YES: _fetchRecurseMode = kGCSubmoduleFetchRecurseMode_Yes; break;
    case GIT_SUBMODULE_RECURSE_ONDEMAND: _fetchRecurseMode = kGCSubmoduleFetchRecurseMode_OnDemand; break;
  }
  switch (git_submodule_update_strategy(_private)) {
    case GIT_SUBMODULE_UPDATE_CHECKOUT: _updateMode = kGCSubmoduleUpdateMode_Checkout; break;
    case GIT_SUBMODULE_UPDATE_REBASE: _updateMode = kGCSubmoduleUpdateMode_Rebase; break;
    case GIT_SUBMODULE_UPDATE_MERGE: _updateMode = kGCSubmoduleUpdateMode_Merge; break;
    case GIT_SUBMODULE_UPDATE_NONE: _updateMode = kGCSubmoduleUpdateMode_None; break;
    case GIT_SUBMODULE_UPDATE_DEFAULT: XLOG_DEBUG_UNREACHABLE();
  }
}

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@] %@ = \"%@\" (%@)", self.class, _name, _path, GCGitURLFromURL(_URL)];
}

@end

@implementation GCRepository (GCSubmodule)

- (instancetype)initWithSubmodule:(GCSubmodule*)submodule error:(NSError**)error {
  git_repository* repository;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_submodule_open, &repository, submodule.private);
  return [self initWithRepository:repository error:error];
}

- (BOOL)checkSubmoduleInitialized:(GCSubmodule*)submodule error:(NSError**)error {
  unsigned int status;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_submodule_status, &status, self.private, git_submodule_name(submodule.private), GIT_SUBMODULE_IGNORE_DIRTY);
  if (status & GIT_SUBMODULE_STATUS_WD_UNINITIALIZED) {
    GC_SET_ERROR(kGCErrorCode_SubmoduleUninitialized, @"Submodule is not initialized");
    return NO;
  }
  return YES;
}

- (BOOL)checkAllSubmodulesInitialized:(BOOL)recursive error:(NSError**)error {
  NSArray* submodules = [self listSubmodules:error];
  if (submodules == nil) {
    return NO;
  }
  for (GCSubmodule* submodule in submodules) {
    if (![self checkSubmoduleInitialized:submodule error:error]) {
      return NO;
    }
    if (recursive) {
      NSError* localError;
      GCRepository* repository = [[GCRepository alloc] initWithSubmodule:submodule error:&localError];
      if (repository == nil) {
        if ([localError.domain isEqualToString:GCErrorDomain] && (localError.code == kGCErrorCode_NotFound)) {
          continue;
        }
        if (error) {
          *error = localError;
        }
        return NO;
      }
      if (![repository checkAllSubmodulesInitialized:recursive error:error]) {
        return NO;
      }
    }
  }
  return YES;
}

- (GCSubmodule*)addSubmoduleWithURL:(NSURL*)url atPath:(NSString*)path recursive:(BOOL)recursive error:(NSError**)error {
  BOOL success = NO;
  git_submodule* submodule = NULL;
  GCRepository* repository;
  GCRemote* remote;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_submodule_add_setup, &submodule, self.private, GCGitURLFromURL(url).UTF8String, GCGitPathFromFileSystemPath(path), true);
  git_repository* subRepository;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_submodule_open, &subRepository, submodule);
  repository = [[GCRepository alloc] initWithRepository:subRepository error:error];
  if (repository == nil) {
    goto cleanup;
  }
  repository.delegate = self.delegate;
  remote = [repository lookupRemoteWithName:@"origin" error:error];
  if (remote == nil) {
    goto cleanup;
  }
  if (![repository cloneUsingRemote:remote recursive:recursive error:error]) {
    goto cleanup;
  }
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_submodule_add_finalize, submodule);  // This just calls git_submodule_add_to_index()
  success = YES;
  
cleanup:
  if (!success) {
    git_submodule_free(submodule);
  }
  return success ? [[GCSubmodule alloc] initWithRepository:self submodule:submodule] : nil;
}

- (BOOL)initializeSubmodule:(GCSubmodule*)submodule recursive:(BOOL)recursive error:(NSError**)error {
  XLOG_DEBUG_CHECK(![self checkSubmoduleInitialized:submodule error:NULL]);
  
  NSString* modulePath = [[self.repositoryPath stringByAppendingPathComponent:@"modules"] stringByAppendingPathComponent:submodule.path];
  if ([[NSFileManager defaultManager] fileExistsAtPath:modulePath] && ![[NSFileManager defaultManager] removeItemAtPath:modulePath error:error]) {
    return NO;
  }
  
  git_submodule_update_options options = GIT_SUBMODULE_UPDATE_OPTIONS_INIT;
  [self setRemoteCallbacks:&options.fetch_opts.callbacks];
  [self willStartRemoteTransferWithURL:submodule.URL];
  int status = git_submodule_update(submodule.private, true, &options);  // This actually does a clone if the submodule is not initialized
  [self didFinishRemoteTransferWithURL:submodule.URL success:(status == GIT_OK)];
  CHECK_LIBGIT2_FUNCTION_CALL(return NO, status, == GIT_OK);
  
  if (recursive) {
    GCRepository* repository = [[GCRepository alloc] initWithSubmodule:submodule error:error];
    if (repository == nil) {
      return NO;
    }
    repository.delegate = self.delegate;
    if (![repository initializeAllSubmodules:recursive error:error]) {
      return NO;
    }
  }
  
  return YES;
}

- (BOOL)initializeAllSubmodules:(BOOL)recursive error:(NSError**)error {
  NSArray* submodules = [self listSubmodules:error];
  if (submodules == nil) {
    return NO;
  }
  for (GCSubmodule* submodule in submodules) {
    if (![self checkSubmoduleInitialized:submodule error:NULL]) {  // Ignore errors
      if (![self initializeSubmodule:submodule recursive:recursive error:error]) {
        return NO;
      }
    }
    if (recursive) {
      GCRepository* repository = [[GCRepository alloc] initWithSubmodule:submodule error:error];
      if (repository == nil) {
        return NO;
      }
      if (![repository initializeAllSubmodules:recursive error:error]) {
        return NO;
      }
    }
  }
  return YES;
}

- (GCSubmodule*)lookupSubmoduleWithName:(NSString*)name error:(NSError**)error {
  git_submodule* submodule;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_submodule_lookup, &submodule, self.private, name.UTF8String);
  return [[GCSubmodule alloc] initWithRepository:self submodule:submodule];
}

- (NSArray*)listSubmodules:(NSError**)error {
  NSMutableArray* submodules = [[NSMutableArray alloc] init];
  int status = git_submodule_foreach_block(self.private, ^int(git_submodule* submodule, const char* name) {  // This calls git_submodule_reload_all(false)
    git_submodule_retain(submodule);
    [submodules addObject:[[GCSubmodule alloc] initWithRepository:self submodule:submodule]];
    return GIT_OK;
  });
  CHECK_LIBGIT2_FUNCTION_CALL(return nil, status, == GIT_OK);
  return submodules;
}

- (BOOL)updateSubmodule:(GCSubmodule*)submodule force:(BOOL)force error:(NSError**)error {
  BOOL success = NO;
  git_repository* subRepository = NULL;
  git_index* index = NULL;
  git_commit* commit = NULL;
  
  switch (git_submodule_update_strategy(submodule.private)) {
    
    case GIT_SUBMODULE_UPDATE_NONE: {
      success = YES;
      break;
    }
    
    // Reimplement git_submodule_update() when no submodule initialization is needed
    case GIT_SUBMODULE_UPDATE_CHECKOUT: {
      CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
      BOOL recreate = NO;
      index = [self reloadRepositoryIndex:error];
      if (index == NULL) {
        goto cleanup;
      }
      const git_index_entry* entry = git_index_get_bypath(index, git_submodule_path(submodule.private), 0);  // We cannot use git_submodule_index_id() as it returns cached information which may be out-of-date and requires an expensive call to git_submodule_reload()
      if (!entry || (entry->mode != GIT_FILEMODE_COMMIT)) {
        GC_SET_GENERIC_ERROR(@"Submodule not in index");
        goto cleanup;
      }
      int status = git_submodule_open(&subRepository, submodule.private);
      if (status == GIT_ENOTFOUND) {  // This means the repository was not initialized or its working directory is gone
        NSString* modulePath = [[self.repositoryPath stringByAppendingPathComponent:@"modules"] stringByAppendingPathComponent:submodule.path];
        git_repository* moduleRepository;
        CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_open, &moduleRepository, modulePath.fileSystemRepresentation);  // If the working directory is gone, then we must have a module around, otherwise the submodule was not initialized
        status = git_repository_update_gitlink(moduleRepository, true);  // This re-creates the workdir and its parent directories and the gitlink inside
        git_repository_free(moduleRepository);
        CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
        status = git_submodule_open(&subRepository, submodule.private);
        recreate = YES;
      }
      CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &commit, subRepository, &entry->id);
      git_checkout_options options = GIT_CHECKOUT_OPTIONS_INIT;
      options.checkout_strategy = force ? GIT_CHECKOUT_FORCE : (recreate ? GIT_CHECKOUT_RECREATE_MISSING : GIT_CHECKOUT_SAFE);
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_checkout_tree, subRepository, (git_object*)commit, &options);
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_set_head_detached, subRepository, &entry->id);
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_submodule_reload, submodule.private, false);  // "force" argument is unused anyway!
      success = YES;
      XLOG_VERBOSE(@"Updated submodule \"%@\" in \"%@\" in %.3f seconds", submodule.name, self.repositoryPath, CFAbsoluteTimeGetCurrent() - time);
      break;
    }
    
    default:
      GC_SET_GENERIC_ERROR(@"Unsupported update mode for submodule \"%@\"", submodule.name);
      break;
    
  }
  
cleanup:
  git_commit_free(commit);
  git_index_free(index);
  git_repository_free(subRepository);
  return success;
}

- (BOOL)updateAllSubmodulesResursively:(BOOL)force error:(NSError**)error {
  NSArray* submodules = [self listSubmodules:error];
  if (submodules == nil) {
    return NO;
  }
  for (GCSubmodule* submodule in submodules) {
    NSError* localError;
    if (![self updateSubmodule:submodule force:force error:&localError]) {
      if ([localError.domain isEqualToString:GCErrorDomain] && (localError.code == kGCErrorCode_NotFound)) {
        continue;
      }
      if (error) {
        *error = localError;
      }
      return NO;
    }
    GCRepository* repository = [[GCRepository alloc] initWithSubmodule:submodule error:error];
    if (![repository updateAllSubmodulesResursively:force error:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)addSubmoduleToRepositoryIndex:(GCSubmodule*)submodule error:(NSError**)error {
  git_index* index = [self reloadRepositoryIndex:error];
  if (index == NULL) {
    return NO;
  }
  git_index_free(index);
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_submodule_add_to_index, submodule.private, true);  // This doesn't reload the index before adding to it
  return YES;
}

@end
