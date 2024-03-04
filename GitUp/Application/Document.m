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

#import "Document.h"
#import "WindowController.h"
#import "Common.h"

#import "KeychainAccessor.h"
#import "AuthenticationWindowController.h"

#import <GitUpKit/GitUpKit.h>
#import <GitUpKit/XLFacilityMacros.h>

#define kWindowModeString_Map @"map"
#define kWindowModeString_Map_QuickView @"quickview"
#define kWindowModeString_Map_Diff @"diff"
#define kWindowModeString_Map_Rewrite @"rewrite"
#define kWindowModeString_Map_Split @"split"
#define kWindowModeString_Map_Resolve @"resolve"
#define kWindowModeString_Map_Config @"config"
#define kWindowModeString_Commit @"commit"
#define kWindowModeString_Stashes @"stashes"

#define kSideViewIdentifier_Search @"search"
#define kSideViewIdentifier_Tags @"tags"
#define kSideViewIdentifier_Snapshots @"snapshots"
#define kSideViewIdentifier_Reflog @"reflog"
#define kSideViewIdentifier_Ancestors @"ancestors"

#define kRestorableStateKey_WindowMode @"windowMode"

#define kSideViewAnimationDuration 0.15  // seconds

#define kMaxAncestorCommits 1000

#define kMaxProgressRefreshRate 10.0  // Hz

#define kNavigateMinWidth 174.0
#define kNavigateSegmentWidth 34.0
#define kTitleMaxWidth HUGE_VALF
#define kSearchFieldCompactWidth 180.0
#define kSearchFieldExpandedWidth 238.0

typedef NS_ENUM(NSInteger, NavigationAction) {
  kNavigationAction_Exit = 0,
  kNavigationAction_Next,
  kNavigationAction_Previous
};

@interface Document () <NSToolbarDelegate, NSTextFieldDelegate, GCLiveRepositoryDelegate, GIWindowControllerDelegate, GIMapViewControllerDelegate, GISnapshotListViewControllerDelegate, GIUnifiedReflogViewControllerDelegate, GICommitListViewControllerDelegate, GICommitRewriterViewControllerDelegate, GICommitSplitterViewControllerDelegate, GIConflictResolverViewControllerDelegate>
@property(nonatomic, strong) AuthenticationWindowController* authenticationWindowController;
@property(nonatomic) IBOutlet GICustomToolbarItem* navigateItem;
@property(nonatomic) IBOutlet GICustomToolbarItem* titleItem;
@property(nonatomic) IBOutlet NSToolbarItem* snapshotsItem;
@property(nonatomic) IBOutlet NSToolbarItem<GISearchToolbarItem>* searchItem;
@end

static NSDictionary* _helpPlist = nil;

static inline NSString* _WindowModeStringFromID(WindowModeID mode) {
  switch (mode) {
    case kWindowModeID_Map:
      return kWindowModeString_Map;
    case kWindowModeID_Commit:
      return kWindowModeString_Commit;
    case kWindowModeID_Stashes:
      return kWindowModeString_Stashes;
  }
  XLOG_DEBUG_UNREACHABLE();
  return nil;
}

static inline WindowModeID _WindowModeIDFromString(NSString* mode) {
  if ([mode isEqualToString:kWindowModeString_Map] || [mode isEqualToString:kWindowModeString_Map_QuickView] || [mode isEqualToString:kWindowModeString_Map_Diff] || [mode isEqualToString:kWindowModeString_Map_Rewrite] || [mode isEqualToString:kWindowModeString_Map_Split] || [mode isEqualToString:kWindowModeString_Map_Resolve] || [mode isEqualToString:kWindowModeString_Map_Config]) {
    return kWindowModeID_Map;
  }
  if ([mode isEqualToString:kWindowModeString_Commit]) {
    return kWindowModeID_Commit;
  }
  if ([mode isEqualToString:kWindowModeString_Stashes]) {
    return kWindowModeID_Stashes;
  }
  XLOG_DEBUG_UNREACHABLE();
  return kWindowModeID_Map;
}

static inline BOOL _WindowModeIsPrimary(NSString* mode) {
  return [mode isEqualToString:kWindowModeString_Map] || [mode isEqualToString:kWindowModeString_Commit] || [mode isEqualToString:kWindowModeString_Stashes];
}

@implementation Document {
  WindowController* _windowController;
  GIMapViewController* _mapViewController;
  GICommitListViewController* _tagsViewController;
  GISnapshotListViewController* _snapshotListViewController;
  GIUnifiedReflogViewController* _unifiedReflogViewController;
  GICommitListViewController* _searchResultsViewController;
  GICommitListViewController* _ancestorsViewController;
  GIQuickViewController* _quickViewController;
  GIDiffViewController* _diffViewController;
  GICommitRewriterViewController* _commitRewriterViewController;
  GICommitSplitterViewController* _commitSplitterViewController;
  GIConflictResolverViewController* _conflictResolverViewController;
  GICommitViewController* _commitViewController;
  GIStashListViewController* _stashListViewController;
  GIConfigViewController* _configViewController;
  GCLiveRepository* _repository;
  NSNumberFormatter* _numberFormatter;
  NSDateFormatter* _dateFormatter;
  CALayer* _fixedSnapshotLayer;
  CALayer* _animatingSnapshotLayer;
  NSMutableArray* _quickViewCommits;
  GCHistoryWalker* _quickViewAncestors;
  GCHistoryWalker* _quickViewDescendants;
  NSUInteger _quickViewIndex;
  BOOL _searchReady;
  BOOL _preventSelectionLoopback;
  NSResponder* _savedFirstResponder;
  id _lastHEADBranch;
  BOOL _checkingForChanges;
  CFRunLoopTimerRef _checkTimer;
  NSDictionary* _updatedReferences;
  NSDictionary* _stateAttributes;
  BOOL _ready;
  NSInteger _resolvingConflicts;
  NSString* _helpIdentifier;
  NSInteger _helpIndex;
  NSURL* _helpURL;
  BOOL _helpHEADDisabled;
  BOOL _indexing;
  BOOL _abortIndexing;
}

#pragma mark - Properties
- (AuthenticationWindowController*)authenticationWindowController {
  if (!_authenticationWindowController) {
    _authenticationWindowController = [[AuthenticationWindowController alloc] init];
  }
  return _authenticationWindowController;
}

#pragma mark - Initialize
+ (void)initialize {
  NSString* path = [[NSBundle mainBundle] pathForResource:@"Help" ofType:@"plist"];
  if (path) {
    NSData* data = [NSData dataWithContentsOfFile:path];
    if (data) {
      _helpPlist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    }
  }
  XLOG_DEBUG_CHECK(_helpPlist);
}

static void _CheckTimerCallBack(CFRunLoopTimerRef timer, void* info) {
  @autoreleasepool {
    [(__bridge Document*)info checkForChanges:nil];
  }
}

- (instancetype)init {
  if ((self = [super init])) {
    _numberFormatter = [[NSNumberFormatter alloc] init];
    _numberFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    _numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    _dateFormatter.dateStyle = NSDateFormatterLongStyle;
    _dateFormatter.timeStyle = NSDateFormatterMediumStyle;

    CFRunLoopTimerContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
    _checkTimer = CFRunLoopTimerCreate(kCFAllocatorDefault, HUGE_VALF, HUGE_VALF, 0, 0, _CheckTimerCallBack, &context);
    CFRunLoopAddTimer(CFRunLoopGetMain(), _checkTimer, kCFRunLoopCommonModes);

    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kUserDefaultsKey_DiffWhitespaceMode options:0 context:(__bridge void*)[Document class]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didResignActive:) name:NSApplicationDidResignActiveNotification object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidResignActiveNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidBecomeActiveNotification object:nil];
  [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kUserDefaultsKey_DiffWhitespaceMode context:(__bridge void*)[Document class]];

  CFRunLoopTimerInvalidate(_checkTimer);
  CFRelease(_checkTimer);

#if DEBUG
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    XLOG_DEBUG_CHECK([GCLiveRepository allocatedCount] == [[[NSDocumentController sharedDocumentController] documents] count]);
  });
#endif
}

// WARNING: This is called *several* times when the default has been changed
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
  if (context == (__bridge void*)[Document class]) {
    if ([keyPath isEqualToString:kUserDefaultsKey_DiffWhitespaceMode]) {
      _repository.diffWhitespaceMode = [[NSUserDefaults standardUserDefaults] integerForKey:kUserDefaultsKey_DiffWhitespaceMode];
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (BOOL)readFromURL:(NSURL*)url ofType:(NSString*)typeName error:(NSError**)outError {
  BOOL success = NO;
  _repository = [[GCLiveRepository alloc] initWithExistingLocalRepository:url.path error:outError];
  if (_repository) {
    if (_repository.bare) {
      if (outError) {
        *outError = MAKE_ERROR(@"Bare repositories are not supported at this time");
      }
    } else {
#if DEBUG
      if ([NSEvent modifierFlags] & NSEventModifierFlagOption) {
        [[NSFileManager defaultManager] removeItemAtPath:_repository.privateAppDirectoryPath error:NULL];
        XLOG_WARNING(@"Resetting private data for repository \"%@\"", _repository.repositoryPath);
      }
#endif
      _repository.delegate = self;
      _repository.undoManager = self.undoManager;
      _repository.snapshotsEnabled = YES;
      if ([NSApp isActive]) {
        [_repository notifyRepositoryChanged];  // Otherwise -didBecomeActive: will take care of it
      } else {
        _repository.automaticSnapshotsEnabled = YES;  // TODO: Is this a good idea?
      }
      _repository.diffWhitespaceMode = [[NSUserDefaults standardUserDefaults] integerForKey:kUserDefaultsKey_DiffWhitespaceMode];

#if DEBUG
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XLOG_DEBUG_CHECK([GCLiveRepository allocatedCount] == [[[NSDocumentController sharedDocumentController] documents] count]);
      });
#endif

      success = YES;
    }
  }
  return success;
}

- (void)closeAndSaveCurrentWindowFrame:(BOOL)shouldSaveCurrentWindowFrame {
  CFRunLoopTimerSetNextFireDate(_checkTimer, HUGE_VALF);

  _repository.delegate = nil;  // Make sure that if the GCLiveRepository is still around afterwards, it won't call back to the dealloc'ed document

  if (shouldSaveCurrentWindowFrame && _mainWindow.isVisible) {
    [_repository setUserInfo:_mainWindow.stringWithSavedFrame forKey:kRepositoryUserInfoKey_MainWindowFrame];
  }

  [super close];
}

- (void)close {
  [self closeAndSaveCurrentWindowFrame:YES];
}

- (void)makeWindowControllers {
  _windowController = [[WindowController alloc] initWithWindowNibName:@"Document" owner:self];
  _windowController.delegate = self;
  [self addWindowController:_windowController];
}

// This is called when opening documents or attempting to open a document already opened
- (void)showWindows {
  [super showWindows];

  if (!_ready) {
    [self performSelector:@selector(_documentDidOpen:) withObject:nil afterDelay:0.0];
    _ready = YES;
  }
}

