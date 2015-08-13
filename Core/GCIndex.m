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

#import <copyfile.h>
#import <sys/attr.h>
#import <sys/stat.h>

#import "GCPrivate.h"

// libgit2 SPI
extern void git_index_entry__init_from_stat(git_index_entry *entry, struct stat *st, bool trust_mode);

@implementation GCIndex

- (instancetype)initWithRepository:(GCRepository*)repository index:(git_index*)index {
  if ((self = [super init])) {
    _repository = repository;
    _private = index;
  }
  return self;
}

- (void)dealloc {
  git_index_free(_private);
}

- (BOOL)isInMemory {
  return _repository ? NO : YES;
}

- (BOOL)isEmpty {
  return (git_index_entrycount(_private) == 0);
}

- (const git_oid*)OIDForFile:(NSString*)path {
  const git_index_entry* entry = git_index_get_bypath(_private, GCGitPathFromFileSystemPath(path), 0);
  return entry ? &entry->id : NULL;
}

- (NSString*)SHA1ForFile:(NSString*)path mode:(GCFileMode*)mode {
  const git_index_entry* entry = git_index_get_bypath(_private, GCGitPathFromFileSystemPath(path), 0);
  if (entry == NULL) {
    return nil;
  }
  if (mode) {
    *mode = GCFileModeFromMode(entry->mode);
  }
  return GCGitOIDToSHA1(&entry->id);
}

- (NSString*)description {
  size_t count = git_index_entrycount(_private);
  NSMutableString* string = [[NSMutableString alloc] initWithFormat:@"%@ (%lu entries)", self.class, count];
  for (size_t i = 0; i < count; ++i) {
    const git_index_entry* entry = git_index_get_byindex(_private, i);
    if (git_index_entry_stage(entry) == 0) {
      [string appendFormat:@"\n[%s] %s", git_oid_tostr_s(&entry->id), entry->path];
    }
  }
  return string;
}

@end

@implementation GCRepository (GCIndex)

- (GCIndex*)createInMemoryIndex:(NSError**)error {
  git_index* memoryIndex;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_index_new, &memoryIndex);
  GCIndex* index = [[GCIndex alloc] initWithRepository:nil index:memoryIndex];
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_index_set_caps, memoryIndex, GIT_INDEXCAP_IGNORE_CASE);
  return index;
}

- (GCIndex*)readRepositoryIndex:(NSError**)error {
  git_index* index = [self reloadRepositoryIndex:error];
  return index ? [[GCIndex alloc] initWithRepository:self index:index] : nil;
}

- (BOOL)writeRepositoryIndex:(GCIndex*)index error:(NSError**)error {
  XLOG_DEBUG_CHECK(!index.inMemory);
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_index_write, index.private);
  return YES;
}

- (BOOL)resetIndex:(GCIndex*)index toTreeForCommit:(GCCommit*)commit error:(NSError**)error {
  BOOL success = NO;
  git_tree* tree = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &tree, commit.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_read_tree, index.private, tree);
  success = YES;
  
cleanup:
  git_tree_free(tree);
  return success;
}

- (BOOL)clearIndex:(GCIndex*)index error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_index_clear, index.private);
  return YES;
}

// Like git_index_add_frombuffer() but works with memory indexes and doesn't clear any conflict at path
- (BOOL)_addEntry:(const git_index_entry*)entry toIndex:(git_index*)index withData:(NSData*)data error:(NSError**)error {
  git_oid oid;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_blob_create_frombuffer, &oid, self.private, data.bytes, data.length);
  git_index_entry copyEntry;
  bcopy(entry, &copyEntry, sizeof(git_index_entry));
  git_oid_cpy(&copyEntry.id, &oid);
  copyEntry.file_size = (uint32_t)data.length;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_index_add, index, &copyEntry);
  return YES;
}

// Like git_index_add_bypath() but works with memory indexes and doesn't clear any conflict at path
- (BOOL)_addEntry:(const git_index_entry*)entry toIndex:(git_index*)index error:(NSError**)error {
  git_oid oid;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_blob_create_fromworkdir, &oid, self.private, entry->path);
  git_index_entry copyEntry;
  bcopy(entry, &copyEntry, sizeof(git_index_entry));
  git_oid_cpy(&copyEntry.id, &oid);
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_index_add, index, &copyEntry);
  return YES;
}

