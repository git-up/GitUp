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

#import "GICommitListViewController.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

@interface GICommitListViewController () <NSTableViewDataSource>
@property(nonatomic, weak) IBOutlet GITableView* tableView;
@property(nonatomic, weak) IBOutlet NSTextField* emptyTextField;
@end

@interface GICommitCellView : GITableCellView
@property(nonatomic, weak) IBOutlet NSTextField* dateTextField;
@property(nonatomic, weak) IBOutlet NSTextField* sha1TextField;
@property(nonatomic, weak) IBOutlet NSTextField* summaryTextField;
@property(nonatomic, weak) IBOutlet NSTextField* authorTextField;
@end

@implementation GICommitCellView
@end

@interface GIReferenceCellView : GITableCellView
@property(nonatomic, weak) IBOutlet NSTextField* typeTextField;
@property(nonatomic, weak) IBOutlet NSTextField* nameTextField;
@end

@implementation GIReferenceCellView
@end

@implementation GICommitListViewController {
  NSDateFormatter* _dateFormatter;
  GICommitCellView* _cachedCommitCellView;
  CGFloat _referenceCellHeight;
  NSMutableArray* _commits;
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
  
  _emptyTextField.stringValue = @"";
  
  _cachedCommitCellView = [_tableView makeViewWithIdentifier:@"commit" owner:self];
  
  GIReferenceCellView* view = [_tableView makeViewWithIdentifier:@"reference" owner:self];
  _referenceCellHeight = view.frame.size.height;
}

- (void)setResults:(NSArray*)results {
  _results = [results copy];
  if (_results) {
    _commits = [[NSMutableArray alloc] initWithCapacity:_results.count];
    for (id result in _results) {
      if ([result isKindOfClass:[GCCommit class]]) {
        [_commits addObject:result];
      } else if ([result isKindOfClass:[GCHistoryLocalBranch class]]) {
        [_commits addObject:[(GCHistoryLocalBranch*)result tipCommit]];
      } else if ([result isKindOfClass:[GCHistoryRemoteBranch class]]) {
        [_commits addObject:[(GCHistoryRemoteBranch*)result tipCommit]];
      } else if ([result isKindOfClass:[GCHistoryTag class]]) {
        [_commits addObject:[(GCHistoryTag*)result commit]];
      } else {
        XLOG_DEBUG_UNREACHABLE();
      }
    }
  } else {
    _commits = nil;
  }
  
  [self _reloadResults];
  
  if (_commits.count) {
    [_tableView scrollRowToVisible:0];
  }
}

- (void)_reloadResults {
  [_tableView reloadData];
  
  if (_results.count) {
    _tableView.hidden = NO;
    _emptyTextField.hidden = YES;
    [self tableViewSelectionDidChange:nil];  // Work around a bug where -tableViewSelectionDidChange is not called when emptying the table
  } else {
    _tableView.hidden = YES;  // Hide table to prevent it to become first responder
    _emptyTextField.hidden = NO;
  }
}

- (void)_selectIndex:(NSUInteger)index {
  if (index != NSNotFound) {
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [_tableView scrollRowToVisible:index];
  } else {
    [_tableView deselectAll:nil];
  }
}

- (void)setSelectedResult:(id)result {
  if (result) {
    [self _selectIndex:[_results indexOfObjectIdenticalTo:result]];
  } else {
    [_tableView deselectAll:nil];
  }
}

- (id)selectedResult {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    return _results[row];
  }
  return nil;
}

- (void)setSelectedCommit:(GCHistoryCommit*)commit {
  if (commit) {
    [self _selectIndex:[_commits indexOfObjectIdenticalTo:commit]];
  } else {
    [_tableView deselectAll:nil];
  }
}

- (GCHistoryCommit*)selectedCommit {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    return _commits[row];
  }
  return nil;
}

- (NSString*)emptyLabel {
  return _emptyTextField.stringValue;
}

- (void)setEmptyLabel:(NSString*)label {
  _emptyTextField.stringValue = label;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return _results.count;
}

#pragma mark - NSTableViewDelegate

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  id result = _results[row];
  
  if ([result isKindOfClass:[GCCommit class]]) {
    GCCommit* commit = result;
    GICommitCellView* view = [tableView makeViewWithIdentifier:@"commit" owner:self];
    view.row = row;
    view.dateTextField.stringValue = [_dateFormatter stringFromDate:commit.date];
    view.sha1TextField.stringValue = commit.shortSHA1;
    view.summaryTextField.stringValue = commit.summary;
    NSMutableAttributedString* author = [[NSMutableAttributedString alloc] init];
    CGFloat fontSize = view.authorTextField.font.pointSize;
    [author beginEditing];
    [author appendString:commit.authorName withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
    [author appendString:@" " withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:fontSize]}];
    [author appendString:commit.authorEmail withAttributes:nil];
    [author endEditing];
    view.authorTextField.attributedStringValue = author;
    return view;
  }
  
  if ([result isKindOfClass:[GCReference class]]) {
    GCReference* reference = result;
    GIReferenceCellView* view = [tableView makeViewWithIdentifier:@"reference" owner:self];
    view.row = row;
    if ([reference isKindOfClass:[GCHistoryLocalBranch class]]) {
      view.typeTextField.stringValue = NSLocalizedString(@"Local Branch", nil);
    } else if ([reference isKindOfClass:[GCHistoryRemoteBranch class]]) {
      view.typeTextField.stringValue = NSLocalizedString(@"Remote Branch", nil);
    } else if ([reference isKindOfClass:[GCHistoryTag class]]) {
      view.typeTextField.stringValue = [(GCHistoryTag*)reference annotation] ? NSLocalizedString(@"Annotated Tag", nil) : NSLocalizedString(@"Tag", nil);
    } else {
      view.typeTextField.stringValue = @"";
      XLOG_DEBUG_UNREACHABLE();
    }
    view.nameTextField.stringValue = reference.name;
    return view;
  }
  
  XLOG_DEBUG_UNREACHABLE();
  return nil;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
  id result = _results[row];
  
  if ([result isKindOfClass:[GCCommit class]]) {
    GCCommit* commit = result;
    _cachedCommitCellView.frame = NSMakeRect(0, 0, [_tableView.tableColumns[0] width], 1000);
    NSTextField* textField = _cachedCommitCellView.summaryTextField;
    NSRect frame = textField.frame;
    textField.stringValue = commit.summary;
    NSSize size = [textField.cell cellSizeForBounds:NSMakeRect(0, 0, frame.size.width, HUGE_VALF)];
    CGFloat delta = ceilf(size.height) - frame.size.height;
    return _cachedCommitCellView.frame.size.height + delta;
  }
  
  if ([result isKindOfClass:[GCReference class]]) {
    return _referenceCellHeight;
  }
  
  XLOG_DEBUG_UNREACHABLE();
  return _tableView.rowHeight;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  if ([_delegate respondsToSelector:@selector(commitListViewControllerDidChangeSelection:)]) {
    [_delegate commitListViewControllerDidChangeSelection:self];
  }
}

@end
