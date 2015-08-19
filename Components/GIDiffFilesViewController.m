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

#import "GIDiffFilesViewController.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

#define kPasteboardType @"GIDiffDelta"  // Raw unretained pointer which is OK since pasteboard is use within process only

@interface GIDiffFileData : NSObject
@property(nonatomic, strong) GCDiffDelta* delta;
@property(nonatomic, strong) GCIndexConflict* conflict;
@end

@interface GIFileCellView : NSTableCellView
@end

@interface GIFilesTableView : GITableView
@property(nonatomic, assign) GIDiffFilesViewController* controller;
@end

@interface GIDiffFilesViewController ()
@property(nonatomic, weak) IBOutlet GIFilesTableView* tableView;
@property(nonatomic, weak) IBOutlet NSTextField* emptyTextField;
@end

@implementation GIDiffFileData
@end

@implementation GIFileCellView
@end

// Override all dragging methods to ensure original behavior of NSTableView is gone
@implementation GIFilesTableView {
  NSDragOperation _dragOperation;
}

- (BOOL)becomeFirstResponder {
  if (![super becomeFirstResponder]) {
    return NO;
  }
  if ([_controller.delegate respondsToSelector:@selector(diffFilesViewControllerDidBecomeFirstResponder:)]) {
    [_controller.delegate diffFilesViewControllerDidBecomeFirstResponder:_controller];
  }
  return YES;
}

- (void)keyDown:(NSEvent*)event {
  if (![_controller.delegate respondsToSelector:@selector(diffFilesViewController:handleKeyDownEvent:)] || ![_controller.delegate diffFilesViewController:_controller handleKeyDownEvent:event]) {
    [super keyDown:event];
  }
}

- (void)awakeFromNib {
  [self registerForDraggedTypes:[NSArray arrayWithObject:kPasteboardType]];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  _dragOperation = NSDragOperationNone;
  if ((sender.draggingSource != self) && [_controller.delegate respondsToSelector:@selector(diffFilesViewControllerShouldAcceptDeltas:fromOtherController:)]) {
    GIDiffFilesViewController* sourceController = [(GIFilesTableView*)sender.draggingSource controller];
    if ([_controller.delegate diffFilesViewControllerShouldAcceptDeltas:_controller fromOtherController:sourceController]) {
      _dragOperation = NSDragOperationCopy;
    }
  }
  return _dragOperation;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
  return _dragOperation;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
  ;
}

- (void)draggingEnded:(id<NSDraggingInfo>)sender {
  ;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
  return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  GIDiffFilesViewController* sourceController = [(GIFilesTableView*)sender.draggingSource controller];
  NSData* buffer = [sender.draggingPasteboard dataForType:kPasteboardType];
  const void** pointer = (const void**)buffer.bytes;
  NSMutableArray* array = [[NSMutableArray alloc] init];
  for (size_t i = 0, count = buffer.length / sizeof(void*); i < count; ++i, ++pointer) {
    [array addObject:(__bridge GCDiffDelta*)*pointer];
  }
  return [_controller.delegate diffFilesViewController:_controller didReceiveDeltas:array fromOtherController:sourceController];
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
  ;
}

- (BOOL)wantsPeriodicDraggingUpdates {
  return NO;
}

- (void)updateDraggingItemsForDrag:(id<NSDraggingInfo>)sender {
  ;
}

@end

static NSImage* _conflictImage = nil;
static NSImage* _addedImage = nil;
static NSImage* _modifiedImage = nil;
static NSImage* _deletedImage = nil;
static NSImage* _renamedImage = nil;
static NSImage* _untrackedImage = nil;

@implementation GIDiffFilesViewController {
  NSMutableArray* _data;
}

+ (void)initialize {
  _conflictImage = [[NSBundle bundleForClass:[GIDiffFilesViewController class]] imageForResource:@"icon_file_conflict"];
  _addedImage = [[NSBundle bundleForClass:[GIDiffFilesViewController class]] imageForResource:@"icon_file_a"];
  _modifiedImage = [[NSBundle bundleForClass:[GIDiffFilesViewController class]] imageForResource:@"icon_file_m"];
  _deletedImage = [[NSBundle bundleForClass:[GIDiffFilesViewController class]] imageForResource:@"icon_file_d"];
  _renamedImage = [[NSBundle bundleForClass:[GIDiffFilesViewController class]] imageForResource:@"icon_file_r"];
  _untrackedImage = [[NSBundle bundleForClass:[GIDiffFilesViewController class]] imageForResource:@"icon_file_u"];
}

- (void)loadView {
  [super loadView];
  
  _tableView.controller = self;
  _tableView.target = self;
  _tableView.doubleAction = @selector(doubleClick:);
  
  _emptyTextField.stringValue = @"";
  
  self.allowsMultipleSelection = NO;
}

- (void)setDeltas:(NSArray*)deltas usingConflicts:(NSDictionary*)conflicts {
  if ((deltas != _deltas) || (conflicts != _conflicts)) {
    _deltas = deltas;
    _conflicts = conflicts;
    [self _reloadDeltas];
  }
}

- (void)_reloadDeltas {
  if (_deltas.count) {
    _data = [[NSMutableArray alloc] init];
    for (GCDiffDelta* delta in _deltas) {
      GIDiffFileData* data = [[GIDiffFileData alloc] init];
      data.delta = delta;
      data.conflict = [_conflicts objectForKey:delta.canonicalPath];
      [_data addObject:data];
    }
  } else {
    _data = nil;
  }
  [_tableView reloadData];
  
  _emptyTextField.hidden = _data.count ? YES : NO;
}

