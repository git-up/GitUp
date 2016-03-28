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

#import "GIUnifiedReflogViewController.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

@interface GIUnifiedReflogViewController () <NSTableViewDataSource>
@property(nonatomic, weak) IBOutlet GITableView* tableView;

@property(nonatomic, strong) IBOutlet NSView* restoreView;
@property(nonatomic, weak) IBOutlet NSTextField* nameTextField;
@end

@interface GIReflogCellView : GITableCellView
@property(nonatomic) NSInteger mode;
@property(nonatomic, weak) IBOutlet NSTextField* dateTextField;
@property(nonatomic, weak) IBOutlet NSTextField* actionTextField;
@property(nonatomic, weak) IBOutlet NSTextField* messageTextField;
@property(nonatomic, weak) IBOutlet NSButton* restoreButton;
@end

@implementation GIReflogCellView
@end

static NSColor* _missingColor = nil;
static NSColor* _unreachableColor = nil;
static NSColor* _reachableColor = nil;

@implementation GIUnifiedReflogViewController {
  NSArray* _entries;
  NSDateFormatter* _dateFormatter;
  GIReflogCellView* _cachedCellView;
}

+ (void)initialize {
  _missingColor = [NSColor colorWithDeviceRed:1.0 green:0.0 blue:0.0 alpha:1.0];
  _unreachableColor = [NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.0 alpha:1.0];
  _reachableColor = [NSColor colorWithDeviceRed:0.7 green:0.7 blue:0.7 alpha:1.0];
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
  
  _cachedCellView = [_tableView makeViewWithIdentifier:[_tableView.tableColumns[0] identifier] owner:self];
}

- (void)viewWillShow {
  [self _reloadUnifiedReflog];
}

- (void)repositoryDidChange {
  if (self.viewVisible) {
    [self _reloadUnifiedReflog];
  }
}

// Since GCReflogEntry objects are all new on reload, attempt to preserve selected one as NSTableView can't do it
- (void)_reloadUnifiedReflog {
  NSError* error;
  NSArray* entries = [self.repository loadAllReflogEntries:&error];
  if (entries) {
    if (![_entries isEqualToArray:entries]) {
      NSInteger row = _tableView.selectedRow;
      GCReflogEntry* selectedEntry = (row >= 0 ? _entries[row] : nil);
      _entries = entries;
      [_tableView reloadData];
      if (selectedEntry) {
        NSUInteger index = [_entries indexOfObject:selectedEntry];
        if (index != NSNotFound) {
          [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        }
      }
    }
    XLOG_VERBOSE(@"Reloaded unified reflog for \"%@\"", self.repository.repositoryPath);
  } else {
    [self presentError:error];
    _entries = nil;
    [_tableView reloadData];
  }
}

- (void)viewDidHide {
  _entries = nil;
  [_tableView reloadData];
}

- (GCReflogEntry*)selectedReflogEntry {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    return _entries[row];
  }
  return nil;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return _entries.count;
}

#pragma mark - NSTableViewDelegate

static NSAttributedString* _AttributedStringFromReflogEntry(GCReflogEntry* entry, CGFloat fontSize) {
  NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
  style.paragraphSpacing = 4.0;
  NSMutableAttributedString* string = [[NSMutableAttributedString alloc] init];
  [string beginEditing];
  for (NSUInteger i = 0, count = entry.messages.count; i < count; ++i) {
    NSString* message = entry.messages[i];
    if ([message hasPrefix:@kGCReflogCustomPrefix]) {
      message = [message substringFromIndex:(sizeof(kGCReflogCustomPrefix) - 1)];
    }
    GCReference* reference = entry.references[i];
    [string appendString:reference.name withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
    [string appendString:@" • " withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:fontSize]}];
    [string appendString:message withAttributes:nil];
    if (i < count - 1) {
      [string appendString:@"\n" withAttributes:nil];
    }
  }
  [string addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, string.length)];
  [string endEditing];
  return string;
}

