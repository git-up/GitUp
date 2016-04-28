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

#import <objc/runtime.h>

#import "GIViewController.h"
#import "GIWindowController.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

@interface GIView ()
@property(nonatomic, assign) GIViewController* viewController;
@end

#define OVERRIDES_METHOD(m) (method_getImplementation(class_getInstanceMethod(self.class, @selector(m))) != method_getImplementation(class_getInstanceMethod([GIViewController class], @selector(m))))

@implementation GIView {
  __unsafe_unretained GIViewController* _viewController;  // This is required since redeclaring a read-only property as "assign" still makes it strong!
}

- (void)viewWillMoveToWindow:(NSWindow*)newWindow {
  [super viewWillMoveToWindow:newWindow];
  
  if (newWindow) {
    [_viewController viewWillShow];
  } else {
    [_viewController viewWillHide];
  }
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  
  if (self.window) {
    [_viewController viewDidShow];
  } else {
    [_viewController viewDidHide];
  }
}

- (void)setViewController:(GIViewController*)viewController {
  _viewController = viewController;
  [super setNextResponder:_viewController];
}

- (void)setNextResponder:(NSResponder*)nextResponder {
  [_viewController setNextResponder:nextResponder];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
  [super resizeSubviewsWithOldSize:oldSize];
  
  [_viewController viewDidResize];
}

- (void)viewWillStartLiveResize {
  [super viewWillStartLiveResize];
  
  [_viewController viewWillBeginLiveResize];
}

- (void)viewDidEndLiveResize {
  [super viewDidEndLiveResize];
  
  [_viewController viewDidFinishLiveResize];
}

@end

@implementation GIViewController {
  NSUndoManager* _textViewUndoManager;
}

@dynamic view;

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithNibName:nil bundle:nil])) {
    _repository = repository;
    _textViewUndoManager = [[NSUndoManager alloc] init];
    
    if (OVERRIDES_METHOD(repositoryDidChange)) {
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositoryDidChange) name:GCLiveRepositoryDidChangeNotification object:_repository];
    }
    if (OVERRIDES_METHOD(repositoryWorkingDirectoryDidChange)) {
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositoryWorkingDirectoryDidChange) name:GCLiveRepositoryWorkingDirectoryDidChangeNotification object:_repository];
    }
    if (OVERRIDES_METHOD(repositoryStateDidUpdate)) {
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositoryStateDidUpdate) name:GCLiveRepositoryStateDidUpdateNotification object:_repository];
    }
    if (OVERRIDES_METHOD(repositoryHistoryDidUpdate)) {
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositoryHistoryDidUpdate) name:GCLiveRepositoryHistoryDidUpdateNotification object:_repository];
    }
    if (OVERRIDES_METHOD(repositoryStashesDidUpdate)) {
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositoryStashesDidUpdate) name:GCLiveRepositoryStashesDidUpdateNotification object:_repository];
    }
    if (OVERRIDES_METHOD(repositoryStatusDidUpdate)) {
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositoryStatusDidUpdate) name:GCLiveRepositoryStatusDidUpdateNotification object:_repository];
    }
    if (OVERRIDES_METHOD(repositorySnapshotsDidUpdate)) {
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositorySnapshotsDidUpdate) name:GCLiveRepositorySnapshotsDidUpdateNotification object:_repository];
    }
    
    self.view.viewController = self;  // This loads the view
  }
  return self;
}

- (void)dealloc {
  self.view.viewController = nil;  // In case someone is still retaining the view
  
  if (OVERRIDES_METHOD(repositoryDidChange)) {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:GCLiveRepositoryDidChangeNotification object:self.repository];
  }
  if (OVERRIDES_METHOD(repositoryWorkingDirectoryDidChange)) {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:GCLiveRepositoryWorkingDirectoryDidChangeNotification object:self.repository];
  }
  if (OVERRIDES_METHOD(repositoryStateDidUpdate)) {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:GCLiveRepositoryStateDidUpdateNotification object:self.repository];
  }
  if (OVERRIDES_METHOD(repositoryHistoryDidUpdate)) {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:GCLiveRepositoryHistoryDidUpdateNotification object:self.repository];
  }
  if (OVERRIDES_METHOD(repositoryStashesDidUpdate)) {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:GCLiveRepositoryStashesDidUpdateNotification object:self.repository];
  }
  if (OVERRIDES_METHOD(repositoryStatusDidUpdate)) {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:GCLiveRepositoryStatusDidUpdateNotification object:self.repository];
  }
  if (OVERRIDES_METHOD(repositorySnapshotsDidUpdate)) {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:GCLiveRepositorySnapshotsDidUpdateNotification object:self.repository];
  }
}

- (void)loadView {
  XLOG_DEBUG_CHECK(!self.nibBundle && !self.nibName);
  Class nibClass = self.class;
  while (nibClass) {
    if ([[NSBundle bundleForClass:nibClass] loadNibNamed:NSStringFromClass(nibClass) owner:self topLevelObjects:NULL]) {
      break;
    }
    nibClass = nibClass.superclass;
  }
  XLOG_DEBUG_CHECK(self.view);
}

// Override super method so that the NSUndoManager is guaranteed to be the same and always around even when view is not visible
- (NSUndoManager*)undoManager {
  return _repository.undoManager;
}

