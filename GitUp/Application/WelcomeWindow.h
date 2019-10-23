//
//  WelcomeWindow.h
//  Application
//
//  Created by Dmitry Lobanov on 10/09/2019.
//

#import <Cocoa/Cocoa.h>
#import <GitUpKit/GitUpKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WelcomeWindow : NSWindow
@property(nonatomic, copy) void(^configureItem)(NSMenuItem *item);
@property(nonatomic, copy) NSArray <NSURL *>*(^getRecentDocuments)();
@end

// Add welcome window controller.
@interface WelcomeWindowControllerModel : NSObject
@property (assign, nonatomic, readonly) BOOL shouldShow;
- (void)setShouldShow;
- (void)setShouldHide;

@property(nonatomic, copy) BOOL(^getUserDefaultsShouldShow)();

@property(nonatomic, copy) void(^configureItem)(NSMenuItem *item);
@property(nonatomic, copy) NSArray <NSURL *>*(^getRecentDocuments)();

@property(nonatomic, copy) void(^openTwitter)();
@property(nonatomic, copy) void(^viewIssues)();
@end

@interface WelcomeWindowController : NSWindowController
@property (strong, nonatomic, readonly) WelcomeWindowControllerModel *model;
- (instancetype)configuredWithModel:(WelcomeWindowControllerModel *)model;
- (void)handleDocumentCountChanged;
@end

NS_ASSUME_NONNULL_END
