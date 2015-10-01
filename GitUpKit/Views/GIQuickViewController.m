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

#import "GIQuickViewController.h"
#import "GIDiffContentsViewController.h"
#import "GIDiffFilesViewController.h"
#import "GIViewController+Utilities.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

@interface GIQuickViewController () <GIDiffContentsViewControllerDelegate, GIDiffFilesViewControllerDelegate>
@property(nonatomic, weak) IBOutlet NSView* infoView;
@property(nonatomic, weak) IBOutlet NSScrollView* infoScrollView;
@property(nonatomic, weak) IBOutlet NSTextField* sha1TextField;
@property(nonatomic, weak) IBOutlet NSTextField* messageTextField;
@property(nonatomic, weak) IBOutlet NSTextField* authorTextField;
@property(nonatomic, weak) IBOutlet NSTextField* authorDateTextField;
@property(nonatomic, weak) IBOutlet NSTextField* committerTextField;
@property(nonatomic, weak) IBOutlet NSTextField* committerDateTextField;
@property(nonatomic, weak) IBOutlet NSView* contentsView;
@property(nonatomic, weak) IBOutlet NSView* filesView;
@property(nonatomic, weak) IBOutlet NSBox* separatorBox;
@property(nonatomic, weak) IBOutlet GIDualSplitView* mainSplitView;
@property(nonatomic, weak) IBOutlet GIDualSplitView* infoSplitView;
@end

@implementation GIQuickViewController {
  GIDiffContentsViewController* _diffContentsViewController;
  GIDiffFilesViewController* _diffFilesViewController;
  NSDateFormatter* _dateFormatter;
  BOOL _disableFeedbackLoop;
  GCDiff* _diff;
}

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithRepository:repository])) {
    _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.dateStyle = NSDateFormatterShortStyle;
    _dateFormatter.timeStyle = NSDateFormatterShortStyle;
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSSplitViewDidResizeSubviewsNotification object:nil];
}

- (void)_recomputeInfoViewFrame {
  NSRect frame = _infoView.frame;
  NSSize size = [(NSTextFieldCell*)_messageTextField.cell cellSizeForBounds:NSMakeRect(0, 0, _messageTextField.frame.size.width, HUGE_VALF)];
  CGFloat delta = ceil(size.height) - _messageTextField.frame.size.height;
  _infoView.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height + delta);
}

- (void)_splitViewDidResizeSubviews:(NSNotification*)notification {
  if (!self.liveResizing) {
    [self _recomputeInfoViewFrame];
  }
}

- (void)loadView {
  [super loadView];
  
  _diffContentsViewController = [[GIDiffContentsViewController alloc] initWithRepository:self.repository];
  _diffContentsViewController.delegate = self;
  _diffContentsViewController.emptyLabel = NSLocalizedString(@"No differences", nil);
  [_contentsView replaceWithView:_diffContentsViewController.view];
  
  _diffFilesViewController = [[GIDiffFilesViewController alloc] initWithRepository:self.repository];
  _diffFilesViewController.delegate = self;
  [_filesView replaceWithView:_diffFilesViewController.view];
  
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_splitViewDidResizeSubviews:) name:NSSplitViewDidResizeSubviewsNotification object:_mainSplitView];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_splitViewDidResizeSubviews:) name:NSSplitViewDidResizeSubviewsNotification object:_infoSplitView];
}

- (void)viewDidFinishLiveResize {
  [self _recomputeInfoViewFrame];
}

static inline void _AppendStringWithoutTrailingWhiteSpace(NSMutableString* string, NSString* append, NSRange range) {
  NSCharacterSet* set = [NSCharacterSet whitespaceCharacterSet];
  while (range.length) {
    if (![set characterIsMember:[append characterAtIndex:(range.location + range.length - 1)]]) {
      break;
    }
    range.length -= 1;
  }
  [string appendString:[append substringWithRange:range]];
}

static NSString* _CleanUpCommitMessage(NSString* message) {
  NSMutableString* string = [[NSMutableString alloc] init];
  NSRange range = NSMakeRange(0, message.length);
  NSCharacterSet* set = [NSCharacterSet alphanumericCharacterSet];
  while (range.length > 0) {
    NSRange subrange = [message rangeOfString:@"\n" options:0 range:range];
    if (subrange.location == NSNotFound) {
      _AppendStringWithoutTrailingWhiteSpace(string, message, range);
      break;
    }
    NSUInteger count = 0;
    while ((subrange.location + count < range.location + range.length) && ([message characterAtIndex:(subrange.location + count)] == '\n')) {
      ++count;
    }
    
    _AppendStringWithoutTrailingWhiteSpace(string, message, NSMakeRange(range.location, subrange.location - range.location));
    if (count > 1) {
      [string appendString:@"\n\n"];
    } else if (range.location + range.length - subrange.location - count > 0) {
      unichar nextCharacter = [message characterAtIndex:(subrange.location + 1)];
      if ([set characterIsMember:nextCharacter]) {
        [string appendString:@" "];
      } else {
        [string appendString:@"\n"];
      }
    }
    
    range = NSMakeRange(subrange.location + count, range.location + range.length - subrange.location - count);
  }
  return string;
}

