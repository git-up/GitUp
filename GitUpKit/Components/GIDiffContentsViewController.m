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

#import "GIDiffContentsViewController.h"

#import "GIInterface.h"
#import "GIViewController+Utilities.h"
#import "GCRepository+Index.h"
#import "XLFacilityMacros.h"

#define kMinSplitDiffViewWidth 1000

#define kContextualMenuOffsetX 0
#define kContextualMenuOffsetY -6

@interface GIDiffContentScrollView : NSScrollView
@end

@interface GIDiffContentData : NSObject
@property(nonatomic, strong) GCDiffDelta* delta;
@property(nonatomic, strong) GCIndexConflict* conflict;
@property(nonatomic, strong) GIDiffView* diffView;
@property(nonatomic, getter=isEmpty) BOOL empty;
@end

@interface GIDiffRowView : NSTableRowView
@end

@interface GIHeaderDiffCellView : NSTableCellView
@property(nonatomic, weak) IBOutlet NSButton* menuButton;
@property(nonatomic, weak) IBOutlet NSButton* actionButton;
@property(nonatomic, strong) NSColor* backgroundColor;
@end

@interface GIEmptyDiffCellView : NSTableCellView
@end

@interface GITextDiffCellView : NSTableCellView
@property(nonatomic, assign) GIDiffView* diffView;
@end

@interface GIBinaryDiffCellView : NSTableCellView
@end

@interface GIConflictDiffCellView : NSTableCellView
@property(nonatomic, weak) IBOutlet NSTextField* statusTextField;
@property(nonatomic, weak) IBOutlet NSButton* openButton;
@property(nonatomic, weak) IBOutlet NSButton* mergeButton;
@property(nonatomic, weak) IBOutlet NSButton* resolveButton;
@end

@interface GISubmoduleDiffCellView : NSTableCellView
@property(nonatomic, weak) IBOutlet NSView* contentView;
@property(nonatomic, weak) IBOutlet NSTextField* oldSHA1TextField;
@property(nonatomic, weak) IBOutlet NSTextField* newSHA1TextField;
@property(nonatomic, weak) IBOutlet NSTextField* customTextField;
- (NSTextField*)newSHA1TextField __attribute__((objc_method_family(none)));  // Work around Clang error for property starting with "new" under ARC
@end

@interface GIContentsTableView : GITableView
@property(nonatomic, assign) GIDiffContentsViewController* controller;
@end

@interface GIDiffContentsViewController () <NSTableViewDataSource, GIDiffViewDelegate>
@property(nonatomic, weak) IBOutlet GIDiffContentScrollView* scrollView;
@property(nonatomic, weak) IBOutlet GIContentsTableView* tableView;
@property(nonatomic, weak) IBOutlet NSTextField* emptyTextField;
@end

NSString* const GIDiffContentsViewControllerUserDefaultKey_DiffViewMode = @"GIDiffContentsViewController_DiffViewMode";

@implementation GIDiffContentScrollView

+ (BOOL)isCompatibleWithResponsiveScrolling {
  return NO;  // Responsive scrolling can reveal blank areas while scrolling rapidly which looks ugly
}

@end

@implementation GIDiffContentData
@end

@implementation GIDiffRowView

- (BOOL)isOpaque {
  return YES;
}

// Override all native drawing
- (void)drawRect:(NSRect)dirtyRect {
  [[NSColor whiteColor] setFill];
  NSRectFill(dirtyRect);
}

@end

@implementation GIHeaderDiffCellView

- (BOOL)isOpaque {
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
  NSRect bounds = self.bounds;
  
  CGContextSaveGState(context);
  [_backgroundColor set];
  
  CGContextFillRect(context, dirtyRect);
  
  CGContextSetBlendMode(context, kCGBlendModeMultiply);
  CGContextMoveToPoint(context, bounds.origin.x, bounds.origin.y + 0.5);
  CGContextAddLineToPoint(context, bounds.origin.x + bounds.size.width, bounds.origin.y + 0.5);
  CGContextStrokePath(context);
  
  CGContextRestoreGState(context);
}

