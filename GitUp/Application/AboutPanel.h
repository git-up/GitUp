//
//  AboutPanel.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface AboutPanel : NSPanel
- (void)populateWithDataWhenUpdateIsPending:(BOOL)updatePending;
@end

@interface AboutPanelWindowController : NSWindowController
- (void)populateWithDataWhenUpdateIsPending:(BOOL)updatePending;
@end

NS_ASSUME_NONNULL_END
