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

@implementation GCIndexConflict {
  git_oid _ancestorOID;
  git_oid _ourOID;
  git_oid _theirOID;
}

- (id)initWithAncestor:(const git_index_entry*)ancestor our:(const git_index_entry*)our their:(const git_index_entry*)their {
  if ((self = [super init])) {
    if (our && their) {
      XLOG_DEBUG_CHECK(!strcmp(our->path, their->path));
      _status = ancestor ? kGCIndexConflictStatus_BothModified : kGCIndexConflictStatus_BothAdded;
      
      git_oid_cpy(&_ourOID, &our->id);
      XLOG_DEBUG_CHECK((our->mode == GIT_FILEMODE_BLOB) || (our->mode == GIT_FILEMODE_BLOB_EXECUTABLE) || (our->mode == GIT_FILEMODE_LINK));
      _ourFileMode = GCFileModeFromMode(our->mode);
      
      git_oid_cpy(&_theirOID, &their->id);
      XLOG_DEBUG_CHECK((their->mode == GIT_FILEMODE_BLOB) || (their->mode == GIT_FILEMODE_BLOB_EXECUTABLE) || (their->mode == GIT_FILEMODE_LINK));
      _theirFileMode = GCFileModeFromMode(their->mode);
    } else if (our) {
      XLOG_DEBUG_CHECK(!strcmp(our->path, ancestor->path));
      _status = kGCIndexConflictStatus_DeletedByThem;
      
      git_oid_cpy(&_ourOID, &our->id);
      XLOG_DEBUG_CHECK((our->mode == GIT_FILEMODE_BLOB) || (our->mode == GIT_FILEMODE_BLOB_EXECUTABLE) || (our->mode == GIT_FILEMODE_LINK));
      _ourFileMode = GCFileModeFromMode(our->mode);
    } else if (their) {
      XLOG_DEBUG_CHECK(!strcmp(their->path, ancestor->path));
      _status = kGCIndexConflictStatus_DeletedByUs;
      
      git_oid_cpy(&_theirOID, &their->id);
      XLOG_DEBUG_CHECK((their->mode == GIT_FILEMODE_BLOB) || (their->mode == GIT_FILEMODE_BLOB_EXECUTABLE) || (their->mode == GIT_FILEMODE_LINK));
      _theirFileMode = GCFileModeFromMode(their->mode);
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }
    if (ancestor) {
      git_oid_cpy(&_ancestorOID, &ancestor->id);
      XLOG_DEBUG_CHECK((ancestor->mode == GIT_FILEMODE_BLOB) || (ancestor->mode == GIT_FILEMODE_BLOB_EXECUTABLE) || (ancestor->mode == GIT_FILEMODE_LINK));
      _ancestorFileMode = GCFileModeFromMode(ancestor->mode);
    }
    if (our) {
      _path = GCFileSystemPathFromGitPath(our->path);
    } else if (their) {
      _path = GCFileSystemPathFromGitPath(their->path);
    } else if (ancestor) {
      _path = GCFileSystemPathFromGitPath(ancestor->path);
    } else {
      XLOG_DEBUG_UNREACHABLE();
      return nil;
    }
  }
  return self;
}

- (const git_oid*)ancestorOID {
  return &_ancestorOID;
}

- (NSString*)ancestorBlobSHA1 {
  return GCGitOIDToSHA1(&_ancestorOID);
}

- (const git_oid*)ourOID {
  return &_ourOID;
}

- (NSString*)ourBlobSHA1 {
  return GCGitOIDToSHA1(&_ourOID);
}

- (const git_oid*)theirOID {
  return &_theirOID;
}

- (NSString*)theirBlobSHA1 {
  return GCGitOIDToSHA1(&_theirOID);
}

static inline BOOL _EqualConflicts(GCIndexConflict* conflict1, GCIndexConflict* conflict2) {
  if (conflict1->_status != conflict2->_status) {
    return NO;
  }
  return [conflict1->_path isEqualToString:conflict2->_path];
}

- (BOOL)isEqualToIndexConflict:(GCIndexConflict*)conflict {
  return (self == conflict) || _EqualConflicts(self, conflict);
}

- (BOOL)isEqual:(id)object {
  if (![object isKindOfClass:[GCIndexConflict class]]) {
    return NO;
  }
  return [self isEqualToIndexConflict:object];
}

- (NSString*)description {
  const char* statuses[] = {"None", "Both Modified", "Both Added", "Deleted By Us", "Deleted By Them"};
  return [NSString stringWithFormat:@"%@ %s \"%@\"\n  Ancestor: %@\n  Ours: %@\n  Theirs: %@", self.class, statuses[_status], _path, self.ancestorBlobSHA1, self.ourBlobSHA1, self.theirBlobSHA1];
}

@end

@implementation GCRepository (Status)

