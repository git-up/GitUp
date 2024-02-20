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

#import "GIViewController.h"

@class GCHistoryCommit;
@class GCCommit;
@class GCDiffDelta;
@class GCIndexConflict;
@protocol GIQuickViewControllerDelegate
- (void)quickViewWantsToShowSelectedCommitsList:(NSArray <GCHistoryCommit *> *)commitsList selectedCommit:(GCHistoryCommit *)commit;
- (void)quickViewDidSelectCommit:(GCHistoryCommit *)commit commitsList:(NSArray <GCHistoryCommit *>*)commitsList;
@end

@interface GIQuickViewController : GIViewController
@property(nonatomic, strong) GCHistoryCommit* commit;
@property(nonatomic, weak) id <GIQuickViewControllerDelegate> delegate;
@property(nonatomic, copy) void(^willShowContextualMenu)(NSMenu *menu, GCDiffDelta *delta, GCIndexConflict *conflict);
@end
