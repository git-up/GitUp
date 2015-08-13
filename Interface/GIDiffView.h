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

#import <AppKit/AppKit.h>

@class GIDiffView, GCDiffPatch;

@protocol GIDiffViewDelegate <NSObject>
- (void)diffViewDidChangeSelection:(GIDiffView*)view;
@end

// Base class
@interface GIDiffView : NSView <NSUserInterfaceValidations>
- (void)didFinishInitializing;  // For subclasses only
- (void)didUpdatePatch;  // For subclasses only

@property(nonatomic, assign) id<GIDiffViewDelegate> delegate;
@property(nonatomic, strong) NSColor* backgroundColor;
@property(nonatomic, strong) GCDiffPatch* patch;
@property(nonatomic, readonly, getter=isEmpty) BOOL empty;
- (CGFloat)updateLayoutForWidth:(CGFloat)width;

@property(nonatomic, readonly) BOOL hasSelection;
@property(nonatomic, readonly) BOOL hasSelectedText;
@property(nonatomic, readonly) BOOL hasSelectedLines;
- (void)clearSelection;
- (void)getSelectedText:(NSString**)text oldLines:(NSIndexSet**)oldLines newLines:(NSIndexSet**)newLines;
@end
