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

#import "GIMapViewController+Operations.h"

#import "GIWindowController.h"
#import "GIInterface.h"
#import "GCRepository+Utilities.h"
#import "GCHistory+Rewrite.h"
#import "XLFacilityMacros.h"

#define kPersistentViewStateKeyNamespace @"GIMapViewController_"

#define kPersistentViewStateKey_HideVirtualTips kPersistentViewStateKeyNamespace @"HideVirtualTips"
#define kPersistentViewStateKey_ShowTagTips kPersistentViewStateKeyNamespace @"ShowTagTips"
#define kPersistentViewStateKey_ShowRemoteBranchTips kPersistentViewStateKeyNamespace @"ShowRemoteBranchTips"
#define kPersistentViewStateKey_ShowStaleBranchTips kPersistentViewStateKeyNamespace @"ShowStaleBranchTips"

#define kPersistentViewStateKey_HideTagLabels kPersistentViewStateKeyNamespace @"HideTagLabels"
#define kPersistentViewStateKey_ShowBranchLabels kPersistentViewStateKeyNamespace @"ShowBranchLabels"

@interface GIMapViewController () <GIGraphViewDelegate>
@property(nonatomic, weak) IBOutlet NSScrollView* graphScrollView;
@property(nonatomic, weak) IBOutlet GIGraphView* graphView;

@property(nonatomic, strong) IBOutlet NSMenu* contextualMenu;
@property(nonatomic, weak) IBOutlet NSMenuItem* checkoutMenuItem;
@property(nonatomic, weak) IBOutlet NSMenuItem* separatorMenuItem;

@property(nonatomic, strong) IBOutlet NSView* tagView;
@property(nonatomic, weak) IBOutlet NSTextField* tagNameTextField;
@property(nonatomic, strong) IBOutlet GICommitMessageView* tagMessageTextView;  // Does not support weak references

@property(nonatomic, strong) IBOutlet NSView* renameBranchView;
@property(nonatomic, weak) IBOutlet NSTextField* renameBranchTextField;

@property(nonatomic, strong) IBOutlet NSView* renameTagView;
@property(nonatomic, weak) IBOutlet NSTextField* renameTagTextField;

@property(nonatomic, strong) IBOutlet NSView* createBranchView;
@property(nonatomic, weak) IBOutlet NSTextField* createBranchTextField;
@property(nonatomic, weak) IBOutlet NSButton* createBranchButton;

@property(nonatomic, strong) IBOutlet NSView* messageView;
@property(nonatomic, weak) IBOutlet NSTextField* messageTextField;
@property(nonatomic, strong) IBOutlet GICommitMessageView* messageTextView;  // Does not support weak references
@property(nonatomic, weak) IBOutlet NSButton* messageButton;
@end

static NSColor* _patternColor = nil;

@implementation GIMapViewController {
  BOOL _showsVirtualTips;
  BOOL _hidesTagTips;
  BOOL _hidesRemoteBranchTips;
  BOOL _hidesStaleBranchTips;
  BOOL _updatePending;
}

+ (void)initialize {
  _patternColor = [NSColor colorWithPatternImage:[[NSBundle bundleForClass:[GIMapViewController class]] imageForResource:@"background_pattern"]];
}

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithRepository:repository])) {
    _showsVirtualTips = ![[self.repository userInfoForKey:kPersistentViewStateKey_HideVirtualTips] boolValue];
    _hidesTagTips = ![[self.repository userInfoForKey:kPersistentViewStateKey_ShowTagTips] boolValue];
    _hidesRemoteBranchTips = ![[self.repository userInfoForKey:kPersistentViewStateKey_ShowRemoteBranchTips] boolValue];
    _hidesStaleBranchTips = ![[self.repository userInfoForKey:kPersistentViewStateKey_ShowStaleBranchTips] boolValue];
  }
  return self;
}

- (void)_setGraphViewBackgroundColors:(BOOL)previewMode {
  if (previewMode) {
    _graphView.backgroundColor = _patternColor;
  } else {
    _graphView.backgroundColor = [NSColor whiteColor];
  }
  _graphScrollView.backgroundColor = _graphView.backgroundColor;  // Required for exposed areas through elasticity
}

- (void)loadView {
  [super loadView];
  
  _graphView.delegate = self;
  [self _setGraphViewBackgroundColors:NO];
  _graphView.showsTagLabels = ![[self.repository userInfoForKey:kPersistentViewStateKey_HideTagLabels] boolValue];
  _graphView.showsBranchLabels = [[self.repository userInfoForKey:kPersistentViewStateKey_ShowBranchLabels] boolValue];
  
  _updatePending = YES;
}

- (void)viewWillShow {
  if (_updatePending) {
    [self _reloadMap:NO];
    _updatePending = NO;
  }
}

- (void)repositoryHistoryDidUpdate {
  if (!_previewHistory) {
    if (self.viewVisible) {
      [self _reloadMap:NO];
    } else {
      _updatePending = YES;
    }
  }
}