- (void)windowControllerDidLoadNib:(NSWindowController*)windowController {
  CGFloat fontSize = _infoTextField2.font.pointSize;
  NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = NSTextAlignmentCenter;
  _stateAttributes = @{NSParagraphStyleAttributeName : style, NSForegroundColorAttributeName : NSColor.systemRedColor, NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]};

  NSString* frameString = [_repository userInfoForKey:kRepositoryUserInfoKey_MainWindowFrame];
  if (frameString) {
    [_mainWindow setFrameFromString:frameString];
  }

  NSSegmentedControl* modeControl = (NSSegmentedControl*)_navigateItem.primaryControl;
  NSSegmentedControl* navigateControl = (NSSegmentedControl*)_navigateItem.secondaryControl;
  if (@available(macOS 11, *)) {
    // Fully custom symbols not available before 11.0.
    [modeControl setImage:[NSImage imageNamed:@"circle.2.line.diagonal"] forSegment:kWindowModeID_Map];
  } else {
    _mainWindow.titleVisibility = NSWindowTitleHidden;
    [modeControl setWidth:kNavigateSegmentWidth forSegment:kWindowModeID_Map];
    [modeControl setWidth:kNavigateSegmentWidth forSegment:kWindowModeID_Commit];
    [modeControl setWidth:kNavigateSegmentWidth forSegment:kWindowModeID_Stashes];
    [navigateControl setWidth:kNavigateSegmentWidth forSegment:kNavigationAction_Exit];
    [navigateControl setWidth:kNavigateSegmentWidth forSegment:kNavigationAction_Next];
    [navigateControl setWidth:kNavigateSegmentWidth forSegment:kNavigationAction_Previous];
  }

  if (@available(macOS 10.14, *)) {
    NSLayoutConstraint* searchFieldPreferredWidth = [_searchItem.searchField.widthAnchor constraintEqualToConstant:kSearchFieldCompactWidth];
    searchFieldPreferredWidth.priority = NSLayoutPriorityDefaultHigh - 20;
    NSLayoutConstraint* searchFieldMaxWidth = [_searchItem.searchField.widthAnchor constraintLessThanOrEqualToConstant:kSearchFieldExpandedWidth];
    [NSLayoutConstraint activateConstraints:@[ searchFieldPreferredWidth, searchFieldMaxWidth ]];
  } else {
    _navigateItem.minSize = NSMakeSize(kNavigateMinWidth, _navigateItem.minSize.height);
    _titleItem.maxSize = NSMakeSize(kTitleMaxWidth, _titleItem.maxSize.height);

    // Text fields must be drawn on an opaque background pre-Mojave to avoid
    // subpixel antialiasing issues during animation.
    for (NSTextField* field in @[ _infoTextField1, _infoTextField2, _progressTextField ]) {
      field.drawsBackground = YES;
      field.backgroundColor = _mainWindow.backgroundColor;
    }
  }

  _mapViewController = [[GIMapViewController alloc] initWithRepository:_repository];
  _mapViewController.delegate = self;
  [_mapControllerView replaceWithView:_mapViewController.view];
  _mapView.frame = _mapContainerView.bounds;
  [_mapContainerView addSubview:_mapView];
  XLOG_DEBUG_CHECK(_mapContainerView.subviews.firstObject == _mapView);
  [self _updateStatusBar];

  _tagsViewController = [[GICommitListViewController alloc] initWithRepository:_repository];
  _tagsViewController.delegate = self;
  _tagsViewController.emptyLabel = NSLocalizedString(@"No Tags", nil);
  [_tagsControllerView replaceWithView:_tagsViewController.view];

  _snapshotListViewController = [[GISnapshotListViewController alloc] initWithRepository:_repository];
  _snapshotListViewController.delegate = self;
  [_snapshotsControllerView replaceWithView:_snapshotListViewController.view];

  _unifiedReflogViewController = [[GIUnifiedReflogViewController alloc] initWithRepository:_repository];
  _unifiedReflogViewController.delegate = self;
  [_reflogControllerView replaceWithView:_unifiedReflogViewController.view];

  _ancestorsViewController = [[GICommitListViewController alloc] initWithRepository:_repository];
  _ancestorsViewController.delegate = self;
  [_ancestorsControllerView replaceWithView:_ancestorsViewController.view];

  _searchResultsViewController = [[GICommitListViewController alloc] initWithRepository:_repository];
  _searchResultsViewController.delegate = self;
  _searchResultsViewController.emptyLabel = NSLocalizedString(@"No Results", nil);
  [_searchControllerView replaceWithView:_searchResultsViewController.view];

  _quickViewController = [[GIQuickViewController alloc] initWithRepository:_repository];
  NSTabViewItem* quickItem = [_mainTabView tabViewItemAtIndex:[_mainTabView indexOfTabViewItemWithIdentifier:kWindowModeString_Map_QuickView]];
  quickItem.view = _quickViewController.view;

  _diffViewController = [[GIDiffViewController alloc] initWithRepository:_repository];
  NSTabViewItem* diffItem = [_mainTabView tabViewItemAtIndex:[_mainTabView indexOfTabViewItemWithIdentifier:kWindowModeString_Map_Diff]];
  diffItem.view = _diffViewController.view;

  _commitRewriterViewController = [[GICommitRewriterViewController alloc] initWithRepository:_repository];
  _commitRewriterViewController.delegate = self;
  [_rewriteControllerView replaceWithView:_commitRewriterViewController.view];
  NSTabViewItem* rewriteItem = [_mainTabView tabViewItemAtIndex:[_mainTabView indexOfTabViewItemWithIdentifier:kWindowModeString_Map_Rewrite]];
  rewriteItem.view = _rewriteView;

  _commitSplitterViewController = [[GICommitSplitterViewController alloc] initWithRepository:_repository];
  _commitSplitterViewController.delegate = self;
  [_splitControllerView replaceWithView:_commitSplitterViewController.view];
  NSTabViewItem* splitItem = [_mainTabView tabViewItemAtIndex:[_mainTabView indexOfTabViewItemWithIdentifier:kWindowModeString_Map_Split]];
  splitItem.view = _splitView;

  _conflictResolverViewController = [[GIConflictResolverViewController alloc] initWithRepository:_repository];
  _conflictResolverViewController.delegate = self;
  [_resolveControllerView replaceWithView:_conflictResolverViewController.view];
  NSTabViewItem* resolveItem = [_mainTabView tabViewItemAtIndex:[_mainTabView indexOfTabViewItemWithIdentifier:kWindowModeString_Map_Resolve]];
  resolveItem.view = _resolveView;

  if ([[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsKey_SimpleCommit]) {
    _commitViewController = [[GISimpleCommitViewController alloc] initWithRepository:_repository];
  } else {
    _commitViewController = [[GIAdvancedCommitViewController alloc] initWithRepository:_repository];
  }
  _commitViewController.delegate = self;
  NSTabViewItem* commitItem = [_mainTabView tabViewItemAtIndex:[_mainTabView indexOfTabViewItemWithIdentifier:kWindowModeString_Commit]];
  commitItem.view = _commitViewController.view;

  _stashListViewController = [[GIStashListViewController alloc] initWithRepository:_repository];
  NSTabViewItem* stashesItem = [_mainTabView tabViewItemAtIndex:[_mainTabView indexOfTabViewItemWithIdentifier:kWindowModeString_Stashes]];
  stashesItem.view = _stashListViewController.view;

  _configViewController = [[GIConfigViewController alloc] initWithRepository:_repository];
  NSTabViewItem* configItem = [_mainTabView tabViewItemAtIndex:[_mainTabView indexOfTabViewItemWithIdentifier:kWindowModeString_Map_Config]];
  configItem.view = _configViewController.view;

  // This always uses a dark appearance.
  _hiddenWarningView.layer.backgroundColor = [[NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.0 alpha:0.5] CGColor];
  _hiddenWarningView.layer.cornerRadius = 10.0;

  [self _setSearchFieldPlaceholder:NSLocalizedString(@"Preparing Search…", nil)];

  for (NSMenuItem* item in _showMenu.itemArray) {  // We don't want first responder targets
    if (item.target == nil && item.action != NULL) {
      item.target = _mapViewController;
    }
  }
  _pullButton.target = _mapViewController;
  _pushButton.target = _mapViewController;

  [self _setWindowMode:kWindowModeString_Map];
}

// Override -updateChangeCount: which is trigged by NSUndoManager to do nothing and not mark document as updated
- (void)updateChangeCount:(NSDocumentChangeType)change {
}

- (BOOL)presentError:(NSError*)error {
  if (error == nil) {
    XLOG_DEBUG_UNREACHABLE();
    return NO;
  }

  if ([error.domain isEqualToString:GCErrorDomain] && ((error.code == kGCErrorCode_UserCancelled) || (error.code == kGCErrorCode_User))) {
    return NO;
  }

  if ([error.domain isEqualToString:GCErrorDomain] && (error.code == -1) && [error.localizedDescription isEqualToString:@"authentication required but no callback set"]) {  // TODO: Avoid hardcoding libgit2 error
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Unable to authenticate with remote!", nil);
    alert.informativeText = NSLocalizedString(@"If using an SSH remote, make sure you have added your key to the ssh-agent, then try again.", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
    alert.type = kGIAlertType_Stop;
    [alert beginSheetModalForWindow:_mainWindow completionHandler:NULL];
    return NO;
  }

  return [super presentError:error];
}

- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)shouldCloseSelector contextInfo:(void*)contextInfo {
  if (![self shouldCloseDocument]) {
    typedef void (*CallbackIMP)(id, SEL, NSDocument*, BOOL, void*);
    CallbackIMP callback = (CallbackIMP)[delegate methodForSelector:shouldCloseSelector];
    callback(delegate, shouldCloseSelector, self, NO, contextInfo);
  } else {
    [super canCloseDocumentWithDelegate:delegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
  }
}

- (void)presentedItemDidMoveToURL:(NSURL*)newURL {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self closeAndSaveCurrentWindowFrame:NO];

    NSDocumentController* controller = NSDocumentController.sharedDocumentController;
    [controller openDocumentWithContentsOfURL:newURL
                                      display:YES
                            completionHandler:^(NSDocument* document, BOOL documentWasAlreadyOpen, NSError* error) {
                              if (document) {
                                XLOG_DEBUG(@"Reopened document for rename to \"%@\"", newURL.path);
                              } else {
                                [controller presentError:error];
                              }
                            }];
  });
}

#pragma mark - Utilities

- (void)_resetCheckTimer {
  CFTimeInterval checkInterval = [[NSUserDefaults standardUserDefaults] doubleForKey:kUserDefaultsKey_CheckInterval];
  if (checkInterval > 0) {
    CFRunLoopTimerSetNextFireDate(_checkTimer, CFAbsoluteTimeGetCurrent() + checkInterval);
  }
}

- (void)_performCloneUsingRemote:(GCRemote*)remote recursive:(BOOL)recursive {
  [_repository setUndoActionName:NSLocalizedString(@"Clone", nil)];
  [_repository suspendHistoryUpdates];
  [_repository performOperationInBackgroundWithReason:@"clone"
      argument:nil
      usingOperationBlock:^BOOL(GCRepository* repository, NSError** outError) {
        return [repository cloneUsingRemote:remote recursive:recursive error:outError];
      }
      completionBlock:^(BOOL success, NSError* error) {
        [_repository resumeHistoryUpdates];
        if (!success) {
          [self presentError:error];
        }
        [self _prepareSearch];
        [self _resetCheckTimer];
      }];
}