- (BOOL)addFile:(NSString*)path withContents:(NSData*)contents toIndex:(GCIndex*)index error:(NSError**)error {
  git_index_entry entry;
  bzero(&entry, sizeof(git_index_entry));
  entry.path = GCGitPathFromFileSystemPath(path);
  entry.mode = GIT_FILEMODE_BLOB;
  return [self _addEntry:&entry toIndex:index.private withData:contents error:error];
}

- (BOOL)addFileInWorkingDirectory:(NSString*)path toIndex:(GCIndex*)index error:(NSError**)error {
  struct stat info;
  CALL_POSIX_FUNCTION_RETURN(NO, lstat, [[self absolutePathForFile:path] fileSystemRepresentation], &info);
  git_index_entry entry;
  bzero(&entry, sizeof(git_index_entry));
  entry.path = GCGitPathFromFileSystemPath(path);
  git_index_entry__init_from_stat(&entry, &info, true);
  return [self _addEntry:&entry toIndex:index.private error:error];
}

- (BOOL)addLinesInWorkingDirectoryFile:(NSString*)path toIndex:(GCIndex*)index error:(NSError**)error usingFilter:(GCIndexLineFilter)filter {
  const char* filePath = GCGitPathFromFileSystemPath(path);
  
  // If the file is already in the index, preserve the entry, otherwise create a new entry from the file metadata
  git_index_entry entry;
  const git_index_entry* entryPtr = git_index_get_bypath(index.private, filePath, 0);
  if (entryPtr == NULL) {
    struct stat info;
    CALL_POSIX_FUNCTION_RETURN(NO, lstat, [[self absolutePathForFile:path] fileSystemRepresentation], &info);
    bzero(&entry, sizeof(git_index_entry));
    entry.path = filePath;
    git_index_entry__init_from_stat(&entry, &info, true);
    entryPtr = &entry;
  }
  NSMutableData* data = [[NSMutableData alloc] initWithCapacity:(1024 * 1024)];
  
  // Diff file in working directory with index and create in-memory file copy excluding the lines we don't want
  GCDiff* diff = [self diffWorkingDirectoryWithIndex:index
                                         filePattern:path
                                             options:(kGCDiffOption_IncludeUntracked | kGCDiffOption_IncludeIgnored)
                                   maxInterHunkLines:NSUIntegerMax
                                     maxContextLines:NSUIntegerMax
                                               error:error];
  if (diff == nil) {
    return NO;
  }
  if (diff.deltas.count != 1) {
    GC_SET_GENERIC_ERROR(@"Internal inconsistency");
    return NO;
  }
  GCDiffPatch* patch = [self makePatchForDiffDelta:diff.deltas[0] isBinary:NULL error:error];
  if (patch == nil) {
    return NO;
  }
  [patch enumerateUsingBeginHunkHandler:NULL lineHandler:^(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber, const char* contentBytes, NSUInteger contentLength) {
    
    /* Comparing workdir to index:
     
     Change      | Filter     | Write?
     ------------|------------|------------
     Unmodified  | -          | YES
     ------------|------------|------------
     Added       | YES        | YES
                 | NO         | NO
     ------------|------------|------------
     Deleted     | YES        | NO
                 | NO         | YES
     
     */
    BOOL shouldWrite = YES;
    switch (change) {
      case kGCLineDiffChange_Unmodified: break;
      case kGCLineDiffChange_Added: shouldWrite = filter(change, oldLineNumber, newLineNumber); break;
      case kGCLineDiffChange_Deleted: shouldWrite = !filter(change, oldLineNumber, newLineNumber); break;
    }
    if (shouldWrite) {
      [data appendBytes:contentBytes length:contentLength];
    }
    
  } endHunkHandler:NULL];
  
  return [self _addEntry:entryPtr toIndex:index.private withData:data error:error];
}

- (BOOL)resetFile:(NSString*)path inIndex:(GCIndex*)index toCommit:(GCCommit*)commit error:(NSError**)error {
  BOOL success = NO;
  git_tree* tree = NULL;
  git_tree_entry* treeEntry = NULL;
  const char* filePath = GCGitPathFromFileSystemPath(path);
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &tree, commit.private);
  int status = git_tree_entry_bypath(&treeEntry, tree, filePath);
  if (status == GIT_ENOTFOUND) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_remove, index.private, filePath, 0);
  } else {
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
    git_index_entry indexEntry;
    bzero(&indexEntry, sizeof(git_index_entry));
    indexEntry.path = filePath;
    indexEntry.mode = git_tree_entry_filemode(treeEntry);
    git_oid_cpy(&indexEntry.id, git_tree_entry_id(treeEntry));
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_add, index.private, &indexEntry);
  }
  success = YES;
  
