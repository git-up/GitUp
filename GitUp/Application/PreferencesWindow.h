//
//  PreferencesWindow.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PreferencesWindow : NSWindow
@property(nonatomic, weak) IBOutlet NSToolbar* preferencesToolbar;
@property(nonatomic, weak) IBOutlet NSTabView* tabView;
@property(nonatomic, weak) IBOutlet NSPopUpButton* channelPopUpButton;
@property(nonatomic, weak) IBOutlet NSPopUpButton* themePopUpButton;
@end

NS_ASSUME_NONNULL_END