- (void)_initializeSubmodules {
  [_repository performOperationInBackgroundWithReason:nil
      argument:nil
      usingOperationBlock:^BOOL(GCRepository* repository, NSError** outError) {
        return [repository initializeAllSubmodules:YES error:outError];
      }
      completionBlock:^(BOOL success, NSError* error) {
        if (!success) {
          [self presentError:error];
        }
        [self _resetCheckTimer];
      }];
}

- (void)_prepareSearch {
  _indexing = YES;
  _abortIndexing = NO;
  [[NSProcessInfo processInfo] disableSuddenTermination];
  NSUInteger totalCount = _repository.history.allCommits.count;
  __block float lastProgress = 0.0;
  __block CFTimeInterval lastTime = 0.0;
  [_repository prepareSearchInBackground:[[_repository userInfoForKey:kRepositoryUserInfoKey_IndexDiffs] boolValue]
      withProgressHandler:^BOOL(BOOL firstUpdate, NSUInteger addedCommits, NSUInteger removedCommits) {
        if (firstUpdate) {
          float progress = MIN(roundf(1000 * (float)addedCommits / (float)totalCount) / 10, 100.0);
          if (progress > lastProgress) {
            CFTimeInterval time = CFAbsoluteTimeGetCurrent();
            if (time > lastTime + 1.0 / kMaxProgressRefreshRate) {
              dispatch_async(dispatch_get_main_queue(), ^{
                if (progress >= 100) {
                  [self _setSearchFieldPlaceholder:NSLocalizedString(@"Finishing…", nil)];
                } else {
                  [self _setSearchFieldPlaceholder:[NSString stringWithFormat:NSLocalizedString(@"Preparing (%.1f%%)…", nil), progress]];
                }
              });
              lastProgress = progress;
              lastTime = time;
            }
          }
        }
        return !_abortIndexing;
      }
      completion:^(BOOL success, NSError* error) {
        if (!_abortIndexing) {  // If indexing has been aborted, this means the document has already been closed, so don't attempt to do *anything*
          if (success) {
            _searchReady = YES;
            [self _setSearchFieldPlaceholder:NSLocalizedString(@"Search Repository…", nil)];
            [_searchItem validate];
          } else {
            [self _setSearchFieldPlaceholder:NSLocalizedString(@"Search Unavailable", nil)];
            [self presentError:error];
          }
          [[NSProcessInfo processInfo] enableSuddenTermination];
          _indexing = NO;
        }
      }];
}

// TODO: Search field placeholder strings must all be about the same length since NSSearchField doesn't recenter updated placeholder strings properly
- (void)_documentDidOpen:(id)restored {
  XLOG_DEBUG_CHECK(_mainWindow.visible);

  // Work around a bug of NSSearchField which is always enabled after restoration even if set to disabled during restoration
  [self _updateToolBar];

  // Check if a clone is needed
  if (_cloneMode != kCloneMode_None) {
    XLOG_DEBUG_CHECK(_repository.empty && !restored);
    NSError* error;
    GCRemote* remote = [_repository lookupRemoteWithName:@"origin" error:&error];
    if (remote) {
      [self _performCloneUsingRemote:remote recursive:(_cloneMode == kCloneMode_Recursive)];
    } else {
      [self presentError:error];
    }
    return;  // Don't do anything else
  }

  // Prepare search
  [self _prepareSearch];

  // Check for uninitialized submodules
  if (!restored && ![[_repository userInfoForKey:kRepositoryUserInfoKey_SkipSubmoduleCheck] boolValue]) {
    NSError* error;
    if (![_repository checkAllSubmodulesInitialized:YES error:&error]) {
      if ([error.domain isEqualToString:GCErrorDomain] && (error.code == kGCErrorCode_SubmoduleUninitialized)) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"Do you want to initialize submodules?", nil);
        alert.informativeText = NSLocalizedString(@"One or more submodules in this repository are uninitialized.", nil);
        [alert addButtonWithTitle:NSLocalizedString(@"Initialize", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
        alert.type = kGIAlertType_Caution;
        alert.showsSuppressionButton = YES;
        [alert beginSheetModalForWindow:_mainWindow
                      completionHandler:^(NSModalResponse returnCode) {
                        if (alert.suppressionButton.state) {
                          [_repository setUserInfo:@(YES) forKey:kRepositoryUserInfoKey_SkipSubmoduleCheck];
                        }
                        if (returnCode == NSAlertFirstButtonReturn) {
                          [self _initializeSubmodules];
                        }
                      }];
        return;  // Don't do anything else
      } else {
        [self presentError:error];
      }
    }
  }

  // Otherwise check for changes immediately
  if ([[NSUserDefaults standardUserDefaults] doubleForKey:kUserDefaultsKey_CheckInterval] > 0) {
    [self checkForChanges:nil];
  }
}

static inline NSString* _FormatCommitCount(NSNumberFormatter* formatter, NSUInteger count) {
  if (count == 0) {
    return NSLocalizedString(@"0 commits", nil);
  } else if (count == 1) {
    return NSLocalizedString(@"1 commit", nil);
  }
  return [NSString stringWithFormat:NSLocalizedString(@"%@ commits", nil), [formatter stringFromNumber:@(count)]];
}

- (void)_updateTitleBar {
  [_windowController synchronizeWindowTitleWithDocumentName];
  NSUInteger totalCount = _repository.history.allCommits.count;
  NSString* countText = [NSString stringWithFormat:NSLocalizedString(@"%@", nil), _FormatCommitCount(_numberFormatter, totalCount)];
  _titleItem.primaryControl.stringValue = _windowController.window.title;
  _titleItem.secondaryControl.stringValue = countText;
  if (@available(macOS 11.0, *)) {
    _windowController.window.subtitle = countText;
  }
}

static NSString* _StringFromRepositoryState(GCRepositoryState state) {
  switch (state) {
    case kGCRepositoryState_None:
      return nil;
    case kGCRepositoryState_Merge:
      return NSLocalizedString(@"merge", nil);
    case kGCRepositoryState_Revert:
      return NSLocalizedString(@"revert", nil);
    case kGCRepositoryState_CherryPick:
      return NSLocalizedString(@"cherry-pick", nil);
    case kGCRepositoryState_Bisect:
      return NSLocalizedString(@"bisect", nil);
    case kGCRepositoryState_Rebase:
    case kGCRepositoryState_RebaseInteractive:
    case kGCRepositoryState_RebaseMerge:
      return NSLocalizedString(@"rebase", nil);
    case kGCRepositoryState_ApplyMailbox:
    case kGCRepositoryState_ApplyMailboxOrRebase:
      return NSLocalizedString(@"apply mailbox", nil);
  }
  XLOG_DEBUG_UNREACHABLE();
  return nil;
}

- (void)_updateStatusBar {
  if (_mapViewController.previewHistory) {
    _infoTextField1.font = [NSFont boldSystemFontOfSize:11];
    _infoTextField1.stringValue = NSLocalizedString(@"Snapshot Preview", nil);
    NSDate* date = _snapshotListViewController.selectedSnapshot.date;
    if (date) {
      _infoTextField2.stringValue = [_dateFormatter stringFromDate:date];
    } else {
      _infoTextField2.stringValue = NSLocalizedString(@"No snapshot selected", nil);
    }

    _pullButton.hidden = YES;
    _pushButton.hidden = YES;
  } else {
    BOOL isBehind = NO;
    NSString* state = [[_StringFromRepositoryState(_repository.state) capitalizedString] stringByAppendingString:NSLocalizedString(@" in progress", nil)];
    NSAttributedString* stateString = state ? [[NSAttributedString alloc] initWithString:state attributes:_stateAttributes] : nil;
    if (_repository.history.HEADDetached) {
      _infoTextField1.font = [NSFont boldSystemFontOfSize:11];
      _infoTextField1.stringValue = NSLocalizedString(@"Not on any branch", nil);

      if (stateString) {
        _infoTextField2.attributedStringValue = stateString;
      } else {
        if (_repository.history.HEADCommit) {
          _infoTextField2.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Detached HEAD at commit %@", nil), _repository.history.HEADCommit.shortSHA1];
        } else {
          _infoTextField2.stringValue = NSLocalizedString(@"Repository is empty", nil);
        }
      }
    } else {
      GCHistoryLocalBranch* branch = _repository.history.HEADBranch;
      GCBranch* upstream = branch.upstream;
      if (upstream) {
        CGFloat fontSize = _infoTextField1.font.pointSize;
        NSMutableAttributedString* string = [[NSMutableAttributedString alloc] init];
        [string beginEditing];
        [string appendString:NSLocalizedString(@"On branch ", nil) withAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:fontSize]}];
        [string appendString:branch.name withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
        [string appendString:NSLocalizedString(@" • tracking upstream ", nil) withAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:fontSize]}];
        [string appendString:upstream.name withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
        [string setAlignment:NSTextAlignmentCenter range:NSMakeRange(0, string.length)];
        [string endEditing];
        _infoTextField1.attributedStringValue = string;

        if (stateString) {
          _infoTextField2.attributedStringValue = stateString;
        } else {
          GCHistoryCommit* localTip = _repository.history.HEADCommit;
          GCHistoryCommit* upstreamTip = [(GCHistoryLocalBranch*)upstream tipCommit];
          if ([localTip isEqualToCommit:upstreamTip]) {
            _infoTextField2.stringValue = NSLocalizedString(@"Up-to-date", nil);
          } else {
            GCCommit* commit = [_repository findMergeBaseForCommits:@[ localTip, upstreamTip ] error:NULL];
            GCHistoryCommit* ancestor = commit ? [_repository.history historyCommitForCommit:commit] : nil;
            if (ancestor) {
              if ([ancestor isEqualToCommit:localTip]) {
                NSUInteger count = [_repository.history countAncestorCommitsFromCommit:upstreamTip toCommit:localTip];
                _infoTextField2.stringValue = [NSString stringWithFormat:NSLocalizedString(@" %@ behind", nil), _FormatCommitCount(_numberFormatter, count)];
                isBehind = YES;
              } else if ([ancestor isEqualToCommit:upstreamTip]) {
                NSUInteger count = [_repository.history countAncestorCommitsFromCommit:localTip toCommit:upstreamTip];
                _infoTextField2.stringValue = [NSString stringWithFormat:NSLocalizedString(@" %@ ahead", nil), _FormatCommitCount(_numberFormatter, count)];
              } else {
                NSUInteger count1 = [_repository.history countAncestorCommitsFromCommit:localTip toCommit:ancestor];
                NSUInteger count2 = [_repository.history countAncestorCommitsFromCommit:upstreamTip toCommit:ancestor];
                _infoTextField2.stringValue = [NSString stringWithFormat:NSLocalizedString(@" %@ ahead, %@ behind", nil), _FormatCommitCount(_numberFormatter, count1), _FormatCommitCount(_numberFormatter, count2)];
                isBehind = YES;
              }
            } else {
              _infoTextField2.stringValue = @"";
              XLOG_DEBUG_UNREACHABLE();
            }
          }
        }

        NSString* upstreamSHA1 = [_updatedReferences objectForKey:upstream.fullName];
        if (upstreamSHA1 && ![upstreamSHA1 isEqualToString:[[(GCHistoryLocalBranch*)upstream tipCommit] SHA1]]) {
          isBehind = YES;
        }
      } else {
        CGFloat fontSize = _infoTextField1.font.pointSize;
        NSMutableAttributedString* string = [[NSMutableAttributedString alloc] init];
        [string beginEditing];
        [string appendString:NSLocalizedString(@"On branch ", nil) withAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:fontSize]}];
        [string appendString:branch.name withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
        [string setAlignment:NSTextAlignmentCenter range:NSMakeRange(0, string.length)];
        [string endEditing];
        _infoTextField1.attributedStringValue = string;

        if (stateString) {
          _infoTextField2.attributedStringValue = stateString;
        } else {
          _infoTextField2.stringValue = NSLocalizedString(@"No upstream configured", nil);
        }
      }
    }

    _pullButton.hidden = NO;
    _pullButton.enabled = [_mapViewController validateUserInterfaceItem:(id)_pullButton];
    NSRect frame = _pullButton.frame;
    if (isBehind) {
      _pullButton.image = [NSImage imageNamed:@"icon_action_fetch_new"];
      _pullButton.toolTip = NSLocalizedString(@"Local tip is behind - pull current branch from upstream", nil);
      _pullButton.frame = NSMakeRect(frame.origin.x + frame.size.width - 53, frame.origin.y, 53, frame.size.height);
    } else {
      _pullButton.image = [NSImage imageNamed:@"icon_action_fetch"];
      _pullButton.frame = NSMakeRect(frame.origin.x + frame.size.width - 37, frame.origin.y, 37, frame.size.height);
    }
    _pushButton.hidden = NO;
    _pushButton.enabled = [_mapViewController validateUserInterfaceItem:(id)_pushButton];
  }
}

