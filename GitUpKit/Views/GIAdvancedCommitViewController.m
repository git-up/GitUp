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

#import "GIAdvancedCommitViewController.h"
#import "GIDiffFilesViewController.h"
#import "GIDiffContentsViewController.h"
#import "GIViewController+Utilities.h"

#import "GIInterface.h"
#import "GIWindowController.h"
#import "XLFacilityMacros.h"

@interface GIAdvancedCommitViewController () <GIDiffFilesViewControllerDelegate, GIDiffContentsViewControllerDelegate>
@property(nonatomic, weak) IBOutlet NSView* workdirFilesView;
@property(nonatomic, weak) IBOutlet NSView* indexFilesView;
@property(nonatomic, weak) IBOutlet NSView* diffContentsView;
@property(nonatomic, weak) IBOutlet NSButton* unstageButton;
@property(nonatomic, weak) IBOutlet NSButton* commitButton;
@property(nonatomic, weak) IBOutlet NSButton* stageButton;
@property(nonatomic, weak) IBOutlet NSButton* discardButton;
@end

@implementation GIAdvancedCommitViewController {
  GIDiffFilesViewController* _workdirFilesViewController;
  GIDiffFilesViewController* _indexFilesViewController;
  GIDiffContentsViewController* _diffContentsViewController;
  GCDiff* _indexStatus;
  GCDiff* _workdirStatus;
  NSDictionary* _indexConflicts;
  BOOL _indexActive;
  BOOL _disableFeedback;
}

- (void)loadView {
  [super loadView];
  
  _workdirFilesViewController = [[GIDiffFilesViewController alloc] initWithRepository:self.repository];
  _workdirFilesViewController.delegate = self;
  _workdirFilesViewController.allowsMultipleSelection = YES;
  _workdirFilesViewController.emptyLabel = NSLocalizedString(@"No changes in working directory", nil);
  [_workdirFilesView replaceWithView:_workdirFilesViewController.view];
  
  _indexFilesViewController = [[GIDiffFilesViewController alloc] initWithRepository:self.repository];
  _indexFilesViewController.delegate = self;
  _indexFilesViewController.allowsMultipleSelection = YES;
  _indexFilesViewController.emptyLabel = NSLocalizedString(@"No changes in index", nil);
  [_indexFilesView replaceWithView:_indexFilesViewController.view];
  
  _diffContentsViewController = [[GIDiffContentsViewController alloc] initWithRepository:self.repository];
  _diffContentsViewController.delegate = self;
  _diffContentsViewController.emptyLabel = NSLocalizedString(@"No file selected", nil);
  [_diffContentsView replaceWithView:_diffContentsViewController.view];
  
  self.messageTextView.string = @"";
}

- (void)viewWillShow {
  [super viewWillShow];
  
  XLOG_DEBUG_CHECK(self.repository.statusMode == kGCLiveRepositoryStatusMode_Disabled);
  self.repository.statusMode = kGCLiveRepositoryStatusMode_Normal;
  
  [self _reloadContents];
  
  _workdirFilesViewController.selectedDelta = _workdirStatus.deltas.firstObject;
  _indexFilesViewController.selectedDelta = _indexStatus.deltas.firstObject;
}

- (void)viewDidHide {
  [super viewDidHide];
  
  _workdirStatus = nil;
  _indexStatus = nil;
  _indexConflicts = nil;
  
  [_workdirFilesViewController setDeltas:nil usingConflicts:nil];
  [_indexFilesViewController setDeltas:nil usingConflicts:nil];
  [_diffContentsViewController setDeltas:nil usingConflicts:nil];
  
  XLOG_DEBUG_CHECK(self.repository.statusMode == kGCLiveRepositoryStatusMode_Normal);
  self.repository.statusMode = kGCLiveRepositoryStatusMode_Disabled;
}

