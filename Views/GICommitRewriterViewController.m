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

#import "GICommitRewriterViewController.h"
#import "GIDiffContentsViewController.h"
#import "GIDiffFilesViewController.h"
#import "GIWindowController.h"

#import "GIInterface.h"
#import "GCRepository+Utilities.h"
#import "GCHistory+Rewrite.h"
#import "XLFacilityMacros.h"

@interface GICommitRewriterViewController () <GIDiffContentsViewControllerDelegate, GIDiffFilesViewControllerDelegate>
@property(nonatomic, weak) IBOutlet NSTextField* titleTextField;
@property(nonatomic, weak) IBOutlet NSView* contentsView;
@property(nonatomic, weak) IBOutlet NSView* filesView;
@property(nonatomic, weak) IBOutlet NSButton* continueButton;

@property(nonatomic, strong) IBOutlet NSView* messageView;
@end

@implementation GICommitRewriterViewController {
  GIDiffContentsViewController* _diffContentsViewController;
  GIDiffFilesViewController* _diffFilesViewController;
  GCDiff* _unifiedStatus;
  BOOL _disableFeedbackLoop;
  NSDateFormatter* _dateFormatter;
  GCHistoryCommit* _targetCommit;
  id _savedHEAD;
}

@dynamic delegate;

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithRepository:repository])) {
    _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.dateStyle = NSDateFormatterShortStyle;
    _dateFormatter.timeStyle = NSDateFormatterShortStyle;
    
    self.showsBranchInfo = NO;
  }
  return self;
}

- (void)loadView {
  [super loadView];
  
  _diffContentsViewController = [[GIDiffContentsViewController alloc] initWithRepository:self.repository];
  _diffContentsViewController.delegate = self;
  _diffContentsViewController.showsUntrackedAsAdded = YES;
  _diffContentsViewController.emptyLabel = NSLocalizedString(@"No changes in working directory", nil);
  [_contentsView replaceWithView:_diffContentsViewController.view];
  
  _diffFilesViewController = [[GIDiffFilesViewController alloc] initWithRepository:self.repository];
  _diffFilesViewController.delegate = self;
  _diffFilesViewController.showsUntrackedAsAdded = YES;
  _diffFilesViewController.emptyLabel = NSLocalizedString(@"No changes in working directory", nil);
  [_filesView replaceWithView:_diffFilesViewController.view];
}

- (void)viewWillShow {
  XLOG_DEBUG_CHECK(_targetCommit != nil);
  [super viewWillShow];
  
  XLOG_DEBUG_CHECK(self.repository.statusMode == kGCLiveRepositoryStatusMode_Disabled);
  self.repository.statusMode = kGCLiveRepositoryStatusMode_Unified;
  
  self.messageTextView.string = _targetCommit.message;
  
  [self _reloadContents];
}

- (void)viewDidHide {
  [super viewDidHide];
  
  _unifiedStatus = nil;
  
  [_diffContentsViewController setDeltas:nil usingConflicts:nil];
  [_diffFilesViewController setDeltas:nil usingConflicts:nil];
  
  XLOG_DEBUG_CHECK(self.repository.statusMode == kGCLiveRepositoryStatusMode_Unified);
  self.repository.statusMode = kGCLiveRepositoryStatusMode_Disabled;
}

- (void)repositoryStatusDidUpdate {
  [super repositoryStatusDidUpdate];
  
  if (self.viewVisible) {
    [self _reloadContents];
  }
}

- (void)_reloadContents {
  CGFloat offset;
  GCDiffDelta* topDelta = [_diffContentsViewController topVisibleDelta:&offset];
  
  _unifiedStatus = self.repository.unifiedStatus;
  [_diffContentsViewController setDeltas:_unifiedStatus.deltas usingConflicts:nil];
  [_diffFilesViewController setDeltas:_unifiedStatus.deltas usingConflicts:nil];
  
  [_diffContentsViewController setTopVisibleDelta:topDelta offset:offset];
  
  _continueButton.enabled = _unifiedStatus.modified;
}

