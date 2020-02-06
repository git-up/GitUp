//  Copyright (C) 2018 Rob Mayoff <gitup@rob.dqd.com>.
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

#import "ToolbarItemWrapperView.h"

@implementation ToolbarItemWrapperView

- (NSView*)hitTest:(NSPoint)point {
  // Normally, a double-click in a window title bar zooms the window on the second mouse-up. In a unified title/toolbar window, if a mouse-up hit-tests into a subview of a toolbar item, the mouse-up cannot zoom the window. This subclass selectively suppresses hits to allow a double-click to zoom its window.
  NSView* hit = [super hitTest:point];

  for (NSView* child = hit; child != nil && child != self; child = [child superview]) {
    if ([child isKindOfClass:[NSTextField class]]) {
      NSTextField* field = (NSTextField*)child;
      if (field.enabled && field.selectable) {
        return hit;
      }

      // We recognised the view but it is not enabled and selectable, so we need to break this loop iteration
      continue;
    }

    if ([child isKindOfClass:[NSControl class]]) {
      NSControl* control = (NSControl*)child;
      if (control.enabled) {
        return hit;
      }
    }

    if ([child isKindOfClass:[NSTextView class]]) {
      // The search field adds the field editor, an NSTextView, as a subview when it's being edited.
      NSTextView* textView = (NSTextView*)child;
      if (textView.selectable) {
        return hit;
      }
    }
  }

  return nil;
}

@end
