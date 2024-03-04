//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
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

static const NSPasteboardType GIPasteboardTypeFileRowIndex = @"co.gitup.mac.file-row-index";
static const NSPasteboardType GIPasteboardTypeFileURL = @"public.file-url";

@interface GIFileCellView : GITableCellView
@end

@interface GIFilesTableView : GITableView
@property(nonatomic, weak) GIDiffFilesViewController* controller;
@end

@interface GIDiffFilesViewController () <NSFilePromiseProviderDelegate>
@property(nonatomic, weak) IBOutlet GIFilesTableView* tableView;
@property(nonatomic, weak) IBOutlet NSTextField* emptyTextField;
@property(nonatomic, readonly) NSArray* items;
@end

/// Allows augmenting a file promise with custom intra-app data.
API_AVAILABLE(macos(10.12))
@interface GIDiffFileProvider : NSFilePromiseProvider
@property(strong) id<NSPasteboardWriting> overridePasteboardWriter;
@end

@implementation GIFileCellView
@end

@implementation GIFilesTableView

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

@end

static NSImage* _conflictImage = nil;
static NSImage* _addedImage = nil;
static NSImage* _modifiedImage = nil;
static NSImage* _deletedImage = nil;
static NSImage* _renamedImage = nil;
static NSImage* _untrackedImage = nil;

@implementation GIDiffFilesViewController

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
  [_tableView registerForDraggedTypes:@[ GIPasteboardTypeFileRowIndex ]];
  [_tableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
  [_tableView setDraggingSourceOperationMask:NSDragOperationGeneric forLocal:NO];

  _emptyTextField.stringValue = @"";

  self.allowsMultipleSelection = NO;
}

- (NSArray*)items {
  return self.deltas;
}

- (void)setDeltas:(NSArray*)deltas usingConflicts:(NSDictionary*)conflicts {
  if ((deltas != _deltas) || (conflicts != _conflicts)) {
    _deltas = [deltas copy];
    _conflicts = [conflicts copy];
    [self _reloadDeltas];
  }
}

- (void)_reloadDeltas {
  [_tableView reloadData];

  _emptyTextField.hidden = self.deltas.count ? YES : NO;
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
  GCDiffDelta* delta = row >= 0 ? self.items[row] : nil;
  return delta;
}

- (void)setSelectedDelta:(GCDiffDelta*)delta {
  self.selectedDeltas = delta ? @[ delta ] : @[];
}

- (NSArray*)selectedDeltas {
  return [self.items objectsAtIndexes:self.tableView.selectedRowIndexes];
}

- (void)setSelectedDeltas:(NSArray*)deltas {
  NSIndexSet* indexes = [self.items indexesOfObjectsPassingTest:^(GCDiffDelta* delta, NSUInteger row, BOOL* stop) {
    for (GCDiffDelta* deltaToSelect in deltas) {
      if ((delta == deltaToSelect) || [delta.canonicalPath isEqualToString:deltaToSelect.canonicalPath]) {  // Don't use -isEqualToDelta:
        return YES;
      }
    }

    return NO;
  }];

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
  NSMutableArray* objects = [NSMutableArray array];
  [_tableView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
    id<NSPasteboardWriting> pasteboardWriter = [self tableView:_tableView pasteboardWriterForRow:index];
    if (!pasteboardWriter) {
      return;
    }
    [objects addObject:pasteboardWriter];
  }];
  [[NSPasteboard generalPasteboard] clearContents];
  [[NSPasteboard generalPasteboard] writeObjects:objects];
}

- (IBAction)doubleClick:(id)sender {
  if ([_delegate respondsToSelector:@selector(diffFilesViewController:didDoubleClickDeltas:)]) {
    [_delegate diffFilesViewController:self didDoubleClickDeltas:self.selectedDeltas];
  }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return self.items.count;
}

- (id<NSPasteboardWriting>)tableView:(NSTableView*)tableView pasteboardWriterForRow:(NSInteger)row {
  GCDiffDelta* delta = self.items[row];

  NSPasteboardItem* pasteboardItem = [[NSPasteboardItem alloc] init];
  [pasteboardItem setPropertyList:@(row) forType:GIPasteboardTypeFileRowIndex];
  [pasteboardItem setString:delta.canonicalPath forType:NSPasteboardTypeString];

  NSString* path = [delta.diff.repository absolutePathForFile:delta.canonicalPath];
  NSURL* url = [NSURL fileURLWithPath:path isDirectory:NO];
  [pasteboardItem setString:url.absoluteString forType:GIPasteboardTypeFileURL];

  if (GC_FILE_MODE_IS_FILE(delta.oldFile.mode) || GC_FILE_MODE_IS_FILE(delta.newFile.mode)) {
    NSString* pathExtension = delta.canonicalPath.pathExtension;
    NSString* utType = (__bridge_transfer NSString*)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)pathExtension, kUTTypeData);

    if (utType) {
      GIDiffFileProvider* provider = [[GIDiffFileProvider alloc] initWithFileType:utType delegate:self];
      provider.userInfo = delta;
      provider.overridePasteboardWriter = pasteboardItem;
      return provider;
    }
  }

  return pasteboardItem;
}

- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
  // Don't allow dropping directly on to rows.
  if (dropOperation != NSTableViewDropAbove) {
    return NSDragOperationNone;
  }

  // The drag must include the private pasteboard type.
  NSPasteboard* pasteboard = info.draggingPasteboard;
  if (![pasteboard canReadItemWithDataConformingToTypes:@[ GIPasteboardTypeFileRowIndex ]]) {
    return NSDragOperationNone;
  }

  // Source must be another compatible files list.
  GIFilesTableView* source = info.draggingSource;
  if (source == tableView || ![self.delegate respondsToSelector:@selector(diffFilesViewControllerShouldAcceptDeltas:fromOtherController:)] || ![self.delegate respondsToSelector:@selector(diffFilesViewController:didReceiveDeltas:fromOtherController:)] || ![self.delegate diffFilesViewControllerShouldAcceptDeltas:self fromOtherController:source.controller]) {
    return NSDragOperationNone;
  }

  // Having passed all those checks, approve the drop.
  [tableView setDropRow:-1 dropOperation:NSTableViewDropAbove];
  return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
  NSArray* pasteboardItems = [info.draggingPasteboard readObjectsForClasses:@[ NSPasteboardItem.self ] options:nil];
  NSMutableIndexSet* indexes = [[NSMutableIndexSet alloc] init];
  for (NSPasteboardItem* pasteboardItem in pasteboardItems) {
    NSNumber* sourceRowNumber = [pasteboardItem propertyListForType:GIPasteboardTypeFileRowIndex];
    if (!sourceRowNumber) continue;
    [indexes addIndex:sourceRowNumber.unsignedIntegerValue];
  }
  GIFilesTableView* source = info.draggingSource;
  NSArray* deltas = [source.controller.items objectsAtIndexes:indexes];
  return [self.delegate diffFilesViewController:self didReceiveDeltas:deltas fromOtherController:source.controller];
}

#pragma mark - NSTableViewDelegate

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  GCDiffDelta* delta = self.items[row];
  GCIndexConflict* conflict = self.conflicts[delta.canonicalPath];
  GIFileCellView* view = [_tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
  view.textField.stringValue = delta.canonicalPath;
  if (conflict) {
    view.imageView.image = _conflictImage;
  } else {
    switch (delta.change) {
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
  GCDiffDelta* delta = row >= 0 ? self.items[row] : nil;
  if ([_delegate respondsToSelector:@selector(diffFilesViewController:willSelectDelta:)]) {
    [_delegate diffFilesViewController:self willSelectDelta:delta];
  }
  return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  if ([_delegate respondsToSelector:@selector(diffFilesViewControllerDidChangeSelection:)]) {
    [_delegate diffFilesViewControllerDidChangeSelection:self];
  }
}

#pragma mark - NSFilePromiseProviderDelegate

- (NSString*)_SHA1ForDelta:(GCDiffDelta*)delta {
  switch (delta.change) {
    case kGCFileDiffChange_Deleted:
    case kGCFileDiffChange_Unmodified:
    case kGCFileDiffChange_Ignored:
    case kGCFileDiffChange_Untracked:
    case kGCFileDiffChange_Unreadable:
      return delta.oldFile.SHA1;
    case kGCFileDiffChange_Added:
    case kGCFileDiffChange_Modified:
    case kGCFileDiffChange_Renamed:
    case kGCFileDiffChange_Copied:
    case kGCFileDiffChange_TypeChanged:
    case kGCFileDiffChange_Conflicted:
      return delta.newFile.SHA1;
  }
}

- (NSString*)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider fileNameForType:(NSString*)fileType API_AVAILABLE(macos(10.12)) {
  GCDiffDelta* delta = filePromiseProvider.userInfo;
  NSString* SHA1 = [[self _SHA1ForDelta:delta] substringToIndex:7];
  NSString* basename = delta.canonicalPath.stringByDeletingPathExtension.lastPathComponent;
  NSString* pathExtension = delta.canonicalPath.pathExtension;
  NSString* filename = [[NSString stringWithFormat:@"%@ (%@)", basename, SHA1] stringByAppendingPathExtension:pathExtension];
  return filename;
}

- (void)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider writePromiseToURL:(NSURL*)url completionHandler:(void (^)(NSError* errorOrNil))completionHandler API_AVAILABLE(macos(10.12)) {
  GCDiffDelta* delta = filePromiseProvider.userInfo;
  NSString* SHA1 = [self _SHA1ForDelta:delta];
  NSError* error;
  BOOL success = [delta.diff.repository exportBlobWithSHA1:SHA1 toPath:url.path error:&error];
  completionHandler(success ? nil : error);
}

@end

@implementation GIDiffFileProvider

- (NSArray<NSPasteboardType>*)writableTypesForPasteboard:(NSPasteboard*)pasteboard {
  return [[self.overridePasteboardWriter writableTypesForPasteboard:pasteboard] arrayByAddingObjectsFromArray:[super writableTypesForPasteboard:pasteboard]];
}

- (NSPasteboardWritingOptions)writingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard*)pasteboard {
  return [self.overridePasteboardWriter writingOptionsForType:type pasteboard:pasteboard] ?: [super writingOptionsForType:type pasteboard:pasteboard];
}

- (id)pasteboardPropertyListForType:(NSPasteboardType)type {
  return [self.overridePasteboardWriter pasteboardPropertyListForType:type] ?: [super pasteboardPropertyListForType:type];
}

@end