- (BOOL)_restoreHEAD:(NSError**)error {
  BOOL success;
  if ([_savedHEAD isKindOfClass:[GCBranch class]]) {
    success = [self.repository checkoutLocalBranch:_savedHEAD options:(kGCCheckoutOption_UpdateSubmodulesRecursively | kGCCheckoutOption_Force) error:error];
  } else if ([_savedHEAD isKindOfClass:[GCCommit class]]) {
    success = [self.repository checkoutCommit:_savedHEAD options:(kGCCheckoutOption_UpdateSubmodulesRecursively | kGCCheckoutOption_Force) error:error];
  } else {
    success = YES;
  }
  XLOG_DEBUG_CHECK(!success || [self.repository checkClean:0 error:NULL]);
  return success;
}

- (BOOL)startRewritingCommit:(GCHistoryCommit*)commit error:(NSError**)error {
  XLOG_DEBUG_CHECK(_targetCommit == nil);
  
  // Check that repository is completely clean (don't even allow untracked files)
  if (![self.repository checkClean:0 error:error]) {
    return NO;
  }
  
  // Check out commit and move back HEAD by 1 to put changes in index
  BOOL success = [self.repository checkoutCommit:commit options:kGCCheckoutOption_UpdateSubmodulesRecursively error:error];
  if (success) {
    success = [self.repository setDetachedHEADToCommit:commit.parents[0] error:error];
  }
  
  // Save original HEAD
  if (success) {
    _savedHEAD = self.repository.history.HEADBranch;
    if (_savedHEAD == nil) {
      _savedHEAD = self.repository.history.HEADCommit;
    }
  }
  
  // Clean up
  [self.repository notifyRepositoryChanged];
  
  _targetCommit = commit;
  _titleTextField.stringValue = [NSString stringWithFormat:@"\"%@\" <%@>", _targetCommit.summary, _targetCommit.shortSHA1];
  return YES;
}

- (BOOL)cancelRewritingCommit:(NSError**)error {
  XLOG_DEBUG_CHECK(_targetCommit != nil);
  BOOL success = [self _restoreHEAD:error];
  _savedHEAD = nil;
  _targetCommit = nil;
  [self.repository notifyRepositoryChanged];
  return success;
}

- (BOOL)finishRewritingCommitWithMessage:(NSString*)message error:(NSError**)error {
  XLOG_DEBUG_CHECK(_targetCommit != nil);
  BOOL success = NO;
  GCCommit* newCommit;
  GCIndex* index;
  
  // Add all workdir changes to index
  if (![self.repository syncIndexWithWorkingDirectory:error]) {
    goto cleanup;
  }
  
  // Copy commit with updated index and message
  index = [self.repository readRepositoryIndex:error];
  if (index == nil) {
    goto cleanup;
  }
  newCommit = [self.repository copyCommit:_targetCommit withUpdatedMessage:message updatedParents:nil updatedTreeFromIndex:index updateCommitter:YES error:error];
  if (newCommit == nil) {
    goto cleanup;
  }
  
  // Restore original HEAD (must happen before transform in case the transform moves it as part of replaying commits)
  if (![self _restoreHEAD:error]) {
    goto cleanup;
  }
  
  // Rewrite commit
  [self.repository suspendHistoryUpdates];  // We need to suspend history updates to prevent history to change during replay if conflict handler is called
  [self.repository setUndoActionName:NSLocalizedString(@"Rewrite Commit", nil)];
  if (![self.repository performReferenceTransformWithReason:@"rewrite_commit"
                                                   argument:_targetCommit.SHA1
                                                      error:error
                                                 usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
    
    return [repository.history rewriteCommit:_targetCommit withUpdatedCommit:newCommit copyTrees:NO conflictHandler:^GCCommit*(GCIndex* index2, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message2, NSError** outError2) {
      
        return [self resolveConflictsWithResolver:self.delegate index:index2 ourCommit:ourCommit theirCommit:theirCommit parentCommits:parentCommits message:message2 error:outError2];
        
      } error:outError1];
    
  }]) {
    [self.repository resumeHistoryUpdates];
    goto cleanup;
  }
  [self.repository resumeHistoryUpdates];
  
  // Make sure index and workdir are in sync with HEAD
  if (![self.repository forceCheckoutHEAD:NO error:error]) {
    goto cleanup;
  }
  success = YES;
  
