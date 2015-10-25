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

#define kMaxFileSizeForTextDiff (8 * 1024 * 1024)  // libgit2 default is 512 MiB

static inline GCFileDiffChange _FileDiffChangeFromStatus(git_delta_t status) {
  switch (status) {
    case GIT_DELTA_UNMODIFIED: return kGCFileDiffChange_Unmodified;
    case GIT_DELTA_ADDED: return kGCFileDiffChange_Added;
    case GIT_DELTA_DELETED: return kGCFileDiffChange_Deleted;
    case GIT_DELTA_MODIFIED: return kGCFileDiffChange_Modified;
    case GIT_DELTA_RENAMED: return kGCFileDiffChange_Renamed;
    case GIT_DELTA_COPIED: return kGCFileDiffChange_Copied;
    case GIT_DELTA_IGNORED: return kGCFileDiffChange_Ignored;
    case GIT_DELTA_UNTRACKED: return kGCFileDiffChange_Untracked;
    case GIT_DELTA_TYPECHANGE: return kGCFileDiffChange_TypeChanged;
    case GIT_DELTA_UNREADABLE: return kGCFileDiffChange_Unreadable;
    case GIT_DELTA_CONFLICTED: return kGCFileDiffChange_Conflicted;
  }
  XLOG_DEBUG_UNREACHABLE();
  return 0;
}

@implementation GCDiffFile {
  git_oid _oid;
}

- (id)initWithDiffFile:(const git_diff_file*)file {
  if ((self = [super init])) {
    _path = GCFileSystemPathFromGitPath(file->path);
    _mode = GCFileModeFromMode(file->mode);
    git_oid_cpy(&_oid, &file->id);
    if (_path == nil) {
      XLOG_DEBUG_UNREACHABLE();
      return nil;
    }
  }
  return self;
}

- (const git_oid*)OID {
  return &_oid;
}

- (NSString*)SHA1 {
  return GCGitOIDToSHA1(&_oid);
}

- (NSString*)description {
  static char modes[] = {' ', 'T', 'B', 'X', 'L', 'C'};
  return [NSString stringWithFormat:@"%@ \"%@\" (%c) {%s}", self.class, _path, modes[_mode], git_oid_tostr_s(&_oid)];
}

@end

@implementation GCDiffPatch

- (instancetype)initWithPatch:(git_patch*)patch {
  if ((self = [super init])) {
    _private = patch;
  }
  return self;
}

- (void)dealloc {
  git_patch_free(_private);
}

- (BOOL)isEmpty {
  return (git_patch_num_hunks(_private) == 0);
}

- (void)enumerateUsingBeginHunkHandler:(GCDiffBeginHunkHandler)beginHunkHandler
                           lineHandler:(GCDiffLineHandler)lineHandler
                        endHunkHandler:(GCDiffEndHunkHandler)endHunkHandler {
  for (size_t i = 0, iMax = git_patch_num_hunks(_private); i < iMax; ++i) {
    if (beginHunkHandler) {
      const git_diff_hunk* hunk;
      if (git_patch_get_hunk(&hunk, NULL, _private, i) == GIT_OK) {
        beginHunkHandler(hunk->old_start, hunk->old_lines, hunk->new_start, hunk->new_lines);
      } else {
        XLOG_DEBUG_UNREACHABLE();
        continue;
      }
    }
    if (lineHandler) {
      for (size_t j = 0, jMax = git_patch_num_lines_in_hunk(_private, i); j < jMax; ++j) {
        const git_diff_line* line;
        if (git_patch_get_line_in_hunk(&line, _private, i, j) == GIT_OK) {
          switch (line->origin) {
            
            case GIT_DIFF_LINE_CONTEXT:
              lineHandler(kGCLineDiffChange_Unmodified, line->old_lineno, line->new_lineno, line->content, line->content_len);
              break;
            
            case GIT_DIFF_LINE_ADDITION:
              lineHandler(kGCLineDiffChange_Added, NSNotFound, line->new_lineno, line->content, line->content_len);
              break;
            
            case GIT_DIFF_LINE_DELETION:
              lineHandler(kGCLineDiffChange_Deleted, line->old_lineno, NSNotFound, line->content, line->content_len);
              break;
            
            case GIT_DIFF_LINE_CONTEXT_EOFNL:
            case GIT_DIFF_LINE_ADD_EOFNL:
            case GIT_DIFF_LINE_DEL_EOFNL:
              break;
            
            default:
              XLOG_DEBUG_UNREACHABLE();
              break;
            
          }
        } else {
          XLOG_DEBUG_UNREACHABLE();
        }
      }
    }
    if (endHunkHandler) {
      endHunkHandler();
    }
  }
}

