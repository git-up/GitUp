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

#import "GIPrivate.h"

#if __GI_HAS_APPKIT__

@implementation NSScrollView (GIPrivate)

- (void)scrollToPoint:(NSPoint)point {
  NSClipView* clipView = self.contentView;
  [clipView setBoundsOrigin:point];
}

- (void)scrollToVisibleRect:(NSRect)rect {
  NSClipView* clipView = self.contentView;
  NSRect bounds = clipView.bounds;
  if (rect.origin.x < bounds.origin.x) {
    bounds.origin.x = rect.origin.x;
  } else if (rect.origin.x + rect.size.width > bounds.origin.x + bounds.size.width) {
    bounds.origin.x = rect.origin.x + rect.size.width - bounds.size.width;
  }
  if (rect.origin.y < bounds.origin.y) {
    bounds.origin.y = rect.origin.y;
  } else if (rect.origin.y + rect.size.height > bounds.origin.y + bounds.size.height) {
    bounds.origin.y = rect.origin.y + rect.size.height - bounds.size.height;
  }
  [clipView setBoundsOrigin:bounds.origin];
}

@end

#endif
