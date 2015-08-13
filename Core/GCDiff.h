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

#import "GCRepository.h"

typedef NS_ENUM(NSUInteger, GCDiffType) {
  kGCDiffType_WorkingDirectoryWithCommit = 0,
  kGCDiffType_WorkingDirectoryWithIndex,
  kGCDiffType_IndexWithCommit,
  kGCDiffType_CommitWithCommit,
  kGCDiffType_IndexWithIndex
};

typedef NS_OPTIONS(NSUInteger, GCDiffOptions) {
  kGCDiffOption_IncludeUnmodified = (1 << 0),
  kGCDiffOption_IncludeUntracked = (1 << 1),
  kGCDiffOption_IncludeIgnored = (1 << 2),
  kGCDiffOption_FindTypeChanges = (1 << 3),
  kGCDiffOption_FindRenames = (1 << 4),
  kGCDiffOption_FindCopies = (1 << 5),  // Requires kGCDiffOption_IncludeUnmodified for best results
  kGCDiffOption_Reverse = (1 << 6),
  kGCDiffOption_IgnoreSpaceChanges = (1 << 7),
  kGCDiffOption_IgnoreAllSpaces = (1 << 8)
};

typedef NS_ENUM(NSUInteger, GCLineDiffChange) {
  kGCLineDiffChange_Unmodified = 0,
  kGCLineDiffChange_Added,
  kGCLineDiffChange_Deleted
};

typedef NS_ENUM(NSUInteger, GCFileDiffChange) {
  kGCFileDiffChange_Unmodified = 0,
  kGCFileDiffChange_Ignored,
  kGCFileDiffChange_Untracked,
  kGCFileDiffChange_Unreadable,
  
  kGCFileDiffChange_Added,
  kGCFileDiffChange_Deleted,
  kGCFileDiffChange_Modified,
  
  kGCFileDiffChange_Renamed,
  kGCFileDiffChange_Copied,
  kGCFileDiffChange_TypeChanged,
  
  kGCFileDiffChange_Conflicted
};

@class GCIndex, GCCommit, GCDiff, GCDiffFile;

typedef void (^GCDiffBeginHunkHandler)(NSUInteger oldLineNumber, NSUInteger oldLineCount, NSUInteger newLineNumber, NSUInteger newLineCount);
typedef void (^GCDiffLineHandler)(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber, const char* contentBytes, NSUInteger contentLength);
typedef void (^GCDiffEndHunkHandler)();

@interface GCDiffFile : NSObject
@property(nonatomic, readonly) NSString* path;
@property(nonatomic, readonly) GCFileMode mode;
@property(nonatomic, readonly) NSString* SHA1;  // May be nil if not in index
@end

/* "x" means non-nil, "-" means nil and [X] means canonical path
 
                Old       New
 Unmodified     [X]        -
 Ignored        [X]        -
 Untracked      [X]        -
 Unreadable     [X]        -
 
 Added           -        [X]
 Deleted        [X]        -
 Modified        x        [X]
 
 Renamed         x        [X]
 Copied          x        [X]
 TypeChanged     x        [X]
 
 Conflicted      x        [X]
 */
@interface GCDiffDelta : NSObject
@property(nonatomic, readonly) GCDiff* diff;  // NOT RETAINED
@property(nonatomic) GCFileDiffChange change;
@property(nonatomic, readonly) GCDiffFile* oldFile;
@property(nonatomic, readonly) GCDiffFile* newFile;
@property(nonatomic, readonly) NSString* canonicalPath;
- (GCDiffFile*)newFile __attribute__((objc_method_family(none)));  // Work around Clang error for property starting with "new" under ARC
@end

@interface GCDiffDelta (Extensions)
@property(nonatomic, readonly, getter=isSubmodule) BOOL submodule;
- (BOOL)isEqualToDelta:(GCDiffDelta*)delta;
@end

@interface GCDiff : NSObject
@property(nonatomic, readonly) GCRepository* repository;  // NOT RETAINED
@property(nonatomic, readonly) GCDiffType type;
@property(nonatomic, readonly) GCDiffOptions options;
@property(nonatomic, readonly) NSUInteger maxInterHunkLines;
@property(nonatomic, readonly) NSUInteger maxContextLines;
@property(nonatomic, readonly, getter=isModified) BOOL modified;  // Ignores unmodified files
@property(nonatomic, readonly) BOOL hasChanges;  // Ignores unmodified and untracked files
@property(nonatomic, readonly) NSArray* deltas;
@end

