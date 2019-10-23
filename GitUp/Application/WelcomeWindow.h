//
//  WelcomeWindow.h
//  Application
//
//  Created by Dmitry Lobanov on 10/09/2019.
//

#import <Cocoa/Cocoa.h>
#import <GitUpKit/GitUpKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WelcomeWindowControllerModel : NSObject
@property (assign, nonatomic, readonly) BOOL shouldShow;
@property (assign, nonatomic, readonly) BOOL notActivedYet;
- (void)setShouldShow;
- (void)setShouldHide;

@property(nonatomic, copy) void(^configureItem)(NSMenuItem *item);

// DefaultsKeys
@property(nonatomic, copy) NSString *keyShouldShowWindow;

// URLs
@property(nonatomic, copy) NSString *twitterURL;
@end

@interface WelcomeWindowController : NSWindowController
@property (strong, nonatomic, readonly) WelcomeWindowControllerModel *model;
- (instancetype)configuredWithModel:(WelcomeWindowControllerModel *)model;
- (void)handleDocumentCountChanged;
@end

NS_ASSUME_NONNULL_END
