//
//  GILaunchServicesLocator.h
//  GitUpKit (OSX)
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Settings
extern NSString* const GIPreferences_DiffTool;
extern NSString* const GIPreferences_MergeTool;
extern NSString* const GIPreferences_TerminalTool;

// DiffTool and MergeTool
extern NSString* const GIPreferences_DiffMergeTool_FileMerge;
extern NSString* const GIPreferences_DiffMergeTool_Kaleidoscope;
extern NSString* const GIPreferences_DiffMergeTool_BeyondCompare;
extern NSString* const GIPreferences_DiffMergeTool_P4Merge;
extern NSString* const GIPreferences_DiffMergeTool_GitTool;
extern NSString* const GIPreferences_DiffMergeTool_DiffMerge;

// TerminalTool
extern NSString* const GIPreferences_TerminalTool_Terminal;
extern NSString* const GIPreferences_TerminalTool_iTerm;

@interface GILaunchServicesLocator : NSObject
#pragma mark - Setup
+ (void)setup;

#pragma mark - Installed Apps
+ (NSDictionary*)installedAppsDictionary;
+ (BOOL)hasInstalledApplicationForDisplayName:(NSString*)displayName;
+ (BOOL)hasInstalledApplicationForBundleIdentifier:(NSString*)bundleIdentifier;

#pragma mark - Diff Tools Supplement
@property(nonatomic, copy, class) NSString* diffTemporaryDirectoryPath;
@end

NS_ASSUME_NONNULL_END
