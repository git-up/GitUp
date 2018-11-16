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

#import <Security/Security.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"
#import <HockeySDK/HockeySDK.h>
#pragma clang diagnostic pop
#import <Sparkle/Sparkle.h>

#import <GitUpKit/XLFacilityMacros.h>

#import "AppDelegate.h"
#import "DocumentController.h"
#import "Document.h"
#import "Common.h"
#import "ToolProtocol.h"
#import "GARawTracker.h"

#define OFFICIAL 0
#define OFFICIAL_RELEASE !DEBUG && OFFICIAL

#define __ENABLE_SUDDEN_TERMINATION__ 1

#define kNotificationUserInfoKey_Action @"action"  // NSString

#define kPreferencePaneIdentifier_General @"general"

#define kInstallerName @"install.sh"
#define kToolName @"gitup"
#define kToolInstallPath @"/usr/local/bin/" kToolName

@interface NSSavePanel (OSX_10_9)
- (void)setShowsTagField:(BOOL)flag;
@end

@interface AppDelegate () <NSUserNotificationCenterDelegate, SUUpdaterDelegate>
- (IBAction)closeWelcomeWindow:(id)sender;
@end

@interface WelcomeWindow : NSWindow
@end

@implementation WelcomeWindow

- (void)awakeFromNib {
  self.opaque = NO;
  self.backgroundColor = [NSColor clearColor];
  self.movableByWindowBackground = YES;
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
  return menuItem.action == @selector(performClose:) ? YES : [super validateMenuItem:menuItem];
}

- (void)performClose:(id)sender {
  [[AppDelegate sharedDelegate] closeWelcomeWindow:sender];
}

- (BOOL)canBecomeKeyWindow {
  return YES;
}

@end

@implementation AppDelegate {
  SUUpdater* _updater;
  BOOL _updatePending;
  BOOL _manualCheck;
  NSInteger _allowWelcome;
  CGFloat _welcomeMaxHeight;

  BOOL _authenticationUseKeychain;
  NSURL* _authenticationURL;
  NSString* _authenticationUsername;
  NSString* _authenticationPassword;

  CFMessagePortRef _messagePort;
}

