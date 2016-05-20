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

#import "GIStashListViewController.h"
#import "GIDiffContentsViewController.h"
#import "GIWindowController.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

#define kUserDefaultsPrefix @"GIStashListViewController_"
#define kUserDefaultsKey_SkipApplyWarning kUserDefaultsPrefix "SkipApplyWarning"

@interface GIStashCellView : GITableCellView
@property(nonatomic, weak) IBOutlet NSTextField* dateTextField;
@property(nonatomic, weak) IBOutlet NSTextField* sha1TextField;
@property(nonatomic, weak) IBOutlet NSTextField* messageTextField;
@end

@interface GIStashListViewController () <NSTableViewDataSource>
@property(nonatomic, weak) IBOutlet GITableView* tableView;
@property(nonatomic, weak) IBOutlet NSView* diffView;
@property(nonatomic, weak) IBOutlet NSButton* dropButton;
@property(nonatomic, weak) IBOutlet NSButton* applyButton;
@property(nonatomic, weak) IBOutlet NSTextField* emptyLabel;

@property(nonatomic, strong) IBOutlet NSView* saveView;
@property(nonatomic, weak) IBOutlet NSTextField* messageTextField;
@property(nonatomic, weak) IBOutlet NSButton* untrackedButton;
@property(nonatomic, weak) IBOutlet NSButton* indexButton;
@end

@implementation GIStashCellView
@end

@implementation GIStashListViewController {
  GIDiffContentsViewController* _diffContentsViewController;
  NSArray* _stashes;
  NSDateFormatter* _dateFormatter;
  GIStashCellView* _cachedCellView;
}

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithRepository:repository])) {
    _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.dateStyle = NSDateFormatterShortStyle;
    _dateFormatter.timeStyle = NSDateFormatterShortStyle;
    if ([_dateFormatter.locale.localeIdentifier hasPrefix:@"en_"]) {
      _dateFormatter.doesRelativeDateFormatting = YES;
    }
  }
  return self;
}

- (void)loadView {
  [super loadView];
  
  _tableView.target = self;
  _tableView.doubleAction = @selector(applyStash:);
  
  _diffContentsViewController = [[GIDiffContentsViewController alloc] initWithRepository:self.repository];
  _diffContentsViewController.emptyLabel = NSLocalizedString(@"No differences", nil);
  [_diffView replaceWithView:_diffContentsViewController.view];
  
  _cachedCellView = [_tableView makeViewWithIdentifier:[_tableView.tableColumns[0] identifier] owner:self];
  
  _dropButton.enabled = NO;
}

- (void)viewWillShow {
  XLOG_DEBUG_CHECK(self.repository.stashesEnabled == NO);
  self.repository.stashesEnabled = YES;
  
  [self _reloadStashes];
}

- (void)viewDidHide {
  _stashes = nil;
  [_tableView reloadData];
  
  XLOG_DEBUG_CHECK(self.repository.stashesEnabled == YES);
  self.repository.stashesEnabled = NO;
}

- (void)repositoryStashesDidUpdate {
  if (self.viewVisible) {
    [self _reloadStashes];
  }
}

- (void)_reloadStashes {
  _stashes = self.repository.stashes;
  [_tableView reloadData];
  
  if (_stashes.count == 0) {
    _emptyLabel.hidden = NO;
    [self tableViewSelectionDidChange:nil];  // Work around a bug where -tableViewSelectionDidChange is not called when emptying the table
  } else {
    _emptyLabel.hidden = YES;
  }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return _stashes.count;
}