- (void)setActionButtonLabel:(NSString*)label {
  NSTextField* titleField = self.textField;
  NSRect titleFrame = titleField.frame;
  NSRect buttonFrame = _actionButton.frame;
  if (label.length) {
    _actionButton.title = label;
    [_actionButton sizeToFit];
    NSSize size = _actionButton.frame.size;
    buttonFrame = NSMakeRect(buttonFrame.origin.x + buttonFrame.size.width - size.width - 10, buttonFrame.origin.y, size.width + 10, buttonFrame.size.height);
    _actionButton.frame = buttonFrame;
    _actionButton.hidden = NO;
    titleField.frame = NSMakeRect(titleFrame.origin.x, titleFrame.origin.y, buttonFrame.origin.x - titleFrame.origin.x - 10, titleFrame.size.height);
  } else {
    _actionButton.hidden = YES;
    titleField.frame = NSMakeRect(titleFrame.origin.x, titleFrame.origin.y, buttonFrame.origin.x + buttonFrame.size.width - titleFrame.origin.x, titleFrame.size.height);
  }
}

@end

@implementation GIEmptyDiffCellView
@end

@implementation GITextDiffCellView
@end

@implementation GIBinaryDiffCellView
@end

@implementation GIConflictDiffCellView
@end

@implementation GISubmoduleDiffCellView
@end

@implementation GIContentsTableView

- (void)keyDown:(NSEvent*)event {
  if (![_controller.delegate respondsToSelector:@selector(diffContentsViewController:handleKeyDownEvent:)] || ![_controller.delegate diffContentsViewController:_controller handleKeyDownEvent:event]) {
    [super keyDown:event];
  }
}

@end

static NSColor* _conflictBackgroundColor = nil;
static NSColor* _addedBackgroundColor = nil;
static NSColor* _modifiedBackgroundColor = nil;
static NSColor* _deletedBackgroundColor = nil;
static NSColor* _renamedBackgroundColor = nil;
static NSColor* _untrackedBackgroundColor = nil;

static NSImage* _conflictImage = nil;
static NSImage* _addedImage = nil;
static NSImage* _modifiedImage = nil;
static NSImage* _deletedImage = nil;
static NSImage* _renamedImage = nil;
static NSImage* _untrackedImage = nil;

@implementation GIDiffContentsViewController {
  NSMutableArray* _data;
  CGFloat _headerViewHeight;
  CGFloat _emptyViewHeight;
  CGFloat _conflictViewHeight;
  CGFloat _submoduleViewHeight;
  CGFloat _binaryViewHeight;
}

static NSColor* _DimColor(NSColor* color) {
  CGFloat hue;
  CGFloat saturation;
  CGFloat brightness;
  [color getHue:&hue saturation:&saturation brightness:&brightness alpha:NULL];
  return [NSColor colorWithDeviceHue:hue saturation:(saturation - 0.15) brightness:(brightness + 0.1) alpha:1.0];
}

+ (void)initialize {
  _conflictBackgroundColor = _DimColor([NSColor colorWithDeviceRed:(255.0 / 255.0) green:(132.0 / 255.0) blue:(0.0 / 255.0) alpha:1.0]);
  _addedBackgroundColor = _DimColor([NSColor colorWithDeviceRed:(75.0 / 255.0) green:(138.0 / 255.0) blue:(231.0 / 255.0) alpha:1.0]);
  _modifiedBackgroundColor = _DimColor([NSColor colorWithDeviceRed:(119.0 / 255.0) green:(178.0 / 255.0) blue:(85.0 / 255.0) alpha:1.0]);
  _deletedBackgroundColor = _DimColor([NSColor colorWithDeviceRed:(241.0 / 255.0) green:(115.0 / 255.0) blue:(116.0 / 255.0) alpha:1.0]);
  _renamedBackgroundColor = _DimColor([NSColor colorWithDeviceRed:(133.0 / 255.0) green:(96.0 / 255.0) blue:(168.0 / 255.0) alpha:1.0]);
  _untrackedBackgroundColor = [NSColor colorWithDeviceRed:0.75 green:0.75 blue:0.75 alpha:1.0];
  
  _conflictImage = [[NSBundle bundleForClass:[GIDiffContentsViewController class]] imageForResource:@"icon_file_conflict"];
  _addedImage = [[NSBundle bundleForClass:[GIDiffContentsViewController class]] imageForResource:@"icon_file_a"];
  _modifiedImage = [[NSBundle bundleForClass:[GIDiffContentsViewController class]] imageForResource:@"icon_file_m"];
  _deletedImage = [[NSBundle bundleForClass:[GIDiffContentsViewController class]] imageForResource:@"icon_file_d"];
  _renamedImage = [[NSBundle bundleForClass:[GIDiffContentsViewController class]] imageForResource:@"icon_file_r"];
  _untrackedImage = [[NSBundle bundleForClass:[GIDiffContentsViewController class]] imageForResource:@"icon_file_u"];
}

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithRepository:repository])) {
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:GIDiffContentsViewControllerUserDefaultKey_DiffViewMode options:0 context:(__bridge void*)[GIDiffContentsViewController class]];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewBoundsDidChangeNotification object:_tableView.superview];
  
  [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:GIDiffContentsViewControllerUserDefaultKey_DiffViewMode context:(__bridge void*)[GIDiffContentsViewController class]];
}