+ (void)initialize {
  NSDictionary* defaults = @{
    GIMapViewControllerStateKey_ShowVirtualTips : @(YES),
    GIMapViewControllerStateKey_ShowTagLabels : @(YES),
    GICommitMessageViewUserDefaultKey_ShowInvisibleCharacters : @(YES),
    GICommitMessageViewUserDefaultKey_ShowMargins : @(YES),
    GICommitMessageViewUserDefaultsKey_ContinuousSpellChecking : @(YES),
    GICommitMessageViewUserDefaultsKey_SmartInsertDelete : @(YES),
    GIUserDefaultKey_FontSize : @(GIDefaultFontSize),
    kUserDefaultsKey_ReleaseChannel : kReleaseChannel_Stable,
    kUserDefaultsKey_CheckInterval : @(15 * 60),
    kUserDefaultsKey_FirstLaunch : @(YES),
    kUserDefaultsKey_DiffWhitespaceMode : @(kGCLiveRepositoryDiffWhitespaceMode_Normal),
    kUserDefaultsKey_EnableVisualEffects : @(NO),
    kUserDefaultsKey_ShowWelcomeWindow : @(YES),
  };
  [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

+ (instancetype)sharedDelegate {
  return (AppDelegate*)[NSApp delegate];
}

// WARNING: We are using the same attributes for the keychain items than Git CLT appears to be using as of version 1.9.3
+ (BOOL)loadPlainTextAuthenticationFormKeychainForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password allowInteraction:(BOOL)allowInteraction {
  const char* serverName = url.host.UTF8String;
  if (serverName && serverName[0]) {  // TODO: How can this be NULL?
    const char* accountName = (*username).UTF8String;
    SecKeychainItemRef itemRef;
    UInt32 passwordLength;
    void* passwordData;
    SecKeychainSetUserInteractionAllowed(allowInteraction);  // Ignore errors
    OSStatus status = SecKeychainFindInternetPassword(NULL,
                                                      (UInt32)strlen(serverName), serverName,
                                                      0, NULL,  // Any security domain
                                                      accountName ? (UInt32)strlen(accountName) : 0, accountName,
                                                      0, NULL,  // Any path
                                                      0,  // Any port
                                                      kSecProtocolTypeAny,
                                                      kSecAuthenticationTypeAny,
                                                      &passwordLength, &passwordData, &itemRef);
    if (status == noErr) {
      BOOL success = NO;
      *password = [[NSString alloc] initWithBytes:passwordData length:passwordLength encoding:NSUTF8StringEncoding];
      if (accountName == NULL) {
        UInt32 tag = kSecAccountItemAttr;
        UInt32 format = CSSM_DB_ATTRIBUTE_FORMAT_STRING;
        SecKeychainAttributeInfo info = {1, &tag, &format};
        SecKeychainAttributeList* attributes;
        status = SecKeychainItemCopyAttributesAndData(itemRef, &info, NULL, &attributes, NULL, NULL);
        if (status == noErr) {
          XLOG_DEBUG_CHECK(attributes->count == 1);
          XLOG_DEBUG_CHECK(attributes->attr[0].tag == kSecAccountItemAttr);
          *username = [[NSString alloc] initWithBytes:attributes->attr[0].data length:attributes->attr[0].length encoding:NSUTF8StringEncoding];
          success = YES;
          SecKeychainItemFreeAttributesAndData(attributes, NULL);
        } else {
          XLOG_ERROR(@"SecKeychainItemCopyAttributesAndData() returned error %i", status);
        }
      } else {
        success = YES;
      }
      SecKeychainItemFreeContent(NULL, passwordData);
      CFRelease(itemRef);
      if (success) {
        return YES;
      }
    } else if (status != errSecItemNotFound) {
      XLOG_ERROR(@"SecKeychainFindInternetPassword() returned error %i", status);
    }
  } else {
    XLOG_WARNING(@"Unable to extract hostname from remote URL: %@", url);
  }
  return NO;
}

+ (void)savePlainTextAuthenticationToKeychainForURL:(NSURL*)url withUsername:(NSString*)username password:(NSString*)password {
  SecProtocolType type;
  if ([url.scheme isEqualToString:@"http"]) {
    type = kSecProtocolTypeHTTP;
  } else if ([url.scheme isEqualToString:@"https"]) {
    type = kSecProtocolTypeHTTPS;
  } else {
    XLOG_DEBUG_UNREACHABLE();
    return;
  }
  const char* serverName = url.host.UTF8String;
  const char* accountName = username.UTF8String;
  const char* accountPassword = password.UTF8String;
  SecKeychainSetUserInteractionAllowed(true);  // Ignore errors
  OSStatus status = SecKeychainAddInternetPassword(NULL,
                                                   (UInt32)strlen(serverName), serverName,
                                                   0, NULL,  // Any security domain
                                                   accountName ? (UInt32)strlen(accountName) : 0, accountName,
                                                   0, NULL,  // Any path
                                                   0,  // Any port
                                                   type,
                                                   kSecAuthenticationTypeAny,
                                                   (UInt32)strlen(accountPassword), accountPassword, NULL);
  if (status != noErr) {
    XLOG_ERROR(@"SecKeychainAddInternetPassword() returned error %i", status);
  } else {
    XLOG_VERBOSE(@"Successfully saved authentication in Keychain");
  }
}

- (void)_setDocumentWindowModeID:(NSArray*)arguments {
  [(Document*)arguments[0] setWindowModeID:[arguments[1] unsignedIntegerValue]];
}

- (void)_openRepositoryWithURL:(NSURL*)url withCloneMode:(CloneMode)cloneMode windowModeID:(WindowModeID)windowModeID {
  [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url
                                                                         display:YES
                                                               completionHandler:^(NSDocument* document, BOOL documentWasAlreadyOpen, NSError* openError) {
                                                                 if (document) {
                                                                   if (documentWasAlreadyOpen) {
                                                                     if ((NSUInteger)windowModeID != NSNotFound) {
                                                                       [(Document*)document setWindowModeID:windowModeID];
                                                                     }
                                                                   } else {
                                                                     [(Document*)document setCloneMode:cloneMode];
                                                                     if ((NSUInteger)windowModeID != NSNotFound) {
                                                                       XLOG_DEBUG_CHECK(cloneMode == kCloneMode_None);
                                                                       [self performSelector:@selector(_setDocumentWindowModeID:) withObject:@[ document, @(windowModeID) ] afterDelay:0.1];  // TODO: Try to schedule *after* -[Document _documentDidOpen] has been called
                                                                     }
                                                                   }
                                                                 } else {
                                                                   [[NSDocumentController sharedDocumentController] presentError:openError];
                                                                 }
                                                               }];
}

- (void)_openDocument:(NSMenuItem*)sender {
  [self _openRepositoryWithURL:sender.representedObject withCloneMode:kCloneMode_None windowModeID:NSNotFound];
}

- (void)_willShowRecentPopUpMenu:(NSNotification*)notification {
  NSMenu* menu = _recentPopUpButton.menu;
  while (menu.numberOfItems > 1) {
    [menu removeItemAtIndex:1];
  }
  NSArray* array = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
  if (array.count) {
    for (NSURL* url in array) {
      NSString* path = url.path;
      NSString* title = path.lastPathComponent;
      for (NSMenuItem* item in menu.itemArray) {  // TODO: Handle identical second-to-last path component
        if ([item.title caseInsensitiveCompare:title] == NSOrderedSame) {
          title = [NSString stringWithFormat:@"%@ — %@", path.lastPathComponent, [[path stringByDeletingLastPathComponent] lastPathComponent]];
          path = [(NSURL*)item.representedObject path];
          item.title = [NSString stringWithFormat:@"%@ — %@", path.lastPathComponent, [[path stringByDeletingLastPathComponent] lastPathComponent]];
          break;
        }
      }
      NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:@selector(_openDocument:) keyEquivalent:@""];
      item.target = self;
      item.representedObject = url;
      [menu addItem:item];
    }
  } else {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Repositories", nil) action:NULL keyEquivalent:@""];
    item.enabled = NO;
    [menu addItem:item];
  }
}

- (void)awakeFromNib {
  _welcomeMaxHeight = _welcomeWindow.frame.size.height;

  _allowWelcome = -1;

  _twitterButton.textAlignment = NSLeftTextAlignment;
  _twitterButton.textFont = [NSFont boldSystemFontOfSize:11];
  _forumsButton.textAlignment = NSLeftTextAlignment;
  _forumsButton.textFont = [NSFont boldSystemFontOfSize:11];

  _preferencesToolbar.selectedItemIdentifier = kPreferencePaneIdentifier_General;
  [self selectPreferencePane:nil];

  [_channelPopUpButton.menu removeAllItems];
  for (NSString* string in @[ kReleaseChannel_Stable, kReleaseChannel_Continuous ]) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(string, nil) action:NULL keyEquivalent:@""];
    item.representedObject = string;
    [_channelPopUpButton.menu addItem:item];
  }

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_willShowRecentPopUpMenu:) name:NSPopUpButtonWillPopUpNotification object:_recentPopUpButton];
}

