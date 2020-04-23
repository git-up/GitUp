//
//  WelcomeWindowController.h
//  Application
//
//  Created by Dmitry Lobanov on 10/09/2019.
//

#import <Cocoa/Cocoa.h>
#import <GitUpKit/GitUpKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WelcomeWindowController : NSWindowController

// Hide and Show
@property(assign, nonatomic, readonly) BOOL shouldShow;
@property(assign, nonatomic, readonly) BOOL notActivedYet;
- (void)setShouldShow;
- (void)setShouldHide;

// Recent items configuration
@property(nonatomic, copy) void (^openDocumentAtURL)(NSURL* url);

// UserDefaultsKeys
@property(nonatomic, copy) NSString* keyShouldShowWindow;

// Actions
- (void)handleDocumentCountChanged;
@end

NS_ASSUME_NONNULL_END