#pragma mark - NSTableViewDelegate

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  GIStashCellView* view = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
  view.row = row;
  GCStash* stash = _stashes[row];
  view.dateTextField.stringValue = [_dateFormatter stringFromDate:stash.date];
  view.sha1TextField.stringValue = stash.shortSHA1;
  view.messageTextField.stringValue = stash.message;
  return view;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
  GCStash* stash = _stashes[row];
  _cachedCellView.frame = NSMakeRect(0, 0, [_tableView.tableColumns[0] width], 1000);
  NSTextField* textField = _cachedCellView.messageTextField;
  NSRect frame = textField.frame;
  textField.stringValue = stash.message;
  NSSize size = [textField.cell cellSizeForBounds:NSMakeRect(0, 0, frame.size.width, HUGE_VALF)];
  CGFloat delta = ceilf(size.height) - frame.size.height;
  return _cachedCellView.frame.size.height + delta;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    GCStash* stash = _stashes[row];
    NSError* error;
    GCDiff* diff = [self.repository diffCommit:stash
                                    withCommit:stash.baseCommit
                                   filePattern:nil
                                       options:(self.repository.diffBaseOptions | kGCDiffOption_FindRenames)
                             maxInterHunkLines:self.repository.diffMaxInterHunkLines
                               maxContextLines:self.repository.diffMaxContextLines
                                         error:&error];
    if (diff && stash.untrackedCommit) {
      GCDiff* untrackedDiff = [self.repository diffCommit:stash.untrackedCommit withCommit:nil filePattern:nil options:0 maxInterHunkLines:0 maxContextLines:0 error:&error];
      if (!untrackedDiff || ![self.repository mergeDiff:untrackedDiff ontoDiff:diff error:&error]) {
        diff = nil;
      }
    }
    if (!diff) {
      [self presentError:error];
    }
    [_diffContentsViewController setDeltas:diff.deltas usingConflicts:nil];
    _dropButton.enabled = YES;
    _applyButton.enabled = YES;
  } else {
    [_diffContentsViewController setDeltas:nil usingConflicts:nil];
    _dropButton.enabled = NO;
    _applyButton.enabled = NO;
  }
}

#pragma mark - Actions

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  
  if (item.action == @selector(copy:)) {
    return (_tableView.selectedRow >= 0);
  }
  
  return NO;
}