- (NSString*)description {
  size_t additions = 0;
  size_t deletions = 0;
  git_patch_line_stats(NULL, &additions, &deletions, _private);
  return [NSString stringWithFormat:@"%@ +%lu -%lu", self.class, additions, deletions];
}

@end

@implementation GCDiffDelta {
  __unsafe_unretained GCDiff* _diff;
  size_t _index;
  GCDiffPatch* _patch;
  GCDiffOptions _options;
}

- (instancetype)initWithDiff:(GCDiff*)diff delta:(const git_diff_delta*)delta index:(size_t)index {
  if ((self = [super init])) {
    _diff = diff;
    _private = delta;
    _index = index;
    _change = _FileDiffChangeFromStatus(delta->status);
    if (delta->nfiles == 1) {
      if (delta->status == GIT_DELTA_DELETED) {
        _oldFile = [[GCDiffFile alloc] initWithDiffFile:&delta->old_file];
      } else if (delta->status == GIT_DELTA_ADDED) {
        _newFile = [[GCDiffFile alloc] initWithDiffFile:&delta->new_file];
      } else if (delta->status == GIT_DELTA_CONFLICTED) {  // For conflicted deltas, either old, new or old & new can be set depending on the circumstances
        _oldFile = [[GCDiffFile alloc] initWithDiffFile:&delta->old_file];
        _newFile = [[GCDiffFile alloc] initWithDiffFile:&delta->new_file];
      } else {
        XLOG_DEBUG_CHECK((delta->status == GIT_DELTA_IGNORED) || (delta->status == GIT_DELTA_UNTRACKED) || (delta->status == GIT_DELTA_UNREADABLE));
        _oldFile = [[GCDiffFile alloc] initWithDiffFile:&delta->new_file];  // For single-file deltas, libgit2 only sets the "new" side except for "deleted"
      }
    } else {
      XLOG_DEBUG_CHECK(delta->nfiles == 2);
      if (delta->status == GIT_DELTA_UNMODIFIED) {
        _oldFile = [[GCDiffFile alloc] initWithDiffFile:&delta->old_file];  // For dual-file deltas, libgit2 considers the "old" side as the primary one
      } else {
        XLOG_DEBUG_CHECK((delta->status == GIT_DELTA_MODIFIED) || (delta->status == GIT_DELTA_RENAMED) || (delta->status == GIT_DELTA_COPIED) || (delta->status == GIT_DELTA_TYPECHANGE) || (delta->status == GIT_DELTA_CONFLICTED));
        _oldFile = [[GCDiffFile alloc] initWithDiffFile:&delta->old_file];
        _newFile = [[GCDiffFile alloc] initWithDiffFile:&delta->new_file];
      }
    }
    _canonicalPath = _newFile ? _newFile.path : _oldFile.path;
    if (_canonicalPath == nil) {
      XLOG_DEBUG_UNREACHABLE();
      return nil;
    }
    _options = diff.options;
  }
  return self;
}

- (GCDiffPatch*)makePatch:(BOOL*)isBinary error:(NSError**)error {
  if (_patch == nil) {
    git_patch* patch;
    CALL_LIBGIT2_FUNCTION_RETURN(nil, git_patch_from_diff, &patch, _diff.private, _index);
    _patch = [[GCDiffPatch alloc] initWithPatch:patch];
  }
  if (isBinary) {
    *isBinary = _private->flags & GIT_DIFF_FLAG_BINARY ? YES : NO;
  }
  return _patch;
}