- (void)repositoryStatusDidUpdate {
  [super repositoryStatusDidUpdate];
  
  if (self.viewVisible) {
    [self _reloadContents];
  }
}

- (void)_updateCommitButton {
  _commitButton.enabled = _indexStatus.modified || (self.repository.state == kGCRepositoryState_Merge) || self.amendButton.state;  // Creating an empty commit is OK for a merge or when amending
}

- (void)_reloadContents {
  CGFloat offset;
  GCDiffDelta* topDelta = [_diffContentsViewController topVisibleDelta:&offset];
  NSArray* selectedWorkdirDeltas = _workdirFilesViewController.selectedDeltas;
  NSUInteger selectedWorkdirRow = selectedWorkdirDeltas.count ? [_workdirStatus.deltas indexOfObjectIdenticalTo:selectedWorkdirDeltas.firstObject] : NSNotFound;
  NSArray* selectedIndexDeltas = _indexFilesViewController.selectedDeltas;
  NSUInteger selectedIndexRow = selectedIndexDeltas.count ? [_indexStatus.deltas indexOfObjectIdenticalTo:selectedIndexDeltas.firstObject] : NSNotFound;
  
  _disableFeedback = YES;
  
  _workdirStatus = self.repository.workingDirectoryStatus;
  _indexStatus = self.repository.indexStatus;
  _indexConflicts = self.repository.indexConflicts;
  
  [_workdirFilesViewController setDeltas:_workdirStatus.deltas usingConflicts:_indexConflicts];
  _workdirFilesViewController.selectedDeltas = selectedWorkdirDeltas;
  if (_workdirStatus.deltas.count && selectedWorkdirDeltas.count && !_workdirFilesViewController.selectedDeltas.count && (selectedWorkdirRow != NSNotFound)) {
    _workdirFilesViewController.selectedDelta = _workdirStatus.deltas[MIN(selectedWorkdirRow, _workdirStatus.deltas.count - 1)];  // If we can't preserve the selected deltas, attempt to preserve the first selected row
  }
  
  [_indexFilesViewController setDeltas:_indexStatus.deltas usingConflicts:_indexConflicts];
  _indexFilesViewController.selectedDeltas = selectedIndexDeltas;
  if (_indexStatus.deltas.count && selectedIndexDeltas.count && !_indexFilesViewController.selectedDeltas.count && (selectedIndexRow != NSNotFound)) {
    _indexFilesViewController.selectedDelta = _indexStatus.deltas[MIN(selectedIndexRow, _indexStatus.deltas.count - 1)];  // If we can't preserve the selected deltas, attempt to preserve the first selected row
  }
  
  if (_indexActive) {
    [_diffContentsViewController setDeltas:_indexFilesViewController.selectedDeltas usingConflicts:_indexConflicts];
  } else {
    [_diffContentsViewController setDeltas:_workdirFilesViewController.selectedDeltas usingConflicts:_indexConflicts];
  }
  [_diffContentsViewController setTopVisibleDelta:topDelta offset:offset];
  
  _disableFeedback = NO;
  
  _unstageButton.enabled = _indexStatus.modified;
  _stageButton.enabled = _workdirStatus.modified;
  _discardButton.enabled = _workdirStatus.modified;
  [self _updateCommitButton];
}

// We can't use the default implementation since we need a dynamic first-responder
- (NSView*)preferredFirstResponder {
  if (_indexStatus.deltas.count && !_workdirStatus.deltas.count) {
    return _indexFilesViewController.preferredFirstResponder;
  }
  return _workdirFilesViewController.preferredFirstResponder;
}

- (void)didCreateCommit:(GCCommit*)commit {
  [super didCreateCommit:commit];
  
  _indexActive = NO;
  [self.view.window makeFirstResponder:_workdirFilesViewController.preferredFirstResponder];
}

#pragma mark - GIDiffFilesViewControllerDelegate

