//
//  PreferencesWindow.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PreferencesWindow : NSWindow
@property (nonatomic, copy) NSArray <NSString *>*channelTitles;
@property (nonatomic, copy) NSArray <NSString *>*themesTitles;
@property (nonatomic, copy) NSString *selectedChannel;
@property (nonatomic, copy) NSString *selectedTheme;
@property (nonatomic, copy) NSString *selectedItemIdentifier;
@end

NS_ASSUME_NONNULL_END