- (NSString*)description {
  static char modes[] = {' ', 'T', 'B', 'X', 'L', 'C'};  // WARNING: Must match GCFileModeFromMode
  static char status[] = {  // WARNING: Must match GCFileDiffChange
    ' ', 'I', '?', 'X',
    'A', 'D', 'M',
    'R', 'C', 'T',
    '!'
  };
  return [NSString stringWithFormat:@"%c \"%s\" (%c) -> \"%s\" (%c)", status[_FileDiffChangeFromStatus(_private->status)],
          _private->old_file.path, modes[GCFileModeFromMode(_private->old_file.mode)],
          _private->new_file.path, modes[GCFileModeFromMode(_private->new_file.mode)]];
}

@end

@implementation GCDiffDelta (Extensions)

// This must match the logic for the canonical path
- (BOOL)isSubmodule {
  switch (_change) {
    
    case kGCFileDiffChange_Deleted:
    case kGCFileDiffChange_Unmodified:
    case kGCFileDiffChange_Ignored:
    case kGCFileDiffChange_Untracked:
    case kGCFileDiffChange_Unreadable:
      return GC_FILE_MODE_IS_SUBMODULE(_oldFile.mode);
    
    case kGCFileDiffChange_Added:
    case kGCFileDiffChange_Modified:
    case kGCFileDiffChange_Renamed:
    case kGCFileDiffChange_Copied:
    case kGCFileDiffChange_TypeChanged:
    case kGCFileDiffChange_Conflicted:
      return GC_FILE_MODE_IS_SUBMODULE(_newFile.mode);
    
  }
  XLOG_DEBUG_UNREACHABLE();
  return NO;
}

static inline BOOL _SafeEqualStrings(const char* string1, const char* string2) {
  if (string1 && string2) {
    return strcmp(string1, string2) == 0;
  }
  return string1 == string2;
}

static inline BOOL _EqualDeltas(const git_diff_delta* delta1, const git_diff_delta* delta2) {
  if (delta1->status != delta2->status) {
    return NO;
  }
  
  if (!_SafeEqualStrings(delta1->old_file.path, delta2->old_file.path) || !_SafeEqualStrings(delta1->new_file.path, delta2->new_file.path)) {
    return NO;
  }
  
  if ((delta1->old_file.flags & GIT_DIFF_FLAG_VALID_ID) && (delta2->old_file.flags & GIT_DIFF_FLAG_VALID_ID)) {
    if (!git_oid_equal(&delta1->old_file.id, &delta2->old_file.id)) {
      return NO;
    }
  } else {
    if ((delta1->old_file.size != delta2->old_file.size) || (delta1->old_file.ctime != delta2->old_file.ctime) || (delta1->old_file.mtime != delta2->old_file.mtime)) {
      return NO;
    }
  }
  
  if ((delta1->new_file.flags & GIT_DIFF_FLAG_VALID_ID) && (delta2->new_file.flags & GIT_DIFF_FLAG_VALID_ID)) {
    if (!git_oid_equal(&delta1->new_file.id, &delta2->new_file.id)) {
      return NO;
    }
  } else {
    if ((delta1->new_file.size != delta2->new_file.size) || (delta1->new_file.ctime != delta2->new_file.ctime) || (delta1->new_file.mtime != delta2->new_file.mtime)) {
      return NO;
    }
  }
  
  return YES;
}

- (BOOL)isEqualToDelta:(GCDiffDelta*)delta {
  return (self == delta) || ((_options == delta->_options) && _EqualDeltas(_private, delta->_private));
}

- (BOOL)isEqual:(id)object {
  if (![object isKindOfClass:[GCDiffDelta class]]) {
    return NO;
  }
  return [self isEqualToDelta:object];
}

@end

@implementation GCDiff {
  __unsafe_unretained GCRepository* _repository;
  NSMutableArray* _deltas;
  BOOL _modified;
  BOOL _changed;
}

- (instancetype)initWithRepository:(GCRepository*)repository
                              diff:(git_diff*)diff
                              type:(GCDiffType)type
                           options:(GCDiffOptions)options
                 maxInterHunkLines:(NSUInteger)maxInterHunkLines
                   maxContextLines:(NSUInteger)maxContextLines {
  if ((self = [super init])) {
    _repository = repository;
    _private = diff;
    _type = type;
    _options = options;
    _maxInterHunkLines = maxInterHunkLines;
    _maxContextLines = maxContextLines;
  }
  return self;
}