- (void)diffFilesViewControllerDidBecomeFirstResponder:(GIDiffFilesViewController*)controller {
  [self diffFilesViewControllerDidChangeSelection:controller];
}

- (void)diffFilesViewControllerDidChangeSelection:(GIDiffFilesViewController*)controller {
  if (!_disableFeedback) {
    if (controller == _workdirFilesViewController) {
      [_diffContentsViewController setDeltas:_workdirFilesViewController.selectedDeltas usingConflicts:_indexConflicts];
      _indexActive = NO;
    } else if (controller == _indexFilesViewController) {
      [_diffContentsViewController setDeltas:_indexFilesViewController.selectedDeltas usingConflicts:_indexConflicts];
      _indexActive = YES;
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }
  }
}

- (void)_stageSelectedFiles:(NSArray*)selectedDeltas {
  NSMutableArray* deltas = [[NSMutableArray alloc] init];
  for (GCDiffDelta* delta in selectedDeltas) {
    if (![_indexConflicts objectForKey:delta.canonicalPath]) {
      if (delta.submodule) {
        [self stageSubmoduleAtPath:delta.canonicalPath];
      } else {
        [self stageAllChangesForFile:delta.canonicalPath];
      }
      [deltas addObject:delta];
    }
  }
  if (deltas.count) {
    _disableFeedback = YES;
    _indexFilesViewController.selectedDeltas = deltas;
    _disableFeedback = NO;
    if (!_workdirFilesViewController.deltas.count) {
      _indexActive = YES;
      [self.view.window makeFirstResponder:_indexFilesViewController.preferredFirstResponder];
    }
  } else {
    NSBeep();
  }
}

- (void)_unstageSelectedFiles:(NSArray*)selectedDeltas {
  NSMutableArray* deltas = [[NSMutableArray alloc] init];
  for (GCDiffDelta* delta in selectedDeltas) {
    if (![_indexConflicts objectForKey:delta.canonicalPath]) {
      if (delta.submodule) {
        [self unstageSubmoduleAtPath:delta.canonicalPath];
      } else {
        [self unstageAllChangesForFile:delta.canonicalPath];
      }
      [deltas addObject:delta];
    }
  }
  if (deltas.count) {
    _disableFeedback = YES;
    _workdirFilesViewController.selectedDeltas = deltas;
    _disableFeedback = NO;
    if (!_indexFilesViewController.deltas.count) {
      _indexActive = NO;
      [self.view.window makeFirstResponder:_workdirFilesViewController.preferredFirstResponder];
    }
  } else {
    NSBeep();
  }
}