- (void)_updatePreferencePanel {
  NSString* channel = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsKey_ReleaseChannel];
  for (NSMenuItem* item in _channelPopUpButton.menu.itemArray) {
    if ([item.representedObject isEqualToString:channel]) {
      [_channelPopUpButton selectItem:item];
      break;
    }
  }
}

- (void)_showNotificationWithTitle:(NSString*)title action:(SEL)action message:(NSString*)format, ... NS_FORMAT_FUNCTION(3, 4) {
  NSUserNotification* notification = [[NSUserNotification alloc] init];
  if (action) {
    notification.userInfo = @{kNotificationUserInfoKey_Action : NSStringFromSelector(action)};
  }
  notification.title = title;
  va_list arguments;
  va_start(arguments, format);
  NSString* string = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  notification.informativeText = string;

  [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

- (void)handleDocumentCountChanged {
  BOOL showWelcomeWindow = [[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsKey_ShowWelcomeWindow];
  if (showWelcomeWindow && (_allowWelcome > 0) && ![[[NSDocumentController sharedDocumentController] documents] count]) {
    if (!_welcomeWindow.visible) {
      [_welcomeWindow makeKeyAndOrderFront:nil];
    }
  } else {
    if (_welcomeWindow.visible) {
      [_welcomeWindow orderOut:nil];
    }
  }
}

#pragma mark - NSApplicationDelegate

- (void)applicationWillFinishLaunching:(NSNotification*)notification {
  // Initialize custom subclass of NSDocumentController
  [DocumentController sharedDocumentController];

#if OFFICIAL_RELEASE
  // Initialize HockeyApp
  [[BITHockeyManager sharedHockeyManager] configureWithIdentifier:@"65233b0e034e4fcbaf6754afba3b2b23"];
  [[BITHockeyManager sharedHockeyManager] setDisableMetricsManager:YES];
  [[BITHockeyManager sharedHockeyManager] setDisableFeedbackManager:YES];
  [[BITHockeyManager sharedHockeyManager] startManager];

  // Initialize Google Analytics
  [[GARawTracker sharedTracker] startWithTrackingID:@"UA-83409580-1"];
#endif

  [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                     andSelector:@selector(_getUrl:withReplyEvent:)
                                                   forEventClass:kInternetEventClass
                                                      andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
#if OFFICIAL_RELEASE
  // Initialize Sparkle and check for update immediately
  if (![[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsKey_DisableSparkle]) {
    _updater = [SUUpdater sharedUpdater];
    _updater.delegate = self;
    _updater.automaticallyChecksForUpdates = NO;
    _updater.sendsSystemProfile = NO;
    _updater.automaticallyDownloadsUpdates = YES;

    _manualCheck = NO;
    [_updater checkForUpdatesInBackground];
  }
#endif

  // Initialize user notification center
  [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

  // Notify user in case app was updated since last launch
  NSString* currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
  NSString* lastVersion = [[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaultsKey_LastVersion];
  if (lastVersion && ([currentVersion integerValue] > [lastVersion integerValue])) {
    NSString* version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    [self _showNotificationWithTitle:[NSString stringWithFormat:NSLocalizedString(@"GitUp Updated to Version %@ (%@)", nil), version, currentVersion]
                              action:@selector(viewReleaseNotes:)
                             message:NSLocalizedString(@"Click to see release notes.", nil)];
  }
  if ([currentVersion integerValue]) {
    [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:kUserDefaultsKey_LastVersion];
  }

  // Prompt to install command line tool if needed
  if (![[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsKey_FirstLaunch] && ![[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsKey_SkipInstallCLT]) {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:kToolInstallPath]) {
      NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Install GitUp command line tool?", nil)
                                       defaultButton:NSLocalizedString(@"Install", nil)
                                     alternateButton:NSLocalizedString(@"Not Now", nil)
                                         otherButton:nil
                           informativeTextWithFormat:NSLocalizedString(@"GitUp can install a companion command line tool at \"%@\" which lets you control GitUp from the terminal.\n\nYou can install it at any time from the GitUp menu.", nil), kToolInstallPath];
      alert.type = kGIAlertType_Note;
      alert.showsSuppressionButton = YES;
      if ([alert runModal] == NSAlertDefaultReturn) {
        [self installTool:nil];
      }
      if (alert.suppressionButton.state) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kUserDefaultsKey_SkipInstallCLT];
      }
    }
  }

  // First launch has completed
  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kUserDefaultsKey_FirstLaunch];

  // Create tool message port
  CFMessagePortContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
  _messagePort = CFMessagePortCreateLocal(kCFAllocatorDefault, CFSTR(kToolPortName), _MessagePortCallBack, &context, NULL);
  if (_messagePort) {
    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, _messagePort, 0);
    if (source) {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopDefaultMode);  // Don't use kCFRunLoopCommonModes on purpose
      CFRelease(source);
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }
  } else {
    XLOG_ERROR(@"Failed creating message port for tool");
    XLOG_DEBUG_UNREACHABLE();
  }

#if __ENABLE_SUDDEN_TERMINATION__
  // Enable sudden termination
  [[NSProcessInfo processInfo] enableSuddenTermination];
#endif
}

- (void)_getUrl:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent {
  NSURL* url = [NSURL URLWithString:[event paramDescriptorForKeyword:keyDirectObject].stringValue];
  BOOL isGitHubMacScheme = [url.scheme rangeOfString:@"github-mac" options:NSCaseInsensitiveSearch].location != NSNotFound;
  BOOL isOpenRepoHost = [url.host rangeOfString:@"openRepo" options:NSCaseInsensitiveSearch].location != NSNotFound;
  NSString* path = url.path.length ? [url.path substringFromIndex:1] : nil;
  if (isGitHubMacScheme && isOpenRepoHost && path) {
    [self _cloneRepositoryFromURLString:path];
  }
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication*)sender {
  return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication*)theApplication hasVisibleWindows:(BOOL)hasVisibleWindows {
  if (!hasVisibleWindows) {
    _allowWelcome = 1;  // Always show welcome when clicking on dock icon
    [self handleDocumentCountChanged];
  }
  return YES;
}

- (void)applicationDidBecomeActive:(NSNotification*)notification {
  if (_allowWelcome < 0) {
    _allowWelcome = 1;
  }
  [self handleDocumentCountChanged];

#if OFFICIAL_RELEASE
  [[GARawTracker sharedTracker] sendEventWithCategory:@"application"
                                               action:@"activate"
                                                label:nil
                                                value:nil
                                      completionBlock:NULL];
#endif
}

#if __ENABLE_SUDDEN_TERMINATION__

// Try to work around -canCloseDocumentWithDelegate:shouldCloseSelector:contextInfo: not being called when quitting even if sudden termination is disabled
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
  BOOL shouldTerminate = YES;
  for (Document* document in [[NSDocumentController sharedDocumentController] documents]) {
    if (![document shouldCloseDocument]) {
      shouldTerminate = NO;
    }
  }
  return shouldTerminate ? NSTerminateNow : NSTerminateCancel;  // TODO: Use NSTerminateLater instead
}