- (void)_reloadMap:(BOOL)force {
  GINode* focus = nil;
  GCHistoryCommit* selectedCommit = _graphView.selectedCommit;
  if (selectedCommit == nil) {
    focus = _graphView.focusedNode;
  }
  
  GIGraphOptions options = kGIGraphOption_PreserveUpstreamRemoteBranchTips;
  if (_showsVirtualTips) {
    options |= kGIGraphOption_ShowVirtualTips;
  }
  if (_hidesStaleBranchTips && !_forceShowAllTips) {
    options |= kGIGraphOption_SkipStaleBranchTips;
  }
  if (_hidesTagTips && !_forceShowAllTips) {
    options |= kGIGraphOption_SkipStandaloneTagTips;
  }
  if (_hidesRemoteBranchTips && !_forceShowAllTips) {
    options |= kGIGraphOption_SkipStandaloneRemoteBranchTips;
  }
  CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
  if (_previewHistory) {
    if (force || (_graphView.graph.history != _previewHistory)) {
      _graphView.graph = [[GIGraph alloc] initWithHistory:_previewHistory options:options];
      [_delegate mapViewControllerDidReloadGraph:self];
    }
  } else {
    _graphView.graph = [[GIGraph alloc] initWithHistory:self.repository.history options:options];
    [_delegate mapViewControllerDidReloadGraph:self];
  }
  XLOG_VERBOSE(@"Graph regenerated for \"%@\" in %.3f seconds", self.repository.repositoryPath, CFAbsoluteTimeGetCurrent() - time);
  
  if (selectedCommit) {
    if (_previewHistory) {
      _graphView.selectedCommit = [_previewHistory historyCommitForCommit:selectedCommit];
    } else {
      _graphView.selectedCommit = [self.repository.history historyCommitForCommit:selectedCommit];
    }
    [_graphView scrollToSelection];
  } else if (focus) {
    [_graphView scrollToNode:focus];
  } else {
    [_graphView scrollToTip];
  }
}

- (void)setPreviewHistory:(GCHistory*)history {
  _previewHistory = history;
  if (_previewHistory) {
    [self _setGraphViewBackgroundColors:YES];
  } else {
    [self _setGraphViewBackgroundColors:NO];
  }
  [self _reloadMap:NO];
  if (_previewHistory) {
    [_graphView scrollToTip];
  }
}

- (GIGraph*)graph {
  return _graphView.graph;
}

- (GCHistoryCommit*)selectedCommit {
  return _graphView.selectedCommit;
}

- (BOOL)selectCommit:(GCCommit*)commit {
  GINode* node = [self nodeForCommit:commit];
  if (node) {
    _graphView.selectedNode = node;
    [_graphView scrollToSelection];
    return YES;
  }
  _graphView.selectedNode = nil;
  return NO;
}

- (GINode*)nodeForCommit:(GCCommit*)commit {
  GCHistoryCommit* historyCommit = commit ? [self.repository.history historyCommitForCommit:commit] : nil;
  return historyCommit ? [_graphView.graph nodeForCommit:historyCommit] : nil;
}

- (NSPoint)positionInViewForCommit:(GCCommit*)commit {
  GINode* node = [self nodeForCommit:commit];
  XLOG_DEBUG_CHECK(node);
  return node ? [self.view convertPoint:[_graphView positionForNode:node] fromView:_graphView] : NSZeroPoint;
}

- (void)setShowsVirtualTips:(BOOL)flag {
  if (flag != _showsVirtualTips) {
    _showsVirtualTips = flag;
    [self.repository setUserInfo:@((BOOL)!_showsVirtualTips) forKey:kPersistentViewStateKey_HideVirtualTips];
    [self _reloadMap:YES];
  }
}

- (void)setHidesTagTips:(BOOL)flag {
  if (flag != _hidesTagTips) {
    _hidesTagTips = flag;
    [self.repository setUserInfo:@((BOOL)!_hidesTagTips) forKey:kPersistentViewStateKey_ShowTagTips];
    [self _reloadMap:YES];
  }
}

- (void)setHidesRemoteBranchTips:(BOOL)flag {
  if (flag != _hidesRemoteBranchTips) {
    _hidesRemoteBranchTips = flag;
    [self.repository setUserInfo:@((BOOL)!_hidesRemoteBranchTips) forKey:kPersistentViewStateKey_ShowRemoteBranchTips];
    [self _reloadMap:YES];
  }
}

- (void)setHidesStaleBranchTips:(BOOL)flag {
  if (flag != _hidesStaleBranchTips) {
    _hidesStaleBranchTips = flag;
    [self.repository setUserInfo:@((BOOL)!_hidesStaleBranchTips) forKey:kPersistentViewStateKey_ShowStaleBranchTips];
    [self _reloadMap:YES];
  }
}

- (void)setForceShowAllTips:(BOOL)flag {
  if (flag != _forceShowAllTips) {
    _forceShowAllTips = flag;
    if (_hidesTagTips || _hidesRemoteBranchTips || _hidesStaleBranchTips) {
      [self _reloadMap:YES];
    }
  }
}

#pragma mark - NSTextViewDelegate

// Intercept Return key and Option-Return key in NSTextView and forward to next responder
- (BOOL)textView:(NSTextView*)textView doCommandBySelector:(SEL)selector {
  if ((textView == _tagMessageTextView) && (selector == @selector(insertNewline:))) {
    return [self.view.window.firstResponder.nextResponder tryToPerform:@selector(keyDown:) with:[NSApp currentEvent]];
  }
  if ((textView == _messageTextView) && (selector == @selector(insertNewlineIgnoringFieldEditor:))) {
    return [self.view.window.firstResponder.nextResponder tryToPerform:@selector(keyDown:) with:[NSApp currentEvent]];
  }
  return [super textView:textView doCommandBySelector:selector];
}

#pragma mark - GIGraphViewDelegate

- (void)graphViewDidChangeSelection:(GIGraphView*)graphView {
  [_delegate mapViewControllerDidChangeSelection:self];
}

- (void)graphView:(GIGraphView*)graphView didDoubleClickOnNode:(GINode*)node {
  if (_previewHistory) {
    NSBeep();
  } else if ([self validateUserInterfaceItem:_checkoutMenuItem]){
    [self checkoutSelectedCommit:nil];
  }
}