cleanup:
  git_tree_entry_free(treeEntry);
  git_tree_free(tree);
  return success;
}

- (BOOL)resetLinesInFile:(NSString*)path index:(GCIndex*)index toCommit:(GCCommit*)commit error:(NSError**)error usingFilter:(GCIndexLineFilter)filter {
  const char* filePath = GCGitPathFromFileSystemPath(path);
  
  // If the file is already in the index, preserve the entry, otherwise create a new entry from the file blob
  git_index_entry entry;
  const git_index_entry* entryPtr = git_index_get_bypath(index.private, filePath, 0);
  if (entryPtr == NULL) {
    git_tree* tree;
    CALL_LIBGIT2_FUNCTION_RETURN(NO, git_commit_tree, &tree, commit.private);
    git_tree_entry* treeEntry;
    int status = git_tree_entry_bypath(&treeEntry, tree, filePath);
    git_tree_free(tree);
    CHECK_LIBGIT2_FUNCTION_CALL(return NO, status, == GIT_OK);
    bzero(&entry, sizeof(git_index_entry));
    entry.path = filePath;
    entry.mode = git_tree_entry_filemode(treeEntry);
    entryPtr = &entry;
    git_tree_entry_free(treeEntry);
  }
  NSMutableData* data = [[NSMutableData alloc] initWithCapacity:(1024 * 1024)];
  
  // Diff file in index directory with commit and create temporary file in memory excluding the lines we don't want
  GCDiff* diff = [self diffIndex:index withCommit:commit filePattern:path options:0 maxInterHunkLines:NSUIntegerMax maxContextLines:NSUIntegerMax error:error];
  if (diff == nil) {
    return NO;
  }
  if (diff.deltas.count != 1) {
    GC_SET_GENERIC_ERROR(@"Internal inconsistency");
    return NO;
  }
  GCDiffPatch* patch = [self makePatchForDiffDelta:diff.deltas[0] isBinary:NULL error:error];
  if (patch == nil) {
    return NO;
  }
  [patch enumerateUsingBeginHunkHandler:NULL lineHandler:^(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber, const char* contentBytes, NSUInteger contentLength) {
    
    /* Comparing index to commit:
     
     Change      | Filter     | Write?
     ------------|------------|------------
     Unmodified  | -          | YES
     ------------|------------|------------
     Added       | YES        | NO
                 | NO         | YES
     ------------|------------|------------
     Deleted     | YES        | YES
                 | NO         | NO
     
     */
    BOOL shouldWrite = YES;
    switch (change) {
      case kGCLineDiffChange_Unmodified: break;
      case kGCLineDiffChange_Added: shouldWrite = !filter(change, oldLineNumber, newLineNumber); break;
      case kGCLineDiffChange_Deleted: shouldWrite = filter(change, oldLineNumber, newLineNumber); break;
    }
    if (shouldWrite) {
      [data appendBytes:contentBytes length:contentLength];
    }
    
  } endHunkHandler:NULL];
  
  return [self _addEntry:entryPtr toIndex:index.private withData:data error:error];
}

- (BOOL)checkoutFileToWorkingDirectory:(NSString*)path fromIndex:(GCIndex*)index error:(NSError**)error {
  git_checkout_options options = GIT_CHECKOUT_OPTIONS_INIT;
  options.checkout_strategy = GIT_CHECKOUT_FORCE | GIT_CHECKOUT_DONT_UPDATE_INDEX | GIT_CHECKOUT_DISABLE_PATHSPEC_MATCH;  // There's no reason to update the index
  options.paths.count = 1;
  const char* filePath = GCGitPathFromFileSystemPath(path);
  options.paths.strings = (char**)&filePath;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_checkout_index, self.private, index.private, &options);
  return YES;
}