#endif

#pragma mark - Tool

static CFDataRef _MessagePortCallBack(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void* info) {
  NSDictionary* input = [NSKeyedUnarchiver unarchiveObjectWithData:(__bridge NSData*)data];
  XLOG_DEBUG_CHECK(input);
  NSDictionary* output = [(__bridge AppDelegate*)info _processToolCommand:input];
  XLOG_DEBUG_CHECK(output);
  return CFBridgingRetain([NSKeyedArchiver archivedDataWithRootObject:output]);
}

- (NSDictionary*)_processToolCommand:(NSDictionary*)input {
  NSString* command = [input objectForKey:kToolDictionaryKey_Command];
  NSString* repository = [[input objectForKey:kToolDictionaryKey_Repository] stringByStandardizingPath];
  if (!command.length || !repository.length) {
    return @{kToolDictionaryKey_Error : @"Invalid command"};
  }
  if ([command isEqualToString:@kToolCommand_Open]) {
    [self _openRepositoryWithURL:[NSURL fileURLWithPath:repository] withCloneMode:kCloneMode_None windowModeID:NSNotFound];
  } else if ([command isEqualToString:@kToolCommand_Map]) {
    [self _openRepositoryWithURL:[NSURL fileURLWithPath:repository] withCloneMode:kCloneMode_None windowModeID:kWindowModeID_Map];
  } else if ([command isEqualToString:@kToolCommand_Commit]) {
    [self _openRepositoryWithURL:[NSURL fileURLWithPath:repository] withCloneMode:kCloneMode_None windowModeID:kWindowModeID_Commit];
  } else if ([command isEqualToString:@kToolCommand_Stash]) {
    [self _openRepositoryWithURL:[NSURL fileURLWithPath:repository] withCloneMode:kCloneMode_None windowModeID:kWindowModeID_Stashes];
  } else {
    return @{kToolDictionaryKey_Error : [NSString stringWithFormat:@"Unknown command '%@'", command]};
  }
  return @{};
}

