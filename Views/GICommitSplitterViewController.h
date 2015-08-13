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

#import "GISimpleCommitViewController.h"
#import "GIViewController+Utilities.h"

@class GICommitSplitterViewController, GCHistoryCommit;

@protocol GICommitSplitterViewControllerDelegate <GICommitViewControllerDelegate, GIMergeConflictResolver>
- (void)commitSplitterViewControllerShouldFinish:(GICommitSplitterViewController*)controller withOldMessage:(NSString*)oldMessage newMessage:(NSString*)newMessage;
- (void)commitSplitterViewControllerShouldCancel:(GICommitSplitterViewController*)controller;
@end

@interface GICommitSplitterViewController : GICommitViewController
@property(nonatomic, assign) id<GICommitSplitterViewControllerDelegate> delegate;
- (BOOL)startSplittingCommit:(GCHistoryCommit*)commit error:(NSError**)error;
- (BOOL)finishSplittingCommitWithOldMessage:(NSString*)oldMessage newMessage:(NSString*)newMessage error:(NSError**)error;
- (void)cancelSplittingCommit;
@end
