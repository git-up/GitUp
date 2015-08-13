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

#import "GCRepository+Status.h"
#import "GCHistory.h"
#import "GCSnapshot.h"
#import "GCCommitDatabase.h"

typedef NS_ENUM(NSUInteger, GCLiveRepositoryStatusMode) {
  kGCLiveRepositoryStatusMode_Disabled = 0,
  kGCLiveRepositoryStatusMode_Normal,
  kGCLiveRepositoryStatusMode_Unified
};

typedef NS_ENUM(NSUInteger, GCLiveRepositoryDiffWhitespaceMode) {
  kGCLiveRepositoryDiffWhitespaceMode_Normal = 0,
  kGCLiveRepositoryDiffWhitespaceMode_IgnoreChanges,
  kGCLiveRepositoryDiffWhitespaceMode_IgnoreAll
};

extern NSString* const GCLiveRepositoryDidChangeNotification;
extern NSString* const GCLiveRepositoryWorkingDirectoryDidChangeNotification;

extern NSString* const GCLiveRepositoryStateDidUpdateNotification;
extern NSString* const GCLiveRepositoryHistoryDidUpdateNotification;
extern NSString* const GCLiveRepositoryStashesDidUpdateNotification;
extern NSString* const GCLiveRepositoryStatusDidUpdateNotification;
extern NSString* const GCLiveRepositorySnapshotsDidUpdateNotification;
extern NSString* const GCLiveRepositorySearchDidUpdateNotification;

extern NSString* const GCLiveRepositoryCommitOperationReason;
extern NSString* const GCLiveRepositoryAmendOperationReason;

@class GCLiveRepository, GCDiff, GCReferenceTransform;

@protocol GCLiveRepositoryDelegate <GCRepositoryDelegate>
@optional
- (void)repositoryDidChange:(GCRepository*)repository;
- (void)repositoryWorkingDirectoryDidChange:(GCRepository*)repository;

- (void)repositoryDidUpdateState:(GCLiveRepository*)repository;

- (void)repositoryDidUpdateHistory:(GCLiveRepository*)repository;
- (void)repository:(GCLiveRepository*)repository historyUpdateDidFailWithError:(NSError*)error;
- (void)repositoryDidUpdateStashes:(GCLiveRepository*)repository;
- (void)repository:(GCLiveRepository*)repository stashesUpdateDidFailWithError:(NSError*)error;
- (void)repositoryDidUpdateStatus:(GCLiveRepository*)repository;
- (void)repository:(GCLiveRepository*)repository statusUpdateDidFailWithError:(NSError*)error;

- (void)repositoryDidUpdateSnapshots:(GCLiveRepository*)repository;
- (void)repository:(GCLiveRepository*)repository snapshotsUpdateDidFailWithError:(NSError*)error;

- (void)repositoryDidUpdateSearch:(GCLiveRepository*)repository;
- (void)repository:(GCLiveRepository*)repository searchUpdateDidFailWithError:(NSError*)error;

- (void)repositoryBackgroundOperationInProgressDidChange:(GCLiveRepository*)repository;

- (void)repository:(GCLiveRepository*)repository undoOperationDidFailWithError:(NSError*)error;
@end

@interface GCLiveRepository : GCRepository
#if DEBUG
+ (NSUInteger)allocatedCount;  // For debugging only
#endif
@property(nonatomic, assign) id<GCLiveRepositoryDelegate> delegate;

- (void)notifyRepositoryChanged;  // Calling this method is required when manipulating the repository from this process as live-updates don't apply
- (void)notifyWorkingDirectoryChanged;  // Calling this method is required when manipulating the working directory from this process as live-updates don't apply

+ (GCHistorySorting)historySorting;  // Default is kGCHistorySorting_None
@property(nonatomic, readonly) GCHistory* history;
@property(nonatomic, readonly, getter=areHistoryUpdatesSuspended) BOOL historyUpdatesSuspended;
- (void)suspendHistoryUpdates;  // Nestable
- (void)resumeHistoryUpdates;  // Nestable

