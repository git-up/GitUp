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
@property(nonatomic, weak) IBOutlet NSPopUpButton* recentPopUpButton;
@property(nonatomic, weak) IBOutlet GILinkButton* twitterButton;
@property(nonatomic, weak) IBOutlet GILinkButton* forumsButton;
@end

NS_ASSUME_NONNULL_END
