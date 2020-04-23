//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"
#pragma clang diagnostic pop
#import <Sparkle/Sparkle.h>

#import <GitUpKit/GitUpKit.h>
#import <GitUpKit/XLFacilityMacros.h>

#import "AppDelegate.h"
#import "ServicesProvider.h"
#import "DocumentController.h"
#import "Document.h"
#import "Common.h"
#import "ToolProtocol.h"
#import "GARawTracker.h"

#import "AboutWindowController.h"
#import "CloneWindowController.h"
#import "PreferencesWindowController.h"
#import "WelcomeWindowController.h"

#define __ENABLE_SUDDEN_TERMINATION__ 1

#define kNotificationUserInfoKey_Action @"action"  // NSString

#define kInstallerName @"install.sh"
#define kToolName @"gitup"
#define kToolInstallPath @"/usr/local/bin/" kToolName

@interface AppDelegate () <NSUserNotificationCenterDelegate, SUUpdaterDelegate>
@property(nonatomic, strong) AboutWindowController* aboutWindowController;
@property(nonatomic, strong) CloneWindowController* cloneWindowController;
@property(nonatomic, strong) PreferencesWindowController* preferencesWindowController;
@property(nonatomic, strong) WelcomeWindowController* welcomeWindowController;
@end

@implementation AppDelegate {
  SUUpdater* _updater;
  BOOL _updatePending;
  BOOL _manualCheck;

  CFMessagePortRef _messagePort;
}

#pragma mark - Properties

- (AboutWindowController*)aboutWindowController {
  if (!_aboutWindowController) {
    _aboutWindowController = [[AboutWindowController alloc] init];
  }
  return _aboutWindowController;
}

- (CloneWindowController*)cloneWindowController {
  if (!_cloneWindowController) {
    _cloneWindowController = [[CloneWindowController alloc] init];
  }
  return _cloneWindowController;
}

- (void)didChangeReleaseChannel:(BOOL)didChange {
  if (didChange) {
    _manualCheck = NO;
    [_updater checkForUpdatesInBackground];
  }
}

- (PreferencesWindowController*)preferencesWindowController {
  if (!_preferencesWindowController) {
    _preferencesWindowController = [[PreferencesWindowController alloc] init];
    __weak typeof(self) weakSelf = self;
    _preferencesWindowController.didChangeReleaseChannel = ^(BOOL didChange) {
      [weakSelf didChangeReleaseChannel:didChange];
    };
  }
  return _preferencesWindowController;
}

- (WelcomeWindowController*)welcomeWindowController {
  if (!_welcomeWindowController) {
    _welcomeWindowController = [[WelcomeWindowController alloc] init];

    _welcomeWindowController.keyShouldShowWindow = kUserDefaultsKey_ShowWelcomeWindow;

    __weak typeof(self) weakSelf = self;
    _welcomeWindowController.openDocumentAtURL = ^(NSURL* _Nonnull url) {
      [weakSelf _openDocumentAtURL:url];
    };
  }
  return _welcomeWindowController;
}

