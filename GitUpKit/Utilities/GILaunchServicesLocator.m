//
//  GILaunchServicesLocator.m
//  GitUpKit (OSX)
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "GILaunchServicesLocator.h"
#import "XLFacilityMacros.h"

// Settings
NSString* const GIPreferences_DiffTool = @"GIPreferences_DiffTool";
NSString* const GIPreferences_MergeTool = @"GIPreferences_MergeTool";
NSString* const GIPreferences_TerminalTool = @"GIPreferences_TerminalTool";

// DiffMerge / Entries
NSString* const GIPreferences_DiffMergeTool_FileMerge = @"FileMerge";
NSString* const GIPreferences_DiffMergeTool_Kaleidoscope = @"Kaleidoscope";
NSString* const GIPreferences_DiffMergeTool_BeyondCompare = @"Beyond Compare";
NSString* const GIPreferences_DiffMergeTool_P4Merge = @"P4Merge";
NSString* const GIPreferences_DiffMergeTool_GitTool = @"Git Tool";
NSString* const GIPreferences_DiffMergeTool_DiffMerge = @"DiffMerge";

// TerminalTool / Entries
NSString* const GIPreferences_TerminalTool_Terminal = @"Terminal";
NSString* const GIPreferences_TerminalTool_iTerm = @"iTerm";

// TerminalTool/iTerm
static NSString* const GIPreferences_TerminalTool_iTerm_Key = @"GIPreferences_TerminalTool_iTerm";
static NSString* const GIPreferences_TerminalTool_iTerm_BundleIdentifier = @"com.googlecode.iterm2";

// Diff Tools Supplement
static NSString* _diffTemporaryDirectoryPath = nil;

// NOTE: Actually, it is an extension of DisplayNames enum.
// It contains methods
// func bundleIdentfier() -> String?
// func standardDefaultsKey() -> String?
@interface GILaunchServicesLocatorHelper : NSObject
+ (nullable NSString*)bundleIdentifierForDisplayName:(NSString*)displayName;
+ (nullable NSString*)standardDefaultsKeyForDisplayName:(NSString*)displayName;
@end

@implementation GILaunchServicesLocatorHelper
+ (nullable NSString*)bundleIdentifierForDisplayName:(NSString*)displayName {
  if ([displayName isEqualToString:GIPreferences_TerminalTool_iTerm]) {
    return GIPreferences_TerminalTool_iTerm_BundleIdentifier;
  }
  return nil;
}
+ (nullable NSString*)standardDefaultsKeyForDisplayName:(NSString*)displayName {
  if ([displayName isEqualToString:GIPreferences_TerminalTool_iTerm]) {
    return GIPreferences_TerminalTool_iTerm_Key;
  }
  return nil;
}
@end

@import CoreServices;
@implementation GILaunchServicesLocator
#pragma mark - Setup
+ (void)setup {
  NSDictionary* defaults = @{
    GIPreferences_DiffTool : GIPreferences_DiffMergeTool_FileMerge,
    GIPreferences_MergeTool : GIPreferences_DiffMergeTool_FileMerge,
    GIPreferences_TerminalTool : GIPreferences_TerminalTool_Terminal,
  };
  [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];

  NSDictionary* installedApps = [GILaunchServicesLocator installedAppsDictionary];
  [[NSUserDefaults standardUserDefaults] registerDefaults:installedApps];

  if (_diffTemporaryDirectoryPath == nil) {
    _diffTemporaryDirectoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
    [[NSFileManager defaultManager] removeItemAtPath:_diffTemporaryDirectoryPath error:NULL];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_diffTemporaryDirectoryPath withIntermediateDirectories:YES attributes:nil error:NULL]) {
      XLOG_DEBUG_UNREACHABLE();
    }
  }
}

#pragma mark - Installed Apps
+ (NSDictionary*)installedAppsDictionary {
  NSMutableDictionary* dictionary = [NSMutableDictionary new];
  NSArray* apps = @[
    GIPreferences_TerminalTool_iTerm
  ];
  for (NSString* app in apps) {
    NSString* key = [GILaunchServicesLocatorHelper standardDefaultsKeyForDisplayName:app];
    if (key != nil) {
      dictionary[key] = @([self hasInstalledApplicationForDisplayName:app]);
    }
  }
  return [dictionary copy];
}
+ (BOOL)hasInstalledApplicationForDisplayName:(NSString*)displayName {
  return [self hasInstalledApplicationForBundleIdentifier:[GILaunchServicesLocatorHelper bundleIdentifierForDisplayName:displayName]];
}
+ (BOOL)hasInstalledApplicationForBundleIdentifier:(NSString*)bundleIdentifier {
  if (bundleIdentifier == nil) {
    return NO;
  }
  CFErrorRef error = NULL;
  NSArray* applications = CFBridgingRelease(LSCopyApplicationURLsForBundleIdentifier((__bridge CFStringRef)bundleIdentifier, &error));
  if (error) {
    //TODO: Handle error.
    CFRelease(error);
    return NO;
  }
  return applications.count > 0;
}

#pragma mark - Diff Tools Supplement
+ (void)setDiffTemporaryDirectoryPath:(NSString*)diffTemporaryDirectoryPath {
  _diffTemporaryDirectoryPath = diffTemporaryDirectoryPath;
}
+ (NSString*)diffTemporaryDirectoryPath {
  return _diffTemporaryDirectoryPath;
}
@end