- (void)_viewBoundsDidChange:(NSNotification*)notification {
  if ([_delegate respondsToSelector:@selector(diffContentsViewControllerDidScroll:)]) {
    [_delegate diffContentsViewControllerDidScroll:self];
  }
}

- (void)loadView {
  [super loadView];
  
  _tableView.controller = self;
  _tableView.backgroundColor = [NSColor colorWithDeviceRed:0.98 green:0.98 blue:0.98 alpha:1.0];
  
  _emptyTextField.stringValue = @"";
  
  _headerViewHeight = [[_tableView makeViewWithIdentifier:@"header" owner:self] frame].size.height;
  _emptyViewHeight = [[_tableView makeViewWithIdentifier:@"empty" owner:self] frame].size.height;
  _conflictViewHeight = [[_tableView makeViewWithIdentifier:@"conflict" owner:self] frame].size.height;
  _submoduleViewHeight = [[_tableView makeViewWithIdentifier:@"submodule" owner:self] frame].size.height;
  _binaryViewHeight = [[_tableView makeViewWithIdentifier:@"binary" owner:self] frame].size.height;
  
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_viewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:_tableView.superview];
}

- (Class)_diffViewClassForChange:(GCFileDiffChange)change {
  NSInteger mode = [[NSUserDefaults standardUserDefaults] integerForKey:GIDiffContentsViewControllerUserDefaultKey_DiffViewMode];
  if (mode == 0) {
    if ((change == kGCFileDiffChange_Untracked) || (change == kGCFileDiffChange_Added) || (change == kGCFileDiffChange_Deleted)) {
      return [GIUnifiedDiffView class];
    }
    return self.view.bounds.size.width < kMinSplitDiffViewWidth ? [GIUnifiedDiffView class] : [GISplitDiffView class];
  }
  return mode > 0 ? [GISplitDiffView class] : [GIUnifiedDiffView class];
}

- (void)_updateDiffViews {
  BOOL reload = NO;
  for (GIDiffContentData* data in _data) {
    if (!data.diffView) {
      continue;
    }
    Class diffViewClass = [self _diffViewClassForChange:data.delta.change];
    if (![data.diffView isKindOfClass:diffViewClass]) {
      GIDiffView* diffView = [[diffViewClass alloc] initWithFrame:NSZeroRect];
      diffView.delegate = self;
      diffView.patch = data.diffView.patch;
      data.diffView.delegate = nil;
      data.diffView.patch = nil;
      data.diffView = diffView;
      reload = YES;
    }
  }
  if (reload) {
    [_tableView reloadData];
  }
}

- (void)viewDidResize {
  if (self.viewVisible && !self.liveResizing) {
    [self _updateDiffViews];
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.0];  // Prevent animations in case the view is actually not on screen yet (e.g. in a hidden tab)
    [_tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self numberOfRowsInTableView:_tableView])]];
    [NSAnimationContext endGrouping];
  }
}

- (void)viewDidFinishLiveResize {
  [self _updateDiffViews];
  [_tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self numberOfRowsInTableView:_tableView])]];
}