// NSToolbar automatic validation fires very often and at unpredictable times so we just do everything by hand
- (void)_updateToolBar {
  [_mainWindow.toolbar validateVisibleItems];
}

- (void)_didBecomeActive:(NSNotification*)notification {
  [_repository notifyRepositoryChanged];  // Make sure we are up-to-date right now

  if (_repository.automaticSnapshotsEnabled) {
    [_repository setUndoActionName:NSLocalizedString(@"External Changes", nil)];
    _repository.automaticSnapshotsEnabled = NO;
  }
}

- (void)_didResignActive:(NSNotification*)notification {
  if (![_windowMode isEqualToString:kWindowModeString_Map_Resolve]) {  // Don't take automatic snapshots while conflict resolver is on screen
    _repository.automaticSnapshotsEnabled = YES;
  }
}

- (void)_setWindowMode:(NSString*)mode {
  if (![_windowMode isEqualToString:mode]) {
    if ([_windowMode isEqualToString:kWindowModeString_Map]) {
      if (![_mainWindow.firstResponder isKindOfClass:[NSWindow class]]) {
        _savedFirstResponder = _mainWindow.firstResponder;
      } else {
        _savedFirstResponder = nil;
      }
    }

    _windowMode = mode;
    [_mainTabView selectTabViewItemWithIdentifier:_windowMode];

    // Don't let AppKit guess / restore first responder
    if ([_windowMode isEqualToString:kWindowModeString_Map]) {
      if (_savedFirstResponder) {
        [_mainWindow makeFirstResponder:_savedFirstResponder];
      } else {
        [_mainWindow makeFirstResponder:_mapViewController.preferredFirstResponder];
      }
    } else if ([_windowMode isEqualToString:kWindowModeString_Map_Rewrite]) {
      [_mainWindow makeFirstResponder:_commitRewriterViewController.preferredFirstResponder];
    } else if ([_windowMode isEqualToString:kWindowModeString_Map_Split]) {
      [_mainWindow makeFirstResponder:_commitSplitterViewController.preferredFirstResponder];
    } else if ([_windowMode isEqualToString:kWindowModeString_Map_Resolve]) {
      [_mainWindow makeFirstResponder:_conflictResolverViewController.preferredFirstResponder];
    } else {
      GIViewController* viewController = [(GIView*)_mainTabView.selectedTabViewItem.view viewController];
      [_mainWindow makeFirstResponder:viewController.preferredFirstResponder];
    }

    [self _updateTitleBar];
    [self _updateToolBar];

    if ([_windowMode isEqualToString:kWindowModeString_Map]) {
      if (_searchView.superview) {
        [self _showHelpWithIdentifier:kSideViewIdentifier_Search];
      } else if (_tagsView.superview) {
        [self _showHelpWithIdentifier:kSideViewIdentifier_Tags];
      } else if (_snapshotsView.superview) {
        [self _showHelpWithIdentifier:kSideViewIdentifier_Snapshots];
      } else if (_reflogView.superview) {
        [self _showHelpWithIdentifier:kSideViewIdentifier_Reflog];
      } else if (_ancestorsView.superview) {
        [self _showHelpWithIdentifier:kSideViewIdentifier_Ancestors];
      } else {
        [self _showHelpWithIdentifier:kWindowModeString_Map];
      }
    } else {
      [self _showHelpWithIdentifier:_windowMode];
    }
  }
}

- (BOOL)setWindowModeID:(WindowModeID)modeID {
  if (!_mainWindow.attachedSheet && !_navigateItem.primaryControl.hidden && _navigateItem.primaryControl.enabled) {
    [self _setWindowMode:_WindowModeStringFromID(modeID)];
    return YES;
  }
  return NO;
}

- (BOOL)shouldCloseDocument {
  if (_windowController.hasModalView) {
    NSBeep();
    return NO;
  }
  if ([_windowMode isEqualToString:kWindowModeString_Map_Rewrite] || [_windowMode isEqualToString:kWindowModeString_Map_Split] || [_windowMode isEqualToString:kWindowModeString_Map_Resolve]) {
    [_windowController showOverlayWithStyle:kGIOverlayStyle_Warning message:NSLocalizedString(@"You must finish or cancel before closing the repository", nil)];
    return NO;
  }
  if (_repository.hasBackgroundOperationInProgress) {
    [_windowController showOverlayWithStyle:kGIOverlayStyle_Warning message:NSLocalizedString(@"The repository cannot be closed while a remote operation is in progress", nil)];
    return NO;
  }
  if (_indexing) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Are you sure you want to close the repository?", nil);
    alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The repository \"%@\" is still being prepared for search. This can take up to a few minutes for large repositories.", nil), self.displayName];
    [alert addButtonWithTitle:NSLocalizedString(@"Close", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    alert.type = kGIAlertType_Caution;
    if ([alert runModal] == NSAlertSecondButtonReturn) {
      return NO;
    }
    _abortIndexing = YES;
  }
  return YES;
}