- (BOOL)checkoutLinesInFileToWorkingDirectory:(NSString*)path fromIndex:(GCIndex*)index error:(NSError**)error usingFilter:(GCIndexLineFilter)filter {
  BOOL success = NO;
  const char* fullPath = [[self absolutePathForFile:path] fileSystemRepresentation];
  int fd = -1;
  GCDiff* diff;
  GCDiffPatch* patch;
  
  // Create temporary path
  const char* tempPath = self.privateTemporaryFilePath.fileSystemRepresentation;
  if (!tempPath) {
    GC_SET_GENERIC_ERROR(@"Failed creating temporary path");
    return NO;
  }
  fd = open(tempPath, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR);
  CHECK_POSIX_FUNCTION_CALL(goto cleanup, fd, >= 0);
  
  // Diff file in working directory with index and create temporary file copy excluding the lines we don't want
  diff = [self diffWorkingDirectoryWithIndex:index
                                 filePattern:path
                                     options:(kGCDiffOption_IncludeUntracked | kGCDiffOption_IncludeIgnored)
                           maxInterHunkLines:NSUIntegerMax
                             maxContextLines:NSUIntegerMax
                                       error:error];
  if (diff == nil) {
    goto cleanup;
  }
  if (diff.deltas.count != 1) {
    GC_SET_GENERIC_ERROR(@"Internal inconsistency");
    goto cleanup;
  }
  patch = [self makePatchForDiffDelta:diff.deltas[0] isBinary:NULL error:error];
  if (patch) {
    __block BOOL failed = NO;
    [patch enumerateUsingBeginHunkHandler:NULL lineHandler:^(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber, const char* contentBytes, NSUInteger contentLength) {
      
      /* Comparing workdir to index:
       
       Change      | Filter     | Write?
       ------------|------------|------------
       Unmodified  | -          | YES
       ------------|------------|------------
       Added       | YES        | NO
                   | NO         | YES
       ------------|------------|------------
       Deleted     | YES        | YES
                   | NO         | NO
       
       */
      BOOL shouldWrite = YES;
      switch (change) {
        case kGCLineDiffChange_Unmodified: break;
        case kGCLineDiffChange_Added: shouldWrite = !filter(change, oldLineNumber, newLineNumber); break;
        case kGCLineDiffChange_Deleted: shouldWrite = filter(change, oldLineNumber, newLineNumber); break;
      }
      if (shouldWrite && (write(fd, contentBytes, contentLength) != (ssize_t)contentLength)) {
        GC_SET_GENERIC_ERROR(@"%s", strerror(errno));
        failed = YES;
        XLOG_DEBUG_UNREACHABLE();
      }
      
    } endHunkHandler:NULL];
    if (failed) {
      goto cleanup;
    }
  } else {
    goto cleanup;
  }
  close(fd);
  fd = -1;
  
  // Copy file metadata onto the temporary copy
  copyfile_state_t state = copyfile_state_alloc();
  int status = copyfile(fullPath, tempPath, state, COPYFILE_METADATA);
  copyfile_state_free(state);
  CHECK_POSIX_FUNCTION_CALL(goto cleanup, status, == 0);
  
  // Swap temporary copy and original file
  CALL_POSIX_FUNCTION_GOTO(cleanup, exchangedata, fullPath, tempPath, FSOPT_NOFOLLOW);
  CALL_POSIX_FUNCTION_GOTO(cleanup, utimes, fullPath, NULL);  // Touch file to make sure any cached information in the index gets invalidated
  
  success = YES;
  
cleanup:
  if (fd >= 0) {
    close(fd);
  }
  unlink(tempPath);  // Ignore error
  return success;
}

// TODO: We should update the resolve undo extension like libgit2 does by default (see https://github.com/git/git/blob/master/Documentation/technical/index-format.txt#L177)
- (BOOL)clearConflictForFile:(NSString*)path inIndex:(GCIndex*)index error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_index_conflict_remove, index.private, GCGitPathFromFileSystemPath(path));
  return YES;
}

- (BOOL)removeFile:(NSString*)path fromIndex:(GCIndex*)index error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_index_remove, index.private, GCGitPathFromFileSystemPath(path), 0);
  return YES;
}

- (BOOL)copyFile:(NSString*)path fromOtherIndex:(GCIndex*)otherIndex toIndex:(GCIndex*)index error:(NSError**)error {
  const git_index_entry* entry = git_index_get_bypath(otherIndex.private, GCGitPathFromFileSystemPath(path), 0);
  if (entry == NULL) {
    GC_SET_GENERIC_ERROR(@"File not in index");
    return NO;
  }
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_index_add, index.private, entry);
  return YES;
}