- (void)setAllowsMultipleSelection:(BOOL)flag {
  _tableView.allowsEmptySelection = flag;
  _tableView.allowsMultipleSelection = flag;
}

- (BOOL)allowsMultipleSelection {
  return _tableView.allowsMultipleSelection;
}

- (NSString*)emptyLabel {
  return _emptyTextField.stringValue;
}

- (void)setEmptyLabel:(NSString*)label {
  _emptyTextField.stringValue = label;
}

- (GCDiffDelta*)selectedDelta {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    return [(GIDiffFileData*)_data[row] delta];
  }
  return nil;
}

- (void)setSelectedDelta:(GCDiffDelta*)delta {
  NSInteger row = 0;
  for (GIDiffFileData* data in _data) {
    if ((data.delta == delta) || [data.delta.canonicalPath isEqualToString:delta.canonicalPath]) {  // Don't use -isEqualToDelta:
      [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
      [_tableView scrollRowToVisible:row];
      break;
    }
    ++row;
  }
}

- (NSArray*)selectedDeltas {
  NSMutableArray* array = [[NSMutableArray alloc] init];
  [_tableView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
    [array addObject:[(GIDiffFileData*)_data[index] delta]];
  }];
  return array;
}

- (void)setSelectedDeltas:(NSArray*)deltas {
  NSMutableIndexSet* indexes = [[NSMutableIndexSet alloc] init];
  NSUInteger row = 0;
  for (GIDiffFileData* data in _data) {
    for (GCDiffDelta* delta in deltas) {
      if ((data.delta == delta) || [data.delta.canonicalPath isEqualToString:delta.canonicalPath]) {  // Don't use -isEqualToDelta:
        [indexes addIndex:row];
        break;
      }
    }
    ++row;
  }
  [_tableView selectRowIndexes:indexes byExtendingSelection:NO];
  [_tableView scrollRowToVisible:indexes.firstIndex];
}

#pragma mark - Actions

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  
  if (item.action == @selector(copy:)) {
    return (_tableView.selectedRow >= 0);
  }
  
  return NO;
}

- (IBAction)copy:(id)sender {
  NSMutableString* string = [[NSMutableString alloc] init];
  [_tableView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
    GCDiffDelta* delta = [(GIDiffFileData*)_data[index] delta];
    if (string.length) {
      [string appendString:@"\n"];
    }
    [string appendString:delta.canonicalPath];
  }];
  [[NSPasteboard generalPasteboard] declareTypes:@[NSPasteboardTypeString] owner:nil];
  [[NSPasteboard generalPasteboard] setString:string forType:NSPasteboardTypeString];
}

- (IBAction)doubleClick:(id)sender {
  if ([_delegate respondsToSelector:@selector(diffFilesViewController:didDoubleClickDeltas:)]) {
    [_delegate diffFilesViewController:self didDoubleClickDeltas:self.selectedDeltas];
  }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return _data.count;
}

- (BOOL)tableView:(NSTableView*)tableView writeRowsWithIndexes:(NSIndexSet*)rowIndexes toPasteboard:(NSPasteboard*)pboard {
  if (![_delegate respondsToSelector:@selector(diffFilesViewControllerShouldAcceptDeltas:fromOtherController:)]) {
    return NO;
  }
  NSMutableData* buffer = [[NSMutableData alloc] init];
  [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
    GIDiffFileData* data = _data[index];
    const void* pointer = (__bridge const void*)data.delta;
    [buffer appendBytes:&pointer length:sizeof(void*)];
  }];
  [pboard declareTypes:[NSArray arrayWithObject:kPasteboardType] owner:self];
  [pboard setData:buffer forType:kPasteboardType];
  return YES;
}

#pragma mark - NSTableViewDelegate

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  GIDiffFileData* data = _data[row];
  GIFileCellView* view = [_tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
  view.textField.stringValue = data.delta.canonicalPath;
  if (data.conflict) {
    view.imageView.image = _conflictImage;
  } else {
    switch (data.delta.change) {
      
      case kGCFileDiffChange_Added:
        view.imageView.image = _addedImage;
        break;
      
      case kGCFileDiffChange_Deleted:
        view.imageView.image = _deletedImage;
        break;
      
      case kGCFileDiffChange_Modified:
        view.imageView.image = _modifiedImage;
        break;
      
      case kGCFileDiffChange_Renamed:
        view.imageView.image = _renamedImage;
        break;
      
      case kGCFileDiffChange_Untracked:
        if (_showsUntrackedAsAdded) {
          view.imageView.image = _addedImage;
        } else {
          view.imageView.image = _untrackedImage;
        }
        break;
      
      default:
        view.imageView.image = nil;
        XLOG_DEBUG_UNREACHABLE();
        break;
      
    }
  }
  return view;
}

- (BOOL)tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row {
  if ([_delegate respondsToSelector:@selector(diffFilesViewController:willSelectDelta:)]) {
    [_delegate diffFilesViewController:self willSelectDelta:(row >= 0 ? [(GIDiffFileData*)_data[row] delta] : nil)];
  }
  return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  if ([_delegate respondsToSelector:@selector(diffFilesViewControllerDidChangeSelection:)]) {
    [_delegate diffFilesViewControllerDidChangeSelection:self];
  }
}

@end
