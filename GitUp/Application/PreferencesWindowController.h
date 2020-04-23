//
//  PreferencesWindowController.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
#pragma mark - Release Channels
extern NSString* const PreferencesWindowController_ReleaseChannel_Stable;
extern NSString* const PreferencesWindowController_ReleaseChannel_Continuous;

#pragma mark - Themes
extern NSString* const PreferencesWindowController_Theme_SystemPreference;
extern NSString* const PreferencesWindowController_Theme_Light;
extern NSString* const PreferencesWindowController_Theme_Dark;

@interface PreferencesThemeService : NSObject
+ (NSString*)selectedTheme;
+ (void)applySelectedTheme;
@end

@interface PreferencesWindowController : NSWindowController
@property(nonatomic, copy) NSArray<NSString*>* channelTitles;
@property(nonatomic, copy) NSArray<NSString*>* themesTitles;
@property(nonatomic, copy) NSString* selectedChannel;
@property(nonatomic, copy) NSString* selectedTheme;
@property(nonatomic, copy) NSString* selectedItemIdentifier;

@property(nonatomic, copy) void (^didChangeReleaseChannel)(BOOL);
@end

NS_ASSUME_NONNULL_END
