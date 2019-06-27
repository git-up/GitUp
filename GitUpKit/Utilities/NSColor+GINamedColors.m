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

+ (NSArray*)gitUpGraphAlternatingBranchColors {
  static dispatch_once_t once;
  static NSArray* colors;
  dispatch_once(&once, ^{
    if (@available(macOS 10.13, *)) {
      NSBundle* bundle = NSBundle.gitUpKitBundle;
      colors = @[
        [NSColor colorNamed:@"branch/1"
                     bundle:bundle],
        [NSColor colorNamed:@"branch/2"
                     bundle:bundle],
        [NSColor colorNamed:@"branch/3"
                     bundle:bundle],
        [NSColor colorNamed:@"branch/4"
                     bundle:bundle],
        [NSColor colorNamed:@"branch/5"
                     bundle:bundle],
        [NSColor colorNamed:@"branch/6"
                     bundle:bundle],
        [NSColor colorNamed:@"branch/7"
                     bundle:bundle],
        [NSColor colorNamed:@"branch/8"
                     bundle:bundle]
      ];
    } else {
      colors = @[
        [NSColor colorWithDeviceRed:0.9
                              green:0.5355
                               blue:0.5355
                              alpha:1],
        [NSColor colorWithDeviceRed:0.9
                              green:0.7137
                               blue:0.495
                              alpha:1],
        [NSColor colorWithDeviceRed:0.9
                              green:0.801
                               blue:0.45
                              alpha:1],
        [NSColor colorWithDeviceRed:0.508194
                              green:0.81
                               blue:0.48195
                              alpha:1],
        [NSColor colorWithDeviceRed:0.495
                              green:0.9
                               blue:0.8514
                              alpha:1],
        [NSColor colorWithDeviceRed:0.495
                              green:0.6813
                               blue:0.9
                              alpha:1],
        [NSColor colorWithDeviceRed:0.75208
                              green:0.544
                               blue:0.85
                              alpha:1],
        [NSColor colorWithDeviceRed:0.9
                              green:0.55575
                               blue:0.741645
                              alpha:1]
      ];
    }
  });
  return colors;
}

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

IMPLEMENT_NAMED_COLOR(Separator, "separator", 0, 0, 0, 0.2)
IMPLEMENT_NAMED_COLOR(DiffDeletedTextBackground, "diff/deleted_text_background", 1, 0.9, 0.9, 1)
IMPLEMENT_NAMED_COLOR(DiffDeletedTextHighlight, "diff/deleted_text_highlight", 1, 0.7, 0.7, 1)
IMPLEMENT_NAMED_COLOR(DiffAddedTextBackground, "diff/added_text_background", 0.85, 1, 0.85, 1)
IMPLEMENT_NAMED_COLOR(DiffAddedTextHighlight, "diff/added_text_highlight", 0.7, 1, 0.7, 1)
IMPLEMENT_NAMED_COLOR(DiffSeparatorBackground, "diff/separator_background", 0.97, 0.97, 0.97, 1)
IMPLEMENT_NAMED_COLOR(DiffConflictBackground, "diff/conflict_background", 1, 0.59, 0.15, 1)
IMPLEMENT_NAMED_COLOR(DiffAddedBackground, "diff/added_background", 0.475, 0.687, 1, 1)
IMPLEMENT_NAMED_COLOR(DiffModifiedBackground, "diff/modified_background", 0.609, 0.798, 0.501, 1)
IMPLEMENT_NAMED_COLOR(DiffDeletedBackground, "diff/deleted_background", 1, 0.627, 0.63, 1)
IMPLEMENT_NAMED_COLOR(DiffRenamedBackground, "diff/renamed_background", 0.656, 0.547, 0.759, 1)
IMPLEMENT_NAMED_COLOR(DiffUntrackedBackground, "diff/untracked_background", 0.75, 0.75, 0.75, 1)
IMPLEMENT_NAMED_COLOR(ConfigConflictBackground, "config/conflict_background", 1, 0.95, 0.95, 1)
IMPLEMENT_NAMED_COLOR(ConfigGlobalBackground, "config/global_background", 0.95, 1, 0.95, 1)
IMPLEMENT_NAMED_COLOR(ConfigHighlightBackground, "config/highlight_background", 1, 1, 0, 0.5)

#undef IMPLEMENT_NAMED_COLOR

@end
