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

#import "GISnapshotListViewController.h"
#import "GIWindowController.h"

#import "GIInterface.h"
#import "GCRepository+Utilities.h"
#import "XLFacilityMacros.h"

@interface GISnapshotListViewController () <NSTableViewDataSource>
@property(nonatomic, weak) IBOutlet GITableView* tableView;
@end

@interface GISnapshotCellView : GITableCellView
@property(nonatomic, weak) IBOutlet NSTextField* dateTextField;
@property(nonatomic, weak) IBOutlet NSTextField* branchTextField;
@property(nonatomic, weak) IBOutlet NSTextField* reasonTextField;
@property(nonatomic, weak) IBOutlet NSButton* restoreButton;
@end

@implementation GISnapshotCellView

- (void)awakeFromNib {
  [super awakeFromNib];
  
  _restoreButton.hidden = YES;
}

@end

@implementation GISnapshotListViewController {
  NSArray* _snapshots;
  NSDateFormatter* _dateFormatter;
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

- (void)viewWillShow {
  [self _reloadSnapshots];
}

- (void)repositorySnapshotsDidUpdate {
  if (self.viewVisible) {
    [self _reloadSnapshots];
  }
}

- (void)_reloadSnapshots {
  _snapshots = self.repository.snapshots;
  [_tableView reloadData];
}

- (void)viewDidHide {
  _snapshots = nil;
  [_tableView reloadData];
}

- (GCSnapshot*)selectedSnapshot {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    return _snapshots[row];
  }
  return nil;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return _snapshots.count;
}

#pragma mark - NSTableViewDelegate

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  GISnapshotCellView* view = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
  view.row = row;
  GCSnapshot* snapshot = _snapshots[row];
  view.dateTextField.stringValue = [_dateFormatter stringFromDate:snapshot.date];
  if (snapshot.empty) {
    view.branchTextField.stringValue = NSLocalizedString(@"Empty Repository", nil);
  } else {
    NSString* name = snapshot.HEADBranchName;
    view.branchTextField.stringValue = name ? [NSString stringWithFormat:NSLocalizedString(@"On '%@'", nil), name] : NSLocalizedString(@"HEAD Detached", nil);
  }
  view.reasonTextField.stringValue = [NSString stringWithFormat:NSLocalizedStringFromTable(snapshot.reason, @"Reasons", nil), snapshot.argument];
  view.restoreButton.hidden = ![_tableView isRowSelected:row];
  return view;
}

// Required to ensure the restore button remains only visible on the selected row even when selection is dynamically changing
- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row {
  GISnapshotCellView* view = [_tableView viewAtColumn:0 row:row makeIfNecessary:NO];
  view.restoreButton.hidden = NO;
  row = _tableView.selectedRow;
  if (row >= 0) {
    view = [_tableView viewAtColumn:0 row:row makeIfNecessary:NO];
    view.restoreButton.hidden = YES;
  }
  return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  if ([_delegate respondsToSelector:@selector(snapshotListViewControllerDidChangeSelection:)]) {
    [_delegate snapshotListViewControllerDidChangeSelection:self];
  }
}

#pragma mark - Actions

- (IBAction)restoreSnapshot:(id)sender {
  NSInteger row = _tableView.selectedRow;
  if (row < 0) {
    return;
  }
  GCSnapshot* snapshot = _snapshots[row];
  BOOL success = NO;
  NSError* error;
  __block BOOL didUpdate = NO;
  if ([self.repository checkClean:0 error:&error]) {
    [self.repository setUndoActionName:NSLocalizedString(@"Restore Snapshot", nil)];
    success = [self.repository performOperationWithReason:@"restore_snapshot"
                                                 argument:snapshot.date
                                       skipCheckoutOnUndo:NO
                                                    error:&error
                                               usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
      
      BOOL didUpdateReferences;
      if (![repository restoreSnapshot:snapshot
                           withOptions:(kGCSnapshotOption_IncludeHEAD | kGCSnapshotOption_IncludeLocalBranches | kGCSnapshotOption_IncludeTags)
                         reflogMessage:kGCReflogMessageFormat_GitUp_RestoreSnapshot
                   didUpdateReferences:&didUpdateReferences
                                 error:outError]) {
        return NO;
      }
      if (didUpdateReferences) {
        if (!repository.HEADUnborn && ![repository forceCheckoutHEAD:YES error:outError]) {
          return NO;
        }
        didUpdate = YES;
      }
      return YES;
      
    }];
  }
  if (success) {
    if (didUpdate) {
      if ([_delegate respondsToSelector:@selector(snapshotListViewController:didRestoreSnapshot:)]) {
        [_delegate snapshotListViewController:self didRestoreSnapshot:snapshot];
      }
    } else {
      [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning message:NSLocalizedString(@"Repository present state is already the same as the snapshot!", nil)];
    }
  } else {
    [self presentError:error];
  }
}

@end
