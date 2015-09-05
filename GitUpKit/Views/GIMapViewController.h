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

#import "GIViewController+Utilities.h"

#import "GCRepository.h"

@class GIMapViewController, GIGraph, GINode, GCHistory, GCHistoryCommit, GCCommit;

@protocol GIMapViewControllerDelegate <GIMergeConflictResolver>
- (void)mapViewControllerDidReloadGraph:(GIMapViewController*)controller;
- (void)mapViewControllerDidChangeSelection:(GIMapViewController*)controller;

- (void)mapViewController:(GIMapViewController*)controller quickViewCommit:(GCHistoryCommit*)commit;
- (void)mapViewController:(GIMapViewController*)controller diffCommit:(GCHistoryCommit*)commit withOtherCommit:(GCHistoryCommit*)otherCommit;
- (void)mapViewController:(GIMapViewController*)controller rewriteCommit:(GCHistoryCommit*)commit;
- (void)mapViewController:(GIMapViewController*)controller splitCommit:(GCHistoryCommit*)commit;
@end

@interface GIMapViewController : GIViewController <NSUserInterfaceValidations>
@property(nonatomic, assign) id<GIMapViewControllerDelegate> delegate;
@property(nonatomic, readonly) GIGraph* graph;
@property(nonatomic, readonly) GCHistoryCommit* selectedCommit;  // Nil if no commit is selected
@property(nonatomic, strong) GCHistory* previewHistory;
@property(nonatomic) BOOL forceShowAllTips;
- (BOOL)selectCommit:(GCCommit*)commit;  // Also scrolls if needed to ensure commit is visible - Returns YES if commit was selected
- (GINode*)nodeForCommit:(GCCommit*)commit;
- (NSPoint)positionInViewForCommit:(GCCommit*)commit;

- (IBAction)toggleTagLabels:(id)sender;
- (IBAction)toggleBranchLabels:(id)sender;
- (IBAction)toggleVirtualTips:(id)sender;
- (IBAction)toggleTagTips:(id)sender;
- (IBAction)toggleRemoteBranchTips:(id)sender;
- (IBAction)toggleStaleBranchTips:(id)sender;

- (IBAction)fetchAllRemoteBranches:(id)sender;
- (IBAction)fetchAllRemoteTags:(id)sender;
- (IBAction)fetchAndPruneAllRemoteTags:(id)sender;

- (IBAction)pushAllLocalBranches:(id)sender;
- (IBAction)pushAllTags:(id)sender;
- (IBAction)pullCurrentBranch:(id)sender;
- (IBAction)pushCurrentBranch:(id)sender;
@end