// WARNING: This is called *several* times when the default has been changed
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
  if (context == (__bridge void*)[GIDiffContentsViewController class]) {
    if (self.viewVisible) {
      [self _updateDiffViews];  // This is idempotent
    }
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)setDeltas:(NSArray*)deltas usingConflicts:(NSDictionary*)conflicts {
  if ((deltas != _deltas) || (conflicts != _conflicts)) {
    _deltas = deltas;
    _conflicts = conflicts;
    [self _reloadDeltas];
  }
}

- (void)_reloadDeltas {
  BOOL flashScrollers = NO;
  
  if (_deltas.count) {
    CFMutableDictionaryRef cache = NULL;
    if (_data) {
      CFDictionaryKeyCallBacks callbacks = {0, NULL, NULL, NULL, CFEqual, CFHash};
      cache = CFDictionaryCreateMutable(kCFAllocatorDefault, _data.count, &callbacks, NULL);
      for (GIDiffContentData* data in _data) {
        CFDictionarySetValue(cache, (__bridge const void*)data.delta.canonicalPath, (__bridge const void*)data);
      }
    } else {
      flashScrollers = YES;
    }
    
    NSMutableArray* array = [[NSMutableArray alloc] init];
    for (GCDiffDelta* delta in _deltas) {
      GCIndexConflict* conflict = [_conflicts objectForKey:delta.canonicalPath];
      GIDiffContentData* data = nil;
      if (cache) {
        GIDiffContentData* oldData = CFDictionaryGetValue(cache, (__bridge const void*)delta.canonicalPath);
        if (!conflict && !oldData.conflict && [oldData.delta isEqualToDelta:delta]) {  // Ignore cache for conflicts
          data = oldData;
        }
        if (!oldData) {
          flashScrollers = YES;
        }
      }
      if (data == nil) {
        data = [[GIDiffContentData alloc] init];
        data.delta = delta;
        data.conflict = conflict;
        
        if (!conflict && !GC_FILE_MODE_IS_SUBMODULE(delta.oldFile.mode) && !GC_FILE_MODE_IS_SUBMODULE(delta.newFile.mode)) {
          NSError* error;
          BOOL isBinary;
          GCDiffPatch* patch = [self.repository makePatchForDiffDelta:delta isBinary:&isBinary error:&error];
          if (patch) {
            XLOG_DEBUG_CHECK(!isBinary || patch.empty);
            if (patch.empty) {
              data.empty = !isBinary;
            } else {
              GIDiffView* diffView = [[[self _diffViewClassForChange:delta.change] alloc] initWithFrame:NSZeroRect];
              diffView.delegate = self;
              diffView.patch = patch;
              data.diffView = diffView;
            }
          } else {
            [self presentError:error];
          }
        }
      }
      [array addObject:data];
    }
    
    _data = array;
    if (cache) {
      CFRelease(cache);
    }
  } else {
    _data = nil;
  }
  [_tableView reloadData];
  
  _emptyTextField.hidden = _data.count ? YES : NO;
  
  if (flashScrollers && self.viewVisible) {
    [_scrollView flashScrollers];
  }
}

- (NSString*)emptyLabel {
  return _emptyTextField.stringValue;
}

- (void)setEmptyLabel:(NSString*)label {
  _emptyTextField.stringValue = label;
}

- (GCDiffDelta*)topVisibleDelta:(CGFloat*)offset {
  NSClipView* clipView = (NSClipView*)_tableView.superview;
  NSInteger row = [_tableView rowAtPoint:clipView.bounds.origin];
  if (_headerView) {
    row -= 1;
  }
  if (row >= 0) {
    if (offset) {
      NSRect rect = [_tableView rectOfRow:(2 * (row / 2))];
      *offset = clipView.bounds.origin.y - rect.origin.y;
    }
    GIDiffContentData* data = _data[row / 2];
    return data.delta;
  }
  return nil;
}

- (void)setTopVisibleDelta:(GCDiffDelta*)delta offset:(CGFloat)offset {
  NSInteger row = _headerView ? 1 : 0;
  for (GIDiffContentData* data in _data) {
    if ([data.delta.canonicalPath isEqualToString:delta.canonicalPath]) {  // Don't use -isEqualToDelta:
      NSRect rect = [_tableView rectOfRow:row];
      NSClipView* clipView = (NSClipView*)_tableView.superview;
      [clipView setBoundsOrigin:NSMakePoint(0, rect.origin.y + offset)];  // Work around -[NSView scrollPoint:] bug on OS X 10.10 where target is not always reached
      break;
    }
    row += 2;
  }
}