- (void)_showHelpWithIdentifier:(NSString*)identifier {
  BOOL showHelp = NO;
  NSDictionary* dictionary = [_helpPlist objectForKey:identifier];
  if (dictionary) {
    NSArray* array = [dictionary objectForKey:@"contents"];
    _helpIdentifier = identifier;
    _helpIndex = [[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat:@"HelpShown_%@", _helpIdentifier.uppercaseString]];  // For backward compatibility
    if (_helpIndex < (NSInteger)array.count) {
      _helpTextField.stringValue = array[_helpIndex];
      if (_helpIndex == (NSInteger)array.count - 1) {
        _helpURL = [NSURL URLWithString:[dictionary objectForKey:@"link"]];
        _helpContinueButton.hidden = YES;
        _helpDismissButton.hidden = NO;
        _helpOpenButton.hidden = NO;
      } else {
        _helpContinueButton.hidden = NO;
        _helpDismissButton.hidden = YES;
        _helpOpenButton.hidden = YES;
      }
      showHelp = YES;
    }
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
  if (showHelp) {
    NSRect contentBounds = _contentView.bounds;
    _helpView.hidden = NO;
    _mainTabView.frame = NSMakeRect(contentBounds.origin.x, contentBounds.origin.y, contentBounds.size.width, contentBounds.size.height - _helpView.frame.size.height);
  } else if (!_helpView.hidden) {
    _mainTabView.frame = _contentView.bounds;
    _helpView.hidden = YES;
  }
}

- (void)_hideHelp:(BOOL)open {
  [[NSUserDefaults standardUserDefaults] setInteger:(_helpIndex + 1) forKey:[NSString stringWithFormat:@"HelpShown_%@", _helpIdentifier.uppercaseString]];  // For backward compatibility

  if (open && _helpURL) {
    [[NSWorkspace sharedWorkspace] openURL:_helpURL];
  }

  [self _showHelpWithIdentifier:_helpIdentifier];
}

#pragma mark - QuickView

- (void)_loadMoreAncestors {
  if (![_quickViewAncestors iterateWithCommitBlock:^(GCHistoryCommit* commit, BOOL* stop) {
        [_quickViewCommits addObject:commit];
      }]) {
    _quickViewAncestors = nil;
  }
}

- (void)_loadMoreDescendants {
  if (![_quickViewDescendants iterateWithCommitBlock:^(GCHistoryCommit* commit, BOOL* stop) {
        [_quickViewCommits insertObject:commit atIndex:0];
        _quickViewIndex += 1;  // We insert commits before the index too!
      }]) {
    _quickViewDescendants = nil;
  }
}

- (void)_enterQuickViewWithHistoryCommit:(GCHistoryCommit*)commit commitList:(NSArray*)commitList {
  [_repository suspendHistoryUpdates];  // We don't want the the history to change while in QuickView because of the walkers

  _quickViewCommits = [[NSMutableArray alloc] init];
  if (commitList) {
    [_quickViewCommits addObjectsFromArray:commitList];
    _quickViewIndex = [_quickViewCommits indexOfObjectIdenticalTo:commit];
    XLOG_DEBUG_CHECK(_quickViewIndex != NSNotFound);
  } else {
    [_quickViewCommits addObject:commit];
    _quickViewIndex = 0;
    _quickViewAncestors = [_repository.history walkerForAncestorsOfCommits:@[ commit ]];
    [self _loadMoreAncestors];
    _quickViewDescendants = [_repository.history walkerForDescendantsOfCommits:@[ commit ]];
    [self _loadMoreDescendants];
  }

  _quickViewController.commit = commit;

  [self _setWindowMode:kWindowModeString_Map_QuickView];
}

- (BOOL)_hasPreviousQuickView {
  return (_quickViewIndex + 1 < _quickViewCommits.count);
}

- (void)_previousQuickView {
  _quickViewIndex += 1;
  GCHistoryCommit* commit = _quickViewCommits[_quickViewIndex];
  _quickViewController.commit = commit;
  if (_searchView.superview) {
    _searchResultsViewController.selectedCommit = commit;
  } else {
    [_mapViewController selectCommit:commit];
  }
  if (_quickViewIndex == _quickViewCommits.count - 1) {
    [self _loadMoreAncestors];
  }
  [self _updateToolBar];
}

- (BOOL)_hasNextQuickView {
  return (_quickViewIndex > 0);
}

- (void)_nextQuickView {
  _quickViewIndex -= 1;
  GCHistoryCommit* commit = _quickViewCommits[_quickViewIndex];
  _quickViewController.commit = commit;
  if (_searchView.superview) {
    _searchResultsViewController.selectedCommit = commit;
  } else {
    [_mapViewController selectCommit:commit];
  }
  if (_quickViewIndex == 0) {
    [self _loadMoreDescendants];
  }
  [self _updateToolBar];
}

- (void)_exitQuickView {
  _quickViewCommits = nil;
  _quickViewAncestors = nil;
  _quickViewDescendants = nil;

  [_repository resumeHistoryUpdates];

  [self _setWindowMode:kWindowModeString_Map];
}

#pragma mark - Diff

- (void)_enterDiffWithCommit:(GCCommit*)commit parentCommit:(GCCommit*)parentCommit {
  [_diffViewController setCommit:commit withParentCommit:parentCommit];
  [self _setWindowMode:kWindowModeString_Map_Diff];
}

- (void)_exitDiff {
  [self _setWindowMode:kWindowModeString_Map];

  [_diffViewController setCommit:nil withParentCommit:nil];  // Unload diff immediately
}

#pragma mark - Rewrite

- (void)_enterRewriteWithCommit:(GCHistoryCommit*)commit {
  _helpHEADDisabled = YES;

  NSError* error;
  if (![_commitRewriterViewController startRewritingCommit:commit error:&error]) {
    [self presentError:error];
    _helpHEADDisabled = NO;
    return;
  }

  [[NSProcessInfo processInfo] disableSuddenTermination];
  [self _setWindowMode:kWindowModeString_Map_Rewrite];
}

// TODO: Rather than a convoluted API to ensure we can remove the GICommitRewriterViewController from the view hierarchy before doing the actual rewrite in case we need to show the GIConflictResolverViewController,
// we should have a proper view controller system allowing to stack multiple view controllers
- (void)_exitRewriteWithMessage:(NSString*)message {
  [self _setWindowMode:kWindowModeString_Map];
  [[NSProcessInfo processInfo] enableSuddenTermination];

  NSError* error;
  if ((message && ![_commitRewriterViewController finishRewritingCommitWithMessage:message error:&error]) || (!message && ![_commitRewriterViewController cancelRewritingCommit:&error])) {
    [self presentError:error];
  }

  _helpHEADDisabled = NO;
}

#pragma mark - Split

- (void)_enterSplitWithCommit:(GCHistoryCommit*)commit {
  NSError* error;
  if (![_commitSplitterViewController startSplittingCommit:commit error:&error]) {
    [self presentError:error];
    return;
  }

  [[NSProcessInfo processInfo] disableSuddenTermination];
  [self _setWindowMode:kWindowModeString_Map_Split];
}

// TODO: Rather than a convoluted API to ensure we can remove the GICommitSplitterViewController from the view hierarchy before doing the actual rewrite in case we need to show the GIConflictResolverViewController,
// we should have a proper view controller system allowing to stack multiple view controllers
- (void)_exitSplitWithOldMessage:(NSString*)oldMessage newMessage:(NSString*)newMessage {
  [self _setWindowMode:kWindowModeString_Map];
  [[NSProcessInfo processInfo] enableSuddenTermination];

  if (oldMessage && newMessage) {
    NSError* error;
    if (![_commitSplitterViewController finishSplittingCommitWithOldMessage:oldMessage newMessage:newMessage error:&error]) {
      [self presentError:error];
    }
  } else {
    [_commitSplitterViewController cancelSplittingCommit];
  }
}

#pragma mark - Resolve

- (void)_enterResolveWithOurCommit:(GCCommit*)ourCommit theirCommit:(GCCommit*)theirCommit {
  _helpHEADDisabled = YES;

  _conflictResolverViewController.ourCommit = ourCommit;
  _conflictResolverViewController.theirCommit = theirCommit;

  [[NSProcessInfo processInfo] disableSuddenTermination];
  [self _setWindowMode:kWindowModeString_Map_Resolve];
}

- (void)_exitResolve {
  [self _setWindowMode:kWindowModeString_Map];
  [[NSProcessInfo processInfo] enableSuddenTermination];

  _conflictResolverViewController.ourCommit = nil;
  _conflictResolverViewController.theirCommit = nil;

  _helpHEADDisabled = NO;
}

#pragma mark - Config

- (void)_enterConfig {
  [self _setWindowMode:kWindowModeString_Map_Config];
}

- (void)_exitConfig {
  [self _setWindowMode:kWindowModeString_Map];
}

#pragma mark - Restoration

// This appears to be called by the NSDocumentController machinery whenever quitting the app even if -invalidateRestorableState was never called
- (void)encodeRestorableStateWithCoder:(NSCoder*)coder {
  [super encodeRestorableStateWithCoder:coder];

  // Restrict to non-modal modes
  [coder encodeObject:_WindowModeStringFromID(_WindowModeIDFromString(_windowMode)) forKey:kRestorableStateKey_WindowMode];
}

- (void)restoreStateWithCoder:(NSCoder*)coder {
  [super restoreStateWithCoder:coder];

  NSString* windowMode = [coder decodeObjectOfClass:[NSString class] forKey:kRestorableStateKey_WindowMode];
  if (windowMode) {
    [self _setWindowMode:windowMode];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }

  if (!_ready) {
    [self performSelector:@selector(_documentDidOpen:) withObject:[NSNull null] afterDelay:0.0];
    _ready = YES;
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

#pragma mark - NSToolbarDelegate

- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
  if (@available(macOS 11, *)) {
    return @[ _navigateItem.itemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, _snapshotsItem.itemIdentifier, _searchItem.itemIdentifier ];
  } else {
    return @[ _navigateItem.itemIdentifier, NSToolbarSpaceItemIdentifier, _titleItem.itemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, _snapshotsItem.itemIdentifier, _searchItem.itemIdentifier ];
  }
}

#pragma mark - NSTextFieldDelegate

// TODO: Should we do something with -insertNewline: i.e. Return key?
- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
  if (commandSelector == @selector(insertTab:)) {
    [_mainWindow selectNextKeyView:nil];
    return YES;
  }
  if (commandSelector == @selector(insertBacktab:)) {
    [_mainWindow selectPreviousKeyView:nil];
    return YES;
  }
  if (commandSelector == @selector(moveDown:)) {
    if (_searchResultsViewController.results.count) {
      [_mainWindow makeFirstResponder:_searchResultsViewController.preferredFirstResponder];
      _searchResultsViewController.selectedResult = _searchResultsViewController.results.firstObject;
      return YES;
    }
  }
  return NO;
}

#pragma mark - GCRepositoryDelegate

- (void)repository:(GCRepository*)repository willStartTransferWithURL:(NSURL*)url {
  [self.authenticationWindowController repository:repository willStartTransferWithURL:url];  // Forward to AuthenticationWindowController

  _infoTextField1.hidden = YES;
  _infoTextField2.hidden = YES;
  _progressTextField.hidden = NO;
  _progressIndicator.minValue = 0.0;
  _progressIndicator.maxValue = 1.0;
  _progressIndicator.indeterminate = YES;
  _progressIndicator.hidden = NO;
  [_progressIndicator startAnimation:nil];
}

- (BOOL)repository:(GCRepository*)repository requiresPlainTextAuthenticationForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password {
  return [self.authenticationWindowController repository:repository requiresPlainTextAuthenticationForURL:url user:user username:username password:password];  // Forward to AuthenticationWindowController
}

- (void)repository:(GCRepository*)repository updateTransferProgress:(float)progress transferredBytes:(NSUInteger)bytes {
  if (progress > 0.0) {
    _progressIndicator.indeterminate = NO;
    _progressIndicator.doubleValue = progress;
  }
}

- (void)repository:(GCRepository*)repository didFinishTransferWithURL:(NSURL*)url success:(BOOL)success {
  [_progressIndicator stopAnimation:nil];
  _progressTextField.hidden = YES;
  _progressIndicator.hidden = YES;
  _infoTextField1.hidden = NO;
  _infoTextField2.hidden = NO;

  [self.authenticationWindowController repository:repository didFinishTransferWithURL:url success:success];  // Forward to AuthenticationWindowController
}

#pragma mark - GCLiveRepositoryDelegate

- (void)repositoryDidUpdateState:(GCLiveRepository*)repository {
  [self _updateStatusBar];
}

- (void)repositoryDidUpdateHistory:(GCLiveRepository*)repository {
  [self _updateTitleBar];
  if (_tagsView.superview) {
    [self _reloadTagsView];
  } else if (_ancestorsView.superview) {
    [self _reloadAncestorsView];
  }
}

- (void)repository:(GCLiveRepository*)repository historyUpdateDidFailWithError:(NSError*)error {
  [self presentError:error];
}

- (void)repository:(GCLiveRepository*)repository stashesUpdateDidFailWithError:(NSError*)error {
  [self presentError:error];
}

- (void)repository:(GCLiveRepository*)repository statusUpdateDidFailWithError:(NSError*)error {
  [self presentError:error];
}

- (void)repository:(GCLiveRepository*)repository snapshotsUpdateDidFailWithError:(NSError*)error {
  [self presentError:error];
}

- (void)repositoryDidUpdateSearch:(GCLiveRepository*)repository {
  if (_searchView.superview) {
    [self performSearch:nil];
  }
}

- (void)repository:(GCLiveRepository*)repository searchUpdateDidFailWithError:(NSError*)error {
  [self presentError:error];
}

- (void)repositoryBackgroundOperationInProgressDidChange:(GCLiveRepository*)repository {
  [self _updateToolBar];
  [self _updateStatusBar];
}

- (void)repository:(GCLiveRepository*)repository undoOperationDidFailWithError:(NSError*)error {
  [self presentError:error];
}

#pragma mark - GIWindowControllerDelegate

- (BOOL)windowController:(GIWindowController*)controller handleKeyDown:(NSEvent*)event {
  BOOL handled = NO;
  if (![event isARepeat]) {
    NSString* characters = event.charactersIgnoringModifiers;
    if ([_windowMode isEqualToString:kWindowModeString_Map]) {
      if (event.keyCode == kGIKeyCode_Esc) {
        if (_tagsView.superview) {
          [self toggleTags:nil];
          handled = YES;
        } else if (_snapshotsView.superview) {
          [self toggleSnapshots:nil];
          handled = YES;
        } else if (_reflogView.superview) {
          [self toggleReflog:nil];
          handled = YES;
        } else if (_searchView.superview) {
          [self closeSearch:nil];
          handled = YES;
        } else if (_ancestorsView.superview) {
          [self toggleAncestors:nil];
          handled = YES;
        }
      } else if ([characters isEqualToString:@" "]) {
        if (_searchView.superview) {
          GCHistoryCommit* commit = _searchResultsViewController.selectedCommit;
          if (commit) {
            if (event.modifierFlags & NSEventModifierFlagOption) {
              [_mapViewController launchDiffToolWithCommit:commit otherCommit:commit.parents.firstObject];  // Use main-line
            } else {
              [self _enterQuickViewWithHistoryCommit:commit commitList:_searchResultsViewController.commits];
            }
            handled = YES;
          }
        } else if (_tagsView.superview) {
          GCHistoryCommit* commit = _tagsViewController.selectedCommit;
          if (commit) {
            if (event.modifierFlags & NSEventModifierFlagOption) {
              [_mapViewController launchDiffToolWithCommit:commit otherCommit:commit.parents.firstObject];  // Use main-line
            } else {
              [self _enterQuickViewWithHistoryCommit:commit commitList:_tagsViewController.commits];
            }
            handled = YES;
          }
        } else if (_reflogView.superview) {
          if (event.modifierFlags & NSEventModifierFlagOption) {
            [_windowController showOverlayWithStyle:kGIOverlayStyle_Help message:NSLocalizedString(@"External Diff is not available for reflog entries", nil)];
          } else {
            [_windowController showOverlayWithStyle:kGIOverlayStyle_Help message:NSLocalizedString(@"Quick View is not available for reflog entries", nil)];
          }
          handled = YES;
        } else if (_ancestorsView.superview) {
          GCHistoryCommit* commit = _ancestorsViewController.selectedCommit;
          if (commit) {
            if (event.modifierFlags & NSEventModifierFlagOption) {
              [_mapViewController launchDiffToolWithCommit:commit otherCommit:commit.parents.firstObject];  // Use main-line
            } else {
              [self _enterQuickViewWithHistoryCommit:commit commitList:_ancestorsViewController.commits];
            }
            handled = YES;
          }
        }
      } else if ([characters isEqualToString:@"i"]) {
        if (_reflogView.superview) {
          GCReflogEntry* entry = _unifiedReflogViewController.selectedReflogEntry;
          if (entry.fromCommit && entry.toCommit) {
            [self _enterDiffWithCommit:entry.toCommit parentCommit:entry.fromCommit];
            handled = YES;
          }
        }
      }

    } else if ([_windowMode isEqualToString:kWindowModeString_Map_QuickView]) {
      if ((event.keyCode == kGIKeyCode_Esc) || [characters isEqualToString:@" "]) {
        [self exit:nil];
        handled = YES;
      }

    } else if ([_windowMode isEqualToString:kWindowModeString_Map_Diff]) {
      if ((event.keyCode == kGIKeyCode_Esc) || [characters isEqualToString:@"i"]) {
        [self exit:nil];
        handled = YES;
      }

    } else if ([_windowMode isEqualToString:kWindowModeString_Map_Config]) {
      if (event.keyCode == kGIKeyCode_Esc) {
        [self exit:nil];
        handled = YES;
      }
    }
  }
  return handled;
}

- (void)windowControllerDidChangeHasModalView:(GIWindowController*)controller {
  [self _updateToolBar];
}

#pragma mark - GIMapViewControllerDelegate

- (void)mapViewControllerDidReloadGraph:(GIMapViewController*)controller {
  [self _updateStatusBar];

  if (_searchView.superview) {
    [self commitListViewControllerDidChangeSelection:nil];
  }

  id headBranch = _repository.history.HEADBranch;
  if (headBranch == nil) {
    headBranch = [NSNull null];
  }
  if (![_lastHEADBranch isEqual:headBranch]) {
    if (!_helpHEADDisabled) {
      if ([headBranch isKindOfClass:[GCHistoryLocalBranch class]]) {
        [_windowController showOverlayWithStyle:kGIOverlayStyle_Informational format:NSLocalizedString(@"You are now on branch \"%@\"", nil), [headBranch name]];
      } else if (headBranch == [NSNull null]) {
        [_windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"You are not on any branch anymore", nil)];
      }
    }
    _lastHEADBranch = headBranch;
  }
}

