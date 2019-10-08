//
//  CloneWindow.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface CloneWindow : NSWindow
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign, readonly) BOOL urlExists;
@property (nonatomic, assign, readonly) BOOL recursive;
@end

NS_ASSUME_NONNULL_END