- (NSMenu*)graphView:(GIGraphView*)graphView willShowContextualMenuForNode:(GINode*)node {
  NSMenuItem* item;
  NSMenu* submenu;
  
  NSInteger index = [_contextualMenu indexOfItem:_separatorMenuItem];
  while (_contextualMenu.numberOfItems > (index + 1)) {
    [_contextualMenu removeItemAtIndex:(index + 1)];
  }
  
  if (!_previewHistory) {
    NSArray* remotes = [self.repository listRemotes:NULL];  // TODO: How to handle errors here?
    
    for (GCHistoryLocalBranch* branch in node.commit.localBranches) {
      GCBranch* upstream = branch.upstream;
      NSMenu* menu = [[NSMenu alloc] init];
      
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Rename…", nil) action:@selector(_renameLocalBranch:) keyEquivalent:@""];
      item.representedObject = branch;
      [menu addItem:item];
      
      [menu addItem:[NSMenuItem separatorItem]];
      
      submenu = [[NSMenu alloc] init];
      for (GCHistoryLocalBranch* localBranch in self.repository.history.localBranches) {
        if (localBranch == branch) {
          continue;
        }
        item = [[NSMenuItem alloc] initWithTitle:localBranch.name action:@selector(_mergeLocalBranch:) keyEquivalent:@""];
        item.representedObject = @[branch, localBranch];
        [submenu addItem:item];
      }
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Merge into…", nil) action:NULL keyEquivalent:@""];
      item.submenu = submenu;
      [menu addItem:item];
      
      submenu = [[NSMenu alloc] init];
      for (GCHistoryLocalBranch* localBranch in self.repository.history.localBranches) {
        if (localBranch == branch) {
          continue;
        }
        item = [[NSMenuItem alloc] initWithTitle:localBranch.name action:@selector(_rebaseLocalBranch:) keyEquivalent:@""];
        item.representedObject = @[branch, localBranch];
        [submenu addItem:item];
      }
      for (GCHistoryRemoteBranch* remoteBranch in self.repository.history.remoteBranches) {
        item = [[NSMenuItem alloc] initWithTitle:remoteBranch.name action:@selector(_rebaseLocalBranch:) keyEquivalent:@""];
        item.representedObject = @[branch, remoteBranch];
        [submenu addItem:item];
      }
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Rebase onto", nil) action:NULL keyEquivalent:@""];
      item.submenu = submenu;
      [menu addItem:item];
      
      [menu addItem:[NSMenuItem separatorItem]];

      BOOL needsSeparator = YES;
      submenu = [[NSMenu alloc] init];
      if (self.repository.history.remoteBranches.count) {
        for (GCHistoryRemoteBranch* remoteBranch in self.repository.history.remoteBranches) {
          item = [[NSMenuItem alloc] initWithTitle:remoteBranch.name action:@selector(_configureUpstreamForLocalBranch:) keyEquivalent:@""];
          item.representedObject = @[branch, remoteBranch];
          if ([upstream isEqualToBranch:remoteBranch]) {
            item.state = NSOnState;
          }
          [submenu addItem:item];
        }
      }
      if (self.repository.history.localBranches.count) {
        for (GCHistoryLocalBranch* localBranch in self.repository.history.localBranches) {
          if (![localBranch isEqualToBranch:branch]) {
            if (needsSeparator) {
              [submenu addItem:[NSMenuItem separatorItem]];
              needsSeparator = NO;
            }
            item = [[NSMenuItem alloc] initWithTitle:localBranch.name action:@selector(_configureUpstreamForLocalBranch:) keyEquivalent:@""];
            item.representedObject = @[branch, localBranch];
            if ([upstream isEqualToBranch:localBranch]) {
              item.state = NSOnState;
            }
            [submenu addItem:item];
          }
        }
      }
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Set Upstream to", nil) action:NULL keyEquivalent:@""];
      item.submenu = submenu;
      [menu addItem:item];
      
      if (upstream) {
        item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Unset Upstream", nil) action:@selector(_configureUpstreamForLocalBranch:) keyEquivalent:@""];
        item.representedObject = branch;
        [menu addItem:item];
      }
      
      [menu addItem:[NSMenuItem separatorItem]];
      
      if (upstream) {
        item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Pull from Upstream", nil) action:@selector(_pullLocalBranchFromUpstream:) keyEquivalent:@""];
        item.representedObject = branch;
        [menu addItem:item];
        
        item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Push to Upstream", nil) action:@selector(_pushLocalBranchToUpstream:) keyEquivalent:@""];
        item.representedObject = branch;
        [menu addItem:item];
      }
      
      submenu = [[NSMenu alloc] init];
      for (GCRemote* remote in remotes) {
        item = [[NSMenuItem alloc] initWithTitle:remote.name action:@selector(_pushLocalBranchToRemote:) keyEquivalent:@""];
        item.representedObject = @[branch, remote];
        [submenu addItem:item];
      }
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Push to Remote", nil) action:NULL keyEquivalent:@""];
      item.submenu = submenu;
      [menu addItem:item];
      
      [menu addItem:[NSMenuItem separatorItem]];
      
      if (![self.repository.history.HEADBranch isEqualToBranch:branch]) {
        item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Delete", nil) action:@selector(_deleteLocalBranch:) keyEquivalent:@""];
        item.representedObject = branch;
      } else {
        item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Delete", nil) action:NULL keyEquivalent:@""];
      }
      [menu addItem:item];
      
      item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Edit Local Branch \"%@\"", nil), branch.name] action:NULL keyEquivalent:@""];
      item.submenu = menu;
      [_contextualMenu addItem:item];
    }
    
    for (GCHistoryRemoteBranch* branch in node.commit.remoteBranches) {
      NSMenu* menu = [[NSMenu alloc] init];
      
      BOOL found = NO;
      for (GCHistoryLocalBranch* localBranch in self.repository.history.localBranches) {
        if ([localBranch.name isEqualToString:branch.branchName]) {
          found = YES;
          break;
        }
      }
      if (!found) {
        item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Checkout New Tracking Local Branch", nil) action:@selector(_checkoutRemoteBranch:) keyEquivalent:@""];
        item.representedObject = branch;
        [menu addItem:item];
        
        [menu addItem:[NSMenuItem separatorItem]];
      }
      
      submenu = [[NSMenu alloc] init];
      for (GCHistoryLocalBranch* localBranch in self.repository.history.localBranches) {
        item = [[NSMenuItem alloc] initWithTitle:localBranch.name action:@selector(_mergeRemoteBranch:) keyEquivalent:@""];
        item.representedObject = @[branch, localBranch];
        [submenu addItem:item];
      }
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Merge into…", nil) action:NULL keyEquivalent:@""];
      item.submenu = submenu;
      [menu addItem:item];
      
      [menu addItem:[NSMenuItem separatorItem]];
      
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Fetch", nil) action:@selector(_fetchRemoteBranch:) keyEquivalent:@""];
      item.representedObject = branch;
      [menu addItem:item];
      
      [menu addItem:[NSMenuItem separatorItem]];
      
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Delete…", nil) action:@selector(_deleteRemoteBranch:) keyEquivalent:@""];
      item.representedObject = branch;
      [menu addItem:item];
      
      GCHostingService service;
      NSURL* url = [self.repository hostingURLForRemoteBranch:branch service:&service error:NULL];  // Ignore errors
      if (url) {
        [menu addItem:[NSMenuItem separatorItem]];
        
        item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"View on %@…", nil), GCNameFromHostingService(service)] action:@selector(_viewBranchOnHostingService:) keyEquivalent:@""];
        item.representedObject = url;
        [menu addItem:item];
        
        submenu = [[NSMenu alloc] init];
        for (GCHistoryRemoteBranch* remoteBranch in self.repository.history.remoteBranches) {
          if (![remoteBranch isEqualToBranch:branch]) {
            url = [self.repository hostingURLForPullRequestFromRemoteBranch:branch toBranch:remoteBranch service:NULL error:NULL];  // Ignore errors
            if (url) {
              item = [[NSMenuItem alloc] initWithTitle:remoteBranch.name action:@selector(_createPullRequestOnHostingService:) keyEquivalent:@""];
              item.representedObject = url;
              [submenu addItem:item];
            }
          }
        }
        switch (service) {
          
          case kGCHostingService_Unknown:
            XLOG_DEBUG_UNREACHABLE();
            break;
          
          case kGCHostingService_GitLab:
            item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Create Merge Request Into…", nil) action:NULL keyEquivalent:@""];
            break;
          
          case kGCHostingService_GitHub:
          case kGCHostingService_BitBucket:
            item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Create Pull Request Against…", nil) action:NULL keyEquivalent:@""];
            break;
          
        }
        item.submenu = submenu;
        [menu addItem:item];
      }
      
      item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Edit Remote Branch \"%@\"", nil), branch.name] action:NULL keyEquivalent:@""];
      item.submenu = menu;
      [_contextualMenu addItem:item];
    }
    
    for (GCHistoryTag* tag in node.commit.tags) {
      NSMenu* menu = [[NSMenu alloc] init];
      
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Rename…", nil) action:@selector(_renameTag:) keyEquivalent:@""];
      item.representedObject = tag;
      [menu addItem:item];
      
      [menu addItem:[NSMenuItem separatorItem]];
      
      submenu = [[NSMenu alloc] init];
      for (GCRemote* remote in remotes) {
        item = [[NSMenuItem alloc] initWithTitle:remote.name action:@selector(_pushTagToRemote:) keyEquivalent:@""];
        item.representedObject = @[tag, remote];
        [submenu addItem:item];
      }
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Push to Remote", nil) action:NULL keyEquivalent:@""];
      item.submenu = submenu;
      [menu addItem:item];
      
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Delete from All Remotes…", nil) action:@selector(_deleteTagFromAllRemotes:) keyEquivalent:@""];
      item.representedObject = tag;
      [menu addItem:item];
      
      [menu addItem:[NSMenuItem separatorItem]];
      
      item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Delete from Repository", nil) action:@selector(_deleteTag:) keyEquivalent:@""];
      item.representedObject = tag;
      [menu addItem:item];
      
      item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Edit Tag \"%@\"", nil), tag.name] action:NULL keyEquivalent:@""];
      item.submenu = menu;
      [_contextualMenu addItem:item];
    }
    
  }
  
  if (_contextualMenu.numberOfItems > (index + 1)) {
    _separatorMenuItem.hidden = NO;
  } else {
    _separatorMenuItem.hidden = YES;
  }
  
  return _contextualMenu;
}