- (void)dealloc {
  git_diff_free(_private);
}

// Generate deltas lazily in case the diff is modified after being created e.g. with git_diff_merge()
- (void)_cacheDeltasIfNeeded {
  if (_deltas == nil) {
    size_t count = git_diff_num_deltas(_private);
    _deltas = [[NSMutableArray alloc] initWithCapacity:count];
    for (size_t i = 0; i < count; ++i) {
      const git_diff_delta* delta = git_diff_get_delta(_private, i);
      GCDiffDelta* diffDelta = [[GCDiffDelta alloc] initWithDiff:self delta:delta index:i];
      if (diffDelta) {
        [_deltas addObject:diffDelta];
        if (delta->status != GIT_DELTA_UNMODIFIED) {
          _modified = YES;
          if (delta->status != GIT_DELTA_UNTRACKED) {
            _changed = YES;
          }
        }
      } else {
        XLOG_WARNING(@"Invalid delta generated for diff in repository \"%@\"", _repository.repositoryPath);
        XLOG_DEBUG_UNREACHABLE();
      }
    }
  }
}

- (NSArray*)deltas {
  [self _cacheDeltasIfNeeded];
  return _deltas;
}

- (BOOL)isModified {
  [self _cacheDeltasIfNeeded];
  return _modified;
}

- (BOOL)hasChanges {
  [self _cacheDeltasIfNeeded];
  return _changed;
}

#if DEBUG

- (GCFileDiffChange)changeForFile:(NSString*)path {
  const char* cPath = GCGitPathFromFileSystemPath(path);
  for (size_t i = 0, count = git_diff_num_deltas(_private); i < count; ++i) {
    const git_diff_delta* delta = git_diff_get_delta(_private, i);
    if (delta->new_file.path && !strcmp(cPath, delta->new_file.path)) {
      return _FileDiffChangeFromStatus(delta->status);
    }
  }
  return NSNotFound;
}

#endif

- (NSString*)description {
  NSMutableString* string = [NSMutableString stringWithFormat:@"[%@] %lu deltas", self.class, git_diff_num_deltas(_private)];
  for (GCDiffDelta* delta in _deltas) {
    [string appendString:@"\n  "];
    [string appendString:delta.description];
  }
  return string;
}

@end

@implementation GCDiff (Extensions)