@interface GCDiff (Extensions)
- (BOOL)isEqualToDiff:(GCDiff*)diff;
@end

@interface GCDiffPatch : NSObject
@property(nonatomic, readonly, getter=isEmpty) BOOL empty;
- (void)enumerateUsingBeginHunkHandler:(GCDiffBeginHunkHandler)beginHunkHandler
                           lineHandler:(GCDiffLineHandler)lineHandler
                        endHunkHandler:(GCDiffEndHunkHandler)endHunkHandler;
@end

@interface GCRepository (GCDiff)
- (GCDiff*)diffWorkingDirectoryWithCommit:(GCCommit*)commit  // May be nil
                               usingIndex:(GCIndex*)index  // Pass nil for repository index
                              filePattern:(NSString*)filePattern  // May be nil
                                  options:(GCDiffOptions)options
                        maxInterHunkLines:(NSUInteger)maxInterHunkLines
                          maxContextLines:(NSUInteger)maxContextLines
                                    error:(NSError**)error;  // (?)

- (GCDiff*)diffWorkingDirectoryWithIndex:(GCIndex*)index  // Pass nil for repository index
                             filePattern:(NSString*)filePattern  // May be nil
                                 options:(GCDiffOptions)options
                       maxInterHunkLines:(NSUInteger)maxInterHunkLines
                         maxContextLines:(NSUInteger)maxContextLines
                                   error:(NSError**)error;  // (?)

- (GCDiff*)diffIndex:(GCIndex*)index  // Pass nil for repository index
          withCommit:(GCCommit*)commit  // May be nil
         filePattern:(NSString*)filePattern  // May be nil
             options:(GCDiffOptions)options
   maxInterHunkLines:(NSUInteger)maxInterHunkLines
     maxContextLines:(NSUInteger)maxContextLines
               error:(NSError**)error;  // (?)

- (GCDiff*)diffCommit:(GCCommit*)newCommit
           withCommit:(GCCommit*)oldCommit  // May be nil
          filePattern:(NSString*)filePattern  // May be nil
              options:(GCDiffOptions)options
    maxInterHunkLines:(NSUInteger)maxInterHunkLines
      maxContextLines:(NSUInteger)maxContextLines
                error:(NSError**)error;  // git diff {old_commit} {new_commit}

- (GCDiff*)diffIndex:(GCIndex*)newIndex
           withIndex:(GCIndex*)oldIndex
         filePattern:(NSString*)filePattern  // May be nil
             options:(GCDiffOptions)options
   maxInterHunkLines:(NSUInteger)maxInterHunkLines
     maxContextLines:(NSUInteger)maxContextLines
               error:(NSError**)error;  // (?)

- (GCDiff*)diffWorkingDirectoryWithHEAD:(NSString*)filePattern  // May be nil
                                options:(GCDiffOptions)options
                      maxInterHunkLines:(NSUInteger)maxInterHunkLines
                        maxContextLines:(NSUInteger)maxContextLines
                                  error:(NSError**)error;  // git diff HEAD

- (GCDiff*)diffWorkingDirectoryWithRepositoryIndex:(NSString*)filePattern  // May be nil
                                           options:(GCDiffOptions)options
                                 maxInterHunkLines:(NSUInteger)maxInterHunkLines
                                   maxContextLines:(NSUInteger)maxContextLines
                                             error:(NSError**)error;  // git diff

- (GCDiff*)diffRepositoryIndexWithHEAD:(NSString*)filePattern  // May be nil
                               options:(GCDiffOptions)options
                     maxInterHunkLines:(NSUInteger)maxInterHunkLines
                       maxContextLines:(NSUInteger)maxContextLines
                                 error:(NSError**)error;  // git diff --cached

- (BOOL)mergeDiff:(GCDiff*)diff ontoDiff:(GCDiff*)ontoDiff error:(NSError**)error;  // Merge diffs the same way Git does for "git diff <sha>"

- (GCDiffPatch*)makePatchForDiffDelta:(GCDiffDelta*)delta isBinary:(BOOL*)isBinary error:(NSError**)error;
@end
