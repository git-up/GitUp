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

#import "NSColor+GINamedColors.h"
#import "NSBundle+GitUpKit.h"

@implementation NSColor (GINamedColors)

#define IMPLEMENT_NAMED_COLOR(__NAME__, __ASSET__, __RED__, __GREEN__, __BLUE__, __ALPHA__) \
  +(NSColor*)gitUp##__NAME__##Color {                                                       \
    if (@available(macOS 10.13, *)) {                                                       \
      NSBundle* bundle = NSBundle.gitUpKitBundle;                                           \
      return [NSColor colorNamed:@__ASSET__                                                 \
                          bundle:bundle];                                                   \
    } else {                                                                                \
      static dispatch_once_t once;                                                          \
      static NSColor* color;                                                                \
      dispatch_once(&once, ^{                                                               \
        color = [NSColor colorWithDeviceRed:__RED__                                         \
                                      green:__GREEN__                                       \
                                       blue:__BLUE__                                        \
                                      alpha:__ALPHA__];                                     \
      });                                                                                   \
      return color;                                                                         \
    }                                                                                       \
  }

#undef IMPLEMENT_NAMED_COLOR

@end