#pragma mark - Interface

- (void)keyDown:(NSEvent*)event {
  BOOL handled = NO;
  if (_graphView.selectedNode && ![event isARepeat]) {
    NSString* characters = event.charactersIgnoringModifiers;
    if ([characters isEqualToString:@"."]) {
      [_graphView showContextualMenuForSelectedNode];
      handled = YES;
    } else {
      if ((characters.length == 1) && ([characters characterAtIndex:0] == 0x7F)) {  // Delete
        unichar character = 0x08;
        characters = [NSString stringWithCharacters:&character length:1];  // Backspace
      }
      NSUInteger modifiers = event.modifierFlags & (NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask);
      for (NSMenuItem* item in _contextualMenu.itemArray) {
        if ([item.keyEquivalent isEqualToString:characters] && (item.keyEquivalentModifierMask == modifiers) && [self validateUserInterfaceItem:item]) {
          if ([NSApp sendAction:item.action to:self from:item]) {
            handled = YES;
            break;
          } else {
            XLOG_DEBUG_UNREACHABLE();
          }
        }
      }
    }
  }
  if (!handled) {
    [self.nextResponder tryToPerform:@selector(keyDown:) with:event];
  }
}

- (id)_smartCheckoutTarget:(GCHistoryCommit*)commit {
  NSArray* branches = commit.localBranches;
  if (branches.count > 1) {
    GCHistoryLocalBranch* headBranch = self.repository.history.HEADBranch;
    NSUInteger index = [branches indexOfObject:headBranch];
    if (index != NSNotFound) {
      return [branches objectAtIndex:((index + 1) % branches.count)];
    }
  }
  GCHistoryLocalBranch* branch = branches.firstObject;
  return branch ? branch : commit;
}

