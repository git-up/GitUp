//
//  AboutWindowController.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AboutWindowController : NSWindowController
@property(assign, nonatomic, readwrite) BOOL updatePending;
@end

NS_ASSUME_NONNULL_END
