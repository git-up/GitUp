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

#import "GIColorView.h"

@implementation GIColorView

- (void)setBackgroundColor:(NSColor*)color {
  _backgroundColor = color;
  
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  if (_backgroundColor) {
    [_backgroundColor setFill];
    NSRectFill(dirtyRect);
  }
}

@end