- (BOOL)isViewVisible {
  return self.view.window != nil;
}

- (BOOL)isLiveResizing {
  return self.view.inLiveResize;
}

- (GIWindowController*)windowController {
  id controller = self.view.window.windowController;
  if ([controller isKindOfClass:[GIWindowController class]]) {
    return controller;
  }
  XLOG_DEBUG_UNREACHABLE();
  return nil;
}

- (void)presentAlert:(NSAlert*)alert completionHandler:(void (^)(NSInteger returnCode))handler {
  [alert beginSheetModalForWindow:self.view.window withCompletionHandler:handler];
}

#pragma mark - NSTextFieldDelegate

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
  if (commandSelector == @selector(insertTab:)) {
    [self.view.window selectNextKeyView:nil];
    return YES;
  }
  if (commandSelector == @selector(insertBacktab:)) {
    [self.view.window selectPreviousKeyView:nil];
    return YES;
  }
  return NO;
}

#pragma mark - NSTextViewDelegate

- (NSUndoManager*)undoManagerForTextView:(NSTextView*)view {
  return _textViewUndoManager;
}

- (BOOL)textView:(NSTextView*)textView doCommandBySelector:(SEL)selector {
  if (selector == @selector(insertTab:)) {
    [self.view.window selectNextKeyView:nil];
    return YES;
  }
  if (selector == @selector(insertBacktab:)) {
    [self.view.window selectPreviousKeyView:nil];
    return YES;
  }
  if (selector == @selector(cancelOperation:)) {  // Esc
    return [self.view.window.firstResponder.nextResponder tryToPerform:@selector(keyDown:) with:[NSApp currentEvent]];
  }
  return NO;
}

#pragma mark - NSTableViewDelegate

// Even if type selection is disabled, NSTableView still attemps to do it!
- (BOOL)tableView:(NSTableView*)tableView shouldTypeSelectForEvent:(NSEvent*)event withCurrentSearchString:(NSString*)searchString {
  return NO;
}

@end

@implementation GIViewController (Extensions)

- (void)presentAlertWithType:(GIAlertType)type title:(NSString*)title message:(NSString*)format, ... {
  NSString* message = nil;
  if (format) {
    va_list arguments;
    va_start(arguments, format);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
    message = [[NSString alloc] initWithFormat:format arguments:arguments];
#pragma clang diagnostic pop
    va_end(arguments);
  }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
  NSAlert* alert = [NSAlert alertWithMessageText:title defaultButton:NSLocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:(message ? message : @"")];
#pragma clang diagnostic pop
  alert.type = type;
  [self presentAlert:alert completionHandler:NULL];
}

- (void)confirmUserActionWithAlertType:(GIAlertType)type
                                 title:(NSString*)title
                               message:(NSString*)message
                                button:(NSString*)button
             suppressionUserDefaultKey:(NSString*)key
                                 block:(dispatch_block_t)block {
  if (key && [[NSUserDefaults standardUserDefaults] boolForKey:key]) {
    block();
  } else {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.type = type;
    alert.messageText = title;
    alert.informativeText = message;
    alert.showsSuppressionButton = key ? YES : NO;
    NSButton* defaultButton = [alert addButtonWithTitle:button];
    if (type == kGIAlertType_Danger) {
      defaultButton.keyEquivalent = @"";
    }
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    [self presentAlert:alert completionHandler:^(NSInteger returnCode) {
      
      if (returnCode == NSAlertFirstButtonReturn) {
        block();
      }
      if (alert.suppressionButton.state) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
      }
      
    }];
  }
}

@end

@implementation GIViewController (Subclassing)

static NSView* _PreferredFirstResponder(NSView* containerView) {
  for (NSView* view in containerView.subviews) {
    if ([view isKindOfClass:[NSSplitView class]]) {
      for (NSView* splitView in view.subviews) {
        NSView* tempView = _PreferredFirstResponder(splitView);
        if (tempView) {
          return tempView;
        }
      }
    } else {
      if ([view isKindOfClass:[GIView class]]) {
        return [[(GIView*)view viewController] preferredFirstResponder];
      }
      if ([view acceptsFirstResponder] && ([view isKindOfClass:[NSTextField class]] || [view isKindOfClass:[NSScrollView class]])) {
        return view;
      }
    }
  }
  return nil;
}

- (NSView*)preferredFirstResponder {
  NSView* view = _PreferredFirstResponder(self.view);
  XLOG_DEBUG_CHECK(view);
  return view;
}

- (void)viewWillShow {
  ;
}

- (void)viewDidShow {
  ;
}

- (void)viewWillHide {
  ;
}

- (void)viewDidHide {
  ;
}

- (void)viewDidResize {
  ;
}

- (void)viewWillBeginLiveResize {
  ;
}

- (void)viewDidFinishLiveResize {
  ;
}

- (void)repositoryDidChange {
  ;
}

- (void)repositoryWorkingDirectoryDidChange {
  ;
}

- (void)repositoryStateDidUpdate {
  ;
}

- (void)repositoryHistoryDidUpdate {
  ;
}

- (void)repositoryStashesDidUpdate {
  ;
}

- (void)repositoryStatusDidUpdate {
  ;
}

- (void)repositorySnapshotsDidUpdate {
  ;
}

@end