- (void)_diffFilesViewControllerDidPressReturn:(GIDiffFilesViewController*)controller {
  if (controller == _workdirFilesViewController) {
    [self _stageSelectedFiles:_workdirFilesViewController.selectedDeltas];
  } else if (controller == _indexFilesViewController) {
    [self _unstageSelectedFiles:_indexFilesViewController.selectedDeltas];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (void)_diffFilesViewControllerDidPressDelete:(GIDiffFilesViewController*)controller {
  if (controller == _workdirFilesViewController) {
    NSArray* deltas = _workdirFilesViewController.selectedDeltas;
    if (deltas.count) {
      [self confirmUserActionWithAlertType:kGIAlertType_Stop
                                     title:NSLocalizedString(@"Are you sure you want to discard all changes from the selected files?", nil)
                                   message:NSLocalizedString(@"This action cannot be undone.", nil)
                                    button:NSLocalizedString(@"Discard", nil)
                 suppressionUserDefaultKey:nil
                                     block:^{
        
        for (GCDiffDelta* delta in deltas) {
          NSError* error;
          BOOL submodule = delta.submodule;
          if ((submodule && ![self discardSubmoduleAtPath:delta.canonicalPath resetIndex:NO error:&error]) || (!submodule && ![self discardAllChangesForFile:delta.canonicalPath resetIndex:NO error:&error])) {
            [self presentError:error];
            break;
          }
        }
        [self.repository notifyWorkingDirectoryChanged];
        if (!_workdirFilesViewController.deltas.count) {
          _indexActive = YES;
          [self.view.window makeFirstResponder:_indexFilesViewController.preferredFirstResponder];
        }
        
      }];
    } else {
      NSBeep();
    }
  } else {
    XLOG_DEBUG_CHECK(controller == _indexFilesViewController);
    NSBeep();
  }
}

- (BOOL)diffFilesViewController:(GIDiffFilesViewController*)controller handleKeyDownEvent:(NSEvent*)event {
  if (!(event.modifierFlags & NSDeviceIndependentModifierFlagsMask)) {
    if (event.keyCode == kGIKeyCode_Return) {
      [self _diffFilesViewControllerDidPressReturn:controller];
      return YES;
    } else if (event.keyCode == kGIKeyCode_Delete) {
      [self _diffFilesViewControllerDidPressDelete:controller];
      return YES;
    }
  }
  
  if (controller == _workdirFilesViewController) {
    return [self handleKeyDownEvent:event forSelectedDeltas:_workdirFilesViewController.selectedDeltas withConflicts:_indexConflicts allowOpen:YES];
  } else if (controller == _indexFilesViewController) {
    return [self handleKeyDownEvent:event forSelectedDeltas:_indexFilesViewController.selectedDeltas withConflicts:_indexConflicts allowOpen:YES];
  }
  
  return NO;
}

- (void)diffFilesViewController:(GIDiffFilesViewController*)controller didDoubleClickDeltas:(NSArray*)deltas {
  if (controller == _workdirFilesViewController) {
    [self _stageSelectedFiles:deltas];
  } else if (controller == _indexFilesViewController) {
    [self _unstageSelectedFiles:deltas];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (BOOL)diffFilesViewControllerShouldAcceptDeltas:(GIDiffFilesViewController*)controller fromOtherController:(GIDiffFilesViewController*)otherController {
  return ((controller == _workdirFilesViewController) && (otherController == _indexFilesViewController)) || ((controller == _indexFilesViewController) && (otherController == _workdirFilesViewController));
}

- (BOOL)diffFilesViewController:(GIDiffFilesViewController*)controller didReceiveDeltas:(NSArray*)deltas fromOtherController:(GIDiffFilesViewController*)otherController {
  if ((controller == _workdirFilesViewController) && (otherController == _indexFilesViewController)) {
    for (GCDiffDelta* delta in deltas) {
      if (![_indexConflicts objectForKey:delta.canonicalPath]) {
        if (delta.submodule) {
          [self unstageSubmoduleAtPath:delta.canonicalPath];
        } else {
          [self unstageAllChangesForFile:delta.canonicalPath];
        }
      }
    }
    _disableFeedback = YES;
    _workdirFilesViewController.selectedDeltas = deltas;
    _disableFeedback = NO;
    if (!_indexFilesViewController.deltas.count) {
      _indexActive = NO;
      [self.view.window makeFirstResponder:_workdirFilesViewController.preferredFirstResponder];
    }
    return YES;
  } else if ((controller == _indexFilesViewController) && (otherController == _workdirFilesViewController)) {
    for (GCDiffDelta* delta in deltas) {
      if (![_indexConflicts objectForKey:delta.canonicalPath]) {
        if (delta.submodule) {
          [self stageSubmoduleAtPath:delta.canonicalPath];
        } else {
          [self stageAllChangesForFile:delta.canonicalPath];
        }
      }
    }
    _disableFeedback = YES;
    _indexFilesViewController.selectedDeltas = deltas;
    _disableFeedback = NO;
    if (!_workdirFilesViewController.deltas.count) {
      _indexActive = YES;
      [self.view.window makeFirstResponder:_indexFilesViewController.preferredFirstResponder];
    }
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
      if (_indexActive) {
        [self unstageSelectedChangesForFile:delta.canonicalPath oldLines:oldLines newLines:newLines];
      } else {
        [self stageSelectedChangesForFile:delta.canonicalPath oldLines:oldLines newLines:newLines];
      }
      [deltas addObject:delta];
    }
  }
  _disableFeedback = YES;
  if (_indexActive) {
    _workdirFilesViewController.selectedDeltas = deltas;
  } else {
    _indexFilesViewController.selectedDeltas = deltas;
  }
  _disableFeedback = NO;
  if ((_indexActive && !_indexFilesViewController.deltas.count) || (!_indexActive && !_workdirFilesViewController.deltas.count)) {
    _indexActive = !_indexActive;
  }
  [self.view.window makeFirstResponder:(_indexActive ? _indexFilesViewController.preferredFirstResponder : _workdirFilesViewController.preferredFirstResponder)];
}

- (void)_diffContentsViewControllerDidPressDelete:(GIDiffContentsViewController*)controller {
  if (!_indexActive) {
    BOOL hasSelection = NO;
    for (GCDiffDelta* delta in _diffContentsViewController.deltas) {
      if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:NULL newLines:NULL]) {
        hasSelection = YES;
        break;
      }
    }
    if (hasSelection) {
      [self confirmUserActionWithAlertType:kGIAlertType_Stop
                                     title:NSLocalizedString(@"Are you sure you want to discard all selected changed lines?", nil)
                                   message:NSLocalizedString(@"This action cannot be undone.", nil)
                                    button:NSLocalizedString(@"Discard", nil)
                 suppressionUserDefaultKey:nil
                                     block:^{
        
        for (GCDiffDelta* delta in _diffContentsViewController.deltas) {
          NSIndexSet* oldLines;
          NSIndexSet* newLines;
          if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:&oldLines newLines:&newLines]) {
            NSError* error;
            if (![self discardSelectedChangesForFile:delta.canonicalPath oldLines:oldLines newLines:newLines resetIndex:NO error:&error]) {
              [self presentError:error];
              break;
            }
          }
        }
        [self.repository notifyWorkingDirectoryChanged];
        if (!_workdirFilesViewController.deltas.count) {
          _indexActive = !_indexActive;
        }
        [self.view.window makeFirstResponder:(_indexActive ? _indexFilesViewController.preferredFirstResponder : _workdirFilesViewController.preferredFirstResponder)];
      
      }];
    } else {
      NSBeep();
    }
  } else {
    NSBeep();
  }
}

