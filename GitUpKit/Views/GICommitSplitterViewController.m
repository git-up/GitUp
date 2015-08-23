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

#import "GICommitSplitterViewController.h"
#import "GIDiffFilesViewController.h"
#import "GIDiffContentsViewController.h"

#import "GCCore.h"
#import "GIInterface.h"
#import "GCHistory+Rewrite.h"
#import "GIWindowController.h"
#import "XLFacilityMacros.h"

#define kGCDefaultMaxDiffContextLines 3

@interface GICommitSplitterViewController () <GIDiffFilesViewControllerDelegate, GIDiffContentsViewControllerDelegate>
@property(nonatomic, weak) IBOutlet NSTextField* titleTextField;
@property(nonatomic, weak) IBOutlet NSView* filesViewNew;
@property(nonatomic, weak) IBOutlet NSView* filesViewOld;
@property(nonatomic, weak) IBOutlet NSView* diffContentsView;
@property(nonatomic, weak) IBOutlet NSButton* continueButton;

@property(nonatomic, strong) IBOutlet NSView* messageView;
@end

@implementation GICommitSplitterViewController {
  GIDiffFilesViewController* _filesViewControllerNew;
  GIDiffFilesViewController* _filesViewControllerOld;
  GIDiffContentsViewController* _diffContentsViewController;
  GCHistoryCommit* _commit;
  GCHistoryCommit* _parentCommit;
  GCIndex* _indexNew;
  GCDiff* _diffNew;
  GCIndex* _indexOld;
  GCDiff* _diffOld;
  BOOL _newActive;
  BOOL _disableFeedback;
}

@dynamic delegate;

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithRepository:repository])) {
    self.showsBranchInfo = NO;
  }
  return self;
}

- (void)loadView {
  [super loadView];
  
  _filesViewControllerNew = [[GIDiffFilesViewController alloc] initWithRepository:self.repository];
  _filesViewControllerNew.delegate = self;
  _filesViewControllerNew.allowsMultipleSelection = YES;
  _filesViewControllerNew.emptyLabel = NSLocalizedString(@"No changes in commit", nil);
  [_filesViewNew replaceWithView:_filesViewControllerNew.view];
  
  _filesViewControllerOld = [[GIDiffFilesViewController alloc] initWithRepository:self.repository];
  _filesViewControllerOld.delegate = self;
  _filesViewControllerOld.allowsMultipleSelection = YES;
  _filesViewControllerOld.emptyLabel = NSLocalizedString(@"No changes in commit", nil);
  [_filesViewOld replaceWithView:_filesViewControllerOld.view];
  
  _diffContentsViewController = [[GIDiffContentsViewController alloc] initWithRepository:self.repository];
  _diffContentsViewController.delegate = self;
  _diffContentsViewController.emptyLabel = NSLocalizedString(@"No file selected", nil);
  [_diffContentsView replaceWithView:_diffContentsViewController.view];
}

- (void)viewWillShow {
  XLOG_DEBUG_CHECK(_commit);
  [super viewWillShow];
  
  _titleTextField.stringValue = [NSString stringWithFormat:@"\"%@\" <%@>", _commit.summary, _commit.shortSHA1];
  
  self.messageTextView.string = _commit.message;
  self.otherMessageTextView.string = _commit.message;
  
  [self _reload];
  
  _filesViewControllerOld.selectedDelta = _diffOld.deltas.firstObject;
}

- (void)viewDidHide {
  [super viewDidHide];
  
  _diffNew = nil;
  _diffOld = nil;
  
  [_filesViewControllerNew setDeltas:nil usingConflicts:nil];
  [_filesViewControllerOld setDeltas:nil usingConflicts:nil];
  [_diffContentsViewController setDeltas:nil usingConflicts:nil];
}