- (void)_promptForCommitMessage:(NSString*)message withTitle:(NSString*)title button:(NSString*)button block:(void (^)(NSString* message))block {
  _messageTextField.stringValue = title;
  _messageTextView.string = message;
  [_messageTextView selectAll:nil];
  _messageButton.title = button;
  [self.windowController runModalView:_messageView withInitialFirstResponder:_messageTextView completionHandler:^(BOOL success) {
    
    if (success) {
      NSString* editedMessage = [_messageTextView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (editedMessage.length) {
        block(editedMessage);
      } else {
        NSBeep();
      }
    }
    _messageTextView.string = @"";
    [_messageTextView.undoManager removeAllActions];
    
  }];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  BOOL editingDisabled = _previewHistory || self.repository.hasBackgroundOperationInProgress;
  
  if ((item.action == @selector(fetchAllRemoteBranches:)) || (item.action == @selector(fetchAllRemoteTags:)) || (item.action == @selector(fetchAndPruneAllRemoteTags:))
      || (item.action == @selector(pushAllLocalBranches:)) || (item.action == @selector(pushAllTags:))) {
    return !_previewHistory && !self.repository.hasBackgroundOperationInProgress;
  }
  
  if (item.action == @selector(toggleVirtualTips:)) {
    [(NSMenuItem*)item setState:(_showsVirtualTips ? NSOnState : NSOffState)];
    return YES;
  }
  if (item.action == @selector(toggleTagTips:)) {
    [(NSMenuItem*)item setState:(_hidesTagTips && !_forceShowAllTips ? NSOffState : NSOnState)];
    return !_forceShowAllTips;
  }
  if (item.action == @selector(toggleRemoteBranchTips:)) {
    [(NSMenuItem*)item setState:(_hidesRemoteBranchTips && !_forceShowAllTips ? NSOffState : NSOnState)];
    return !_forceShowAllTips;
  }
  if (item.action == @selector(toggleStaleBranchTips:)) {
    [(NSMenuItem*)item setState:(_hidesStaleBranchTips && !_forceShowAllTips ? NSOffState : NSOnState)];
    return !_forceShowAllTips;
  }
  
  if (item.action == @selector(toggleTagLabels:)) {
    [(NSMenuItem*)item setState:(_graphView.showsTagLabels ? NSOnState : NSOffState)];
    return YES;
  }
  if (item.action == @selector(toggleBranchLabels:)) {
    [(NSMenuItem*)item setState:(_graphView.showsBranchLabels ? NSOnState : NSOffState)];
    return YES;
  }
  
  if (item.action == @selector(pullCurrentBranch:)) {
    return !editingDisabled && self.repository.history.HEADBranch.upstream;
  }
  if (item.action == @selector(pushCurrentBranch:)) {
    return !editingDisabled && self.repository.history.HEADBranch;
  }
  
  GCHistoryCommit* commit = _graphView.selectedCommit;
  if (commit == nil) {
    XLOG_DEBUG_UNREACHABLE();
    return NO;
  }
  
  if ((item.action == @selector(quickViewSelectedCommit:)) || (item.action == @selector(externalDiffSelectedCommit:))) {
    return YES;
  }
  if (item.action == @selector(viewSelectedCommitInHostingService:)) {
    GCHostingService service;
    NSURL* url = [self.repository hostingURLForCommit:commit service:&service error:NULL];  // Ignore errors
    if (url == nil) {
      service = kGCHostingService_Unknown;
    }
    switch (service) {
      case kGCHostingService_Unknown: [(NSMenuItem*)item setTitle:NSLocalizedString(@"View on Hosting Service…", nil)]; break;
      default: [(NSMenuItem*)item setTitle:[NSString stringWithFormat:NSLocalizedString(@"View on %@…", nil), GCNameFromHostingService(service)]]; break;
    }
    [(NSMenuItem*)item setRepresentedObject:url];
    return (service != kGCHostingService_Unknown);
  }
  if ((item.action == @selector(diffSelectedCommitWithHEAD:)) || (item.action == @selector(externalDiffWithHEAD:))) {
    return ![self.repository.history.HEADCommit isEqualToCommit:commit];
  }
  
  if (editingDisabled) {
    return NO;
  }
  
  if (item.action == @selector(checkoutSelectedCommit:)) {
    id target = [self _smartCheckoutTarget:commit];
    if ([target isKindOfClass:[GCLocalBranch class]]) {
      _checkoutMenuItem.title = [NSString stringWithFormat:NSLocalizedString(@"Checkout \"%@\" Branch", nil), [target name]];
      return ![self.repository.history.HEADBranch isEqualToBranch:target];
    } else {
      _checkoutMenuItem.title = NSLocalizedString(@"Checkout Detached HEAD", nil);
      return ![self.repository.history.HEADCommit isEqualToCommit:target];
    }
  }
  
  BOOL onAnyLocalBranch = [self.repository.history isCommitOnAnyLocalBranch:commit];
  if (item.action == @selector(deleteSelectedCommit:)) {
    return onAnyLocalBranch || commit.remoteBranches.count;
  }
  if (item.action == @selector(editSelectedCommitMessage:)) {
    return onAnyLocalBranch;
  }
  if ((item.action == @selector(rewriteSelectedCommit:)) || (item.action == @selector(splitSelectedCommit:))
      || (item.action == @selector(fixupSelectedCommit:)) || (item.action == @selector(squashSelectedCommit:))) {
    return onAnyLocalBranch && (commit.parents.count == 1);
  }
  if (item.action == @selector(swapSelectedCommitWithParent:)) {
    return onAnyLocalBranch && (commit.parents.count == 1);  // TODO: If there is more than parent, we don't know which one to swap with
  }
  if (item.action == @selector(swapSelectedCommitWithChild:)) {
    return onAnyLocalBranch && (commit.children.count == 1);  // TODO: If there is more than child, we don't know which one to swap with
  }
  if ((item.action == @selector(cherryPickSelectedCommit:)) || (item.action == @selector(mergeSelectedCommit:))
      || (item.action == @selector(rebaseOntoSelectedCommit:))) {
    return !self.repository.history.HEADDetached && ![self.repository.history.HEADCommit isEqualToCommit:commit];
  }
  if (item.action == @selector(revertSelectedCommit:)) {
    return !self.repository.history.HEADDetached;
  }
  if ((item.action == @selector(setBranchTipToSelectedCommit:)) || (item.action == @selector(moveBranchTipToSelectedCommit:))) {
    return !self.repository.history.HEADDetached && ![self.repository.history.HEADCommit isEqualToCommit:commit];
  }
  
  return [self respondsToSelector:item.action];
}

#pragma mark - Public Actions

- (IBAction)toggleTagLabels:(id)sender {
  BOOL show = !_graphView.showsTagLabels;
  _graphView.showsTagLabels = show;
  [self.repository setUserInfo:@((BOOL)!show) forKey:kPersistentViewStateKey_HideTagLabels];
}

- (IBAction)toggleBranchLabels:(id)sender {
  BOOL show = !_graphView.showsBranchLabels;
  _graphView.showsBranchLabels = show;
  [self.repository setUserInfo:@(show) forKey:kPersistentViewStateKey_ShowBranchLabels];
}

- (IBAction)toggleVirtualTips:(id)sender {
  self.showsVirtualTips = !_showsVirtualTips;
}

- (IBAction)toggleTagTips:(id)sender {
  self.hidesTagTips = !_hidesTagTips;
}

- (IBAction)toggleRemoteBranchTips:(id)sender {
  self.hidesRemoteBranchTips = !_hidesRemoteBranchTips;
}

- (IBAction)toggleStaleBranchTips:(id)sender {
  self.hidesStaleBranchTips = !_hidesStaleBranchTips;
}

- (IBAction)fetchAllRemoteBranches:(id)sender {
  [self fetchDefaultRemoteBranchesFromAllRemotes];
}

- (IBAction)fetchAllRemoteTags:(id)sender {
  [self fetchAllTagsFromAllRemotes:NO];
}

- (IBAction)fetchAndPruneAllRemoteTags:(id)sender {
  [self fetchAllTagsFromAllRemotes:YES];
}

- (IBAction)pushAllLocalBranches:(id)sender {
  [self pushAllLocalBranchesToAllRemotes];
}

- (IBAction)pushAllTags:(id)sender {
  [self pushAllTagsToAllRemotes];
}

- (IBAction)pullCurrentBranch:(id)sender {
  GCHistoryLocalBranch* branch = self.repository.history.HEADBranch;
  [self pullLocalBranchFromUpstream:branch];
}

- (IBAction)pushCurrentBranch:(id)sender {
  GCHistoryLocalBranch* branch = self.repository.history.HEADBranch;
  if (branch.upstream) {
    [self pushLocalBranchToUpstream:branch];
  } else {
    NSError* error;
    NSArray* remotes = [self.repository listRemotes:&error];
    if (remotes) {
      GCRemote* bestRemote = remotes.firstObject;
      for (GCRemote* remote in remotes) {
        if ([remote.name isEqualToString:@"origin"]) {
          bestRemote = remote;
          break;
        }
      }
      if (bestRemote) {
        [self pushLocalBranch:branch toRemote:bestRemote];
      }
    } else {
      [self presentError:error];
    }
  }
}

#pragma mark - Contextual Menu Actions

- (IBAction)quickViewSelectedCommit:(id)sender {
  [_delegate mapViewController:self quickViewCommit:_graphView.selectedCommit];
}

- (IBAction)externalDiffSelectedCommit:(id)sender {
  [self launchDiffToolWithCommit:_graphView.selectedCommit otherCommit:_graphView.selectedCommit.parents.firstObject];  // Use main-line
}

- (IBAction)viewSelectedCommitInHostingService:(id)sender {
  NSURL* url = [(NSMenuItem*)sender representedObject];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)_diffSelectedCommitWithHEAD:(void (^)(GCHistoryCommit* commit, GCHistoryCommit* otherCommit))handler {
  GCHistoryCommit* headCommit = self.repository.history.HEADCommit;
  GCHistoryCommit* selectedCommit = _graphView.selectedCommit;
  switch ([selectedCommit.date compare:headCommit.date]) {
    
    case NSOrderedAscending:  // Selected commit is older than HEAD commit
      handler(headCommit, selectedCommit);
      break;
    
    case NSOrderedDescending:  // Selected commit is newer than HEAD commit
      handler(selectedCommit, headCommit);
      break;
    
    case NSOrderedSame: {  // Selected and HEAD commits have the exact same date
      NSError* error;
      GCCommitRelation relation = [self.repository findRelationOfCommit:selectedCommit relativeToCommit:headCommit error:&error];
      switch (relation) {
        
        case kGCCommitRelation_Unknown:
          [self presentError:error];
          break;
        
        case kGCCommitRelation_Identical:  // Selected and HEAD commits are the same
          XLOG_DEBUG_UNREACHABLE();
          break;
        
        case kGCCommitRelation_Ancestor:   // Selected commit is an ancestor of HEAD commit
          handler(headCommit, selectedCommit);
          break;
        
        case kGCCommitRelation_Descendant:  // Anything else
        case kGCCommitRelation_Cousin:
        case kGCCommitRelation_Unrelated:
          handler(selectedCommit, headCommit);
          break;
        
      }
      break;
    }
    
  }
}

- (IBAction)diffSelectedCommitWithHEAD:(id)sender {
  [self _diffSelectedCommitWithHEAD:^(GCHistoryCommit* commit, GCHistoryCommit* otherCommit) {
    [_delegate mapViewController:self diffCommit:commit withOtherCommit:otherCommit];
  }];
}

- (IBAction)externalDiffWithHEAD:(id)sender {
  [self _diffSelectedCommitWithHEAD:^(GCHistoryCommit* commit, GCHistoryCommit* otherCommit) {
    [self launchDiffToolWithCommit:commit otherCommit:otherCommit];
  }];
}

- (IBAction)checkoutSelectedCommit:(id)sender {
  GCHistoryCommit* commit = _graphView.selectedCommit;
  id target = [self _smartCheckoutTarget:commit];
  if ([target isKindOfClass:[GCLocalBranch class]]) {
    [self checkoutLocalBranch:target];
  } else {
    GCHistoryRemoteBranch* branch = commit.remoteBranches.firstObject;
    if (branch && ![self.repository.history historyLocalBranchWithName:branch.branchName]) {
      NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Do you want to just checkout the commit or also create a new local branch?", nil)
                                       defaultButton:NSLocalizedString(@"Create Local Branch", nil)
                                     alternateButton:NSLocalizedString(@"Cancel", nil)
                                         otherButton:NSLocalizedString(@"Checkout Commit", nil)
                           informativeTextWithFormat:NSLocalizedString(@"The selected commit is also the tip of the remote branch \"%@\".", nil), branch.name];
      alert.type = kGIAlertType_Note;
      [self presentAlert:alert completionHandler:^(NSInteger returnCode) {
        
        if (returnCode == NSAlertDefaultReturn) {
          [self checkoutRemoteBranch:branch];
        } else if (returnCode == NSAlertOtherReturn) {
          [self checkoutCommit:target];
        }
        
      }];
    } else {
      [self checkoutCommit:target];
    }
  }
}

