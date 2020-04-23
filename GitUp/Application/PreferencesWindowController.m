//
//  PreferencesWindowController.m
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "PreferencesWindowController.h"
#import "Common.h"

#pragma mark - Preferences
#pragma mark - Preferences / Channels
NSString* const PreferencesWindowController_ReleaseChannel_Stable = @"stable";
NSString* const PreferencesWindowController_ReleaseChannel_Continuous = @"continuous";

#pragma mark - Preferences / Themes
NSString* const PreferencesWindowController_Theme_SystemPreference = @"systemTheme";
NSString* const PreferencesWindowController_Theme_Light = @"lightTheme";
NSString* const PreferencesWindowController_Theme_Dark = @"darkTheme";

#pragma mark - Preferences / Item Identifiers
static NSString* const PreferencesWindowController_Identifier_General = @"general";

@interface PreferencesThemeService ()
+ (NSAppearanceName)appearanceNameWithTheme:(NSString*)theme;
+ (void)applyTheme:(NSString*)theme;
@end

@implementation PreferencesThemeService
+ (NSAppearanceName)appearanceNameWithTheme:(NSString*)theme {
  if (@available(macOS 10.14, *)) {
    if ([theme isEqualToString:PreferencesWindowController_Theme_Dark]) {
      return NSAppearanceNameDarkAqua;
    }
  }
  if ([theme isEqualToString:PreferencesWindowController_Theme_SystemPreference]) {
    return nil;
  }
  if ([theme isEqualToString:PreferencesWindowController_Theme_Light]) {
    return NSAppearanceNameAqua;
  }
  return nil;
}

+ (void)applyTheme:(NSString*)theme {
  NSAppearanceName name = [self appearanceNameWithTheme:theme];
  NSApp.appearance = name != nil ? [NSAppearance appearanceNamed:name] : nil;
  [NSUserDefaults.standardUserDefaults setObject:theme forKey:kUserDefaultsKey_Theme];
}

+ (NSString*)selectedTheme {
  return [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsKey_Theme];
}

+ (void)applySelectedTheme {
  [self applyTheme:self.selectedTheme];
}
@end

@interface PreferencesWindowController ()
@property(nonatomic, weak) IBOutlet NSToolbar* preferencesToolbar;
@property(nonatomic, weak) IBOutlet NSTabView* preferencesTabView;
@property(nonatomic, weak) IBOutlet NSPopUpButton* channelPopUpButton;
@property(nonatomic, weak) IBOutlet NSPopUpButton* themePopUpButton;
@end

@implementation PreferencesWindowController

#pragma mark - Initialization
- (instancetype)init {
  return [super initWithWindowNibName:@"PreferencesWindowController"];
}

#pragma mark - Window Lifecycle
- (void)windowDidLoad {
  [super windowDidLoad];

  self.channelTitles = @[
    PreferencesWindowController_ReleaseChannel_Stable,
    PreferencesWindowController_ReleaseChannel_Continuous
  ];

  self.themesTitles = @[
    PreferencesWindowController_Theme_SystemPreference,
    PreferencesWindowController_Theme_Light,
    PreferencesWindowController_Theme_Dark
  ];

  self.selectedItemIdentifier = PreferencesWindowController_Identifier_General;
}

- (void)showWindow:(id)sender {
  // sync NSUserDefaults
  NSString* theme = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsKey_Theme];
  self.selectedTheme = theme;
  NSString* channel = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsKey_ReleaseChannel];
  self.selectedChannel = channel;
  [self selectPreferencePane:self];
  [super showWindow:sender];
}

#pragma mark - PopUp Buttons
- (void)setChannelTitles:(NSArray<NSString*>*)channelTitles {
  [self.channelPopUpButton.menu removeAllItems];
  for (NSString* string in channelTitles) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(string, nil) action:NULL keyEquivalent:@""];
    item.representedObject = string;
    [self.channelPopUpButton.menu addItem:item];
  }
}

- (void)setThemesTitles:(NSArray<NSString*>*)themesTitles {
  [self.themePopUpButton.menu removeAllItems];
  for (NSString* string in themesTitles) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(string, nil) action:NULL keyEquivalent:@""];
    item.representedObject = string;
    [self.themePopUpButton.menu addItem:item];
  }
}

- (NSArray<NSString*>*)channelTitles {
  return self.channelPopUpButton.itemTitles;
}

- (NSArray<NSString*>*)themesTitles {
  return self.themePopUpButton.itemTitles;
}

- (void)setSelectedChannel:(NSString*)selectedChannel {
  for (NSMenuItem* item in self.channelPopUpButton.itemArray) {
    if ([item.representedObject isEqualToString:selectedChannel]) {
      [self.channelPopUpButton selectItem:item];
      break;
    }
  }
}

- (void)setSelectedTheme:(NSString*)selectedTheme {
  for (NSMenuItem* item in self.themePopUpButton.itemArray) {
    if ([item.representedObject isEqualToString:selectedTheme]) {
      [self.themePopUpButton selectItem:item];
      break;
    }
  }
}

- (NSString*)selectedChannel {
  return self.channelPopUpButton.selectedItem.representedObject;
}

- (NSString*)selectedTheme {
  return self.themePopUpButton.selectedItem.representedObject;
}

#pragma mark - Selection
- (void)setSelectedItemIdentifier:(NSString*)selectedItemIdentifier {
  self.preferencesToolbar.selectedItemIdentifier = selectedItemIdentifier;
  [self selectPreferencePane:nil];
}

- (NSString*)selectedItemIdentifier {
  return self.preferencesToolbar.selectedItemIdentifier;
}

#pragma mark - Actions
#pragma mark - Actions / Select Preference Pane
- (IBAction)selectPreferencePane:(id)sender {
  NSWindow* window = self.window;
  [_preferencesTabView selectTabViewItemWithIdentifier:_preferencesToolbar.selectedItemIdentifier];
  NSSize size = NSSizeFromString(_preferencesTabView.selectedTabViewItem.label);
  NSRect rect = [window contentRectForFrameRect:window.frame];
  if (sender) {
    rect.origin.y += rect.size.height;
  }
  rect.size.width = size.width;
  rect.size.height = size.height;
  if (sender) {
    rect.origin.y -= rect.size.height;
  }
  [window setFrame:[window frameRectForContentRect:rect] display:YES animate:(sender ? YES : NO)];
}

#pragma mark - Actions / Change Theme
- (IBAction)changeTheme:(id)sender {
  NSString* theme = self.selectedTheme;
  [PreferencesThemeService applyTheme:theme];
}

#pragma mark - Actions / Change Release Channel
- (IBAction)changeReleaseChannel:(id)sender {
  NSString* newChannel = self.selectedChannel;
  NSString* oldChannel = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsKey_ReleaseChannel];
  BOOL didChangeReleaseChannel = ![newChannel isEqualToString:oldChannel];
  if (didChangeReleaseChannel) {
    [NSUserDefaults.standardUserDefaults setObject:newChannel forKey:kUserDefaultsKey_ReleaseChannel];
    if (self.didChangeReleaseChannel) {
      self.didChangeReleaseChannel(didChangeReleaseChannel);
    }
  }
}

@end
