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

#import <GitUpKit/GitUpKit.h>

#import "Document.h"

#define kToolbarItem_LeftView @"left"
#define kToolbarItem_RightView @"right"

@interface Document () <NSToolbarDelegate, NSTableViewDelegate, GCLiveRepositoryDelegate, GIDiffContentsViewControllerDelegate>
@property(nonatomic, strong) IBOutlet NSArrayController* arrayController;
@property(nonatomic, strong) IBOutlet NSView* leftToolbarView;
@property(nonatomic, strong) IBOutlet NSView* rightToolbarView;
@property(nonatomic, weak) IBOutlet NSTabView* tabView;
@property(nonatomic, weak) IBOutlet NSView* diffView;
@property(nonatomic, strong) IBOutlet NSView* headerView;
@property(nonatomic, weak) IBOutlet NSTextField* messageTextField;
@property(nonatomic) NSUInteger viewIndex;  // Used for bindings in XIB
@end

@implementation Document {
  GCLiveRepository* _repository;
  GIWindowController* _windowController;
  NSToolbar* _toolbar;
  GIDiffContentsViewController* _diffContentsViewController;
  GIAdvancedCommitViewController* _commitViewController;
  GCDiff* _currentDiff;
  CGFloat _messageTextFieldMargins;
  CGFloat _headerViewMinHeight;
}

- (BOOL)readFromURL:(NSURL*)url ofType:(NSString*)typeName error:(NSError**)outError {
  BOOL success = NO;
  _repository = [[GCLiveRepository alloc] initWithExistingLocalRepository:url.path error:outError];
  if (_repository) {
    if (_repository.bare) {
      if (outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Bare repositories are not supported!"}];
      }
    } else {
      _repository.delegate = self;
      success = YES;
    }
  }
  return success;
}

- (void)close {
  [super close];

  _repository.delegate = nil;
  _repository = nil;
}

- (void)makeWindowControllers {
  _windowController = [[GIWindowController alloc] initWithWindowNibName:@"Document" owner:self];
  [self addWindowController:_windowController];
}

- (void)windowControllerDidLoadNib:(NSWindowController*)aController {
  [super windowControllerDidLoadNib:aController];

  _toolbar = [[NSToolbar alloc] initWithIdentifier:@"default"];
  _toolbar.delegate = self;
  _windowController.window.toolbar = _toolbar;

  NSSortDescriptor* descriptor = [[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO selector:@selector(compare:)];
  _arrayController.sortDescriptors = @[ descriptor ];

  _diffContentsViewController = [[GIDiffContentsViewController alloc] initWithRepository:_repository];
  _diffContentsViewController.delegate = self;
  _diffContentsViewController.headerView = _headerView;
  _diffContentsViewController.view.frame = _diffView.frame;
  [_diffView.superview replaceSubview:_diffView with:_diffContentsViewController.view];

  _commitViewController = [[GIAdvancedCommitViewController alloc] initWithRepository:_repository];
  [[_tabView tabViewItemAtIndex:1] setView:_commitViewController.view];

  _headerViewMinHeight = _headerView.frame.size.height - _messageTextField.frame.size.height;
  _messageTextFieldMargins = _headerView.frame.size.width - _messageTextField.frame.size.width;

  [self repositoryDidUpdateHistory:nil];
}

// Override -updateChangeCount: which is trigged by NSUndoManager to do nothing and not mark document as updated
- (void)updateChangeCount:(NSDocumentChangeType)change {
  ;
}

#pragma mark - NSToolbarDelegate

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSString*)identifier willBeInsertedIntoToolbar:(BOOL)flag {
  NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
  if ([identifier isEqualToString:kToolbarItem_LeftView]) {
    item.view = _leftToolbarView;
    item.label = NSLocalizedString(@"View", nil);
  } else if ([identifier isEqualToString:kToolbarItem_RightView]) {
    item.view = _rightToolbarView;
    item.label = NSLocalizedString(@"Search", nil);
  }
  return item;
}

- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
  return @[ kToolbarItem_LeftView, NSToolbarFlexibleSpaceItemIdentifier, kToolbarItem_RightView ];
}

- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
  return [self toolbarDefaultItemIdentifiers:toolbar];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  GCHistoryCommit* commit = _arrayController.selectedObjects.firstObject;
  if (commit) {
    _currentDiff = [_repository diffCommit:commit
                                withCommit:commit.parents.firstObject
                               filePattern:nil
                                   options:(_repository.diffBaseOptions | kGCDiffOption_FindRenames)
                         maxInterHunkLines:_repository.diffMaxInterHunkLines
                           maxContextLines:_repository.diffMaxContextLines
                                     error:NULL];
    [_diffContentsViewController setDeltas:_currentDiff.deltas usingConflicts:nil];
  } else {
    _currentDiff = nil;
    [_diffContentsViewController setDeltas:nil usingConflicts:nil];
  }
}

#pragma mark - GCLiveRepositoryDelegate

- (void)repositoryDidUpdateHistory:(GCLiveRepository*)repository {
  _arrayController.content = _repository.history.allCommits;
}

- (void)repository:(GCLiveRepository*)repository historyUpdateDidFailWithError:(NSError*)error {
  [self presentError:error];
}

#pragma mark - GIDiffContentsViewControllerDelegate

- (CGFloat)diffContentsViewController:(GIDiffContentsViewController*)controller headerViewHeightForWidth:(CGFloat)width {
  NSSize size = [_messageTextField.cell cellSizeForBounds:NSMakeRect(0, 0, width - _messageTextFieldMargins, HUGE_VALF)];
  return _headerViewMinHeight + size.height;
}

@end