- (BOOL)getSelectedLinesForDelta:(GCDiffDelta*)delta oldLines:(NSIndexSet**)oldLines newLines:(NSIndexSet**)newLines {
  for (GIDiffContentData* data in _data) {
    if ([data.delta.canonicalPath isEqualToString:delta.canonicalPath]) {  // Don't use -isEqualToDelta:
      if (data.diffView.hasSelectedLines) {
        [data.diffView getSelectedText:NULL oldLines:oldLines newLines:newLines];
        return YES;
      }
      return NO;
    }
  }
  return NO;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return (_headerView ? 1 : 0) + 2 * _data.count;
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView*)tableView isGroupRow:(NSInteger)row {
  if (_headerView) {
    if (row == 0) {
      return NO;
    }
    row -= 1;
  }
  return row % 2 == 0;
}

- (NSTableRowView*)tableView:(NSTableView*)tableView rowViewForRow:(NSInteger)row {
  return [[GIDiffRowView alloc] init];
}

- (void)tableView:(NSTableView *)tableView didRemoveRowView:(NSTableRowView*)rowView forRow:(NSInteger)row {
  if (_headerView) {
    row -= 1;
  }
  if (row % 2) {
    GITextDiffCellView* view = [rowView viewAtColumn:0];
    if ([view isKindOfClass:[GITextDiffCellView class]]) {
      [view.diffView removeFromSuperview];
      view.diffView = nil;
    }
  }
}

