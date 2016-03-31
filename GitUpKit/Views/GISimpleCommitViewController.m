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

#import "GISimpleCommitViewController.h"
#import "GIDiffContentsViewController.h"
#import "GIDiffFilesViewController.h"
#import "GIViewController+Utilities.h"

#import "GIInterface.h"
#import "GCRepository+Utilities.h"
#import "XLFacilityMacros.h"

@interface GISimpleCommitViewController () <GIDiffContentsViewControllerDelegate, GIDiffFilesViewControllerDelegate>
@property(nonatomic, weak) IBOutlet NSView* contentsView;
@property(nonatomic, weak) IBOutlet NSView* filesView;
@property(nonatomic, weak) IBOutlet NSButton* commitButton;
@end

@implementation GISimpleCommitViewController {
  GIDiffContentsViewController* _diffContentsViewController;
  GIDiffFilesViewController* _diffFilesViewController;
  GCDiff* _unifiedStatus;
  NSDictionary* _indexConflicts;
  BOOL _disableFeedbackLoop;
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
  
  self.messageTextView.string = @"";
}

- (void)viewWillShow {
  [super viewWillShow];
  
  XLOG_DEBUG_CHECK(self.repository.statusMode == kGCLiveRepositoryStatusMode_Disabled);
  self.repository.statusMode = kGCLiveRepositoryStatusMode_Unified;
  
  [self _reloadContents];
}

- (void)viewDidHide {
  [super viewDidHide];
  
  _unifiedStatus = nil;
  _indexConflicts = nil;
  
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
  _indexConflicts = self.repository.indexConflicts;
  [_diffContentsViewController setDeltas:_unifiedStatus.deltas usingConflicts:_indexConflicts];
  [_diffFilesViewController setDeltas:_unifiedStatus.deltas usingConflicts:_indexConflicts];
  
  [_diffContentsViewController setTopVisibleDelta:topDelta offset:offset];
  
  _commitButton.enabled = _unifiedStatus.modified || (self.repository.state == kGCRepositoryState_Merge);  // Creating an empty commit is OK for a merge
}

#pragma mark - GIDiffContentsViewControllerDelegate

- (void)diffContentsViewControllerDidScroll:(GIDiffContentsViewController*)scroll {
  if (!_disableFeedbackLoop) {
    _diffFilesViewController.selectedDelta = [_diffContentsViewController topVisibleDelta:NULL];
  }
}

- (NSString*)diffContentsViewController:(GIDiffContentsViewController*)controller actionButtonLabelForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  if (!conflict) {
    if (delta.submodule) {
      return NSLocalizedString(@"Discard Submodule Changes…", nil);
    } else if ([_diffContentsViewController getSelectedLinesForDelta:delta oldLines:NULL newLines:NULL]) {
      return NSLocalizedString(@"Discard Line Changes…", nil);
    } else {
      return NSLocalizedString(@"Discard File Changes…", nil);
    }
  }
  return nil;
}

- (void)diffContentsViewController:(GIDiffContentsViewController*)controller didClickActionButtonForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  if (delta.submodule) {
    [self discardSubmoduleAtPath:delta.canonicalPath resetIndex:YES];
  } else if (delta.change == kGCFileDiffChange_Untracked) {
    [self discardAllChangesForFile:delta.canonicalPath resetIndex:NO];
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
  return [self contextualMenuForDelta:delta withConflict:conflict allowOpen:YES];
}

#pragma mark - GIDiffFilesViewControllerDelegate

- (void)diffFilesViewController:(GIDiffFilesViewController*)controller willSelectDelta:(GCDiffDelta*)delta {
  _disableFeedbackLoop = YES;
  [_diffContentsViewController setTopVisibleDelta:delta offset:0];
  _disableFeedbackLoop = NO;
}

- (BOOL)diffFilesViewController:(GIDiffFilesViewController*)controller handleKeyDownEvent:(NSEvent*)event {
  return [self handleKeyDownEvent:event forSelectedDeltas:_diffFilesViewController.selectedDeltas withConflicts:_indexConflicts allowOpen:YES];
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
  NSError* error;
  if ([self.repository syncIndexWithWorkingDirectory:&error]) {
    [self createCommitFromHEADWithMessage:message];
  } else {
    [self presentError:error];
  }
}

@end