#pragma mark - Actions

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem {
  if (anItem.action == @selector(checkForUpdates:)) {
    return _updater && !_updatePending && ![_updater updateInProgress];
  }
  return YES;
}

- (IBAction)openDocument:(id)sender {
  [[NSDocumentController sharedDocumentController] openDocument:sender];
}

- (IBAction)changeReleaseChannel:(id)sender {
  NSString* oldChannel = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsKey_ReleaseChannel];
  NSString* newChannel = _channelPopUpButton.selectedItem.representedObject;
  if (![newChannel isEqualToString:oldChannel]) {
    [[NSUserDefaults standardUserDefaults] setObject:newChannel forKey:kUserDefaultsKey_ReleaseChannel];

    _manualCheck = NO;
    [_updater checkForUpdatesInBackground];
  }
}

- (IBAction)viewWiki:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kURL_Wiki]];
}

- (IBAction)viewReleaseNotes:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kURL_ReleaseNotes]];
}

- (IBAction)viewIssues:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kURL_Issues]];
}

- (IBAction)showAboutPanel:(id)sender {
#if DEBUG
  _versionTextField.stringValue = @"DEBUG";
#else
  if (_updatePending) {
    _versionTextField.stringValue = NSLocalizedString(@"Update Pending", nil);
  } else {
    _versionTextField.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@)", nil), [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
  }