static inline NSString* _StringFromFileMode(GCFileMode mode) {
  switch (mode) {
    case kGCFileMode_Unreadable: return NSLocalizedString(@"Unreadable", nil);
    case kGCFileMode_Tree: return NSLocalizedString(@"Tree", nil);
    case kGCFileMode_Blob: return NSLocalizedString(@"Blob", nil);
    case kGCFileMode_BlobExecutable: return NSLocalizedString(@"Executable", nil);
    case kGCFileMode_Link: return NSLocalizedString(@"Link", nil);
    case kGCFileMode_Commit: return NSLocalizedString(@"Commit", nil);
  }
  return nil;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  if (_headerView) {
    if (row == 0) {
      return _headerView;
    }
    row -= 1;
  }
  
  GIDiffContentData* data = _data[row / 2];
  GCDiffDelta* delta = data.delta;
  
  if (row % 2) {
    if (data.diffView) {
      GITextDiffCellView* view = [_tableView makeViewWithIdentifier:@"text" owner:self];
      XLOG_DEBUG_CHECK(view.diffView == nil);
      XLOG_DEBUG_CHECK(data.diffView.superview == nil);
      data.diffView.frame = view.bounds;
      data.diffView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
      [view addSubview:data.diffView];
      view.diffView = data.diffView;
      return view;
    } else if (data.empty) {
      GIEmptyDiffCellView* view = [_tableView makeViewWithIdentifier:@"empty" owner:self];
      return view;
    } else if (data.conflict) {
      NSString* status = nil;
      switch (data.conflict.status) {
        case kGCIndexConflictStatus_None: XLOG_DEBUG_UNREACHABLE(); break;
        case kGCIndexConflictStatus_BothModified: status = NSLocalizedString(@"both modified", nil); break;
        case kGCIndexConflictStatus_BothAdded: status = NSLocalizedString(@"both added", nil); break;
        case kGCIndexConflictStatus_DeletedByUs: status = NSLocalizedString(@"deleted by us", nil); break;
        case kGCIndexConflictStatus_DeletedByThem: status = NSLocalizedString(@"deleted by them", nil); break;
      }
      GIConflictDiffCellView* view = [_tableView makeViewWithIdentifier:@"conflict" owner:self];
      view.statusTextField.stringValue = [NSString stringWithFormat:NSLocalizedString(@"This file has conflicts (%@)", nil), status];
      view.openButton.tag = data;
      view.mergeButton.tag = data;
      view.resolveButton.tag = data;
      return view;
    } else if (GC_FILE_MODE_IS_SUBMODULE(delta.oldFile.mode) || GC_FILE_MODE_IS_SUBMODULE(delta.newFile.mode)) {
      GISubmoduleDiffCellView* view = [_tableView makeViewWithIdentifier:@"submodule" owner:self];
      NSString* oldSHA1 = delta.oldFile ? delta.oldFile.SHA1 : nil;
      NSString* newSHA1 = delta.newFile ? delta.newFile.SHA1 : nil;
      if ((oldSHA1 && newSHA1) && [newSHA1 isEqualToString:oldSHA1]) {
        view.customTextField.stringValue = NSLocalizedString(@"Submodule contents have been modified", nil);
        view.customTextField.hidden = NO;
        view.contentView.hidden = YES;
      } else {
        view.oldSHA1TextField.stringValue = oldSHA1 ? oldSHA1 : NSLocalizedString(@"(missing)", nil);
        view.newSHA1TextField.stringValue = newSHA1 ? newSHA1 : NSLocalizedString(@"(missing)", nil);
        view.contentView.hidden = NO;
        view.customTextField.hidden = YES;
      }
      return view;
    } else {
      GIBinaryDiffCellView* view = [_tableView makeViewWithIdentifier:@"binary" owner:self];
      NSImage* image = [[NSWorkspace sharedWorkspace] iconForFileType:data.delta.canonicalPath.pathExtension];  // TODO: Can we use a lower-level API?
      image.size = view.imageView.bounds.size;
      view.imageView.image = image;  // Required or the image is always at 32x32
      return view;
    }
  }
  
  GIHeaderDiffCellView* view = [_tableView makeViewWithIdentifier:@"header" owner:self];
  NSRange oldPathRange = {0, 0};
  NSRange newPathRange = {0, 0};
  NSString* label = data.delta.canonicalPath;
  if (data.conflict) {
    view.backgroundColor = _conflictBackgroundColor;
    view.imageView.image = _conflictImage;
  } else {
    switch (delta.change) {
      
      case kGCFileDiffChange_Added:
        view.backgroundColor = _addedBackgroundColor;
        view.imageView.image = _addedImage;
        break;
      
      case kGCFileDiffChange_Deleted:
        view.backgroundColor = _deletedBackgroundColor;
        view.imageView.image = _deletedImage;
        break;
      
      case kGCFileDiffChange_Modified:
        view.backgroundColor = _modifiedBackgroundColor;
        view.imageView.image = _modifiedImage;
        break;
      
      case kGCFileDiffChange_Renamed: {
        NSString* oldPath = delta.oldFile.path;
        NSString* newPath = delta.newFile.path;
        view.backgroundColor = _renamedBackgroundColor;
        view.imageView.image = _renamedImage;
        label = [NSString stringWithFormat:@"%@ ▶ %@", oldPath, newPath];  // TODO: Handle truncation
        GIComputeModifiedRanges(oldPath, &oldPathRange, newPath, &newPathRange);
        newPathRange.location += oldPath.length + 3;
        break;
      }
      
      case kGCFileDiffChange_Untracked:
        if (_showsUntrackedAsAdded) {
          view.backgroundColor = _addedBackgroundColor;
          view.imageView.image = _addedImage;
        } else {
          view.backgroundColor = _untrackedBackgroundColor;
          view.imageView.image = _untrackedImage;
        }
        break;
      
      default:
        view.imageView.image = nil;
        XLOG_DEBUG_UNREACHABLE();
        break;
      
    }
  }
  if (!data.conflict && delta.oldFile && delta.newFile && (delta.oldFile.mode != delta.newFile.mode)) {
    label = [label stringByAppendingFormat:@" (%@ ▶ %@)", _StringFromFileMode(delta.oldFile.mode), _StringFromFileMode(delta.newFile.mode)];
  }
  if (oldPathRange.length || newPathRange.length) {
    NSDictionary* attributes = @{NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)};
    NSMutableAttributedString* string = [[NSMutableAttributedString alloc] initWithString:label attributes:nil];
    [string beginEditing];
    [string setAttributes:attributes range:oldPathRange];
    [string setAttributes:attributes range:newPathRange];
    [string endEditing];
    view.textField.attributedStringValue = string;
  } else {
    view.textField.stringValue = label;
  }
  BOOL hasActionMenu = [_delegate respondsToSelector:@selector(diffContentsViewController:willShowContextualMenuForDelta:conflict:)];
  view.menuButton.hidden = !hasActionMenu;
  view.menuButton.tag = data;
  BOOL hasActionButton = [_delegate respondsToSelector:@selector(diffContentsViewController:actionButtonLabelForDelta:conflict:)];
  [view setActionButtonLabel:(hasActionButton ? [_delegate diffContentsViewController:self actionButtonLabelForDelta:delta conflict:data.conflict] : nil)];
  view.actionButton.tag = data;
  return view;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
  if (_headerView) {
    if (row == 0) {
      if ([_delegate respondsToSelector:@selector(diffContentsViewController:headerViewHeightForWidth:)]) {
        return [_delegate diffContentsViewController:self headerViewHeightForWidth:[_tableView.tableColumns[0] width]];
      }
      return _headerView.frame.size.height;
    }
    row -= 1;
  }
  if (row % 2) {
    GIDiffContentData* data = _data[row / 2];
    GCDiffDelta* delta = data.delta;
    if (data.diffView) {
      return [data.diffView updateLayoutForWidth:[_tableView.tableColumns[0] width]];
    } else if (data.empty) {
      return _emptyViewHeight;
    } else if (data.conflict) {
      return _conflictViewHeight;
    } else if (GC_FILE_MODE_IS_SUBMODULE(delta.oldFile.mode) || GC_FILE_MODE_IS_SUBMODULE(delta.newFile.mode)) {
      return _submoduleViewHeight;
    } else {
      return _binaryViewHeight;
    }
  }
  return _headerViewHeight;
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView*)tableView {
  return NO;
}