- (BOOL)diffContentsViewController:(GIDiffContentsViewController*)controller handleKeyDownEvent:(NSEvent*)event {
  if (!(event.modifierFlags & NSDeviceIndependentModifierFlagsMask)) {
    if (event.keyCode == kGIKeyCode_Return) {
      [self _diffContentsViewControllerDidPressReturn:controller];
      return YES;
    } else if (event.keyCode == kGIKeyCode_Delete) {
      [self _diffContentsViewControllerDidPressDelete:controller];
      return YES;
    }
  }
  return NO;
}

- (NSString*)diffContentsViewController:(GIDiffContentsViewController*)controller actionButtonLabelForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  if (!conflict) {
    if (_indexActive) {
      if (delta.submodule) {
        return NSLocalizedString(@"Unstage Submodule", nil);
      } else if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:NULL newLines:NULL]) {
        return NSLocalizedString(@"Unstage Lines", nil);
      } else {
        return NSLocalizedString(@"Unstage File", nil);
      }
    } else {
      if (delta.submodule) {
        return NSLocalizedString(@"Stage Submodule", nil);
      } else if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:NULL newLines:NULL]) {
        return NSLocalizedString(@"Stage Lines", nil);
      } else {
        return NSLocalizedString(@"Stage File", nil);
      }
    }
  }
  return nil;
}