static inline BOOL _EqualDiffs(git_diff* diff1, git_diff* diff2) {
  if (git_diff_num_deltas(diff1) != git_diff_num_deltas(diff2)) {
    return NO;
  }
  for (size_t i = 0, count = git_diff_num_deltas(diff1); i < count; ++i) {
    const git_diff_delta* delta1 = git_diff_get_delta(diff1, i);
    const git_diff_delta* delta2 = git_diff_get_delta(diff2, i);
    if (!_EqualDeltas(delta1, delta2)) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)isEqualToDiff:(GCDiff*)diff {
  return (self == diff) || ((_options == diff->_options) && _EqualDiffs(_private, diff->_private));
}

- (BOOL)isEqual:(id)object {
  if (![object isKindOfClass:[GCDiff class]]) {
    return NO;
  }
  return [self isEqualToDiff:object];
}

@end

@implementation GCRepository (GCDiff)

// GIT_DIFF_SKIP_BINARY_CHECK only matters if creating patches from the diff either with git_diff_foreach() if passing non-NULL hunk or line callbacks or with git_patch_from_diff()
// For libgit2, which mirrors Core Git, a file is binary if non-empty and it contains a NUL byte in the first 8000 bytes
// However the GIT_DIFF_FLAG_BINARY flag will NOT be set on old_file.flags / new_file.flags / delta.flags unless a patch is generated
- (GCDiff*)_diffWithType:(GCDiffType)type
             filePattern:(NSString*)filePattern
                 options:(GCDiffOptions)options
       maxInterHunkLines:(NSUInteger)maxInterHunkLines
         maxContextLines:(NSUInteger)maxContextLines
                   error:(NSError**)error
                   block:(int (^)(git_diff** outDiff, git_diff_options* diffOptions))block {
  GCDiff* gcDiff = nil;
  git_diff* diff = NULL;
  
  git_diff_options diffOptions = GIT_DIFF_OPTIONS_INIT;
  if (options & kGCDiffOption_IncludeUnmodified) {
    diffOptions.flags |= GIT_DIFF_INCLUDE_UNMODIFIED;
  }
  if (options & kGCDiffOption_IncludeUntracked) {
    diffOptions.flags |= GIT_DIFF_INCLUDE_UNTRACKED | GIT_DIFF_RECURSE_UNTRACKED_DIRS | GIT_DIFF_SHOW_UNTRACKED_CONTENT;
  }
  if (options & kGCDiffOption_IncludeIgnored) {
    diffOptions.flags |= GIT_DIFF_INCLUDE_IGNORED | GIT_DIFF_RECURSE_IGNORED_DIRS;
  }
  if (options & kGCDiffOption_FindTypeChanges) {
    diffOptions.flags |= GIT_DIFF_INCLUDE_TYPECHANGE | GIT_DIFF_INCLUDE_TYPECHANGE_TREES;
  }
  if (options & kGCDiffOption_Reverse) {
    diffOptions.flags |= GIT_DIFF_REVERSE;
  }
  if (options & kGCDiffOption_IgnoreSpaceChanges) {
    diffOptions.flags |= GIT_DIFF_IGNORE_WHITESPACE_CHANGE;
  }
  if (options & kGCDiffOption_IgnoreAllSpaces) {
    diffOptions.flags |= GIT_DIFF_IGNORE_WHITESPACE;
  }
  if (filePattern) {
    diffOptions.pathspec.count = 1;
    const char* filePath = GCGitPathFromFileSystemPath(filePattern);
    diffOptions.pathspec.strings = (char**)&filePath;
    
    static NSCharacterSet* set = nil;
    if (set == nil) {
      set = [NSCharacterSet characterSetWithCharactersInString:@"?*[]"];
    }
    if ([filePattern rangeOfCharacterFromSet:set].location == NSNotFound) {
      diffOptions.flags |= GIT_DIFF_DISABLE_PATHSPEC_MATCH;
    }
  }
  diffOptions.ignore_submodules = GIT_SUBMODULE_IGNORE_NONE;  // If unset, libgit2 will fall back to "diff.ignoresubmodules" from the config or GIT_SUBMODULE_IGNORE_DEFAULT if absent, which itself stands for GIT_SUBMODULE_IGNORE_NONE
  diffOptions.max_size = kMaxFileSizeForTextDiff;
  diffOptions.context_lines = (uint32_t)MIN(maxContextLines, (NSUInteger)UINT32_MAX);
  diffOptions.interhunk_lines = (uint32_t)MIN(maxInterHunkLines, (NSUInteger)UINT32_MAX);
  int status = block(&diff, &diffOptions);
  CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
  if (options & (kGCDiffOption_FindRenames | kGCDiffOption_FindCopies)) {
    git_diff_find_options findOptions = GIT_DIFF_FIND_OPTIONS_INIT;
    findOptions.flags = 0;
    if (options & kGCDiffOption_FindRenames) {
      findOptions.flags |= GIT_DIFF_FIND_RENAMES;
    }
    if (options & kGCDiffOption_FindCopies) {
      findOptions.flags |= GIT_DIFF_FIND_COPIES;
      if (options & kGCDiffOption_IncludeUnmodified) {
        findOptions.flags |= GIT_DIFF_FIND_COPIES_FROM_UNMODIFIED;
      }
    }
    if (options & kGCDiffOption_IncludeUntracked) {
      findOptions.flags |= GIT_DIFF_FIND_FOR_UNTRACKED;
    }
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_diff_find_similar, diff, &findOptions);
  }
  gcDiff = [[GCDiff alloc] initWithRepository:self diff:diff type:type options:options maxInterHunkLines:diffOptions.interhunk_lines maxContextLines:diffOptions.context_lines];
  diff = NULL;
  
cleanup:
  git_diff_free(diff);
  return gcDiff;
}

