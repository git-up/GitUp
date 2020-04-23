//
//  WelcomeWindowController.m
//  Application
//
//  Created by Dmitry Lobanov on 10/09/2019.
//

#import "WelcomeWindowController.h"

#define kURL_Twitter @"https://twitter.com/GitUpApp"

@interface WelcomeWindowView : NSView <NSDraggingDestination>

// Drag and Drop
@property(weak, nonatomic) IBOutlet NSImageView* imageView;
@property(assign, nonatomic) BOOL receivingDrag;

// Open document
@property(copy, nonatomic) void (^openDocumentAtURL)(NSURL* url);
@end

@implementation WelcomeWindowView

#pragma mark - Setup
- (void)setup {
  [self.imageView unregisterDraggedTypes];
  [self registerForDraggedTypes:@[ NSURLPboardType ]];
}

- (void)awakeFromNib {
  [super awakeFromNib];
  [self setup];
}

#pragma mark - Drawing
- (void)setReceivingDrag:(BOOL)receivingDrag {
  _receivingDrag = receivingDrag;
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  if (self.receivingDrag) {
    [NSColor.selectedControlColor set];
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10];
    path.lineWidth = 5;
    [path stroke];
  }
}

#pragma mark - Dragging Data Extraction
- (BOOL)canDragItem:(id<NSDraggingInfo>)sender {
  return [self draggingItems:sender].count > 0;
}

- (NSArray<NSURL*>*)draggingItems:(id<NSDraggingInfo>)sender {
  return [[sender draggingPasteboard] readObjectsForClasses:@[ NSURL.class ] options:nil];
}

#pragma mark - NSDraggingDestination
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  BOOL canDragItem = [self canDragItem:sender];
  self.receivingDrag = canDragItem;
  return canDragItem ? NSDragOperationCopy : NSDragOperationNone;
}

- (void)draggingEnded:(id<NSDraggingInfo>)sender {
  self.receivingDrag = NO;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
  self.receivingDrag = NO;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
  return [self canDragItem:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  self.receivingDrag = NO;

  NSURL* url = [self draggingItems:sender].firstObject;

  if (self.openDocumentAtURL) {
    self.openDocumentAtURL(url);
  }

  return YES;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
  // necessary cleanup?
}
@end

@interface WelcomeWindow : NSWindow
@end

@implementation WelcomeWindow

#pragma mark - Setup
- (void)setup {
  self.opaque = NO;
  self.backgroundColor = [NSColor clearColor];
  self.movableByWindowBackground = YES;
}

- (void)awakeFromNib {
  [self setup];
}

#pragma mark - Window
- (BOOL)canBecomeKeyWindow {
  return YES;
}

@end

typedef NS_ENUM(NSInteger, WelcomeWindowControllerWindowState) {
  WelcomeWindowControllerWindowStateNotActivated,
  WelcomeWindowControllerWindowStateClosed,
  WelcomeWindowControllerWindowStateShouldBeOpened
};

@interface WelcomeWindowController ()
@property(nonatomic, weak) IBOutlet NSButton* closeButton;
@property(nonatomic, weak) IBOutlet NSPopUpButton* recentPopUpButton;
@property(nonatomic, weak) IBOutlet GILinkButton* twitterButton;
@property(nonatomic, weak) IBOutlet GILinkButton* forumsButton;
@property(nonatomic, weak) IBOutlet WelcomeWindowView* destinationView;
@property(assign, nonatomic, readwrite) WelcomeWindowControllerWindowState state;
@end

@implementation WelcomeWindowController
#pragma mark - States
#pragma mark - States / Setters
- (void)setShouldShow {
  self.state = WelcomeWindowControllerWindowStateShouldBeOpened;
}
- (void)setShouldHide {
  self.state = WelcomeWindowControllerWindowStateClosed;
}

#pragma mark - States / Getters
- (BOOL)notActivedYet {
  return self.state == WelcomeWindowControllerWindowStateNotActivated;
}
- (BOOL)shouldShow {
  return self.state == WelcomeWindowControllerWindowStateShouldBeOpened;
}

#pragma mark - Initialization
- (instancetype)init {
  return [super initWithWindowNibName:@"WelcomeWindowController"];
}

#pragma mark - Setup
- (void)setupUIElements {
  self.twitterButton.textAlignment = NSLeftTextAlignment;
  self.twitterButton.textFont = [NSFont boldSystemFontOfSize:11];
  self.forumsButton.textAlignment = NSLeftTextAlignment;
  self.forumsButton.textFont = [NSFont boldSystemFontOfSize:11];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willShowPopUpMenu) name:NSPopUpButtonWillPopUpNotification object:self.recentPopUpButton];

  self.closeButton.action = @selector(closeButtonPressed);
  self.twitterButton.action = @selector(openTwitter);

  self.closeButton.target = self;
  self.twitterButton.target = self;

  self.destinationView.openDocumentAtURL = self.openDocumentAtURL;
}

#pragma mark - Window Lifecycle
- (void)windowDidLoad {
  [super windowDidLoad];
  [self setupUIElements];
}

#pragma mark - Reactions
- (void)handleDocumentCountChanged {
  BOOL showWelcomeWindow = [NSUserDefaults.standardUserDefaults boolForKey:self.keyShouldShowWindow];
  if (showWelcomeWindow && (self.shouldShow) && !NSDocumentController.sharedDocumentController.documents.count) {
    [self showWindow:nil];
  } else {
    [self close];
  }
}

#pragma mark - Actions/Close
- (void)closeButtonPressed {
  [self setShouldHide];
  [self close];
}

#pragma mark - Actions/Recent
- (void)cleanupRecentEntries {
  NSMenu* menu = self.recentPopUpButton.menu;
  NSMenuItem* item = menu.itemArray.firstObject;
  [menu removeAllItems];
  if (item) {
    [menu addItem:item];
  }
}

- (void)didPressPopUpItem:(NSMenuItem*)item {
  if ([item.representedObject isKindOfClass:NSURL.class]) {
    if (self.openDocumentAtURL) {
      self.openDocumentAtURL(item.representedObject);
    }
  }
}

- (void)willShowPopUpMenu {
  [self cleanupRecentEntries];
  NSMenu* menu = self.recentPopUpButton.menu;
  NSArray* array = NSDocumentController.sharedDocumentController.recentDocumentURLs;
  if (array.count) {
    for (NSURL* url in array) {
      NSString* path = url.path;
      NSString* title = path.lastPathComponent;
      for (NSMenuItem* item in menu.itemArray) {  // TODO: Handle identical second-to-last path component
        if ([item.title caseInsensitiveCompare:title] == NSOrderedSame) {
          title = [NSString stringWithFormat:@"%@ — %@", path.lastPathComponent, path.stringByDeletingLastPathComponent.lastPathComponent];
          path = [(NSURL*)item.representedObject path];
          item.title = [NSString stringWithFormat:@"%@ — %@", path.lastPathComponent, path.stringByDeletingLastPathComponent.lastPathComponent];
          break;
        }
      }
      NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
      item.representedObject = url;
      item.target = self;
      item.action = @selector(didPressPopUpItem:);
      [menu addItem:item];
    }
  } else {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Repositories", nil) action:NULL keyEquivalent:@""];
    item.enabled = NO;
    [menu addItem:item];
  }
}

#pragma mark - Actions/Twitter&Issues
- (void)openTwitter {
  [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:kURL_Twitter]];
}

@end