- (void)mapViewControllerDidChangeSelection:(GIMapViewController*)controller {
  if (_searchView.superview) {
    if (!_preventSelectionLoopback) {
      _preventSelectionLoopback = YES;
      _searchResultsViewController.selectedCommit = _mapViewController.selectedCommit;
      _preventSelectionLoopback = NO;
    }
  } else if (_tagsView.superview) {
    if (!_preventSelectionLoopback) {
      _preventSelectionLoopback = YES;
      _tagsViewController.selectedCommit = _mapViewController.selectedCommit;
      _preventSelectionLoopback = NO;
    }
  } else if (_ancestorsView.superview) {
    if (!_preventSelectionLoopback) {
      _preventSelectionLoopback = YES;
      _ancestorsViewController.selectedCommit = _mapViewController.selectedCommit;
      _preventSelectionLoopback = NO;
    }
  }
  if (![_windowMode isEqualToString:kWindowModeString_Map_QuickView]) {
    _quickViewController.commit = nil;
  }
}

- (void)mapViewController:(GIMapViewController*)controller quickViewCommit:(GCHistoryCommit*)commit {
  [self _enterQuickViewWithHistoryCommit:commit commitList:nil];
}

- (void)mapViewController:(GIMapViewController*)controller diffCommit:(GCHistoryCommit*)commit withOtherCommit:(GCHistoryCommit*)otherCommit {
  [self _enterDiffWithCommit:commit parentCommit:otherCommit];
}

- (void)mapViewController:(GIMapViewController*)controller rewriteCommit:(GCHistoryCommit*)commit {
  [self _enterRewriteWithCommit:commit];
}

- (void)mapViewController:(GIMapViewController*)controller splitCommit:(GCHistoryCommit*)commit {
  [self _enterSplitWithCommit:commit];
}

#pragma mark - GISnapshotListViewControllerDelegate

- (void)snapshotListViewControllerDidChangeSelection:(GISnapshotListViewController*)controller {
  GCSnapshot* snapshot = _snapshotListViewController.selectedSnapshot;
  if (snapshot) {
    NSError* error;
    GCHistory* history = [_repository loadHistoryFromSnapshot:snapshot usingSorting:kGCHistorySorting_None error:&error];
    if (history) {
      _mapViewController.previewHistory = history;
    } else {
      [self presentError:error];
    }
  } else {
    XLOG_DEBUG_UNREACHABLE();
    _mapViewController.previewHistory = nil;
  }
}

- (void)snapshotListViewController:(GISnapshotListViewController*)controller didRestoreSnapshot:(GCSnapshot*)snapshot {
  [self toggleSnapshots:nil];
}

#pragma mark - GIUnifiedReflogViewControllerDelegate

- (void)unifiedReflogViewControllerDidChangeSelection:(GIUnifiedReflogViewController*)controller {
  GCReflogEntry* entry = _unifiedReflogViewController.selectedReflogEntry;
  [_mapViewController selectCommit:entry.toCommit];
}

- (void)unifiedReflogViewController:(GIUnifiedReflogViewController*)controller didRestoreReflogEntry:(GCReflogEntry*)entry {
  [self toggleReflog:nil];
}

#pragma mark - GICommitListViewControllerDelegate

- (void)commitListViewControllerDidChangeSelection:(GICommitListViewController*)controller {
  if (!_preventSelectionLoopback) {
    GCHistoryCommit* commit = nil;
    if (_searchView.superview) {
      commit = _searchResultsViewController.selectedCommit;
    } else if (_tagsView.superview) {
      commit = _tagsViewController.selectedCommit;
    } else if (_ancestorsView.superview) {
      commit = _ancestorsViewController.selectedCommit;
    }
    if (commit) {  // Don't deselect commit in map if no commit is selected in the list
      _preventSelectionLoopback = YES;
      [_mapViewController selectCommit:commit];
      _preventSelectionLoopback = NO;
    }
  }

  if (((_searchView.superview && _searchResultsViewController.selectedResult) || (_tagsView.superview && _tagsViewController.selectedResult) || (_ancestorsView.superview && _ancestorsViewController.selectedResult)) && !_mapViewController.selectedCommit) {
    _hiddenWarningView.hidden = NO;
  } else {
    _hiddenWarningView.hidden = YES;
  }
}

#pragma mark - GICommitViewControllerDelegate

- (void)commitViewController:(GICommitViewController*)controller didCreateCommit:(GCCommit*)commit {
}

#pragma mark - GICommitRewriterViewControllerDelegate

- (void)commitRewriterViewControllerShouldFinish:(GICommitRewriterViewController*)controller withMessage:(NSString*)message {
  [self _exitRewriteWithMessage:message];
}

- (void)commitRewriterViewControllerShouldCancel:(GICommitRewriterViewController*)controller {
  [self _exitRewriteWithMessage:nil];
}

#pragma mark - GICommitSplitterViewControllerDelegate

- (void)commitSplitterViewControllerShouldFinish:(GICommitSplitterViewController*)controller withOldMessage:(NSString*)oldMessage newMessage:(NSString*)newMessage {
  [self _exitSplitWithOldMessage:oldMessage newMessage:newMessage];
}

- (void)commitSplitterViewControllerShouldCancel:(GICommitSplitterViewController*)controller {
  [self _exitSplitWithOldMessage:nil newMessage:nil];
}

#pragma mark - GIConflictResolverViewControllerDelegate

- (void)conflictResolverViewControllerShouldCancel:(GIConflictResolverViewController*)controller {
  _resolvingConflicts = -1;
}

- (void)conflictResolverViewControllerDidFinish:(GIConflictResolverViewController*)controller {
  _resolvingConflicts = 1;
}

#pragma mark - GIMergeConflictResolver

- (BOOL)resolveMergeConflictsWithOurCommit:(GCCommit*)ourCommit theirCommit:(GCCommit*)theirCommit {
  [self _enterResolveWithOurCommit:ourCommit theirCommit:theirCommit];

  // TODO: Is re-entering NSApp's event loop really AppKit-safe (it appears to partially break NSAnimationContext animations for instance)?
  _resolvingConflicts = 0;
  while (!_resolvingConflicts) {
    NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture] inMode:NSModalPanelRunLoopMode dequeue:YES];
    [NSApp sendEvent:event];
  }

  [self _exitResolve];

  return (_resolvingConflicts > 0);
}

