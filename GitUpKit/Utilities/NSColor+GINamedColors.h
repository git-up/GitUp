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

#import "GIAppKit.h"

@interface NSColor (GINamedColors)

@property(class, strong, readonly) NSArray<NSColor*>* gitUpGraphAlternatingBranchColors;

@property(class, strong, readonly) NSColor* gitUpSeparatorColor;

@property(class, strong, readonly) NSColor* gitUpDiffDeletedTextBackgroundColor;
@property(class, strong, readonly) NSColor* gitUpDiffDeletedTextHighlightColor;
@property(class, strong, readonly) NSColor* gitUpDiffAddedTextBackgroundColor;
@property(class, strong, readonly) NSColor* gitUpDiffAddedTextHighlightColor;
@property(class, strong, readonly) NSColor* gitUpDiffSeparatorBackgroundColor;

@property(class, strong, readonly) NSColor* gitUpDiffConflictBackgroundColor;
@property(class, strong, readonly) NSColor* gitUpDiffAddedBackgroundColor;
@property(class, strong, readonly) NSColor* gitUpDiffModifiedBackgroundColor;
@property(class, strong, readonly) NSColor* gitUpDiffDeletedBackgroundColor;
@property(class, strong, readonly) NSColor* gitUpDiffRenamedBackgroundColor;
@property(class, strong, readonly) NSColor* gitUpDiffUntrackedBackgroundColor;

@property(class, strong, readonly) NSColor* gitUpConfigConflictBackgroundColor;
@property(class, strong, readonly) NSColor* gitUpConfigGlobalBackgroundColor;
@property(class, strong, readonly) NSColor* gitUpConfigHighlightBackgroundColor;

@end