cleanup:
  _savedHEAD = nil;
  _targetCommit = nil;
  [self.repository notifyRepositoryChanged];
  if (success) {
    [self didCreateCommit:newCommit];
  }
  return success;
}

#pragma mark - GIDiffContentsViewControllerDelegate

- (void)diffContentsViewControllerDidScroll:(GIDiffContentsViewController*)scroll {
  if (!_disableFeedbackLoop) {
    _diffFilesViewController.selectedDelta = [_diffContentsViewController topVisibleDelta:NULL];
  }
}

- (NSString*)diffContentsViewController:(GIDiffContentsViewController*)controller actionButtonLabelForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  if (delta.submodule) {
    return NSLocalizedString(@"Discard Submodule Changes…", nil);
  } else if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:NULL newLines:NULL]) {
    return NSLocalizedString(@"Discard Line Changes…", nil);
  } else {
    return NSLocalizedString(@"Discard File Changes…", nil);
  }
  return nil;
}

- (void)diffContentsViewController:(GIDiffContentsViewController*)controller didClickActionButtonForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  if (delta.submodule) {
    [self discardSubmoduleAtPath:delta.canonicalPath resetIndex:YES];
  } else {
    NSIndexSet* oldLines;
    NSIndexSet* newLines;
    if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:&oldLines newLines:&newLines]) {
      [self discardSelectedChangesForFile:delta.canonicalPath oldLines:oldLines newLines:newLines resetIndex:YES];
    } else {
      [self discardAllChangesForFile:delta.canonicalPath resetIndex:YES];
    }
  }
}

- (NSMenu*)diffContentsViewController:(GIDiffContentsViewController*)controller willShowContextualMenuForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  XLOG_DEBUG_CHECK(conflict == nil);
  return [self contextualMenuForDelta:delta withConflict:nil allowOpen:YES];
}

#pragma mark - GIDiffFilesViewControllerDelegate

- (void)diffFilesViewController:(GIDiffFilesViewController*)controller willSelectDelta:(GCDiffDelta*)delta {
  _disableFeedbackLoop = YES;
  [_diffContentsViewController setTopVisibleDelta:delta offset:0];
  _disableFeedbackLoop = NO;
}

- (BOOL)diffFilesViewController:(GIDiffFilesViewController*)controller handleKeyDownEvent:(NSEvent*)event {
  return [self handleKeyDownEvent:event forSelectedDeltas:_diffFilesViewController.selectedDeltas withConflicts:nil allowOpen:YES];
}

#pragma mark - NSTextViewDelegate

// Intercept Option-Return key in NSTextView and forward to next responder
- (BOOL)textView:(NSTextView*)textView doCommandBySelector:(SEL)selector {
  if (selector == @selector(insertNewlineIgnoringFieldEditor:)) {
    return [self.view.window.firstResponder.nextResponder tryToPerform:@selector(keyDown:) with:[NSApp currentEvent]];
  }
  return [super textView:textView doCommandBySelector:selector];
}

#pragma mark - Actions

- (IBAction)cancel:(id)sender {
  [self.delegate commitRewriterViewControllerShouldCancel:self];
}

- (IBAction)continue:(id)sender {
  if (self.repository.indexConflicts.count) {
    [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"You must resolve conflicts before continuing!", nil) message:nil];
    return;
  }
  [self.windowController runModalView:self.messageView withInitialFirstResponder:self.messageTextView completionHandler:^(BOOL success) {
    
    if (success) {
      NSString* message = [self.messageTextView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (message.length) {
        [self.delegate commitRewriterViewControllerShouldFinish:self withMessage:message];
      } else {
        [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"You must provide a non-empty commit message", nil) message:nil];
      }
    }
    
  }];
}

@end