@property(nonatomic, getter=areSnapshotsEnabled) BOOL snapshotsEnabled;  // Default is NO - Should be enabled *after* setting delegate so any error can be received
@property(nonatomic, getter=areAutomaticSnapshotsEnabled) BOOL automaticSnapshotsEnabled;  // Requires @snapshotsEnabled to be YES
@property(nonatomic, readonly) NSArray* snapshots;  // Nil if snapshots are disabled

@property(nonatomic) GCLiveRepositoryDiffWhitespaceMode diffWhitespaceMode;  // Default is kGCLiveRepositoryDiffWhitespaceMode_Normal
@property(nonatomic) NSUInteger diffMaxInterHunkLines;  // Default is 0
@property(nonatomic) NSUInteger diffMaxContextLines;  // Default is 3
@property(nonatomic, readonly) GCDiffOptions diffBaseOptions;  // For convenience

@property(nonatomic) GCLiveRepositoryStatusMode statusMode;  // Default is kGCLiveRepositoryStatusMode_Disabled - Should be changed *after* setting delegate so any error can be received
@property(nonatomic, readonly) GCDiff* unifiedStatus;  // Nil on error
@property(nonatomic, readonly) GCDiff* workingDirectoryStatus;  // Nil on error
@property(nonatomic, readonly) GCDiff* indexStatus;  // Nil on error
@property(nonatomic, readonly) NSDictionary* indexConflicts;  // Nil on error

@property(nonatomic, getter=areStashesEnabled) BOOL stashesEnabled;  // Default is NO - Should be enabled *after* setting delegate so any error can be received
@property(nonatomic, readonly) NSArray* stashes;  // Nil on error

@property(nonatomic, strong) NSUndoManager* undoManager;  // Default is nil
- (void)setUndoActionName:(NSString*)name;  // Wrapper for -[NSUndoManager setActionName:] that doesn't open an undo block

- (BOOL)performOperationWithReason:(NSString*)reason  // Pass nil to disable automatic snapshots and undo
                          argument:(id<NSCoding>)argument  // May be nil
                skipCheckoutOnUndo:(BOOL)skipCheckout
                             error:(NSError**)error
                        usingBlock:(BOOL (^)(GCLiveRepository* repository, NSError** outError))block;  // Automatically updates snapshots and register undo action with NSUndoManager

@property(nonatomic, readonly) BOOL hasBackgroundOperationInProgress;
- (void)performOperationInBackgroundWithReason:(NSString*)reason  // Pass nil to disable automatic snapshots and undo
                                      argument:(id<NSCoding>)argument  // May be nil
                           usingOperationBlock:(BOOL (^)(GCRepository* repository, NSError** outError))operationBlock  // "repository" is a new instance
                               completionBlock:(void (^)(BOOL success, NSError* error))completionBlock;
@end

@interface GCLiveRepository (Extensions)
- (BOOL)performReferenceTransformWithReason:(NSString*)reason
                                   argument:(id<NSCoding>)argument
                                      error:(NSError**)error
                                 usingBlock:(GCReferenceTransform* (^)(GCLiveRepository* repository, NSError** outError))block;  // Convenience method for transform operations

- (GCCommit*)performCommitCreationFromHEADAndOtherParent:(GCCommit*)parent withMessage:(NSString*)message error:(NSError**)error;  // Convenience method for creating a commit with custom undo/redo that only moves the HEAD and does not checkout
- (GCCommit*)performHEADCommitAmendingWithMessage:(NSString*)message error:(NSError**)error;  // Convenience method for amending HEAD commit with custom undo/redo that only moves the HEAD and does not checkout
@end

@interface GCLiveRepository (Search)
- (void)prepareSearchInBackground:(BOOL)indexDiffs
              withProgressHandler:(GCCommitDatabaseProgressHandler)handler  // Called from background thread!
                       completion:(void (^)(BOOL success, NSError* error))completion;
- (NSArray*)findCommitsMatching:(NSString*)match;  // Returns GCHistoryCommit, GCHistoryLocalBranch, GCHistoryRemoteBranch or GCHistoryTag (references are guaranteed to have a corresponding commit)
@end

@interface GCSnapshot (GCLiveRepository)
- (NSDate*)date;
- (NSString*)reason;
- (id<NSCoding>)argument;  // May be nil
@end
