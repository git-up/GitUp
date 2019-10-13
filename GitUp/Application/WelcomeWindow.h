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

NS_ASSUME_NONNULL_END