#pragma mark - GIDiffViewDelegate

// TODO: Avoid scanning all data
- (void)diffViewDidChangeSelection:(GIDiffView*)view {
  NSUInteger row = _headerView ? 1 : 0;
  for (GIDiffContentData* data in _data) {
    if (data.diffView == view) {
      GIHeaderDiffCellView* headerView = [_tableView viewAtColumn:0 row:row makeIfNecessary:NO];
      if (headerView) {
        if (!headerView.actionButton.hidden) {
          [headerView setActionButtonLabel:[_delegate diffContentsViewController:self actionButtonLabelForDelta:data.delta conflict:data.conflict]];
        }
      } else {
        XLOG_DEBUG_UNREACHABLE();
      }
      break;
    }
    row += 2;
  }
  if ([_delegate respondsToSelector:@selector(diffContentsViewControllerDidChangeSelection:)]) {
    [_delegate diffContentsViewControllerDidChangeSelection:self];
  }
}

#pragma mark - Actions

- (IBAction)showActionMenu:(id)sender {
  GIDiffContentData* data = (__bridge GIDiffContentData*)(void*)[(NSButton*)sender tag];
  GIHeaderDiffCellView* headerView = (GIHeaderDiffCellView*)[(NSButton*)sender superview];
  XLOG_DEBUG_CHECK([headerView isKindOfClass:[GIHeaderDiffCellView class]]);
  NSMenu* menu = [_delegate diffContentsViewController:self willShowContextualMenuForDelta:data.delta conflict:data.conflict];
  NSPoint point = headerView.menuButton.frame.origin;
  [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(point.x + kContextualMenuOffsetX, point.y + kContextualMenuOffsetY) inView:headerView];
}

- (IBAction)performAction:(id)sender {
  GIDiffContentData* data = (__bridge GIDiffContentData*)(void*)[(NSButton*)sender tag];
  [_delegate diffContentsViewController:self didClickActionButtonForDelta:data.delta conflict:data.conflict];
}

- (IBAction)openWithEditor:(id)sender {
  GIDiffContentData* data = (__bridge GIDiffContentData*)(void*)[(NSButton*)sender tag];
  [self openFileWithDefaultEditor:data.delta.canonicalPath];
}

- (IBAction)resolveWithTool:(id)sender {
  GIDiffContentData* data = (__bridge GIDiffContentData*)(void*)[(NSButton*)sender tag];
  [self resolveConflictInMergeTool:data.conflict];
}

- (IBAction)markAsResolved:(id)sender {
  GIDiffContentData* data = (__bridge GIDiffContentData*)(void*)[(NSButton*)sender tag];
  [self markConflictAsResolved:data.conflict];
}

@end
