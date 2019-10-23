//
//  WelcomeWindow.m
//  Application
//
//  Created by Dmitry Lobanov on 10/09/2019.
//

#import "WelcomeWindow.h"

#import "AppDelegate.h"
#import "Document.h"

@interface AppDelegate (WelcomeWindow)
- (IBAction)closeWelcomeWindow:(id)sender;
- (void)_openRepositoryWithURL:(NSURL*)url withCloneMode:(CloneMode)cloneMode windowModeID:(WindowModeID)windowModeID;
@end

@interface WelcomeWindowView : NSView <NSDraggingDestination>

@property (weak, nonatomic, readonly) AppDelegate *appDelegate;
@property (weak, nonatomic) IBOutlet NSImageView *imageView;
@property (assign, nonatomic) BOOL receivingDrag;
@end

@implementation WelcomeWindowView

#pragma mark - Accessors
- (AppDelegate *)appDelegate {
  return [AppDelegate sharedDelegate];
}

#pragma mark - Setup
- (void)setup {
  [self.imageView unregisterDraggedTypes];
  [self registerForDraggedTypes:@[NSURLPboardType]];
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
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10];
    path.lineWidth = 5;
    [path stroke];
  }
}

#pragma mark - Dragging Data Extraction
- (BOOL)canDragItem:(id<NSDraggingInfo>)sender {
  return [self draggingItems:sender].count > 0;
}

- (NSArray <NSURL *>*)draggingItems:(id<NSDraggingInfo>)sender {
  return [[sender draggingPasteboard] readObjectsForClasses:@[NSURL.class] options:nil];
}

#pragma mark - NSDraggingDestination
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  BOOL canDragItem = [self canDragItem:sender];
  self.receivingDrag = canDragItem;
  return canDragItem ? NSDragOperationCopy :  NSDragOperationNone;
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
  
  NSURL *first = [self draggingItems:sender].firstObject;
  [self.appDelegate _openRepositoryWithURL:first withCloneMode:kCloneMode_None windowModeID:NSNotFound];
  
  return YES;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
  // necessary cleanup?
}
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

@interface WelcomeWindowControllerModel ()
@property (assign, nonatomic, readwrite) BOOL shouldShow;
@end

@implementation WelcomeWindowControllerModel
#pragma mark - Show
- (void)setShouldShow {
  self.shouldShow = YES;
}
- (void)setShouldHide {
  self.shouldShow = NO;
}
@end

@interface WelcomeWindowController ()
@property(nonatomic, weak) IBOutlet NSButton *closeButton;
@property(nonatomic, weak) IBOutlet NSPopUpButton* recentPopUpButton;
@property(nonatomic, weak) IBOutlet GILinkButton* twitterButton;
@property(nonatomic, weak) IBOutlet GILinkButton* forumsButton;

@property (weak, nonatomic, readonly) WelcomeWindow *welcomeWindow;
@property (strong, nonatomic, readwrite) WelcomeWindowControllerModel *model;
@end

@implementation WelcomeWindowController
- (WelcomeWindow *)welcomeWindow {
  return (WelcomeWindow *)self.window;
}
#pragma mark - Initialization
- (instancetype)init {
  return [[super initWithWindowNibName:@"Welcome"] configuredWithModel:[[WelcomeWindowControllerModel alloc] init]];
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
  self.forumsButton.action = @selector(viewIssues);
  
  self.closeButton.target = self;
  self.twitterButton.target = self;
  self.forumsButton.target = self;
}

#pragma mark - Window Lifecycle
- (void)windowDidLoad {
  [super windowDidLoad];
  WelcomeWindow *welcomeWindow = (WelcomeWindow *)self.window;
  welcomeWindow.configureItem = self.model.configureItem;
  welcomeWindow.getRecentDocuments = self.model.getRecentDocuments;
  
  [self setupUIElements];
}

#pragma mark - Configuration
- (instancetype)configuredWithModel:(WelcomeWindowControllerModel *)model {
  self.model = model;
  return self;
}

#pragma mark - Reactions
- (void)handleDocumentCountChanged {
  BOOL showWelcomeWindow = self.model.getUserDefaultsShouldShow();
  if (showWelcomeWindow && (self.model.shouldShow) && ![[[NSDocumentController sharedDocumentController] documents] count]) {
    if (!self.welcomeWindow.visible) {
      [self.welcomeWindow makeKeyAndOrderFront:nil];
    }
  } else {
    if (self.welcomeWindow.visible) {
      [self.welcomeWindow orderOut:nil];
    }
  }
}

#pragma mark - Actions
- (void)closeButtonPressed {
  [self.model setShouldHide];
  [self.window orderOut:nil];
}

#pragma mark - Actions/Recent
- (void)cleanupRecentEntries {
  NSMenu* menu = self.recentPopUpButton.menu;
  while (menu.numberOfItems > 1) {
    [menu removeItemAtIndex:1];
  }
}

- (void)willShowPopUpMenu {
  [self cleanupRecentEntries];
  NSMenu* menu = self.recentPopUpButton.menu;
  NSArray* array = self.model.getRecentDocuments(); // [[NSDocumentController sharedDocumentController] recentDocumentURLs];
  if (array.count) {
    for (NSURL* url in array) {
      NSString* path = url.path;
      NSString* title = path.lastPathComponent;
      for (NSMenuItem* item in menu.itemArray) {  // TODO: Handle identical second-to-last path component
        if ([item.title caseInsensitiveCompare:title] == NSOrderedSame) {
          title = [NSString stringWithFormat:@"%@ — %@", path.lastPathComponent, [[path stringByDeletingLastPathComponent] lastPathComponent]];
          path = [(NSURL*)item.representedObject path];
          item.title = [NSString stringWithFormat:@"%@ — %@", path.lastPathComponent, [[path stringByDeletingLastPathComponent] lastPathComponent]];
          break;
        }
      }
      NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
      item.representedObject = url;
      if (self.model.configureItem) {
        self.model.configureItem(item);
      }
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
  if (self.model.openTwitter) {
    self.model.openTwitter();
  }
}

- (void)viewIssues {
  if (self.model.viewIssues) {
    self.model.viewIssues();
  }
}
@end