- (void)setCommit:(GCHistoryCommit*)commit {
  if (commit != _commit) {
    _commit = commit;
    if (_commit) {
      _messageTextField.stringValue = _CleanUpCommitMessage(_commit.message);
      [self _recomputeInfoViewFrame];
      
      _sha1TextField.stringValue = _commit.SHA1;
      
      _authorDateTextField.stringValue = [NSString stringWithFormat:@"%@ (%@)", [_dateFormatter stringFromDate:_commit.authorDate], GIFormatDateRelativelyFromNow(_commit.authorDate, NO)];
      _committerDateTextField.stringValue = [NSString stringWithFormat:@"%@ (%@)", [_dateFormatter stringFromDate:_commit.committerDate], GIFormatDateRelativelyFromNow(_commit.committerDate, NO)];
      
      CGFloat authorFontSize = _authorTextField.font.pointSize;
      NSMutableAttributedString* author = [[NSMutableAttributedString alloc] init];
      [author beginEditing];
      [author appendString:_commit.authorName withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:authorFontSize]}];
      [author appendString:@" " withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:authorFontSize]}];
      [author appendString:_commit.authorEmail withAttributes:nil];
      [author endEditing];
      _authorTextField.attributedStringValue = author;
      
      CGFloat committerFontSize = _committerTextField.font.pointSize;
      NSMutableAttributedString* committer = [[NSMutableAttributedString alloc] init];
      [committer beginEditing];
      [committer appendString:_commit.committerName withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:committerFontSize]}];
      [committer appendString:@" " withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:committerFontSize]}];
      [committer appendString:_commit.committerEmail withAttributes:nil];
      [committer endEditing];
      _committerTextField.attributedStringValue = committer;
      
      NSError* error;
      _diff = [self.repository diffCommit:_commit
                               withCommit:_commit.parents.firstObject  // Use main line
                              filePattern:nil
                                  options:(self.repository.diffBaseOptions | kGCDiffOption_FindRenames)
                        maxInterHunkLines:self.repository.diffMaxInterHunkLines
                          maxContextLines:self.repository.diffMaxContextLines
                                    error:&error];
      if (!_diff) {
        [self presentError:error];
      }
      [_diffContentsViewController setDeltas:_diff.deltas usingConflicts:nil];
      [_diffFilesViewController setDeltas:_diff.deltas usingConflicts:nil];
    } else {
      _sha1TextField.stringValue = @"";
      _authorTextField.stringValue = @"";
      _authorDateTextField.stringValue = @"";
      _committerTextField.stringValue = @"";
      _committerDateTextField.stringValue = @"";
      _messageTextField.stringValue = @"";
      
      _diff = nil;
      [_diffContentsViewController setDeltas:nil usingConflicts:nil];
      [_diffFilesViewController setDeltas:nil usingConflicts:nil];
    }
  }
}

#pragma mark - GIDiffContentsViewControllerDelegate

- (void)diffContentsViewControllerDidScroll:(GIDiffContentsViewController*)scroll {
  if (!_disableFeedbackLoop) {
    _diffFilesViewController.selectedDelta = [_diffContentsViewController topVisibleDelta:NULL];
  }
}

- (NSMenu*)diffContentsViewController:(GIDiffContentsViewController*)controller willShowContextualMenuForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict {
  XLOG_DEBUG_CHECK(conflict == nil);
  NSMenu* menu = [self contextualMenuForDelta:delta withConflict:nil allowOpen:NO];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  if (GC_FILE_MODE_IS_FILE(delta.newFile.mode)) {
    [menu addItemWithTitle:NSLocalizedString(@"Restore File to This Version…", nil) block:^{
      [self restoreFile:delta.canonicalPath toCommit:_commit];
    }];
  } else {
    [menu addItemWithTitle:NSLocalizedString(@"Restore File to This Version…", nil) block:NULL];
  }
  
  return menu;
}

#pragma mark - GIDiffFilesViewControllerDelegate

- (void)diffFilesViewController:(GIDiffFilesViewController*)controller willSelectDelta:(GCDiffDelta*)delta {
  _disableFeedbackLoop = YES;
  [_diffContentsViewController setTopVisibleDelta:delta offset:0];
  _disableFeedbackLoop = NO;
}

- (BOOL)diffFilesViewController:(GIDiffFilesViewController*)controller handleKeyDownEvent:(NSEvent*)event {
  return [self handleKeyDownEvent:event forSelectedDeltas:_diffFilesViewController.selectedDeltas withConflicts:nil allowOpen:NO];
}

@end
