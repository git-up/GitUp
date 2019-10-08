//
//  GILaunchServicesLocator.m
//  GitUpKit (OSX)
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "GILaunchServicesLocator.h"
#import "XLFacilityMacros.h"

NSString* const GIViewControllerTool_FileMerge = @"FileMerge";
NSString* const GIViewControllerTool_Kaleidoscope = @"Kaleidoscope";
NSString* const GIViewControllerTool_BeyondCompare = @"Beyond Compare";
NSString* const GIViewControllerTool_P4Merge = @"P4Merge";
NSString* const GIViewControllerTool_GitTool = @"Git Tool";
NSString* const GIViewControllerTool_DiffMerge = @"DiffMerge";

NSString* const GIViewController_DiffTool = @"GIViewController_DiffTool";
NSString* const GIViewController_MergeTool = @"GIViewController_MergeTool";
NSString* const GIViewController_TerminalTool = @"GIViewController_TerminalTool";

// TerminalTool
NSString* const GIViewController_TerminalTool_Terminal = @"Terminal";
NSString* const GIViewController_TerminalTool_iTerm = @"iTerm";
static NSString* const GIViewController_TerminalTool_iTerm_Key = @"GIViewController_TerminalTool_iTerm";
static NSString* const GIViewController_TerminalTool_iTerm_BundleIdentifier = @"com.googlecode.iterm2";

// Diff Tools Supplement
static NSString* _diffTemporaryDirectoryPath = nil;

@import CoreServices;
@implementation GILaunchServicesLocator
#pragma mark - Setup
+ (void)setup {
  NSDictionary* defaults = @{
    GIViewController_DiffTool : GIViewControllerTool_FileMerge,
    GIViewController_MergeTool : GIViewControllerTool_FileMerge,
    GIViewController_TerminalTool : GIViewController_TerminalTool_Terminal,
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
+ (NSString *)bundleIdentifierForDisplayName:(NSString *)displayName {
  if ([displayName isEqualToString:GIViewController_TerminalTool_iTerm]) {
    return GIViewController_TerminalTool_iTerm_BundleIdentifier;
  }
  return nil;
}
+ (NSString *)standardDefaultsKeyForDisplayName:(NSString *)displayName {
  if ([displayName isEqualToString:GIViewController_TerminalTool_iTerm]) {
    return GIViewController_TerminalTool_iTerm_Key;
  }
  return nil;
}
+ (NSDictionary *)installedAppsDictionary {
  NSMutableDictionary *dictionary = [NSMutableDictionary new];
  NSArray *apps = @[
    GIViewController_TerminalTool_iTerm
  ];
  for (NSString *app in apps) {
    NSString *key = [self standardDefaultsKeyForDisplayName:app];
    if (key != nil) {
      dictionary[key] = @([self hasInstalledApplicationForDisplayName:app]);
    }
  }
  return [dictionary copy];
}
+ (BOOL)hasInstalledApplicationForDisplayName:(NSString *)displayName {
  return [self hasInstalledApplicationForBundleIdentifier:[self bundleIdentifierForDisplayName:displayName]];
}
+ (BOOL)hasInstalledApplicationForBundleIdentifier:(NSString *)bundleIdentifier {
  if (bundleIdentifier == nil) {
    return NO;
  }
  CFErrorRef error = NULL;
  NSArray *applications = (__bridge NSArray *)LSCopyApplicationURLsForBundleIdentifier((__bridge CFStringRef)bundleIdentifier, &error);
  return applications.count > 0;
}

#pragma mark - Diff Tools Supplement
+ (void)setDiffTemporaryDirectoryPath:(NSString *)diffTemporaryDirectoryPath {
  _diffTemporaryDirectoryPath = diffTemporaryDirectoryPath;
}
+ (NSString *)diffTemporaryDirectoryPath {
  return _diffTemporaryDirectoryPath;
}
@end
