//
//  PreferencesWindow.m
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "PreferencesWindow.h"

@interface PreferencesWindow ()
@property(nonatomic, weak) IBOutlet NSToolbar* preferencesToolbar;
@property(nonatomic, weak) IBOutlet NSTabView* preferencesTabView;
@property(nonatomic, weak) IBOutlet NSPopUpButton* channelPopUpButton;
@property(nonatomic, weak) IBOutlet NSPopUpButton* themePopUpButton;
@end

@implementation PreferencesWindow

#pragma mark - PopUp Buttons
- (void)setChannelTitles:(NSArray<NSString *> *)channelTitles {
  [self.channelPopUpButton.menu removeAllItems];
  for (NSString* string in channelTitles) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(string, nil) action:NULL keyEquivalent:@""];
    item.representedObject = string;
    [self.channelPopUpButton.menu addItem:item];
  }
}

- (void)setThemesTitles:(NSArray<NSString *> *)themesTitles {
  [self.themePopUpButton.menu removeAllItems];
  for (NSString* string in themesTitles) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(string, nil) action:NULL keyEquivalent:@""];
    item.representedObject = string;
    [self.themePopUpButton.menu addItem:item];
  }
}

- (NSArray<NSString *> *)channelTitles {
  return self.channelPopUpButton.itemTitles;
}

- (NSArray<NSString *> *)themesTitles {
  return self.themePopUpButton.itemTitles;
}

- (void)setSelectedChannel:(NSString *)selectedChannel {
  for (NSMenuItem *item in self.channelPopUpButton.itemArray) {
    if ([item.representedObject isEqualToString:selectedChannel]) {
      [self.channelPopUpButton selectItem:item];
      break;
    }
  }
}

- (void)setSelectedTheme:(NSString *)selectedTheme {
  for (NSMenuItem *item in self.themePopUpButton.itemArray) {
    if ([item.representedObject isEqualToString:selectedTheme]) {
      [self.themePopUpButton selectItem:item];
      break;
    }
  }
}

- (NSString *)selectedChannel {
  return self.channelPopUpButton.selectedItem.representedObject;
}

- (NSString *)selectedTheme {
  return self.themePopUpButton.selectedItem.representedObject;
}

#pragma mark - Selection
- (void)setSelectedItemIdentifier:(NSString *)selectedItemIdentifier {
  self.preferencesToolbar.selectedItemIdentifier = selectedItemIdentifier;
  [self selectPreferencePane:nil];
}

- (NSString *)selectedItemIdentifier {
  return self.preferencesToolbar.selectedItemIdentifier;
}

#pragma mark - Actions
- (IBAction)selectPreferencePane:(id)sender {
  [_preferencesTabView selectTabViewItemWithIdentifier:_preferencesToolbar.selectedItemIdentifier];
  NSSize size = NSSizeFromString(_preferencesTabView.selectedTabViewItem.label);
  NSRect rect = [self contentRectForFrameRect:self.frame];
  if (sender) {
    rect.origin.y += rect.size.height;
  }
  rect.size.width = size.width;
  rect.size.height = size.height;
  if (sender) {
    rect.origin.y -= rect.size.height;
  }
  [self setFrame:[self frameRectForContentRect:rect] display:YES animate:(sender ? YES : NO)];
}

@end
