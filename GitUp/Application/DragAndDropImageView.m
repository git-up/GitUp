//  Copyright (C) 2015-2018 Pierre-Olivier Latour <info@pol-online.net>
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

#import "DragAndDropImageView.h"
#import "AppDelegate.h"

@interface DragAndDropImageView()
@property (nonatomic, assign) BOOL isHiglighted;
@end

@implementation DragAndDropImageView

- (void)awakeFromNib {
  [super awakeFromNib];
  [self registerForDraggedTypes:@[NSFilenamesPboardType]];
}

- (void)dealloc {
  [self unregisterDraggedTypes];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
  BOOL isDragOperationGeneric = (NSDragOperationGeneric & [sender draggingSourceOperationMask]) == NSDragOperationGeneric;
  NSPasteboard *pasteboard = [sender draggingPasteboard];
  if (isDragOperationGeneric && [self directoryURLFromPasteboard:pasteboard]) {
    self.isHiglighted = YES;
    return NSDragOperationGeneric;
  } else {
    return NSDragOperationNone;
  }
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
  self.isHiglighted = NO;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
  NSPasteboard *pasteboard = [sender draggingPasteboard];
  NSURL *directoryURL = [self directoryURLFromPasteboard:pasteboard];
  if (directoryURL) {
    AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
    [appDelegate openRepositoryWithURL:directoryURL];
    return YES;
  } else {
    return NO;
  }
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
  self.isHiglighted = NO;
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  if (self.isHiglighted) {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:dirtyRect xRadius:10 yRadius:10];
    // systemBlueColor from https://developer.apple.com/design/human-interface-guidelines/macos/visual-design/color/
    NSColor *higlightColor = [NSColor colorWithRed:27.0/255.0
                                             green:173.0/255.0
                                              blue:248.0/255.0
                                             alpha:0.2];
    [higlightColor set];
    [path fill];
  }
}

#pragma mark -

// Returns first directory URL from the given pasteboard
- (NSURL *)directoryURLFromPasteboard:(NSPasteboard *)pasteboard {
  NSString *desiredType = [pasteboard availableTypeFromArray:@[NSFilenamesPboardType]];
  if (![desiredType isEqualToString:NSFilenamesPboardType]) {
    return nil;
  }
  NSArray *filenames = [pasteboard propertyListForType:NSFilenamesPboardType];
  NSURL *url = [NSURL fileURLWithPath:[filenames firstObject]];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  BOOL isDirectory = NO;
  if ([fileManager fileExistsAtPath:[url path] isDirectory:&isDirectory] && isDirectory) {
    return url;
  } else {
    return nil;
  }
}

- (void)setIsHiglighted:(BOOL)isHiglighted {
  if (_isHiglighted != isHiglighted) {
    _isHiglighted = isHiglighted;

    [self setNeedsDisplay:YES];
  }
}

@end