- (IBAction)createTagAtSelectedCommit:(id)sender {
  GCHistoryCommit* commit = _graphView.selectedCommit;
  _tagNameTextField.stringValue = @"";
  _tagMessageTextView.string = @"";
  [self.windowController runModalView:_tagView withInitialFirstResponder:_tagNameTextField completionHandler:^(BOOL success) {
    
    if (success) {
      NSString* name = _tagNameTextField.stringValue;
      NSString* message = [_tagMessageTextView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (name.length) {
        [self createTagAtCommit:commit withName:name message:message];
      } else {
        NSBeep();
      }
    }
    _tagMessageTextView.string = @"";
    [_tagMessageTextView.undoManager removeAllActions];
    
  }];
}

- (IBAction)editSelectedCommitMessage:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self editCommitMessage:commit];
}

- (IBAction)rewriteSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  if ([self checkCleanRepositoryForOperationOnCommit:commit]) {
    [_delegate mapViewController:self rewriteCommit:commit];
  }
}

- (IBAction)splitSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  if ([self checkCleanRepositoryForOperationOnCommit:commit]) {
    [_delegate mapViewController:self splitCommit:commit];
  }
}

- (IBAction)revertSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self revertCommit:commit againstLocalBranch:self.repository.history.HEADBranch];
}

