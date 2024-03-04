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
  });
  return colors;
}

#define IMPLEMENT_NAMED_COLOR(__NAME__, __ASSET__) \
  +(NSColor*)gitUp##__NAME__##Color {              \
    NSBundle* bundle = NSBundle.gitUpKitBundle;    \
    return [NSColor colorNamed:@__ASSET__          \
                        bundle:bundle];            \
  }

IMPLEMENT_NAMED_COLOR(Separator, "separator")
IMPLEMENT_NAMED_COLOR(DiffDeletedTextBackground, "diff/deleted_text_background")
IMPLEMENT_NAMED_COLOR(DiffDeletedTextHighlight, "diff/deleted_text_highlight")
IMPLEMENT_NAMED_COLOR(DiffAddedTextBackground, "diff/added_text_background")
IMPLEMENT_NAMED_COLOR(DiffAddedTextHighlight, "diff/added_text_highlight")
IMPLEMENT_NAMED_COLOR(DiffSeparatorBackground, "diff/separator_background")
IMPLEMENT_NAMED_COLOR(DiffConflictBackground, "diff/conflict_background")
IMPLEMENT_NAMED_COLOR(DiffAddedBackground, "diff/added_background")
IMPLEMENT_NAMED_COLOR(DiffModifiedBackground, "diff/modified_background")
IMPLEMENT_NAMED_COLOR(DiffDeletedBackground, "diff/deleted_background")
IMPLEMENT_NAMED_COLOR(DiffRenamedBackground, "diff/renamed_background")
IMPLEMENT_NAMED_COLOR(DiffUntrackedBackground, "diff/untracked_background")
IMPLEMENT_NAMED_COLOR(ConfigConflictBackground, "config/conflict_background")
IMPLEMENT_NAMED_COLOR(ConfigGlobalBackground, "config/global_background")
IMPLEMENT_NAMED_COLOR(ConfigHighlightBackground, "config/highlight_background")
IMPLEMENT_NAMED_COLOR(CommitHeaderBackground, "commit/header_background")

#undef IMPLEMENT_NAMED_COLOR

@end
