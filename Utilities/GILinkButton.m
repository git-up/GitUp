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

#import "GILinkButton.h"

@interface GILinkButton ()
@property(nonatomic, assign) id target;
@property(nonatomic) SEL action;
@end

@implementation GILinkButton {
  BOOL _highlighted;
}

@synthesize target, action;  // Required for pre-10.10

- (void)_initialize {
  _textAlignment = NSCenterTextAlignment;
  _textFont = [NSFont systemFontOfSize:[NSFont systemFontSize]];
  _linkColor = [NSColor darkGrayColor];
  _alternateLinkColor = [NSColor blackColor];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  if ((self = [super initWithFrame:frameRect])) {
    [self _initialize];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
  if ((self = [super initWithCoder:coder])) {
    [self _initialize];
  }
  return self;
}

- (void)mouseDown:(NSEvent*)event {
  NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
  if (NSPointInRect(location, self.bounds)) {
    _highlighted = YES;
    [self setNeedsDisplay:YES];
  }
}

- (void)mouseDragged:(NSEvent*)event {
  NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
  _highlighted = NSPointInRect(location, self.bounds);
  [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent*)event {
  if (_highlighted) {
    [NSApp sendAction:self.action to:self.target from:self];
    _highlighted = NO;
    [self setNeedsDisplay:YES];
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = _textAlignment;
  NSMutableDictionary* attributes = [[NSMutableDictionary alloc] init];
  [attributes setObject:style forKey:NSParagraphStyleAttributeName];
  [attributes setValue:_textFont forKey:NSFontAttributeName];
  [attributes setValue:(_highlighted ? _alternateLinkColor : _linkColor) forKey:NSForegroundColorAttributeName];
  [_link drawInRect:self.bounds withAttributes:attributes];
}

@end