- (IBAction)deleteSelectedCommit:(id)sender {
  GCHistoryCommit* commit = _graphView.selectedCommit;
  GCHistoryLocalBranch* localBranch = commit.localBranches.firstObject;
  if (localBranch) {
    NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Do you want to delete the commit or the local branch?", nil)
                                     defaultButton:NSLocalizedString(@"Delete Local Branch", nil)
                                   alternateButton:NSLocalizedString(@"Cancel", nil)
                                       otherButton:NSLocalizedString(@"Delete Commit", nil)
                         informativeTextWithFormat:NSLocalizedString(@"The selected commit is also the tip of the local branch \"%@\".", nil), localBranch.name];
    alert.type = kGIAlertType_Note;
    [self presentAlert:alert completionHandler:^(NSInteger returnCode) {
      
      if (returnCode == NSAlertDefaultReturn) {
        [self deleteLocalBranch:localBranch];
      } else if (returnCode == NSAlertOtherReturn) {
        [self deleteCommit:commit];
      }
      
    }];
  } else {
    GCHistoryRemoteBranch* remoteBranch = commit.remoteBranches.firstObject;
    if (remoteBranch && ![self.repository.history isCommitOnAnyLocalBranch:commit]) {
      [self deleteRemoteBranch:remoteBranch];
    } else {
      [self deleteCommit:commit];
    }
  }
}

- (IBAction)fixupSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self fixupCommitWithParent:commit];
}

- (IBAction)squashSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self squashCommitWithParent:commit];
}

- (IBAction)swapSelectedCommitWithChild:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self swapCommitWithChild:commit];
}

- (IBAction)swapSelectedCommitWithParent:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self swapCommitWithParent:commit];
}

- (IBAction)cherryPickSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self cherryPickCommit:commit againstLocalBranch:self.repository.history.HEADBranch];
}

- (IBAction)mergeSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  GCBranch* branch = commit.localBranches.firstObject;  // TODO: What if there are multiple local branches?
  if (branch == nil) {
    branch = commit.remoteBranches.firstObject;  // TODO: What if there are multiple remote branches?
  }
  [self smartMergeCommitOrBranch:(branch ? branch : commit) intoLocalBranch:self.repository.history.HEADBranch withUserMessage:nil];
}

- (IBAction)rebaseOntoSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self smartRebaseLocalBranch:self.repository.history.HEADBranch ontoCommit:commit withUserMessage:nil];
}

- (IBAction)setBranchTipToSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self setTipCommit:commit forLocalBranch:self.repository.history.HEADBranch];
}

- (IBAction)moveBranchTipToSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  [self moveTipCommit:commit forLocalBranch:self.repository.history.HEADBranch];
}

- (IBAction)createBranchAtSelectedCommit:(id)sender {
  GCHistoryCommit* commit = self.graphView.selectedNode.commit;
  _createBranchTextField.stringValue = @"";
  _createBranchButton.state = NSOnState;
  [self.windowController runModalView:_createBranchView withInitialFirstResponder:_createBranchTextField completionHandler:^(BOOL success) {
    
    if (success) {
      NSString* name = _createBranchTextField.stringValue;
      if (name.length) {
        [self createLocalBranchAtCommit:commit withName:name checkOut:_createBranchButton.state];
      } else {
        NSBeep();
      }
    }
    
  }];
}