- (IBAction)copy:(id)sender {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    [[NSPasteboard generalPasteboard] declareTypes:@[NSPasteboardTypeString] owner:nil];
    [[NSPasteboard generalPasteboard] setString:[NSString stringWithFormat:@"stash@{%li}", row] forType:NSPasteboardTypeString];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (void)_undoSaveStash:(GCStash*)stash withMessage:(NSString*)message keepIndex:(BOOL)keepIndex includeUntracked:(BOOL)includeUntracked ignore:(BOOL)ignore {
  if (ignore) {
    [[self.undoManager prepareWithInvocationTarget:self] _undoSaveStash:stash withMessage:message keepIndex:keepIndex includeUntracked:includeUntracked ignore:NO];
    return;
  }
  
  BOOL success;
  NSError* error;
  if (stash) {
    success = [self.repository applyStash:stash restoreIndex:!keepIndex error:&error] && [self.repository dropStash:stash error:&error];
    if (success) {
      [[self.undoManager prepareWithInvocationTarget:self] _undoSaveStash:nil withMessage:message keepIndex:keepIndex includeUntracked:includeUntracked ignore:NO];
    }
    [self.repository notifyRepositoryChanged];
  } else {
    stash = [self.repository saveStashWithMessage:message keepIndex:keepIndex includeUntracked:includeUntracked error:&error];
    if (stash) {
      [[self.undoManager prepareWithInvocationTarget:self] _undoSaveStash:stash withMessage:message keepIndex:keepIndex includeUntracked:includeUntracked ignore:NO];
      [self.repository notifyRepositoryChanged];
      success = YES;
    } else {
      success = NO;
    }
  }
  if (!success) {  // In case of error, put a dummy operation on the undo stack since we *must* put something, but pop it at the next runloop iteration
    [[self.undoManager prepareWithInvocationTarget:self] _undoSaveStash:stash withMessage:message keepIndex:keepIndex includeUntracked:includeUntracked ignore:YES];
    [self.undoManager performSelector:(self.undoManager.isRedoing ? @selector(undo) : @selector(redo)) withObject:nil afterDelay:0.0];
    [self presentError:error];
  }
}

- (IBAction)saveStash:(id)sender {
  _messageTextField.stringValue = @"";
  _untrackedButton.state = NO;
  _indexButton.state = NO;
  [self.windowController runModalView:_saveView withInitialFirstResponder:_messageTextField completionHandler:^(BOOL success) {
    
    if (success) {
      NSString* message = [_messageTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      NSError* error;
      GCStash* stash = [self.repository saveStashWithMessage:(message.length ? message : nil) keepIndex:_indexButton.state includeUntracked:_untrackedButton.state error:&error];
      if (stash) {
        [self.undoManager setActionName:NSLocalizedString(@"Save Stash", nil)];
        [[self.undoManager prepareWithInvocationTarget:self] _undoSaveStash:stash withMessage:(message.length ? message : nil) keepIndex:_indexButton.state includeUntracked:_untrackedButton.state ignore:NO];  // TODO: We should really use the built-in undo mechanism from GCLiveRepository
        [self.repository notifyRepositoryChanged];
        
        [self.view.window makeFirstResponder:_tableView];
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [_tableView scrollRowToVisible:0];
      } else {
        [self presentError:error];
      }
    }
    
  }];
}

- (IBAction)applyStash:(id)sender {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    GCStash* stash = _stashes[row];
    [self confirmUserActionWithAlertType:kGIAlertType_Caution
                                   title:NSLocalizedString(@"Are you sure you want to apply this stash?", nil)
                                 message:NSLocalizedString(@"This action cannot be undone.", nil)
                                  button:NSLocalizedString(@"Apply Stash", nil)
               suppressionUserDefaultKey:kUserDefaultsKey_SkipApplyWarning
                                   block:^{
      
      NSError* error;
      if ([self.repository applyStash:stash restoreIndex:NO error:&error]) {
        [self.repository notifyRepositoryChanged];
        [self.windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"Stash was applied successfully!", nil)];
      } else {
        [self presentError:error];
      }
      
    }];
  } else {
    NSBeep();
  }
}

- (void)_undoDropStashWithPreviousState:(GCStashState*)state ignore:(BOOL)ignore {
  if (ignore) {
    [[self.undoManager prepareWithInvocationTarget:self] _undoDropStashWithPreviousState:state ignore:NO];
    return;
  }
  
  NSError* error;
  GCStashState* currentState = [self.repository saveStashState:&error];
  if (currentState && [self.repository restoreStashState:state error:&error]) {
    [[self.undoManager prepareWithInvocationTarget:self] _undoDropStashWithPreviousState:currentState ignore:NO];
    [self.repository notifyRepositoryChanged];
  } else {  // In case of error, put a dummy operation on the undo stack since we *must* put something, but pop it at the next runloop iteration
    [[self.undoManager prepareWithInvocationTarget:self] _undoDropStashWithPreviousState:state ignore:YES];
    [self.undoManager performSelector:(self.undoManager.isRedoing ? @selector(undo) : @selector(redo)) withObject:nil afterDelay:0.0];
    [self presentError:error];
  }
}

- (IBAction)dropStash:(id)sender {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    GCStash* stash = _stashes[row];
    NSError* error;
    GCStashState* currentState = [self.repository saveStashState:&error];
    if (currentState && [self.repository dropStash:stash error:&error]) {
      [self.undoManager setActionName:NSLocalizedString(@"Drop Stash", nil)];
      [[self.undoManager prepareWithInvocationTarget:self] _undoDropStashWithPreviousState:currentState ignore:NO];  // TODO: We should really use the built-in undo mechanism from GCLiveRepository
      [self.repository notifyRepositoryChanged];
      if (row > 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(row - 1)] byExtendingSelection:NO];
      }
    } else {
      [self presentError:error];
    }
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

@end