- (void)_reload {
  CGFloat offset;
  GCDiffDelta* topDelta = [_diffContentsViewController topVisibleDelta:&offset];
  NSArray* selectedDeltasNew = _filesViewControllerNew.selectedDeltas;
  NSUInteger selectedRowNew = selectedDeltasNew.count ? [_diffNew.deltas indexOfObjectIdenticalTo:selectedDeltasNew.firstObject] : NSNotFound;
  NSArray* selectedDeltasOld = _filesViewControllerOld.selectedDeltas;
  NSUInteger selectedRowOld = selectedDeltasOld.count ? [_diffOld.deltas indexOfObjectIdenticalTo:selectedDeltasOld.firstObject] : NSNotFound;
  
  NSError* error;
  _diffNew = [self.repository diffIndex:_indexNew withIndex:_indexOld filePattern:nil options:kGCDiffOption_FindRenames maxInterHunkLines:0 maxContextLines:kGCDefaultMaxDiffContextLines error:&error];
  if (_diffNew == nil) {
    [self presentError:error];
  }
  _diffOld = [self.repository diffIndex:_indexOld withCommit:_parentCommit filePattern:nil options:kGCDiffOption_FindRenames maxInterHunkLines:0 maxContextLines:kGCDefaultMaxDiffContextLines error:&error];
  if (_diffOld == nil) {
    [self presentError:error];
  }
  
  _disableFeedback = YES;
  
  [_filesViewControllerNew setDeltas:_diffNew.deltas usingConflicts:nil];
  _filesViewControllerNew.selectedDeltas = selectedDeltasNew;
  if (_diffNew.deltas.count && selectedDeltasNew.count && !_filesViewControllerNew.selectedDeltas.count && (selectedRowNew != NSNotFound)) {
    _filesViewControllerNew.selectedDelta = _diffNew.deltas[MIN(selectedRowNew, _diffNew.deltas.count - 1)];  // If we can't preserve the selected deltas, attempt to preserve the first selected row
  }
  
  [_filesViewControllerOld setDeltas:_diffOld.deltas usingConflicts:nil];
  _filesViewControllerOld.selectedDeltas = selectedDeltasOld;
  if (_diffOld.deltas.count && selectedDeltasOld.count && !_filesViewControllerOld.selectedDeltas.count && (selectedRowOld != NSNotFound)) {
    _filesViewControllerOld.selectedDelta = _diffOld.deltas[MIN(selectedRowOld, _diffOld.deltas.count - 1)];  // If we can't preserve the selected deltas, attempt to preserve the first selected row
  }
  
  if (_newActive) {
    [_diffContentsViewController setDeltas:_filesViewControllerNew.selectedDeltas usingConflicts:nil];
  } else {
    [_diffContentsViewController setDeltas:_filesViewControllerOld.selectedDeltas usingConflicts:nil];
  }
  [_diffContentsViewController setTopVisibleDelta:topDelta offset:offset];
  
  _disableFeedback = NO;
  
  _continueButton.enabled = _diffNew.modified && _diffOld.modified;
}

- (void)_copyFileFromIndexNewToIndexOld:(GCDiffDelta*)delta {
  NSError* error;
  BOOL success = delta.change == kGCFileDiffChange_Deleted ? [self.repository removeFile:delta.canonicalPath fromIndex:_indexOld error:&error]
                                                           : [self.repository copyFile:delta.canonicalPath fromOtherIndex:_indexNew toIndex:_indexOld error:&error];
  if (success) {
    [self _reload];
    _disableFeedback = YES;
    _filesViewControllerOld.selectedDelta = delta;
    _disableFeedback = NO;
  } else {
    [self presentError:error];
  }
}

- (void)_copyFilesFromIndexNewToIndexOld:(NSArray*)deltas {
  for (GCDiffDelta* delta in deltas) {
    NSError* error;
    BOOL success = delta.change == kGCFileDiffChange_Deleted ? [self.repository removeFile:delta.canonicalPath fromIndex:_indexOld error:&error]
                                                             : [self.repository copyFile:delta.canonicalPath fromOtherIndex:_indexNew toIndex:_indexOld error:&error];
    if (!success) {
      [self presentError:error];
      break;
    }
  }
  [self _reload];
  _disableFeedback = YES;
  _filesViewControllerOld.selectedDeltas = deltas;
  _disableFeedback = NO;
  if (!_filesViewControllerNew.deltas.count) {
    _newActive = NO;
    [self.view.window makeFirstResponder:_filesViewControllerOld.preferredFirstResponder];
  }
}

