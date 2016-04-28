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

#import "GIAppKit.h"

@class GIWindowController, GIViewController, GCLiveRepository, GCSnapshot;

@interface GIView : NSView
@property(nonatomic, readonly) GIViewController* viewController;
@end

@interface GIViewController : NSViewController <NSTextFieldDelegate, NSTextViewDelegate, NSTableViewDelegate>
@property(nonatomic, readonly) GCLiveRepository* repository;
@property(strong) GIView* view;
@property(nonatomic, readonly, getter=isViewVisible) BOOL viewVisible;
@property(nonatomic, readonly, getter=isLiveResizing) BOOL liveResizing;
@property(nonatomic, readonly) GIWindowController* windowController;
- (instancetype)initWithRepository:(GCLiveRepository*)repository;
- (void)presentAlert:(NSAlert*)alert completionHandler:(void (^)(NSInteger returnCode))handler;
@end

@interface GIViewController (Extensions)
- (void)presentAlertWithType:(GIAlertType)type title:(NSString*)title message:(NSString*)format, ... NS_FORMAT_FUNCTION(3, 4);
- (void)confirmUserActionWithAlertType:(GIAlertType)type
                                 title:(NSString*)title
                               message:(NSString*)message
                                button:(NSString*)button
             suppressionUserDefaultKey:(NSString*)key  // May be nil
                                 block:(dispatch_block_t)block;
@end

@interface GIViewController (Subclassing)
@property(nonatomic, readonly) NSView* preferredFirstResponder;  // Default implementation returns first subview that accepts first responder status

- (void)viewWillShow;  // Default implementation does nothing
- (void)viewDidShow;  // Default implementation does nothing
- (void)viewWillHide;  // Default implementation does nothing
- (void)viewDidHide;  // Default implementation does nothing

- (void)viewDidResize;  // Default implementation does nothing
- (void)viewWillBeginLiveResize;  // Default implementation does nothing
- (void)viewDidFinishLiveResize;  // Default implementation does nothing

- (void)repositoryDidChange;  // Default implementation does nothing
- (void)repositoryWorkingDirectoryDidChange;  // Default implementation does nothing
- (void)repositoryStateDidUpdate;  // Default implementation does nothing
- (void)repositoryHistoryDidUpdate;  // Default implementation does nothing
- (void)repositoryStashesDidUpdate;  // Default implementation does nothing
- (void)repositoryStatusDidUpdate;  // Default implementation does nothing
- (void)repositorySnapshotsDidUpdate;  // Default implementation does nothing
@end
