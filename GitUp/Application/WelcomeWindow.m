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

@interface WelcomeWindow ()
@property (weak, nonatomic, readonly) AppDelegate *appDelegate;
@property (weak, nonatomic, readwrite) IBOutlet WelcomeWindowView *destinationView;
@end

@implementation WelcomeWindow

#pragma mark - Accessors
- (AppDelegate *)appDelegate {
  return [AppDelegate sharedDelegate];
}

#pragma mark - Setup
- (void)setup {
  self.opaque = NO;
  self.backgroundColor = [NSColor clearColor];
  self.movableByWindowBackground = YES;
}

- (void)awakeFromNib {
  [self setup];
}

#pragma mark - Actions
- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
  return menuItem.action == @selector(performClose:) ? YES : [super validateMenuItem:menuItem];
}

- (void)performClose:(id)sender {
  [self.appDelegate closeWelcomeWindow:sender];
}

#pragma mark - Window
- (BOOL)canBecomeKeyWindow {
  return YES;
}

@end