#pragma mark - Actions

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  if (item.action == @selector(editSettings:)) {
    return YES;
  }
  if ((item.action == @selector(openInTerminal:)) || (item.action == @selector(openInFinder:))) {
    return YES;
  }
  if (item.action == @selector(openInHostingService:)) {
    GCHostingService service = kGCHostingService_Unknown;
    [_repository hostingURLForProject:&service error:NULL];  // Ignore errors
    switch (service) {
      case kGCHostingService_Unknown:
        [(NSMenuItem*)item setTitle:NSLocalizedString(@"Open in Hosting Service…", nil)];
        return NO;  // Must match title in the NIB
      default:
        [(NSMenuItem*)item setTitle:[NSString stringWithFormat:NSLocalizedString(@"Open in %@…", nil), GCNameFromHostingService(service)]];
        return YES;
    }
  }

  if (item.action == @selector(openSubmoduleMenu:)) {
    NSMenu* submenu = [(NSMenuItem*)item submenu];
    [submenu removeAllItems];
    NSArray* submodules = [_repository listSubmodules:NULL];
    if (submodules.count) {
      for (GCSubmodule* submodule in submodules) {
        NSMenuItem* menuItem = [[NSMenuItem alloc] initWithTitle:submodule.name action:@selector(_openSubmodule:) keyEquivalent:@""];
        menuItem.representedObject = submodule.name;  // Don't use "submodule" to avoid retaining it forever
        menuItem.target = self;
        [submenu addItem:menuItem];
      }
    } else {
      [submenu addItemWithTitle:NSLocalizedString(@"No Submodules in Repository", nil) action:NULL keyEquivalent:@""];
    }
    return YES;
  }

  if (_windowController.hasModalView) {
    return NO;
  }

  if ((item.action == @selector(focusSearch:)) || (item.action == @selector(performSearch:))) {
    return [_windowMode isEqualToString:kWindowModeString_Map] && !_tagsView.superview && !_snapshotsView.superview && !_reflogView.superview && !_ancestorsView.superview && _searchReady;
  }
  if (item.action == @selector(toggleTags:)) {
    return [_windowMode isEqualToString:kWindowModeString_Map] && !_searchView.superview && !_snapshotsView.superview && !_reflogView.superview && !_ancestorsView.superview ? YES : NO;
  }
  if (item.action == @selector(toggleSnapshots:)) {
    return [_windowMode isEqualToString:kWindowModeString_Map] && !_searchView.superview && !_tagsView.superview && !_reflogView.superview && !_ancestorsView.superview && _repository.snapshots.count ? YES : NO;
  }
  if (item.action == @selector(toggleReflog:)) {
    return [_windowMode isEqualToString:kWindowModeString_Map] && !_searchView.superview && !_tagsView.superview && !_snapshotsView.superview && !_ancestorsView.superview ? YES : NO;
  }
  if (item.action == @selector(toggleAncestors:)) {
    return [_windowMode isEqualToString:kWindowModeString_Map] && !_searchView.superview && !_tagsView.superview && !_snapshotsView.superview && !_reflogView.superview && _repository.history.HEADCommit ? YES : NO;
  }

  if (_repository.hasBackgroundOperationInProgress) {
    return NO;
  }

  if (item.action == @selector(resetHard:)) {
    return _repository.history.HEADCommit ? YES : NO;
  }

  if (item.action == @selector(switchMode:)) {
    NSSegmentedControl* modeControl = [(id<NSObject>)item isKindOfClass:NSSegmentedControl.self] ? (NSSegmentedControl*)item : nil;
    NSMenuItem* menuItem = [(id<NSObject>)item isKindOfClass:NSMenuItem.self] ? (NSMenuItem*)item : nil;
    BOOL isIncompatibleMode = !_WindowModeIsPrimary(_windowMode);

    modeControl.hidden = isIncompatibleMode;
    if (isIncompatibleMode) {
      return NO;
    }

    WindowModeID windowModeID = _WindowModeIDFromString(_windowMode);
    [modeControl selectSegmentWithTag:windowModeID];
    menuItem.state = menuItem.tag == windowModeID ? NSOnState : NSOffState;

    return !_windowController.hasModalView;
  }

  if (item.action == @selector(navigate:)) {
    NSSegmentedControl* navigateControl = (NSSegmentedControl*)item;
    BOOL isIncompatibleMode = _WindowModeIsPrimary(_windowMode);

    navigateControl.hidden = isIncompatibleMode;
    if (isIncompatibleMode) {
      return NO;
    }

    [navigateControl setEnabled:[_windowMode isEqualToString:kWindowModeString_Map_QuickView] || [_windowMode isEqualToString:kWindowModeString_Map_Diff] || [_windowMode isEqualToString:kWindowModeString_Map_Config] forSegment:kNavigationAction_Exit];
    [navigateControl setEnabled:[_windowMode isEqualToString:kWindowModeString_Map_QuickView] && [self _hasNextQuickView] forSegment:kNavigationAction_Next];
    [navigateControl setEnabled:[_windowMode isEqualToString:kWindowModeString_Map_QuickView] && [self _hasPreviousQuickView] forSegment:kNavigationAction_Previous];

    return YES;
  }
  if (item.action == @selector(selectPreviousCommit:)) {
    return [_windowMode isEqualToString:kWindowModeString_Map_QuickView] && [self _hasPreviousQuickView] ? YES : NO;
  }
  if (item.action == @selector(selectNextCommit:)) {
    return [_windowMode isEqualToString:kWindowModeString_Map_QuickView] && [self _hasNextQuickView] ? YES : NO;
  }

  if (item.action == @selector(checkForChanges:)) {
    return _checkingForChanges ? NO : YES;
  }

  if (item.action == @selector(editConfiguration:)) {
    return [_windowMode isEqualToString:kWindowModeString_Map];
  }

  return [super validateUserInterfaceItem:item];
}

- (IBAction)resetHard:(id)sender {
  _untrackedButton.state = NSOffState;
  NSAlert* alert = [[NSAlert alloc] init];
  alert.type = kGIAlertType_Stop;
  alert.messageText = NSLocalizedString(@"Are you sure you want to reset the index and working directory to the current checkout?", nil);
  alert.informativeText = NSLocalizedString(@"Any operation in progress (merge, rebase, etc...) will be aborted, and any uncommitted change, including in submodules, will be discarded.\n\nThis action cannot be undone.", nil);
  alert.accessoryView = _resetView;
  NSButton* reset = [alert addButtonWithTitle:NSLocalizedString(@"Reset", nil)];
  if (@available(macOS 11, *)) {
    reset.hasDestructiveAction = YES;
  }
  [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
  [alert beginSheetModalForWindow:_mainWindow
                completionHandler:^(NSInteger returnCode) {
                  if (returnCode == NSAlertFirstButtonReturn) {
                    NSError* error;
                    if (![_repository resetToHEAD:kGCResetMode_Hard error:&error] || (_untrackedButton.state && ![_repository cleanWorkingDirectory:&error]) || ![_repository updateAllSubmodulesResursively:YES error:&error]) {
                      [self presentError:error];
                    }
                    [_repository notifyRepositoryChanged];
                  }
                }];
}

- (IBAction)switchMode:(id)sender {
  if ([sender isKindOfClass:[NSMenuItem class]]) {
    [self _setWindowMode:_WindowModeStringFromID([(NSMenuItem*)sender tag])];
  } else {
    [self _setWindowMode:_WindowModeStringFromID([(NSSegmentedControl*)sender selectedSegment])];
  }
}

- (void)_addSideView:(NSView*)view withIdentifier:(NSString*)identifier completion:(dispatch_block_t)completion {
  NSRect contentFrame = _mapContainerView.bounds;
  NSRect mapFrame = _mapView.frame;
  NSRect viewFrame = view.frame;
  NSRect newMapFrame = NSMakeRect(0, mapFrame.origin.y, contentFrame.size.width - viewFrame.size.width, mapFrame.size.height);
  NSRect newViewFrame = NSMakeRect(contentFrame.size.width - viewFrame.size.width, mapFrame.origin.y, viewFrame.size.width, mapFrame.size.height);
  view.frame = NSOffsetRect(newViewFrame, viewFrame.size.width, 0);
  [_mapContainerView addSubview:view positioned:NSWindowAbove relativeTo:_mapView];

#if 0  // TODO: On 10.13, the first time the view is shown after animating, it is completely empty
  [NSAnimationContext beginGrouping];
  [[NSAnimationContext currentContext] setDuration:kSideViewAnimationDuration];
  if (completion) {
    [[NSAnimationContext currentContext] setCompletionHandler:^{
      completion();
    }];
  }
  [_mapView.animator setFrame:newMapFrame];
  [view.animator setFrame:newViewFrame];
  [NSAnimationContext endGrouping];
#else
  [_mapView setFrame:newMapFrame];
  [view setFrame:newViewFrame];
  if (completion) {
    completion();
  }
#endif
  [self _updateToolBar];

  [self _showHelpWithIdentifier:identifier];
}

- (void)_removeSideView:(NSView*)view completion:(dispatch_block_t)completion {
  NSRect contentFrame = _mapContainerView.bounds;
  NSRect mapFrame = _mapView.frame;
  NSRect newMapFrame = NSMakeRect(0, mapFrame.origin.y, contentFrame.size.width, mapFrame.size.height);
  NSRect viewFrame = view.frame;
  NSRect newViewFrame = NSOffsetRect(viewFrame, viewFrame.size.width, 0);

  [NSAnimationContext beginGrouping];
  [[NSAnimationContext currentContext] setDuration:kSideViewAnimationDuration];
  [[NSAnimationContext currentContext] setCompletionHandler:^{
    [view removeFromSuperview];
    [self _updateToolBar];
    if (completion) {
      completion();
    }
  }];
  [_mapView.animator setFrame:newMapFrame];
  [view.animator setFrame:newViewFrame];
  [NSAnimationContext endGrouping];

  [self _showHelpWithIdentifier:_windowMode];
}

- (void)_reloadTagsView {
  _tagsViewController.results = _repository.history.tags;  // TODO: Should we resort the tags?

  _preventSelectionLoopback = YES;
  _tagsViewController.selectedCommit = _mapViewController.selectedCommit;
  _preventSelectionLoopback = NO;
}

- (IBAction)toggleTags:(id)sender {
  if (_tagsView.superview) {
    [self _removeSideView:_tagsView
               completion:^{
                 _tagsViewController.results = nil;
               }];
    _hiddenWarningView.hidden = YES;  // Hide immediately
    [_mainWindow makeFirstResponder:_mapViewController.preferredFirstResponder];
  } else {
    [self _reloadTagsView];

    [_mainWindow makeFirstResponder:nil];  // Force end-editing in search field to avoid close button remaining around
    [self _addSideView:_tagsView withIdentifier:kSideViewIdentifier_Tags completion:NULL];
    [_mainWindow makeFirstResponder:_tagsViewController.preferredFirstResponder];
  }
}

- (IBAction)toggleSnapshots:(id)sender {
  if (_snapshotsView.superview) {
    [self setSnapshotToggleState:NSOffState];
    _mapViewController.previewHistory = nil;
    [self _removeSideView:_snapshotsView completion:NULL];
    [_mainWindow makeFirstResponder:_mapViewController.preferredFirstResponder];
  } else {
    [self setSnapshotToggleState:NSOnState];
    [_mainWindow makeFirstResponder:nil];  // Force end-editing in search field to avoid close button remaining around
    [self _addSideView:_snapshotsView withIdentifier:kSideViewIdentifier_Snapshots completion:NULL];
    [_mainWindow makeFirstResponder:_snapshotListViewController.preferredFirstResponder];
  }
}

- (void)setSnapshotToggleState:(NSControlStateValue)state {
  NSButton* button = (NSButton*)_snapshotsItem.view;
  if (![button isKindOfClass:[NSButton class]]) {
    XLOG_ERROR(@"This used to be a button, update this function if the layout has changed.");
    return;
  }

  [button setState:state];
}

- (IBAction)toggleReflog:(id)sender {
  if (_reflogView.superview) {
    _mapViewController.forceShowAllTips = NO;
    [self _removeSideView:_reflogView completion:NULL];
    [_mainWindow makeFirstResponder:_mapViewController.preferredFirstResponder];
  } else {
    [_mainWindow makeFirstResponder:nil];  // Force end-editing in search field to avoid close button remaining around
    _mapViewController.forceShowAllTips = YES;
    [self _addSideView:_reflogView withIdentifier:kSideViewIdentifier_Reflog completion:NULL];
    [_mainWindow makeFirstResponder:_unifiedReflogViewController.preferredFirstResponder];
  }
}

- (void)_reloadAncestorsView {
  NSMutableArray* commits = [[NSMutableArray alloc] init];
  [commits addObject:_repository.history.HEADCommit];
  [_repository.history walkAncestorsOfCommits:@[ _repository.history.HEADCommit ]
                                   usingBlock:^(GCHistoryCommit* commit, BOOL* stop) {
                                     [commits addObject:commit];
                                     if (commits.count == kMaxAncestorCommits) {
                                       *stop = YES;
                                     }
                                   }];
  _ancestorsViewController.results = commits;

  _preventSelectionLoopback = YES;
  _ancestorsViewController.selectedCommit = _mapViewController.selectedCommit;
  _preventSelectionLoopback = NO;
}

- (IBAction)toggleAncestors:(id)sender {
  if (_ancestorsView.superview) {
    [self _removeSideView:_ancestorsView
               completion:^{
                 _ancestorsViewController.results = nil;
               }];
    _hiddenWarningView.hidden = YES;  // Hide immediately
    [_mainWindow makeFirstResponder:_mapViewController.preferredFirstResponder];
  } else {
    [self _reloadAncestorsView];

    [_mainWindow makeFirstResponder:nil];  // Force end-editing in search field to avoid close button remaining around
    [self _addSideView:_ancestorsView withIdentifier:kSideViewIdentifier_Ancestors completion:NULL];
    [_mainWindow makeFirstResponder:_ancestorsViewController.preferredFirstResponder];
  }
}

- (IBAction)editConfiguration:(id)sender {
  [self _enterConfig];
}

- (void)_setSearchFieldPlaceholder:(NSString*)placeholder {
  _searchItem.searchField.placeholderString = placeholder;
}

- (IBAction)performSearch:(id)sender {
  NSString* query = _searchItem.searchField.stringValue;
  if (query.length) {
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    NSArray* results = [_repository findCommitsMatching:query];
    XLOG_VERBOSE(@"Searched %lu commits in \"%@\" for \"%@\" in %.3f seconds finding %lu matches", _repository.history.allCommits.count, _repository.repositoryPath, query, CFAbsoluteTimeGetCurrent() - time, results.count);

    _searchResultsViewController.results = results;
    if (_searchView.superview == nil) {
      [self _addSideView:_searchView withIdentifier:kSideViewIdentifier_Search completion:NULL];
    }
  } else {
    if (_searchView.superview) {
      _hiddenWarningView.hidden = YES;  // Hide immediately
      [self _removeSideView:_searchView
                 completion:^{
                   _searchResultsViewController.results = nil;
                 }];
    }

    [_mainWindow makeFirstResponder:_mapViewController.preferredFirstResponder];
  }
}

- (IBAction)focusSearch:(id)sender {
  [_searchItem beginSearchInteraction];
}

- (IBAction)closeSearch:(id)sender {
  _searchItem.searchField.stringValue = @"";
  [self performSearch:nil];
}

- (IBAction)navigate:(NSSegmentedControl*)sender {
  switch ((NavigationAction)sender.selectedSegment) {
    case kNavigationAction_Exit:
      [self exit:sender];
      break;
    case kNavigationAction_Next:
      [self selectNextCommit:sender];
      break;
    case kNavigationAction_Previous:
      [self selectPreviousCommit:sender];
      break;
  }
}

- (IBAction)exit:(id)sender {
  if ([_windowMode isEqualToString:kWindowModeString_Map_QuickView]) {
    [self _exitQuickView];
  } else if ([_windowMode isEqualToString:kWindowModeString_Map_Diff]) {
    [self _exitDiff];
  } else if ([_windowMode isEqualToString:kWindowModeString_Map_Config]) {
    [self _exitConfig];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (IBAction)selectPreviousCommit:(id)sender {
  [self _previousQuickView];
}

- (IBAction)selectNextCommit:(id)sender {
  [self _nextQuickView];
}

+ (BOOL)repository:(GCRepository*)repository requiresPlainTextAuthenticationForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password {
  return [KeychainAccessor loadPlainTextAuthenticationFormKeychainForURL:url user:user username:username password:password allowInteraction:NO];
}

- (IBAction)checkForChanges:(id)sender {
  CFRunLoopTimerSetNextFireDate(_checkTimer, HUGE_VALF);
  if (_repository) {
    _checkingForChanges = YES;
    NSString* path = _repository.repositoryPath;  // Avoid race-condition in case _repository is set to nil before block is executed
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSMutableDictionary* updatedReferences = [[NSMutableDictionary alloc] init];
      GCRepository* repository = [[GCRepository alloc] initWithExistingLocalRepository:path error:NULL];
      repository.delegate = (id<GCRepositoryDelegate>)self.class;  // Don't use self as we don't want to show progress UI nor authentication prompts
      for (GCRemote* remote in [repository listRemotes:NULL]) {
        @autoreleasepool {
          NSDictionary* added;
          NSDictionary* modified;
          NSDictionary* deleted;
          if (![repository checkForChangesInRemote:remote withOptions:kGCRemoteCheckOption_IncludeBranches addedReferences:&added modifiedReferences:&modified deletedReferences:&deleted error:NULL]) {
            break;
          }
          [updatedReferences addEntriesFromDictionary:added];
          [updatedReferences addEntriesFromDictionary:modified];
          [updatedReferences addEntriesFromDictionary:deleted];
        }
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        if (_repository) {
          _updatedReferences = updatedReferences;
          if (_updatedReferences.count) {
            [_windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"New commits are available from the repository remotes - Use Fetch to retrieve them", nil)];
            XLOG_VERBOSE(@"Repository is out-of-sync with its remotes: %@", _updatedReferences.allKeys);
          } else {
            if (sender) {
              [_windowController showOverlayWithStyle:kGIOverlayStyle_Informational message:NSLocalizedString(@"Repository is up-to-date", nil)];
            }
            XLOG_VERBOSE(@"Repository is up-to-date with its remotes");
          }

          _checkingForChanges = NO;
          [self _resetCheckTimer];
          [self _updateStatusBar];
        } else {
          XLOG_WARNING(@"Remote check completed after document was closed");
        }
      });
    });
  } else {
    XLOG_DEBUG_UNREACHABLE();  // Not sure how this can happen but it has in the field
  }
}