#pragma mark - Internal Actions

- (IBAction)_renameTag:(id)sender {
  GCHistoryTag* tag = [(NSMenuItem*)sender representedObject];
  _renameTagTextField.stringValue = tag.name;
  [self.windowController runModalView:_renameTagView withInitialFirstResponder:_renameTagTextField completionHandler:^(BOOL success) {
    
    if (success) {
      NSString* name = _renameTagTextField.stringValue;
      if (name.length && ![name isEqualToString:tag.name]) {
        [self setName:name forTag:tag];
      } else {
        NSBeep();
      }
    }
    
  }];
}

- (IBAction)_deleteTag:(id)sender {
  GCHistoryTag* tag = [(NSMenuItem*)sender representedObject];
  [self deleteTag:tag];
}

- (IBAction)_deleteTagFromAllRemotes:(id)sender {
  GCHistoryTag* tag = [(NSMenuItem*)sender representedObject];
  [self deleteTagFromAllRemotes:tag];
}

- (IBAction)_pushTagToRemote:(id)sender {
  GCHistoryTag* tag = [[(NSMenuItem*)sender representedObject] objectAtIndex:0];
  GCRemote* remote = [[(NSMenuItem*)sender representedObject] objectAtIndex:1];
  [self pushTag:tag toRemote:remote];
}

- (IBAction)_checkoutRemoteBranch:(id)sender {
  GCHistoryRemoteBranch* branch = [(NSMenuItem*)sender representedObject];
  [self checkoutRemoteBranch:branch];
}

- (IBAction)_fetchRemoteBranch:(id)sender {
  GCHistoryRemoteBranch* branch = [(NSMenuItem*)sender representedObject];
  [self fetchRemoteBranch:branch];
}

- (IBAction)_deleteRemoteBranch:(id)sender {
  GCHistoryRemoteBranch* branch = [(NSMenuItem*)sender representedObject];
  [self deleteRemoteBranch:branch];
}

- (IBAction)_viewBranchOnHostingService:(id)sender {
  NSURL* url = [(NSMenuItem*)sender representedObject];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)_createPullRequestOnHostingService:(id)sender {
  NSURL* url = [(NSMenuItem*)sender representedObject];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)_pullLocalBranchFromUpstream:(id)sender {
  GCHistoryLocalBranch* branch = [(NSMenuItem*)sender representedObject];
  [self pullLocalBranchFromUpstream:branch];
}

- (IBAction)_pushLocalBranchToUpstream:(id)sender {
  GCHistoryLocalBranch* branch = [(NSMenuItem*)sender representedObject];
  [self pushLocalBranchToUpstream:branch];
}

- (IBAction)_pushLocalBranchToRemote:(id)sender {
  GCHistoryLocalBranch* branch = [[(NSMenuItem*)sender representedObject] objectAtIndex:0];
  GCRemote* remote = [[(NSMenuItem*)sender representedObject] objectAtIndex:1];
  [self pushLocalBranch:branch toRemote:remote];
}

- (IBAction)_renameLocalBranch:(id)sender {
  GCHistoryLocalBranch* branch = [(NSMenuItem*)sender representedObject];
  _renameBranchTextField.stringValue = branch.name;
  [self.windowController runModalView:_renameBranchView withInitialFirstResponder:_renameBranchTextField completionHandler:^(BOOL success) {
    
    if (success) {
      NSString* name = _renameBranchTextField.stringValue;
      if (name.length && ![name isEqualToString:branch.name]) {
        [self setName:_renameBranchTextField.stringValue forLocalBranch:branch];
      } else {
        NSBeep();
      }
    }
    
  }];
}

- (IBAction)_deleteLocalBranch:(id)sender {
  GCHistoryLocalBranch* branch = [(NSMenuItem*)sender representedObject];
  [self deleteLocalBranch:branch];
}

- (IBAction)_configureUpstreamForLocalBranch:(id)sender {
  GCHistoryLocalBranch* localBranch;
  GCHistoryRemoteBranch* remoteBranch;
  id representedObject = [(NSMenuItem*)sender representedObject];
  if ([representedObject isKindOfClass:[NSArray class]]) {
    localBranch = [representedObject objectAtIndex:0];
    remoteBranch = [representedObject objectAtIndex:1];
  } else {
    localBranch = representedObject;
    remoteBranch = nil;
  }
  [self setUpstream:remoteBranch forLocalBranch:localBranch];
}

- (IBAction)_mergeLocalBranch:(id)sender {
  GCHistoryLocalBranch* mergeBranch = [[(NSMenuItem*)sender representedObject] objectAtIndex:0];
  GCHistoryLocalBranch* intoBranch = [[(NSMenuItem*)sender representedObject] objectAtIndex:1];
  [self smartMergeCommitOrBranch:mergeBranch intoLocalBranch:intoBranch withUserMessage:nil];
}

- (IBAction)_rebaseLocalBranch:(id)sender {
  GCHistoryLocalBranch* rebaseBranch = [[(NSMenuItem*)sender representedObject] objectAtIndex:0];
  GCHistoryLocalBranch* ontoBranch = [[(NSMenuItem*)sender representedObject] objectAtIndex:1];  // Could be GCHistoryRemoteBranch too
  [self smartRebaseLocalBranch:rebaseBranch ontoCommit:ontoBranch.tipCommit withUserMessage:nil];
}

- (IBAction)_mergeRemoteBranch:(id)sender {
  GCHistoryLocalBranch* mergeBranch = [[(NSMenuItem*)sender representedObject] objectAtIndex:0];
  GCHistoryLocalBranch* intoBranch = [[(NSMenuItem*)sender representedObject] objectAtIndex:1];
  [self smartMergeCommitOrBranch:mergeBranch intoLocalBranch:intoBranch withUserMessage:nil];
}

@end