static NSString* _StringFromActions(GCReflogActions actions) {
  if (actions & kGCReflogAction_GitUp) {
    return NSLocalizedString(@"Made by GitUp", nil);
  }
  if (actions & kGCReflogAction_Checkout) {
    return NSLocalizedString(@"Checkout", nil);
  }
  if (actions & (kGCReflogAction_InitialCommit | kGCReflogAction_Commit)) {
    return NSLocalizedString(@"New Commit", nil);
  }
  if (actions & kGCReflogAction_AmendCommit) {
    return NSLocalizedString(@"Amend Commit", nil);
  }
  if (actions & kGCReflogAction_CherryPick) {
    return NSLocalizedString(@"Cherry-Pick Commit", nil);
  }
  if (actions & kGCReflogAction_Revert) {
    return NSLocalizedString(@"Revert Commit", nil);
  }
  if (actions & kGCReflogAction_CreateBranch) {
    return NSLocalizedString(@"New Branch", nil);
  }
  if (actions & kGCReflogAction_Merge) {
    return NSLocalizedString(@"Merge", nil);
  }
  if (actions & kGCReflogAction_Rebase) {
    return NSLocalizedString(@"Rebase", nil);
  }
  if (actions & kGCReflogAction_Fetch) {
    return NSLocalizedString(@"Fetch", nil);
  }
  if (actions & kGCReflogAction_Push) {
    return NSLocalizedString(@"Push", nil);
  }
  if (actions & kGCReflogAction_Pull) {
    return NSLocalizedString(@"Pull", nil);
  }
  if (actions & kGCReflogAction_Reset) {
    return NSLocalizedString(@"Reset", nil);
  }
  return NSLocalizedString(@"Other Git Operation", nil);  // kGCReflogAction_RenameBranch kGCReflogAction_Clone
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  GIReflogCellView* view = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
  view.row = row;
  GCReflogEntry* entry = _entries[row];
  GCCommit* commit = entry.toCommit;
  NSColor* color;
  if (commit) {
    if ([self.repository.history historyCommitForCommit:entry.toCommit]) {
      view.mode = 1;
      color = _reachableColor;
    } else {
      view.mode = 0;
      color = _unreachableColor;
    }
  } else {
    view.mode = -1;
    color = _missingColor;
  }
  view.dateTextField.stringValue = [_dateFormatter stringFromDate:entry.date];
  view.dateTextField.textColor = color;
  view.actionTextField.stringValue = _StringFromActions(entry.actions);
  view.actionTextField.textColor = color;
  view.messageTextField.attributedStringValue = _AttributedStringFromReflogEntry(entry, view.messageTextField.font.pointSize);
  view.messageTextField.textColor = color;
  view.restoreButton.hidden = ![_tableView isRowSelected:row] || (view.mode > 0);
  view.restoreButton.enabled = (view.mode == 0);
  [view saveTextFieldColors];
  return view;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
  GCReflogEntry* entry = _entries[row];
  _cachedCellView.frame = NSMakeRect(0, 0, [_tableView.tableColumns[0] width], 1000);
  NSTextField* textField = _cachedCellView.messageTextField;
  NSRect frame = textField.frame;
  textField.attributedStringValue = _AttributedStringFromReflogEntry(entry, textField.font.pointSize);
  NSSize size = [textField.cell cellSizeForBounds:NSMakeRect(0, 0, frame.size.width, HUGE_VALF)];
  CGFloat delta = ceilf(size.height) - frame.size.height;
  return _cachedCellView.frame.size.height + delta;
}

// Required to ensure the restore button remains only visible on the selected row even when selection is dynamically changing
- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row {
  GIReflogCellView* view = [_tableView viewAtColumn:0 row:row makeIfNecessary:NO];
  view.restoreButton.hidden = (view.mode > 0);
  view.restoreButton.enabled = (view.mode == 0);
  row = _tableView.selectedRow;
  if (row >= 0) {
    view = [_tableView viewAtColumn:0 row:row makeIfNecessary:NO];
    view.restoreButton.hidden = YES;
  }
  return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  if ([_delegate respondsToSelector:@selector(unifiedReflogViewControllerDidChangeSelection:)]) {
    [_delegate unifiedReflogViewControllerDidChangeSelection:self];
  }
}

#pragma mark - Actions

- (IBAction)restoreEntry:(id)sender {
  NSInteger row = _tableView.selectedRow;
  if (row < 0) {
    NSBeep();
    return;
  }
  GCReflogEntry* entry = _entries[row];
  if (!entry.toCommit) {
    NSBeep();
    return;
  }
  _nameTextField.stringValue = @"";
  NSAlert* alert = [[NSAlert alloc] init];
  alert.type = kGIAlertType_Note;
  alert.messageText = NSLocalizedString(@"Create New Branch for Reflog Entry", nil);
  alert.informativeText = NSLocalizedString(@"This will create and checkout a new local branch at the commit of the selected reflog entry, making it reachable again.", nil);
  alert.accessoryView = _restoreView;
  [alert addButtonWithTitle:NSLocalizedString(@"Create Branch", nil)];
  [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
  [self presentAlert:alert completionHandler:^(NSInteger returnCode) {
    
    if (returnCode == NSAlertFirstButtonReturn) {
      NSString* name = [_nameTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (name.length) {
        BOOL success = NO;
        NSError* error;
        if ([self.repository checkClean:0 error:&error]) {
          [self.repository setUndoActionName:NSLocalizedString(@"Restore Reflog Entry", nil)];
          success = [self.repository performOperationWithReason:@"restore_reflog_entry"
                                                       argument:entry.toCommit.SHA1
                                             skipCheckoutOnUndo:NO
                                                          error:&error
                                                     usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
            
            GCLocalBranch* branch = [repository createLocalBranchFromCommit:entry.toCommit withName:name force:NO error:outError];
            if (branch == nil) {
              return NO;
            }
            if (![repository checkoutLocalBranch:branch options:kGCCheckoutOption_UpdateSubmodulesRecursively error:outError]) {
              [repository deleteLocalBranch:branch error:NULL];  // Ignore errors
              return NO;
            }
            return YES;
            
          }];
        }
        if (success) {
          if ([_delegate respondsToSelector:@selector(unifiedReflogViewController:didRestoreReflogEntry:)]) {
            [_delegate unifiedReflogViewController:self didRestoreReflogEntry:entry];
          }
        } else {
          [self presentError:error];
        }
      } else {
        NSBeep();
      }
    }
    
  }];
}

@end