- (void)diffContentsViewController:(GIDiffContentsViewController*)controller didClickActionButtonForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  NSIndexSet* oldLines;
  NSIndexSet* newLines;
  if (_indexActive) {
    if (delta.submodule) {
      [self unstageSubmoduleAtPath:delta.canonicalPath];
    } else if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:&oldLines newLines:&newLines]) {
      [self unstageSelectedChangesForFile:delta.canonicalPath oldLines:oldLines newLines:newLines];
    } else {
      [self unstageAllChangesForFile:delta.canonicalPath];
    }
    _disableFeedback = YES;
    _workdirFilesViewController.selectedDelta = delta;
    _disableFeedback = NO;
  } else {
    if (delta.submodule) {
      [self stageSubmoduleAtPath:delta.canonicalPath];
    } else if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:&oldLines newLines:&newLines]) {
      [self stageSelectedChangesForFile:delta.canonicalPath oldLines:oldLines newLines:newLines];
    } else {
      [self stageAllChangesForFile:delta.canonicalPath];
    }
    _disableFeedback = YES;
    _indexFilesViewController.selectedDelta = delta;
    _disableFeedback = NO;
  }
}

- (NSMenu*)diffContentsViewController:(GIDiffContentsViewController*)controller willShowContextualMenuForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  NSMenu* menu = [self contextualMenuForDelta:delta withConflict:conflict allowOpen:YES];
  
  if (!_indexActive && !conflict) {
    [menu addItem:[NSMenuItem separatorItem]];
    
    if (GC_FILE_MODE_IS_FILE(delta.oldFile.mode) || GC_FILE_MODE_IS_FILE(delta.newFile.mode)) {
      if (delta.change == kGCFileDiffChange_Untracked) {
        [menu addItemWithTitle:NSLocalizedString(@"Delete File…", nil) block:^{
          [self deleteUntrackedFile:delta.canonicalPath];
        }];
      } else {
        if ([controller getSelectedLinesForDelta:delta oldLines:NULL newLines:NULL]) {
          [menu addItemWithTitle:NSLocalizedString(@"Discard Line Changes…", nil) block:^{
            NSIndexSet* oldLines;
            NSIndexSet* newLines;
            [_diffContentsViewController getSelectedLinesForDelta:delta oldLines:&oldLines newLines:&newLines];
            [self discardSelectedChangesForFile:delta.canonicalPath oldLines:oldLines newLines:newLines resetIndex:NO];
          }];
        } else {
          [menu addItemWithTitle:NSLocalizedString(@"Discard File Changes…", nil) block:^{
            [self discardAllChangesForFile:delta.canonicalPath resetIndex:NO];
          }];
        }
      }
    } else if (delta.submodule) {
      [menu addItemWithTitle:NSLocalizedString(@"Discard Submodule Changes…", nil) block:^{
        [self discardSubmoduleAtPath:delta.canonicalPath resetIndex:NO];
      }];
    }
  }
  
  return menu;
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

// Override
- (IBAction)toggleAmend:(id)sender {
  [super toggleAmend:sender];
  
  [self _updateCommitButton];
}

- (IBAction)discardAll:(id)sender {
  [self discardAllFiles];
}

- (IBAction)stageAll:(id)sender {
  [self stageAllFiles];
  [self.view.window makeFirstResponder:_indexFilesViewController.preferredFirstResponder];
}

- (IBAction)unstageAll:(id)sender {
  [self unstageAllFiles];
  [self.view.window makeFirstResponder:_workdirFilesViewController.preferredFirstResponder];
}

- (IBAction)commit:(id)sender {
  if (_indexConflicts.count) {
    [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"You must resolve conflicts before committing!", nil) message:nil];
    return;
  }
  NSString* message = [self.messageTextView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (!message.length) {
    [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"You must provide a non-empty commit message", nil) message:nil];
    return;
  }
  [self createCommitFromHEADWithMessage:message];
  [self _updateCommitButton];
}

@end