#pragma mark - Initialize
+ (void)initialize {
  NSDictionary* defaults = @{
    GICommitMessageViewUserDefaultKey_ShowInvisibleCharacters : @(YES),
    GICommitMessageViewUserDefaultKey_ShowMargins : @(YES),
    GICommitMessageViewUserDefaultKey_EnableSpellChecking : @(YES),
    GIUserDefaultKey_FontSize : @(GIDefaultFontSize),
    kUserDefaultsKey_ReleaseChannel : PreferencesWindowController_ReleaseChannel_Stable,
    kUserDefaultsKey_CheckInterval : @(15 * 60),
    kUserDefaultsKey_FirstLaunch : @(YES),
    kUserDefaultsKey_DiffWhitespaceMode : @(kGCLiveRepositoryDiffWhitespaceMode_Normal),
    kUserDefaultsKey_ShowWelcomeWindow : @(YES),
    kUserDefaultsKey_Theme : PreferencesWindowController_Theme_SystemPreference,
  };
  [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

+ (instancetype)sharedDelegate {
  return (AppDelegate*)[NSApp delegate];
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

- (void)_openDocumentAtURL:(NSURL*)url {
  [self _openRepositoryWithURL:url withCloneMode:kCloneMode_None windowModeID:NSNotFound];
}

- (void)handleDocumentCountChanged {
  [self.welcomeWindowController handleDocumentCountChanged];
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

#pragma mark - NSApplicationDelegate

- (void)applicationWillFinishLaunching:(NSNotification*)notification {
  // Initialize custom subclass of NSDocumentController
  [DocumentController sharedDocumentController];

#if !DEBUG
  // Initialize Google Analytics
  [[GARawTracker sharedTracker] startWithTrackingID:@"UA-83409580-1"];
#endif

  [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                     andSelector:@selector(_getUrl:withReplyEvent:)
                                                   forEventClass:kInternetEventClass
                                                      andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
#if !DEBUG
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

  // Locate installed apps.
  [GILaunchServicesLocator setup];

  // Initialize user notification center
  [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

  // Register finder context menu services.
  [NSApplication sharedApplication].servicesProvider = [ServicesProvider new];

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
      NSAlert* alert = [[NSAlert alloc] init];
      alert.messageText = NSLocalizedString(@"Install GitUp command line tool?", nil);
      alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"GitUp can install a companion command line tool at \"%@\" which lets you control GitUp from the terminal.\n\nYou can install it at any time from the GitUp menu.", nil), kToolInstallPath];
      [alert addButtonWithTitle:NSLocalizedString(@"Install", nil)];
      [alert addButtonWithTitle:NSLocalizedString(@"Not Now", nil)];
      alert.type = kGIAlertType_Note;
      alert.showsSuppressionButton = YES;
      if ([alert runModal] == NSAlertFirstButtonReturn) {
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

  // Load theme preference
  [PreferencesThemeService applySelectedTheme];

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
    // Always show welcome when clicking on dock icon
    [self.welcomeWindowController setShouldShow];
    [self handleDocumentCountChanged];
  }
  return YES;
}

- (void)applicationDidBecomeActive:(NSNotification*)notification {
  if (self.welcomeWindowController.notActivedYet) {
    [self.welcomeWindowController setShouldShow];
  }
  [self handleDocumentCountChanged];
#if !DEBUG
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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
  // The deprecation for this method in the macOS 10.14 SDK marks the incorrect
  // version for its introduction. However, it is useful to keep availability
  // guards on in general. FB6233110
  return CFBridgingRetain([NSKeyedArchiver archivedDataWithRootObject:output]);
#pragma clang diagnostic pop
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
  self.aboutWindowController.updatePending = _updatePending;
  [self.aboutWindowController showWindow:nil];
}

- (IBAction)showPreferences:(id)sender {
  [self.preferencesWindowController showWindow:nil];
}

- (IBAction)resetPreferences:(id)sender {
  [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
}

- (IBAction)newRepository:(id)sender {
  NSSavePanel* savePanel = [NSSavePanel savePanel];
  savePanel.title = NSLocalizedString(@"Create New Repository", nil);
  savePanel.prompt = NSLocalizedString(@"Create", nil);
  savePanel.nameFieldLabel = NSLocalizedString(@"Name:", nil);
  savePanel.showsTagField = NO;
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
  [self.cloneWindowController runModalForURL:urlString
                                  completion:^(CloneWindowControllerResult* _Nonnull result) {
                                    if (result.invalidRepository) {
                                      [NSApp presentError:MAKE_ERROR(@"Invalid Git repository URL")];
                                      return;
                                    }

                                    if (result.emptyDirectoryPath) {
                                      return;
                                    }

                                    NSURL* url = result.repositoryURL;
                                    NSString* path = result.directoryPath;
                                    CloneMode cloneMode = result.recursive ? kCloneMode_Recursive : kCloneMode_Default;
                                    NSError* error;

                                    BOOL fileDoesntExistOrEvictedToTrash = ![[NSFileManager defaultManager] fileExistsAtPath:path followLastSymlink:NO] || [[NSFileManager defaultManager] moveItemAtPathToTrash:path error:&error];

                                    if (!fileDoesntExistOrEvictedToTrash) {
                                      [NSApp presentError:error];
                                      return;
                                    }

                                    GCRepository* repository = [[GCRepository alloc] initWithNewLocalRepository:path bare:NO error:&error];
                                    if (!repository) {
                                      [NSApp presentError:error];
                                      return;
                                    }

                                    if ([repository addRemoteWithName:@"origin" url:url error:&error]) {
                                      [self _openRepositoryWithURL:[NSURL fileURLWithPath:repository.workingDirectoryPath] withCloneMode:cloneMode windowModeID:NSNotFound];
                                    } else {
                                      [NSApp presentError:error];
                                      [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];  // Ignore errors
                                    }
                                  }];
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
          NSAlert* alert = [[NSAlert alloc] init];
          alert.messageText = NSLocalizedString(@"GitUp command line tool was successfully installed!", nil);
          alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The tool has been installed at \"%@\".\nRun \"gitup help\" in Terminal to learn more.", nil), kToolInstallPath];
          [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
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

#pragma mark - SUUpdaterDelegate

- (NSString*)feedURLStringForUpdater:(SUUpdater*)updater {
  NSString* channel = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsKey_ReleaseChannel];
  return [NSString stringWithFormat:kURL_AppCast, channel];
}

- (void)updater:(SUUpdater*)updater didFindValidUpdate:(SUAppcastItem*)item {
  NSString* channel = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsKey_ReleaseChannel];
  XLOG_INFO(@"Did find app update on channel '%@' for version %@", channel, item.versionString);
  if (_manualCheck) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"A GitUp update is available!", nil);
    alert.informativeText = NSLocalizedString(@"The update will download automatically in the background and be installed when you quit GitUp.", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
    alert.type = kGIAlertType_Note;
    [alert runModal];
  }
}

- (void)updaterDidNotFindUpdate:(SUUpdater*)updater {
  NSString* channel = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsKey_ReleaseChannel];
  XLOG_VERBOSE(@"App is up-to-date at version %@ on channel '%@'", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"], channel);
  if (_manualCheck) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"GitUp is already up-to-date!", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
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
