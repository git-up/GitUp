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

#import "GIViewController.h"

#import "GCDiff.h"

extern NSString* const GIDiffContentsViewControllerUserDefaultKey_DiffViewMode;  // Integer (-1, 0 or 1)

@class GIDiffContentsViewController, GCIndexConflict;

@protocol GIDiffContentsViewControllerDelegate <NSObject>
@optional
- (CGFloat)diffContentsViewController:(GIDiffContentsViewController*)controller headerViewHeightForWidth:(CGFloat)width;
- (void)diffContentsViewControllerDidScroll:(GIDiffContentsViewController*)controller;
- (void)diffContentsViewControllerDidChangeSelection:(GIDiffContentsViewController*)controller;
- (BOOL)diffContentsViewController:(GIDiffContentsViewController*)controller handleKeyDownEvent:(NSEvent*)event;
- (NSMenu*)diffContentsViewController:(GIDiffContentsViewController*)controller willShowContextualMenuForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict;
- (NSString*)diffContentsViewController:(GIDiffContentsViewController*)controller actionButtonLabelForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict;
- (void)diffContentsViewController:(GIDiffContentsViewController*)controller didClickActionButtonForDelta:(GCDiffDelta*)delta conflict:(GCIndexConflict*)conflict;
@end

@interface GIDiffContentsViewController : GIViewController
@property(nonatomic, assign) id<GIDiffContentsViewControllerDelegate> delegate;
@property(nonatomic) BOOL showsUntrackedAsAdded;  // Default is NO
@property(nonatomic, copy) NSString* emptyLabel;
@property(nonatomic, strong) NSView* headerView;

@property(nonatomic, readonly) NSArray* deltas;
@property(nonatomic, readonly) NSDictionary* conflicts;
- (void)setDeltas:(NSArray*)deltas usingConflicts:(NSDictionary*)conflicts;

- (GCDiffDelta*)topVisibleDelta:(CGFloat*)offset;
- (void)setTopVisibleDelta:(GCDiffDelta*)delta offset:(CGFloat)offset;

- (BOOL)getSelectedLinesForDelta:(GCDiffDelta*)delta oldLines:(NSIndexSet**)oldLines newLines:(NSIndexSet**)newLines;
@end