- (void)_copyFileLinesFromIndexNewToIndexOld:(GCDiffDelta*)delta oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines {
  NSError* error;
  BOOL success;
  if (delta.change == kGCFileDiffChange_Deleted) {
    success = [self.repository resetLinesInFile:delta.canonicalPath index:_indexOld toCommit:_commit error:&error usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
      
      if (change == kGCLineDiffChange_Added) {
        return [oldLines containsIndex:newLineNumber];
      }
      return NO;
      
    }];
  } else {
    success = [self.repository copyLinesInFile:delta.canonicalPath fromOtherIndex:_indexNew toIndex:_indexOld error:&error usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
      
      if (change == kGCLineDiffChange_Added) {
        return [newLines containsIndex:newLineNumber];
      }
      if (change == kGCLineDiffChange_Deleted) {
        return [oldLines containsIndex:oldLineNumber];
      }
      return NO;
      
    }];
  }
  if (success) {
    [self _reload];
    _disableFeedback = YES;
    _filesViewControllerNew.selectedDelta = delta;
    _disableFeedback = NO;
  } else {
    [self presentError:error];
  }
}

- (void)_copyFileFromIndexOldToIndexNew:(GCDiffDelta*)delta {
  NSError* error;
  if ([self.repository resetFile:delta.canonicalPath inIndex:_indexOld toCommit:_parentCommit error:&error]) {
    [self _reload];
    _disableFeedback = YES;
    _filesViewControllerNew.selectedDelta = delta;
    _disableFeedback = NO;
  } else {
    [self presentError:error];
  }
}

- (void)_copyFilesFromIndexOldToIndexNew:(NSArray*)deltas {
  for (GCDiffDelta* delta in deltas) {
    NSError* error;
    if (![self.repository resetFile:delta.canonicalPath inIndex:_indexOld toCommit:_parentCommit error:&error]) {
      [self presentError:error];
      break;
    }
  }
  [self _reload];
  _disableFeedback = YES;
  _filesViewControllerNew.selectedDeltas = deltas;
  _disableFeedback = NO;
  if (!_filesViewControllerOld.deltas.count) {
    _newActive = YES;
    [self.view.window makeFirstResponder:_filesViewControllerNew.preferredFirstResponder];
  }
}

- (void)_copyFileLinesFromIndexOldToIndexNew:(GCDiffDelta*)delta oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines {
  NSError* error;
  if ([self.repository resetLinesInFile:delta.canonicalPath index:_indexOld toCommit:_parentCommit error:&error usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
    
    if (change == kGCLineDiffChange_Added) {
      return [newLines containsIndex:newLineNumber];
    }
    if (change == kGCLineDiffChange_Deleted) {
      return [oldLines containsIndex:oldLineNumber];
    }
    return NO;
    
  }]) {
    [self _reload];
    _disableFeedback = YES;
    _filesViewControllerNew.selectedDelta = delta;
    _disableFeedback = NO;
  } else {
    [self presentError:error];
  }
}

- (BOOL)startSplittingCommit:(GCHistoryCommit*)commit error:(NSError**)error {
  GCIndex* indexNew = [self.repository createInMemoryIndex:error];
  if (!indexNew || ![self.repository resetIndex:indexNew toTreeForCommit:commit error:error]) {
    return NO;
  }
  GCIndex* indexOld = [self.repository createInMemoryIndex:error];
  if (!indexOld || ![self.repository resetIndex:indexOld toTreeForCommit:commit error:error]) {
    return NO;
  }
  
  _commit = commit;
  _parentCommit = commit.parents.firstObject;  // Use mainline
  _indexNew = indexNew;
  _indexOld = indexOld;
  return YES;
}

- (void)_cleanup {
  _indexNew = nil;
  _indexOld = nil;
  _commit = nil;
  _parentCommit = nil;
}

- (void)cancelSplittingCommit {
  [self _cleanup];
}

