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

@class GICommitViewController, GCCommit, GCSubmodule, GCIndexConflict, GICommitMessageView;

@protocol GICommitViewControllerDelegate <NSObject>
- (void)commitViewController:(GICommitViewController*)controller didCreateCommit:(GCCommit*)commit;
@end

// Abstract base class
@interface GICommitViewController : GIViewController
@property(nonatomic, assign) id<GICommitViewControllerDelegate> delegate;
@property(nonatomic, weak) IBOutlet NSTextField* infoTextField;
@property(nonatomic, strong) IBOutlet GICommitMessageView* messageTextView;  // Does not support weak references
@property(nonatomic, strong) IBOutlet GICommitMessageView* otherMessageTextView;  // Does not support weak references
@property(nonatomic, weak) IBOutlet NSButton* amendButton;
@property(nonatomic) BOOL showsBranchInfo;  // Default is YES
- (void)didCreateCommit:(GCCommit*)commit;
- (IBAction)toggleAmend:(id)sender;
@end

@interface GICommitViewController (Extensions)
- (void)createCommitFromHEADWithMessage:(NSString*)message;  // Automatically handles commit hooks, merges and undo
@end