- (NSDictionary*)checkConflicts:(NSError**)error {
  BOOL success = NO;
  NSMutableDictionary* result = [[NSMutableDictionary alloc] init];
  git_index_conflict_iterator* iterator = NULL;
  
  git_index* index = [self reloadRepositoryIndex:error];
  if (index == NULL) {
    goto cleanup;
  }
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_conflict_iterator_new, &iterator, index);
  while (1) {
    const git_index_entry* ancestor;
    const git_index_entry* our;
    const git_index_entry* their;
    int output = git_index_conflict_next(&ancestor, &our, &their, iterator);
    if (output == GIT_ITEROVER) {
      break;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, output, == GIT_OK);
    GCIndexConflict* conflict = [[GCIndexConflict alloc] initWithAncestor:ancestor our:our their:their];
    if (conflict) {
      [result setObject:conflict forKey:conflict.path];
    } else {
      XLOG_WARNING(@"Invalid status conflict generated in repository \"%@\"", self.repositoryPath);
      XLOG_DEBUG_UNREACHABLE();
    }
  }
  success = YES;
  
cleanup:
  git_index_conflict_iterator_free(iterator);
  git_index_free(index);
  return success ? result : nil;
}

// Because we don't set GIT_DIFF_ENABLE_FAST_UNTRACKED_DIRS, the callback can still be called when poking inside an untracked dir that may actually only contain ignored files
static int _DiffNotifyCallback(const git_diff* diff_so_far, const git_diff_delta* delta_to_add, const char* matched_pathspec, void* payload) {
  if ((delta_to_add->nfiles == 1) && (delta_to_add->status == GIT_DELTA_UNTRACKED) && (delta_to_add->new_file.path[strlen(delta_to_add->new_file.path) - 1] == '/')) {
    return GIT_OK;
  }
  *(git_delta_t*)payload = delta_to_add->status;
  return GIT_EUSER;
}

- (BOOL)checkClean:(GCCleanCheckOptions)options error:(NSError**)error {
  BOOL clean = NO;
  git_commit* commit = NULL;
  git_tree* tree = NULL;
  git_diff* diff1 = NULL;
  git_diff* diff2 = NULL;
  git_diff_options diffOptions = GIT_DIFF_OPTIONS_INIT;
  git_delta_t delta_status = GIT_DELTA_UNMODIFIED;
  int status;
  
  // Prepare
  diffOptions.flags = GIT_DIFF_SKIP_BINARY_CHECK;  // This should not be needed since not generating patches anyway
  diffOptions.notify_cb = _DiffNotifyCallback;
  diffOptions.notify_payload = &delta_status;
  git_index* index = [self reloadRepositoryIndex:error];
  if (index == NULL) {
    goto cleanup;
  }
  
  // Check repository state
  if (!(options & kGCCleanCheckOption_IgnoreState)) {
    if (git_repository_state(self.private) != GIT_REPOSITORY_STATE_NONE) {
      GC_SET_ERROR(kGCErrorCode_RepositoryDirty, @"Repository has an in-progress operation");
      goto cleanup;
    }
  }
  
  // Check index conflicts
  if (!(options & kGCCleanCheckOption_IgnoreIndexConflicts)) {
    if (git_index_has_conflicts(index)) {
      GC_SET_ERROR(kGCErrorCode_RepositoryDirty, @"Index has conflicts");
      goto cleanup;
    }
  }
  
  // Check index changes
  if (!(options & kGCCleanCheckOption_IgnoreIndexChanges)) {
    if (![self loadHEADCommit:&commit resolvedReference:NULL error:error]) {
      goto cleanup;
    }
    if (commit) {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &tree, commit);
    }
    status = git_diff_tree_to_index(&diff1, self.private, tree, index, &diffOptions);
    if ((status == GIT_EUSER) || ((status == GIT_OK) && (git_diff_num_deltas(diff1) > 0))) {
      GC_SET_ERROR(kGCErrorCode_RepositoryDirty, @"Index has changes");
      goto cleanup;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
  }
  
  // Check working directory changes
  if (!(options & kGCCleanCheckOption_IgnoreWorkingDirectoryChanges)) {
    if (!(options & kGCCleanCheckOption_IgnoreUntrackedFiles)) {
      diffOptions.flags |= GIT_DIFF_INCLUDE_UNTRACKED;
    }
    status = git_diff_index_to_workdir(&diff2, self.private, index, &diffOptions);  // TODO: Should we set GIT_DIFF_UPDATE_INDEX?
    if ((status == GIT_EUSER) || ((status == GIT_OK) && (git_diff_num_deltas(diff2) > 0))) {
      if (status == GIT_OK) {
        delta_status = git_diff_get_delta(diff2, 0)->status;
      }
      if (delta_status == GIT_DELTA_UNTRACKED) {
        GC_SET_ERROR(kGCErrorCode_RepositoryDirty, @"Working directory contains untracked files");
      } else {
        XLOG_DEBUG_CHECK(delta_status != GIT_DELTA_UNMODIFIED);
        GC_SET_ERROR(kGCErrorCode_RepositoryDirty, @"Working directory contains modified files");
      }
      goto cleanup;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
  }
  
  // We're clean
  clean = YES;
  
cleanup:
  git_diff_free(diff2);
  git_diff_free(diff1);
  git_tree_free(tree);
  git_commit_free(commit);
  git_index_free(index);
  return clean;
}

@end