#endif
  _copyrightTextField.stringValue = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"];
  [_aboutPanel makeKeyAndOrderFront:nil];
}

- (IBAction)showPreferences:(id)sender {
  [self _updatePreferencePanel];
  [_preferencesWindow makeKeyAndOrderFront:nil];
}

- (IBAction)selectPreferencePane:(id)sender {
  [_preferencesTabView selectTabViewItemWithIdentifier:_preferencesToolbar.selectedItemIdentifier];
  NSSize size = NSSizeFromString(_preferencesTabView.selectedTabViewItem.label);
  NSRect rect = [_preferencesWindow contentRectForFrameRect:_preferencesWindow.frame];
  if (sender) {
    rect.origin.y += rect.size.height;
  }
  rect.size.width = size.width;
  rect.size.height = size.height;
  if (sender) {
    rect.origin.y -= rect.size.height;
  }
  [_preferencesWindow setFrame:[_preferencesWindow frameRectForContentRect:rect] display:YES animate:(sender ? YES : NO)];
}

- (IBAction)resetPreferences:(id)sender {
  [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
}

- (IBAction)newRepository:(id)sender {
  NSSavePanel* savePanel = [NSSavePanel savePanel];
  savePanel.title = NSLocalizedString(@"Create New Repository", nil);
  savePanel.prompt = NSLocalizedString(@"Create", nil);
  savePanel.nameFieldLabel = NSLocalizedString(@"Name:", nil);
  if ([savePanel respondsToSelector:@selector(setShowsTagField:)]) {
    [savePanel setShowsTagField:NO];
  }
  if ([savePanel runModal] == NSFileHandlingPanelOKButton) {
    NSString* path = savePanel.URL.path;
    NSError* error;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path followLastSymlink:NO] || [[NSFileManager defaultManager] moveItemAtPathToTrash:path error:&error]) {
      GCRepository* repository = [[GCRepository alloc] initWithNewLocalRepository:path bare:NO error:&error];
      if (repository) {
        [self _openRepositoryWithURL:[NSURL fileURLWithPath:repository.workingDirectoryPath] withCloneMode:kCloneMode_None windowModeID:NSNotFound];
      } else {
        [NSApp presentError:error];
      }
    } else {
      [NSApp presentError:error];
    }
  }
}

- (void)_cloneRepositoryFromURLString:(NSString*)urlString {
  _cloneURLTextField.stringValue = urlString;
  _cloneRecursiveButton.state = NSOnState;
  if ([NSApp runModalForWindow:_cloneWindow] && _cloneURLTextField.stringValue.length) {
    NSURL* url = GCURLFromGitURL(_cloneURLTextField.stringValue);
    if (url) {
      NSString* name = [url.path.lastPathComponent stringByDeletingPathExtension];
      NSSavePanel* savePanel = [NSSavePanel savePanel];
      savePanel.title = NSLocalizedString(@"Clone Repository", nil);
      savePanel.prompt = NSLocalizedString(@"Clone", nil);
      savePanel.nameFieldLabel = NSLocalizedString(@"Name:", nil);
      savePanel.nameFieldStringValue = name ? name : @"";
      if ([savePanel respondsToSelector:@selector(setShowsTagField:)]) {
        [savePanel setShowsTagField:NO];
      }
      if ([savePanel runModal] == NSFileHandlingPanelOKButton) {
        NSString* path = savePanel.URL.path;
        NSError* error;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path followLastSymlink:NO] || [[NSFileManager defaultManager] moveItemAtPathToTrash:path error:&error]) {
          GCRepository* repository = [[GCRepository alloc] initWithNewLocalRepository:path bare:NO error:&error];
          if (repository) {
            if ([repository addRemoteWithName:@"origin" url:url error:&error]) {
              [self _openRepositoryWithURL:[NSURL fileURLWithPath:repository.workingDirectoryPath] withCloneMode:(_cloneRecursiveButton.state ? kCloneMode_Recursive : kCloneMode_Default)windowModeID:NSNotFound];
            } else {
              [NSApp presentError:error];
              [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];  // Ignore errors
            }
          } else {
            [NSApp presentError:error];
          }
        } else {
          [NSApp presentError:error];
        }
      }
    } else {
      [NSApp presentError:MAKE_ERROR(@"Invalid Git repository URL")];
    }
  }
}