- (BOOL)copyLinesInFile:(NSString*)path fromOtherIndex:(GCIndex*)otherIndex toIndex:(GCIndex*)index error:(NSError**)error usingFilter:(GCIndexLineFilter)filter {
  const char* filePath = GCGitPathFromFileSystemPath(path);
  
  // Just grab entry from other index
  const git_index_entry* entry = git_index_get_bypath(otherIndex.private, filePath, 0);
  if (entry == NULL) {
    GC_SET_GENERIC_ERROR(@"File not in index");
    return NO;
  }
  NSMutableData* data = [[NSMutableData alloc] initWithCapacity:(1024 * 1024)];
  
  // Diff file in other index with index and create temporary file in memory excluding the lines we don't want
  GCDiff* diff = [self diffIndex:otherIndex withIndex:index filePattern:path options:0 maxInterHunkLines:NSUIntegerMax maxContextLines:NSUIntegerMax error:error];
  if (diff == nil) {
    return NO;
  }
  if (diff.deltas.count != 1) {
    GC_SET_GENERIC_ERROR(@"Internal inconsistency");
    return NO;
  }
  GCDiffPatch* patch = [self makePatchForDiffDelta:diff.deltas[0] isBinary:NULL error:error];
  if (patch == nil) {
    return NO;
  }
  [patch enumerateUsingBeginHunkHandler:NULL lineHandler:^(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber, const char* contentBytes, NSUInteger contentLength) {
    
    /* Comparing other index to index:
     
     Change      | Filter     | Write?
     ------------|------------|------------
     Unmodified  | -          | YES
     ------------|------------|------------
     Added       | YES        | YES
                 | NO         | NO
     ------------|------------|------------
     Deleted     | YES        | NO
                 | NO         | YES
     
     */
    BOOL shouldWrite = YES;
    switch (change) {
      case kGCLineDiffChange_Unmodified: break;
      case kGCLineDiffChange_Added: shouldWrite = filter(change, oldLineNumber, newLineNumber); break;
      case kGCLineDiffChange_Deleted: shouldWrite = !filter(change, oldLineNumber, newLineNumber); break;
    }
    if (shouldWrite) {
      [data appendBytes:contentBytes length:contentLength];
    }
    
  } endHunkHandler:NULL];
  
  return [self _addEntry:entry toIndex:index.private withData:data error:error];
}

@end

@implementation GCRepository (GCIndex_Private)

- (git_index*)reloadRepositoryIndex:(NSError**)error {
  git_index* index = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_index, &index, self.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_read, index, false);  // Force reading shouldn't be needed
  return index;
  
cleanup:
  XLOG_DEBUG_UNREACHABLE();
  git_index_free(index);
  return NULL;
}

#if DEBUG

// See https://github.com/libgit2/libgit2/issues/2687
- (BOOL)addAllFilesToIndex:(NSError**)error {
  BOOL success = NO;
  git_index* index = NULL;
  git_status_list* list = NULL;
  
  index = [self reloadRepositoryIndex:error];
  if (index == NULL) {
    goto cleanup;
  }
  git_status_options options = GIT_STATUS_OPTIONS_INIT;
  options.show = GIT_STATUS_SHOW_WORKDIR_ONLY;
  options.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_status_list_new, &list, self.private, &options);
  for (size_t i = 0, count = git_status_list_entrycount(list); i < count; ++i) {
    const git_status_entry* entry = git_status_byindex(list, i);
    switch (entry->status) {
      
      case GIT_STATUS_WT_NEW:
      case GIT_STATUS_WT_MODIFIED:
      case GIT_STATUS_WT_TYPECHANGE:
        CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_add_bypath, index, entry->index_to_workdir->new_file.path);
        break;
      
      case GIT_STATUS_WT_DELETED:
        CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_remove_bypath, index, entry->index_to_workdir->old_file.path);
        break;
      
      case GIT_STATUS_CONFLICTED:
        CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_add_bypath, index, entry->index_to_workdir->new_file.path);  // Resolve conflict
        break;
      
      default:
        XLOG_DEBUG_UNREACHABLE();
        break;
      
    }
  }
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_write, index);
  success = YES;
  
cleanup:
  git_status_list_free(list);
  git_index_free(index);
  return success;
}

#endif

@end
