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

#import "GIViewController.h"

@class GCCommit, GCIndex, GCDiffDelta, GCIndexConflict;

extern NSString* const GIViewControllerTool_FileMerge;
extern NSString* const GIViewControllerTool_Kaleidoscope;
extern NSString* const GIViewControllerTool_BeyondCompare;
extern NSString* const GIViewControllerTool_P4Merge;
extern NSString* const GIViewControllerTool_GitTool;

extern NSString* const GIViewController_DiffTool;
extern NSString* const GIViewController_MergeTool;

@protocol GIMergeConflictResolver <NSObject>
- (BOOL)resolveMergeConflictsWithOurCommit:(GCCommit*)ourCommit theirCommit:(GCCommit*)theirCommit;
@end

@interface GIViewController (Utilities)
- (void)discardAllFiles;  // Prompts user
- (void)stageAllFiles;
- (void)unstageAllFiles;

- (void)stageSubmoduleAtPath:(NSString*)path;
- (void)unstageSubmoduleAtPath:(NSString*)path;
- (BOOL)discardSubmoduleAtPath:(NSString*)path resetIndex:(BOOL)resetIndex error:(NSError**)error;
- (void)discardSubmoduleAtPath:(NSString*)path resetIndex:(BOOL)resetIndex;  // Prompts user

- (void)stageAllChangesForFile:(NSString*)path;
- (void)stageSelectedChangesForFile:(NSString*)path oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines;
- (void)unstageAllChangesForFile:(NSString*)path;
- (void)unstageSelectedChangesForFile:(NSString*)path oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines;

- (BOOL)discardAllChangesForFile:(NSString*)path resetIndex:(BOOL)resetIndex error:(NSError**)error;
- (void)discardAllChangesForFile:(NSString*)path resetIndex:(BOOL)resetIndex;  // Prompts user
- (BOOL)discardSelectedChangesForFile:(NSString*)path oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines resetIndex:(BOOL)resetIndex error:(NSError**)error;
- (void)discardSelectedChangesForFile:(NSString*)path oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines resetIndex:(BOOL)resetIndex;  // Prompts user

- (void)deleteUntrackedFile:(NSString*)path;  // Prompts user

- (void)restoreFile:(NSString*)path toCommit:(GCCommit*)commit;  // Prompts user

- (void)showFileInFinder:(NSString*)path;
- (void)openFileWithDefaultEditor:(NSString*)path;
- (void)openSubmoduleWithApp:(NSString*)path;
- (void)viewDeltasInDiffTool:(NSArray*)deltas;
- (void)resolveConflictInMergeTool:(GCIndexConflict*)conflict;
- (void)markConflictAsResolved:(GCIndexConflict*)conflict;

- (GCCommit*)resolveConflictsWithResolver:(id<GIMergeConflictResolver>)resolver
                                    index:(GCIndex*)index
                                ourCommit:(GCCommit*)ourCommit
                              theirCommit:(GCCommit*)theirCommit
                            parentCommits:(NSArray*)parentCommits
                                  message:(NSString*)message
                                    error:(NSError**)error;

- (NSMenu*)contextualMenuForDelta:(GCDiffDelta*)delta withConflict:(GCIndexConflict*)conflict allowOpen:(BOOL)allowOpen;
- (BOOL)handleKeyDownEvent:(NSEvent*)event forSelectedDeltas:(NSArray*)deltas withConflicts:(NSDictionary*)conflicts allowOpen:(BOOL)allowOpen;

- (void)launchDiffToolWithCommit:(GCCommit*)commit otherCommit:(GCCommit*)otherCommit;
@end
