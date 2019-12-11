//
//  GILaunchServicesLocator.h
//  GitUpKit (OSX)
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
extern NSString* const GIViewController_DiffTool;
extern NSString* const GIViewController_MergeTool;
extern NSString* const GIViewController_TerminalTool;

// DiffTool and MergeTool
extern NSString* const GIViewControllerTool_FileMerge;
extern NSString* const GIViewControllerTool_Kaleidoscope;
extern NSString* const GIViewControllerTool_BeyondCompare;
extern NSString* const GIViewControllerTool_P4Merge;
extern NSString* const GIViewControllerTool_GitTool;
extern NSString* const GIViewControllerTool_DiffMerge;

// TerminalTool
extern NSString* const GIViewController_TerminalTool_Terminal;
extern NSString* const GIViewController_TerminalTool_iTerm;

@interface GILaunchServicesLocator : NSObject
#pragma mark - Setup
+ (void)setup;

#pragma mark - Installed Apps
+ (NSString *)bundleIdentifierForDisplayName:(NSString *)displayName;
+ (NSString *)standardDefaultsKeyForDisplayName:(NSString *)displayName;
+ (NSDictionary *)installedAppsDictionary;
+ (BOOL)hasInstalledApplicationForDisplayName:(NSString *)displayName;
+ (BOOL)hasInstalledApplicationForBundleIdentifier:(NSString *)bundleIdentifier;

#pragma mark - Diff Tools Supplement
@property (nonatomic, copy, class) NSString *diffTemporaryDirectoryPath;
@end

NS_ASSUME_NONNULL_END