- (BOOL)finishSplittingCommitWithOldMessage:(NSString*)oldMessage newMessage:(NSString*)newMessage error:(NSError**)error {
  BOOL success = NO;
  GCCommit* newCommit;
  
  // Copy old commit with updated index and message
  newCommit = [self.repository copyCommit:_commit withUpdatedMessage:oldMessage updatedParents:nil updatedTreeFromIndex:_indexOld updateCommitter:YES error:error];
  if (newCommit == nil) {
    goto cleanup;
  }
  
  // Copy new commit with updated index and message
  newCommit = [self.repository copyCommit:_commit withUpdatedMessage:newMessage updatedParents:@[newCommit] updatedTreeFromIndex:_indexNew updateCommitter:YES error:error];
  if (newCommit == nil) {
    goto cleanup;
  }
  
  // Rewrite commit
  [self.repository suspendHistoryUpdates];  // We need to suspend history updates to prevent history to change during replay if conflict handler is called
  [self.repository setUndoActionName:NSLocalizedString(@"Split Commit", nil)];
  if ([self.repository performReferenceTransformWithReason:@"split_commit"
                                                  argument:_commit.SHA1
                                                     error:error
                                                usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
    
    return [repository.history rewriteCommit:_commit withUpdatedCommit:newCommit copyTrees:YES conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message3, NSError** outError2) {
      
        XLOG_DEBUG_UNREACHABLE();  // Splitting a commit should not generate index conflicts when replaying descendants
        return [self resolveConflictsWithResolver:self.delegate index:index ourCommit:ourCommit theirCommit:theirCommit parentCommits:parentCommits message:message3 error:outError2];
        
      } error:outError1];
    
  }]) {
    success = YES;
  }
  [self.repository resumeHistoryUpdates];
  
cleanup:
  [self _cleanup];
  if (success) {
    [self didCreateCommit:newCommit];
  }
  return success;
}

#pragma mark - GIDiffFilesViewControllerDelegate

- (void)diffFilesViewControllerDidBecomeFirstResponder:(GIDiffFilesViewController*)controller {
  [self diffFilesViewControllerDidChangeSelection:controller];
}

- (void)diffFilesViewControllerDidChangeSelection:(GIDiffFilesViewController*)controller {
  if (!_disableFeedback) {
    if (controller == _filesViewControllerNew) {
      [_diffContentsViewController setDeltas:_filesViewControllerNew.selectedDeltas usingConflicts:nil];
      _newActive = YES;
    } else if (controller == _filesViewControllerOld) {
      [_diffContentsViewController setDeltas:_filesViewControllerOld.selectedDeltas usingConflicts:nil];
      _newActive = NO;
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }
  }
}