- (GCDiff*)diffWorkingDirectoryWithCommit:(GCCommit*)commit
                               usingIndex:(GCIndex*)index
                              filePattern:(NSString*)filePattern
                                  options:(GCDiffOptions)options
                        maxInterHunkLines:(NSUInteger)maxInterHunkLines
                          maxContextLines:(NSUInteger)maxContextLines
                                    error:(NSError**)error {
  if (index == nil) {
    index = [self readRepositoryIndex:error];
    if (index == nil) {
      return nil;
    }
  }
  git_tree* tree = NULL;
  if (commit) {
    CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_tree, &tree, commit.private);
  }
  GCDiff* diff = [self _diffWithType:kGCDiffType_WorkingDirectoryWithCommit filePattern:filePattern options:options maxInterHunkLines:maxInterHunkLines maxContextLines:maxContextLines error:error block:^int(git_diff** outDiff, git_diff_options* diffOptions) {
    
    int status = git_diff_tree_to_index(outDiff, self.private, tree, index.private, diffOptions);
    if (status == GIT_OK) {
      git_diff* diff2;
      diffOptions->flags |= GIT_DIFF_UPDATE_INDEX;
      status = git_diff_index_to_workdir(&diff2, self.private, index.private, diffOptions);
      if (status == GIT_ELOCKED) {
        status = GIT_OK;  // Passing GIT_DIFF_UPDATE_INDEX means git_diff_index_to_workdir() may attempt to write the index and this could fail if it is currently locked by another process but that's OK to ignore this failure
      }
      if (status == GIT_OK) {
        status = git_diff_merge(*outDiff, diff2);
        if (status != GIT_OK) {
          git_diff_free(*outDiff);
        }
        git_diff_free(diff2);
      } else {
        git_diff_free(*outDiff);
      }
    }
    return status;
    
  }];
  git_tree_free(tree);
  return diff;
}

- (GCDiff*)diffWorkingDirectoryWithIndex:(GCIndex*)index
                             filePattern:(NSString*)filePattern
                                 options:(GCDiffOptions)options
                       maxInterHunkLines:(NSUInteger)maxInterHunkLines
                         maxContextLines:(NSUInteger)maxContextLines
                                   error:(NSError**)error {
  if (index == nil) {
    index = [self readRepositoryIndex:error];
    if (index == nil) {
      return nil;
    }
  }
  return [self _diffWithType:kGCDiffType_WorkingDirectoryWithIndex filePattern:filePattern options:options maxInterHunkLines:maxInterHunkLines maxContextLines:maxContextLines error:error block:^int(git_diff** outDiff, git_diff_options* diffOptions) {
    
    diffOptions->flags |= GIT_DIFF_UPDATE_INDEX;
    int status = git_diff_index_to_workdir(outDiff, self.private, index.private, diffOptions);
    if (status == GIT_ELOCKED) {
      status = GIT_OK;  // Passing GIT_DIFF_UPDATE_INDEX means git_diff_index_to_workdir() will attempt to write the index even if there are no changes and this could fail if it is currently locked by another process
    }
    return status;
    
  }];
}

- (GCDiff*)diffIndex:(GCIndex*)index
          withCommit:(GCCommit*)commit
         filePattern:(NSString*)filePattern
             options:(GCDiffOptions)options
   maxInterHunkLines:(NSUInteger)maxInterHunkLines
     maxContextLines:(NSUInteger)maxContextLines
               error:(NSError**)error {
  if (index == nil) {
    index = [self readRepositoryIndex:error];
    if (index == nil) {
      return nil;
    }
  }
  git_tree* tree = NULL;
  if (commit) {
    CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_tree, &tree, commit.private);
  }
  GCDiff* diff = [self _diffWithType:kGCDiffType_IndexWithCommit filePattern:filePattern options:options maxInterHunkLines:maxInterHunkLines maxContextLines:maxContextLines error:error block:^int(git_diff** outDiff, git_diff_options* diffOptions) {
    
    return git_diff_tree_to_index(outDiff, self.private, tree, index.private, diffOptions);
    
  }];
  git_tree_free(tree);
  return diff;
}

