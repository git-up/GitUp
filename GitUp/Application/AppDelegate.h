//  Copyright (C) 2015-2018 Pierre-Olivier Latour <info@pol-online.net>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#import <GitUpKit/GitUpKit.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, GCRepositoryDelegate>
@property(nonatomic, strong) IBOutlet NSWindow* preferencesWindow;
@property(nonatomic, weak) IBOutlet NSToolbar* preferencesToolbar;
@property(nonatomic, weak) IBOutlet NSTabView* preferencesTabView;
@property(nonatomic, weak) IBOutlet NSPopUpButton* channelPopUpButton;

@property(nonatomic, strong) IBOutlet NSWindow* cloneWindow;
@property(nonatomic, weak) IBOutlet NSTextField* cloneURLTextField;
@property(nonatomic, weak) IBOutlet NSButton* cloneRecursiveButton;

@property(nonatomic, strong) IBOutlet NSWindow* authenticationWindow;
@property(nonatomic, weak) IBOutlet NSTextField* authenticationURLTextField;
@property(nonatomic, weak) IBOutlet NSTextField* authenticationNameTextField;
@property(nonatomic, weak) IBOutlet NSSecureTextField* authenticationPasswordTextField;

@property(nonatomic, strong) IBOutlet NSPanel* aboutPanel;
@property(nonatomic, weak) IBOutlet NSTextField* versionTextField;
@property(nonatomic, weak) IBOutlet NSTextField* copyrightTextField;

@property(nonatomic, strong) IBOutlet NSWindow* welcomeWindow;
@property(nonatomic, weak) IBOutlet NSPopUpButton* recentPopUpButton;
@property(nonatomic, weak) IBOutlet GILinkButton* twitterButton;
@property(nonatomic, weak) IBOutlet GILinkButton* forumsButton;

+ (instancetype)sharedDelegate;
+ (BOOL)loadPlainTextAuthenticationFormKeychainForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password allowInteraction:(BOOL)allowInteraction;
+ (void)savePlainTextAuthenticationToKeychainForURL:(NSURL*)url withUsername:(NSString*)username password:(NSString*)password;

- (void)repository:(GCRepository*)repository willStartTransferWithURL:(NSURL*)url;
- (BOOL)repository:(GCRepository*)repository requiresPlainTextAuthenticationForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password;
- (void)repository:(GCRepository*)repository didFinishTransferWithURL:(NSURL*)url success:(BOOL)success;

- (void)handleDocumentCountChanged;
@end