- (IBAction)openInHostingService:(id)sender {
  NSError* error;
  NSURL* url = [_repository hostingURLForProject:NULL error:&error];
  if (url) {
    [[NSWorkspace sharedWorkspace] openURL:url];
  } else {
    [self presentError:error];
  }
}

- (IBAction)openInFinder:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:_repository.workingDirectoryPath isDirectory:YES]];
}

// NOTE: To reset permissions via terminal:

// reset permissions of all apps in category AppleEvents ( Automation )
// $ tccutil reset AppleEvents

// reset all permissions for all apps
// $ tccutil reset All

// reset all permissions for particular bundle identifier.
// $ tccutil reset All co.gitup.mac-debug

- (NSString*)scriptForTerminalAppName:(NSString*)name {
  if ([name isEqualToString:GIPreferences_TerminalTool_Terminal]) {
    return [NSString stringWithFormat:
                         @""
                          "tell application \"%@\" \n"
                          ""
                          ""
                          "reopen \n"
                          ""
                          ""
                          "activate \n"
                          ""
                          ""
                          "do script \"cd \\\"%@\\\"\" \n"
                          ""
                          ""
                          "end tell \n"
                          "",
                         name, _repository.workingDirectoryPath];
  }
  /*
   -- if application is running, we already have a window.
   -- so, we create new window and write our command.
   -- otherwise, we reopen application, activate it and
    if application "iTerm" is running then
      tell application "iTerm"
        tell current session of (create window with default profile)
          set command to "cd '~/GitUp'"
          write text command
        end tell
        activate
      end tell
    else
      tell application "iTerm"
        reopen
        activate -- bring to front and also set current window to fresh window
        tell current session of current window
          select -- give focus to current window to start typing in it.
          set command to "cd '~/GitUp'"
          write text command
        end tell
      end tell
    end if
   */
  if ([name isEqualToString:GIPreferences_TerminalTool_iTerm] || [name isEqualToString:GIPreferences_TerminalTool_Terminal]) {
    NSString* command = [NSString stringWithFormat:@"cd '%@'", _repository.workingDirectoryPath];
    NSString* isRunningPhase = [NSString stringWithFormat:
                                             @""
                                              "tell application \"%@\" \n"
                                              ""
                                              ""
                                              "tell current session of (create window with default profile) \n"
                                              ""
                                              ""
                                              "set command to \"%@\" \n"
                                              ""
                                              ""
                                              "write text command \n"
                                              ""
                                              ""
                                              "end tell \n"
                                              ""
                                              ""
                                              "activate \n"
                                              ""
                                              ""
                                              "end tell \n"
                                              "",
                                             name, command];
    NSString* isNotRunningPhase = [NSString stringWithFormat:
                                                @""
                                                 "tell application \"%@\" \n"
                                                 ""
                                                 ""
                                                 "activate \n"
                                                 ""
                                                 ""
                                                 "tell current session of current window \n"
                                                 ""
                                                 ""
                                                 "select \n"
                                                 ""
                                                 ""
                                                 "set command to \"%@\" \n"
                                                 ""
                                                 ""
                                                 "write text command \n"
                                                 ""
                                                 ""
                                                 "end tell \n"
                                                 ""
                                                 ""
                                                 "end tell \n"
                                                 "",
                                                name, command];
    NSString* script = [NSString stringWithFormat:
                                     @""
                                      "if application \"%@\" is running then \n"
                                      ""
                                      ""
                                      " %@ \n"
                                      ""
                                      ""
                                      "else \n"
                                      ""
                                      ""
                                      " %@ \n"
                                      ""
                                      ""
                                      "end if \n"
                                      "",
                                     name, isRunningPhase, isNotRunningPhase];
    return script;
  }
  return nil;
}

- (void)openInTerminalAppName:(NSString*)name {
  NSString* script = [self scriptForTerminalAppName:name];

  if (script == nil) {
    NSUInteger code = 1000;
    NSDictionary* userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(@"Error occured! Unsupported key in user defaults for Preferred terminal app is occured. Key is", nil)};
    NSError* error = [NSError errorWithDomain:@"org.gitup.preferences.terminal" code:code userInfo:userInfo];
    [self presentError:error];
    return;
  }

  NSDictionary* dictionary = nil;
  [[[NSAppleScript alloc] initWithSource:script] executeAndReturnError:&dictionary];
  if (dictionary != nil) {
    NSString* message = (NSString*)dictionary[NSAppleScriptErrorMessage] ?: @"Unknown error!";
    // show error?
    NSInteger code = [dictionary[NSAppleScriptErrorNumber] integerValue];
    NSString* key = @"NSAppleEventsUsageDescription";
    NSString* recovery = [[NSBundle mainBundle] localizedStringForKey:key value:nil table:@"InfoPlist"];
    NSDictionary* userInfo = @{NSLocalizedDescriptionKey : message, NSLocalizedRecoveryOptionsErrorKey : recovery};
    NSError* error = [NSError errorWithDomain:@"com.apple.security.automation.appleEvents" code:code userInfo:userInfo];
    [self presentError:error];
  }
  //  [[NSWorkspace sharedWorkspace] launchApplication:name];
}

- (IBAction)openInTerminal:(id)sender {
  NSString* identifier = [[NSUserDefaults standardUserDefaults] stringForKey:GIPreferences_TerminalTool];
  [self openInTerminalAppName:identifier];
}

- (IBAction)dismissHelp:(id)sender {
  [self _hideHelp:NO];
}

- (IBAction)openHelp:(id)sender {
  [self _hideHelp:YES];
}

- (IBAction)openSubmoduleMenu:(id)sender {
  XLOG_DEBUG_UNREACHABLE();  // This action only exists to populate the menu in -validateUserInterfaceItem:
}

- (IBAction)_openSubmodule:(id)sender {
  [_mapViewController openSubmoduleWithApp:[(NSMenuItem*)sender representedObject]];
}

- (IBAction)editSettings:(id)sender {
  _indexDiffsButton.state = [[_repository userInfoForKey:kRepositoryUserInfoKey_IndexDiffs] boolValue];

  [_mainWindow beginSheet:_settingsWindow completionHandler:NULL];
}

- (IBAction)saveSettings:(id)sender {
  [NSApp endSheet:_settingsWindow];
  [_settingsWindow orderOut:nil];

  [_repository setUserInfo:(_indexDiffsButton.state ? @(YES) : @(NO)) forKey:kRepositoryUserInfoKey_IndexDiffs];
}

@end
