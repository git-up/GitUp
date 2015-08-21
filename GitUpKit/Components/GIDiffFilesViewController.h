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

@class GIDiffFilesViewController;

@protocol GIDiffFilesViewControllerDelegate <NSObject>
@optional
- (void)diffFilesViewControllerDidBecomeFirstResponder:(GIDiffFilesViewController*)controller;
- (void)diffFilesViewControllerDidChangeSelection:(GIDiffFilesViewController*)controller;
- (void)diffFilesViewController:(GIDiffFilesViewController*)controller didDoubleClickDeltas:(NSArray*)deltas;
- (BOOL)diffFilesViewController:(GIDiffFilesViewController*)controller handleKeyDownEvent:(NSEvent*)event;
- (void)diffFilesViewController:(GIDiffFilesViewController*)controller willSelectDelta:(GCDiffDelta*)delta;
- (BOOL)diffFilesViewControllerShouldAcceptDeltas:(GIDiffFilesViewController*)controller fromOtherController:(GIDiffFilesViewController*)otherController;
- (BOOL)diffFilesViewController:(GIDiffFilesViewController*)controller didReceiveDeltas:(NSArray*)deltas fromOtherController:(GIDiffFilesViewController*)otherController;
@end

@interface GIDiffFilesViewController : GIViewController
@property(nonatomic, assign) id<GIDiffFilesViewControllerDelegate> delegate;
@property(nonatomic) BOOL showsUntrackedAsAdded;  // Default is NO
@property(nonatomic, copy) NSString* emptyLabel;
@property(nonatomic) BOOL allowsMultipleSelection;  // Default is NO

@property(nonatomic, readonly) NSArray* deltas;
@property(nonatomic, readonly) NSDictionary* conflicts;
- (void)setDeltas:(NSArray*)deltas usingConflicts:(NSDictionary*)conflicts;

@property(nonatomic, assign) GCDiffDelta* selectedDelta;
@property(nonatomic, assign) NSArray* selectedDeltas;
@end