- (void)_diffFilesViewControllerDidPressReturn:(GIDiffFilesViewController*)controller {
  if (controller == _filesViewControllerNew) {
    [self _copyFilesFromIndexNewToIndexOld:_filesViewControllerNew.selectedDeltas];
  } else if (controller == _filesViewControllerOld) {
    [self _copyFilesFromIndexOldToIndexNew:_filesViewControllerOld.selectedDeltas];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (BOOL)diffFilesViewController:(GIDiffFilesViewController*)controller handleKeyDownEvent:(NSEvent*)event {
  if (!(event.modifierFlags & NSDeviceIndependentModifierFlagsMask)) {
    if (event.keyCode == kGIKeyCode_Return) {
      [self _diffFilesViewControllerDidPressReturn:controller];
      return YES;
    }
  }
  
  if (controller == _filesViewControllerNew) {
    return [self handleKeyDownEvent:event forSelectedDeltas:_filesViewControllerNew.selectedDeltas withConflicts:nil allowOpen:NO];
  } else if (controller == _filesViewControllerOld) {
    return [self handleKeyDownEvent:event forSelectedDeltas:_filesViewControllerOld.selectedDeltas withConflicts:nil allowOpen:NO];
  }
  
  return NO;
}

- (void)diffFilesViewController:(GIDiffFilesViewController*)controller didDoubleClickDeltas:(NSArray*)deltas {
  if (controller == _filesViewControllerNew) {
    [self _copyFilesFromIndexNewToIndexOld:deltas];
  } else if (controller == _filesViewControllerOld) {
    [self _copyFilesFromIndexOldToIndexNew:deltas];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (BOOL)diffFilesViewControllerShouldAcceptDeltas:(GIDiffFilesViewController*)controller fromOtherController:(GIDiffFilesViewController*)otherController {
  return ((controller == _filesViewControllerNew) && (otherController == _filesViewControllerOld)) || ((controller == _filesViewControllerOld) && (otherController == _filesViewControllerNew));
}

- (BOOL)diffFilesViewController:(GIDiffFilesViewController*)controller didReceiveDeltas:(NSArray*)deltas fromOtherController:(GIDiffFilesViewController*)otherController {
  if ((controller == _filesViewControllerNew) && (otherController == _filesViewControllerOld)) {
    [self _copyFilesFromIndexOldToIndexNew:deltas];
    return YES;
  } else if ((controller == _filesViewControllerOld) && (otherController == _filesViewControllerNew)) {
    [self _copyFilesFromIndexNewToIndexOld:deltas];
    return YES;
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
  return NO;
}

#pragma mark - GIDiffContentsViewControllerDelegate

- (void)_diffContentsViewControllerDidPressReturn:(GIDiffContentsViewController*)controller {
  NSMutableArray* deltas = [[NSMutableArray alloc] init];
  for (GCDiffDelta* delta in _diffContentsViewController.deltas) {
    NSIndexSet* oldLines;
    NSIndexSet* newLines;
    if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:&oldLines newLines:&newLines]) {
      if (_newActive) {
        [self _copyFileLinesFromIndexNewToIndexOld:delta oldLines:oldLines newLines:newLines];
      } else {
        [self _copyFileLinesFromIndexOldToIndexNew:delta oldLines:oldLines newLines:newLines];
      }
      [deltas addObject:delta];
    }
  }
  _disableFeedback = YES;
  if (_newActive) {
    _filesViewControllerNew.selectedDeltas = deltas;
  } else {
    _filesViewControllerOld.selectedDeltas = deltas;
  }
  _disableFeedback = NO;
  if ((!_newActive && !_filesViewControllerOld.deltas.count) || (_newActive && !_filesViewControllerNew.deltas.count)) {
    _newActive = !_newActive;
  }
  [self.view.window makeFirstResponder:(_newActive ? _filesViewControllerNew.preferredFirstResponder : _filesViewControllerOld.preferredFirstResponder)];
}

- (BOOL)diffContentsViewController:(GIDiffContentsViewController*)controller handleKeyDownEvent:(NSEvent*)event {
  if (!(event.modifierFlags & NSDeviceIndependentModifierFlagsMask)) {
    if (event.keyCode == kGIKeyCode_Return) {
      [self _diffContentsViewControllerDidPressReturn:controller];
      return YES;
    }
  }
  return NO;
}

- (NSString*)diffContentsViewController:(GIDiffContentsViewController*)controller actionButtonLabelForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  if (delta.submodule) {
    return NSLocalizedString(@"Move Changed Submodule", nil);
  } else if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:NULL newLines:NULL]) {
    return NSLocalizedString(@"Move Changed Lines", nil);
  } else {
    return NSLocalizedString(@"Move Changed File", nil);
  }
  return nil;
}

- (void)diffContentsViewController:(GIDiffContentsViewController*)controller didClickActionButtonForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  NSIndexSet* oldLines;
  NSIndexSet* newLines;
  if (_newActive) {
    if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:&oldLines newLines:&newLines]) {
      [self _copyFileLinesFromIndexNewToIndexOld:delta oldLines:oldLines newLines:newLines];
    } else {
      [self _copyFileFromIndexNewToIndexOld:delta];
    }
  } else {
    if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:&oldLines newLines:&newLines]) {
      [self _copyFileLinesFromIndexOldToIndexNew:delta oldLines:oldLines newLines:newLines];
    } else {
      [self _copyFileFromIndexOldToIndexNew:delta];
    }
  }
}

- (NSMenu*)diffContentsViewController:(GIDiffContentsViewController*)controller willShowContextualMenuForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  XLOG_DEBUG_CHECK(conflict == nil);
  return [self contextualMenuForDelta:delta withConflict:nil allowOpen:NO];
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
  [self.delegate commitSplitterViewControllerShouldCancel:self];
}

- (IBAction)continue:(id)sender {
  [self.windowController runModalView:_messageView withInitialFirstResponder:self.messageTextView completionHandler:^(BOOL success) {
    
    if (success) {
      NSString* message = [self.messageTextView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      NSString* otherMessage = [self.otherMessageTextView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (message.length && otherMessage.length) {
        [self.delegate commitSplitterViewControllerShouldFinish:self withOldMessage:message newMessage:otherMessage];
      } else {
        [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"You must provide non-empty commit messages", nil) message:nil];
      }
    }
    
  }];
}

@end