- (GCDiff*)diffCommit:(GCCommit*)newCommit
           withCommit:(GCCommit*)oldCommit
          filePattern:(NSString*)filePattern
              options:(GCDiffOptions)options
    maxInterHunkLines:(NSUInteger)maxInterHunkLines
      maxContextLines:(NSUInteger)maxContextLines
                error:(NSError**)error {
  git_tree* oldTree = NULL;
  if (oldCommit) {
    CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_tree, &oldTree, oldCommit.private);
  }
  git_tree* newTree = NULL;
  int status = git_commit_tree(&newTree, newCommit.private);  // Work around "goto into protected scope" Clang error
  if (status != GIT_OK) {
    CHECK_LIBGIT2_FUNCTION_CALL(return nil, status, == GIT_OK);
    git_tree_free(oldTree);
  }
  GCDiff* diff = [self _diffWithType:kGCDiffType_CommitWithCommit filePattern:filePattern options:options maxInterHunkLines:maxInterHunkLines maxContextLines:maxContextLines error:error block:^int(git_diff** outDiff, git_diff_options* diffOptions) {
    
    return git_diff_tree_to_tree(outDiff, self.private, oldTree, newTree, diffOptions);
    
  }];
  git_tree_free(newTree);
  git_tree_free(oldTree);
  return diff;
}

- (GCDiff*)diffIndex:(GCIndex*)newIndex
           withIndex:(GCIndex*)oldIndex
         filePattern:(NSString*)filePattern
             options:(GCDiffOptions)options
   maxInterHunkLines:(NSUInteger)maxInterHunkLines
     maxContextLines:(NSUInteger)maxContextLines
               error:(NSError**)error {
  return [self _diffWithType:kGCDiffType_IndexWithIndex filePattern:filePattern options:options maxInterHunkLines:maxInterHunkLines maxContextLines:maxContextLines error:error block:^int(git_diff** outDiff, git_diff_options* diffOptions) {
    
    return git_diff_index_to_index(outDiff, self.private, oldIndex.private, newIndex.private, diffOptions);
    
  }];
}

- (BOOL)mergeDiff:(GCDiff*)diff ontoDiff:(GCDiff*)ontoDiff error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_diff_merge, ontoDiff.private, diff.private);
  return YES;
}

- (GCDiffPatch*)makePatchForDiffDelta:(GCDiffDelta*)delta isBinary:(BOOL*)isBinary error:(NSError**)error {
  return [delta makePatch:isBinary error:error];
}

#pragma mark - Convenience

- (GCDiff*)diffWorkingDirectoryWithHEAD:(NSString*)filePattern
                                options:(GCDiffOptions)options
                      maxInterHunkLines:(NSUInteger)maxInterHunkLines
                        maxContextLines:(NSUInteger)maxContextLines
                                  error:(NSError**)error {
  GCCommit* headCommit;
  if (![self lookupHEADCurrentCommit:&headCommit branch:NULL error:error]) {
    return nil;
  }
  return [self diffWorkingDirectoryWithCommit:headCommit usingIndex:nil filePattern:filePattern options:options maxInterHunkLines:maxInterHunkLines maxContextLines:maxContextLines error:error];
}

- (GCDiff*)diffWorkingDirectoryWithRepositoryIndex:(NSString*)filePattern
                                           options:(GCDiffOptions)options
                                 maxInterHunkLines:(NSUInteger)maxInterHunkLines
                                   maxContextLines:(NSUInteger)maxContextLines
                                             error:(NSError**)error {
  return [self diffWorkingDirectoryWithIndex:nil filePattern:filePattern options:options maxInterHunkLines:maxInterHunkLines maxContextLines:maxContextLines error:error];
}

- (GCDiff*)diffRepositoryIndexWithHEAD:(NSString*)filePattern
                               options:(GCDiffOptions)options
                     maxInterHunkLines:(NSUInteger)maxInterHunkLines
                       maxContextLines:(NSUInteger)maxContextLines
                                 error:(NSError**)error {
  GCCommit* headCommit;
  if (![self lookupHEADCurrentCommit:&headCommit branch:NULL error:error]) {
    return nil;
  }
  return [self diffIndex:nil withCommit:headCommit filePattern:filePattern options:options maxInterHunkLines:maxInterHunkLines maxContextLines:maxContextLines error:error];
}

@end