- (IBAction)cloneRepository:(id)sender {
  [self _cloneRepositoryFromURLString:@""];
}

- (IBAction)dimissModal:(id)sender {
  [NSApp stopModalWithCode:[(NSButton*)sender tag]];
  [[(NSButton*)sender window] orderOut:nil];
}

- (IBAction)checkForUpdates:(id)sender {
  _manualCheck = YES;
  [_updater checkForUpdatesInBackground];
}

- (IBAction)closeWelcomeWindow:(id)sender {
  [_welcomeWindow orderOut:nil];
  _allowWelcome = 0;
}

- (IBAction)openTwitter:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kURL_Twitter]];
}

- (IBAction)installTool:(id)sender {
  AuthorizationRef authorization;
  OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorization);
  if (status == errAuthorizationSuccess) {
    AuthorizationItem items = {kAuthorizationRightExecute, 0, NULL, 0};
    AuthorizationRights rights = {1, &items};
    status = AuthorizationCopyRights(authorization, &rights, NULL, kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights, NULL);
    if (status == errAuthorizationSuccess) {
      NSString* installerPath = [[[NSBundle mainBundle] sharedSupportPath] stringByAppendingPathComponent:kInstallerName];
      NSString* toolPath = [[[NSBundle mainBundle] sharedSupportPath] stringByAppendingPathComponent:kToolName];
      NSString* installPath = kToolInstallPath;
      char* arguments[] = {(char*)toolPath.fileSystemRepresentation, (char*)installPath.fileSystemRepresentation, NULL};
      FILE* communicationPipe = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      status = AuthorizationExecuteWithPrivileges(authorization, installerPath.fileSystemRepresentation, kAuthorizationFlagDefaults, arguments, &communicationPipe);
#pragma clang diagnostic pop
      if (status == errAuthorizationSuccess) {
        NSMutableData* data = [[NSMutableData alloc] init];
        while (1) {
          char buffer[128];
          ssize_t count = read(fileno(communicationPipe), buffer, sizeof(buffer));
          if (count <= 0) {
            break;
          }
          [data appendBytes:buffer length:count];
        }
        if ((data.length == 2) && (((const char*)data.bytes)[0] == 'O') && (((const char*)data.bytes)[1] == 'K')) {
          NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedString(@"GitUp command line tool was successfully installed!", nil)
                                           defaultButton:NSLocalizedString(@"OK", nil)
                                         alternateButton:nil
                                             otherButton:nil
                               informativeTextWithFormat:NSLocalizedString(@"The tool has been installed at \"%@\".\nRun \"gitup help\" in Terminal to learn more.", nil), kToolInstallPath];
          alert.type = kGIAlertType_Note;
          [alert runModal];
        } else {
          status = -1;  // Code doesn't matter
        }
      }
    }
    AuthorizationFree(authorization, kAuthorizationFlagDefaults);
  }
  if ((status != errAuthorizationSuccess) && (status != errAuthorizationCanceled)) {
    [NSApp presentError:MAKE_ERROR(@"Failed installing command line tool")];
  }
}

#pragma mark - NSUserNotificationCenterDelegate

- (BOOL)userNotificationCenter:(NSUserNotificationCenter*)center shouldPresentNotification:(NSUserNotification*)notification {
  return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter*)center didActivateNotification:(NSUserNotification*)notification {
  NSString* action = notification.userInfo[kNotificationUserInfoKey_Action];
  if (action) {
    [NSApp sendAction:NSSelectorFromString(action) to:self from:nil];
  }
}

#pragma mark - GCRepositoryDelegate

- (void)repository:(GCRepository*)repository willStartTransferWithURL:(NSURL*)url {
  _authenticationUseKeychain = YES;
  _authenticationURL = nil;
  _authenticationUsername = nil;
  _authenticationPassword = nil;
}

- (BOOL)repository:(GCRepository*)repository requiresPlainTextAuthenticationForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password {
  if (_authenticationUseKeychain) {
    _authenticationUseKeychain = NO;
    if ([self.class loadPlainTextAuthenticationFormKeychainForURL:url user:user username:username password:password allowInteraction:YES]) {
      return YES;
    }
  } else {
    XLOG_VERBOSE(@"Skipping Keychain lookup for repeated authentication failures");
  }

  _authenticationURLTextField.stringValue = url.absoluteString;
  _authenticationNameTextField.stringValue = *username ? *username : @"";
  _authenticationPasswordTextField.stringValue = @"";
  [_authenticationWindow makeFirstResponder:(*username ? _authenticationPasswordTextField : _authenticationNameTextField)];
  if ([NSApp runModalForWindow:_authenticationWindow] && _authenticationNameTextField.stringValue.length && _authenticationPasswordTextField.stringValue.length) {
    _authenticationURL = url;
    _authenticationUsername = [_authenticationNameTextField.stringValue copy];
    _authenticationPassword = [_authenticationPasswordTextField.stringValue copy];
    *username = _authenticationNameTextField.stringValue;
    *password = _authenticationPasswordTextField.stringValue;
    return YES;
  }
  return NO;
}

- (void)repository:(GCRepository*)repository didFinishTransferWithURL:(NSURL*)url success:(BOOL)success {
  if (success && _authenticationURL && _authenticationUsername && _authenticationPassword) {
    [self.class savePlainTextAuthenticationToKeychainForURL:_authenticationURL withUsername:_authenticationUsername password:_authenticationPassword];
  }
  _authenticationURL = nil;
  _authenticationUsername = nil;
  _authenticationPassword = nil;
}

#pragma mark - SUUpdaterDelegate

- (NSString*)feedURLStringForUpdater:(SUUpdater*)updater {
  NSString* channel = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsKey_ReleaseChannel];
  return [NSString stringWithFormat:kURL_AppCast, channel];
}

- (void)updater:(SUUpdater*)updater didFindValidUpdate:(SUAppcastItem*)item {
  NSString* channel = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsKey_ReleaseChannel];
  XLOG_INFO(@"Did find app update on channel '%@' for version %@", channel, item.versionString);
  if (_manualCheck) {
    NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedString(@"A GitUp update is available!", nil)
                                     defaultButton:NSLocalizedString(@"OK", nil)
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:NSLocalizedString(@"The update will download automatically in the background and be installed when you quit GitUp.", nil)];
    alert.type = kGIAlertType_Note;
    [alert runModal];
  }
}

- (void)updaterDidNotFindUpdate:(SUUpdater*)updater {
  NSString* channel = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsKey_ReleaseChannel];
  XLOG_VERBOSE(@"App is up-to-date at version %@ on channel '%@'", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"], channel);
  if (_manualCheck) {
    NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedString(@"GitUp is already up-to-date!", nil)
                                     defaultButton:NSLocalizedString(@"OK", nil)
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:@""];
    alert.type = kGIAlertType_Note;
    [alert runModal];
  }
}

- (void)updater:(SUUpdater*)updater didAbortWithError:(NSError*)error {
  NSString* channel = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsKey_ReleaseChannel];
  if (![error.domain isEqualToString:SUSparkleErrorDomain] || (error.code != SUNoUpdateError)) {
    XLOG_ERROR(@"App update on channel '%@' aborted: %@", channel, error);
  }
}

- (void)updater:(SUUpdater*)updater willInstallUpdate:(SUAppcastItem*)item {
  XLOG_INFO(@"Installing app update for version %@", item.versionString);
}

- (void)updater:(SUUpdater*)updater willInstallUpdateOnQuit:(SUAppcastItem*)item immediateInstallationInvocation:(NSInvocation*)invocation {
  XLOG_INFO(@"Will install app update for version %@ on quit", item.versionString);
  _updatePending = YES;
  [self _showNotificationWithTitle:NSLocalizedString(@"Update Available", nil)
                            action:NULL
                           message:NSLocalizedString(@"Relaunch GitUp to update to version %@ (%@).", nil), item.displayVersionString, item.versionString];
}

@end
