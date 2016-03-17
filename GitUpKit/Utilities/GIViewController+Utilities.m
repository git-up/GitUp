//  Copyright (C) 2015 Pierre-Olivier Latour <info@pol-online.net>
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

#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GIViewController+Utilities.h"
#import "GIWindowController.h"

#import "GCCore.h"
#import "GCRepository+Index.h"
#import "GCRepository+Utilities.h"
#import "GIAppKit.h"
#import "XLFacilityMacros.h"

#define kOpenDiffPath @"/usr/bin/opendiff"
#define kKSDiffPath @"/usr/local/bin/ksdiff"
#define kBComparePath @"/usr/local/bin/bcompare"
#define kP4MergePath @"/Applications/p4merge.app/Contents/Resources/launchp4merge"

NSString* const GIViewControllerTool_FileMerge = @"FileMerge";
NSString* const GIViewControllerTool_Kaleidoscope = @"Kaleidoscope";
NSString* const GIViewControllerTool_BeyondCompare = @"Beyond Compare";
NSString* const GIViewControllerTool_P4Merge = @"P4Merge";
NSString* const GIViewControllerTool_GitTool = @"Git Tool";

NSString* const GIViewController_DiffTool = @"GIViewController_DiffTool";
NSString* const GIViewController_MergeTool = @"GIViewController_MergeTool";

static NSString* _diffTemporaryDirectoryPath = nil;

@implementation GIViewController (Utilities)

+ (void)initialize {
  NSDictionary* defaults = @{
    GIViewController_DiffTool: GIViewControllerTool_FileMerge,
    GIViewController_MergeTool: GIViewControllerTool_FileMerge
  };
  [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
  
  if (_diffTemporaryDirectoryPath == nil) {
    _diffTemporaryDirectoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
    [[NSFileManager defaultManager] removeItemAtPath:_diffTemporaryDirectoryPath error:NULL];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_diffTemporaryDirectoryPath withIntermediateDirectories:YES attributes:nil error:NULL]) {
      XLOG_DEBUG_UNREACHABLE();
    }
  }
}

- (void)discardAllFiles {
  [self confirmUserActionWithAlertType:kGIAlertType_Stop
                                 title:NSLocalizedString(@"Are you sure you want to discard changes in all working directory files?", nil)
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Discard All", nil)
             suppressionUserDefaultKey:nil
                                 block:^{
    
    NSError* error;
    if ([self.repository syncWorkingDirectoryWithIndex:&error]) {
      [self.repository notifyWorkingDirectoryChanged];
    } else {
      [self presentError:error];
    }
    
  }];
}

- (void)stageAllFiles {
  NSError* error;
  if ([self.repository syncIndexWithWorkingDirectory:&error]) {
    [self.repository notifyRepositoryChanged];
  } else {
    [self presentError:error];
  }
}

- (void)unstageAllFiles {
  NSError* error;
  if ([self.repository resetIndexToHEAD:&error]) {
    [self.repository notifyRepositoryChanged];
  } else {
    [self presentError:error];
  }
}

- (void)stageSubmoduleAtPath:(NSString*)path {
  NSError* error;
  GCSubmodule* submodule = [self.repository lookupSubmoduleWithName:path error:&error];
  if (submodule && [self.repository addSubmoduleToRepositoryIndex:submodule error:&error]) {
    [self.repository notifyRepositoryChanged];
  } else {
    [self presentError:error];
  }
}

- (void)unstageSubmoduleAtPath:(NSString*)path {
  NSError* error;
  if ([self.repository resetFileInIndexToHEAD:path error:&error]) {
    [self.repository notifyRepositoryChanged];
  } else {
    [self presentError:error];
  }
}

- (BOOL)discardSubmoduleAtPath:(NSString*)path resetIndex:(BOOL)resetIndex error:(NSError**)error {
  GCSubmodule* submodule = [self.repository lookupSubmoduleWithName:path error:error];
  return submodule && (!resetIndex || [self.repository resetFileInIndexToHEAD:path error:error]) && [self.repository updateSubmodule:submodule force:YES error:error];
}

- (void)discardSubmoduleAtPath:(NSString*)path resetIndex:(BOOL)resetIndex {
  [self confirmUserActionWithAlertType:kGIAlertType_Stop
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to discard changes in the submodule \"%@\"?", nil), path.lastPathComponent]
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Discard", nil)
             suppressionUserDefaultKey:nil
                                 block:^{
    
    NSError* error;
    if (![self discardSubmoduleAtPath:path resetIndex:resetIndex error:&error]) {
      [self presentError:error];
    }
    [self.repository notifyWorkingDirectoryChanged];
    
  }];
}

- (void)stageAllChangesForFile:(NSString*)path {
  NSError* error;
  BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:[self.repository absolutePathForFile:path]];
  if ((fileExists && [self.repository addFileToIndex:path error:&error]) || (!fileExists && [self.repository removeFileFromIndex:path error:&error])) {
    [self.repository notifyRepositoryChanged];
  } else {
    [self presentError:error];
  }
}

- (void)stageSelectedChangesForFile:(NSString*)path oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines {
  NSError* error;
  if ([self.repository addLinesFromFileToIndex:path error:&error usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
    
    if (change == kGCLineDiffChange_Added) {
      return [newLines containsIndex:newLineNumber];
    }
    if (change == kGCLineDiffChange_Deleted) {
      return [oldLines containsIndex:oldLineNumber];
    }
    return YES;
    
  }]) {
    [self.repository notifyRepositoryChanged];
  } else {
    [self presentError:error];
  }
}

- (void)unstageAllChangesForFile:(NSString*)path {
  NSError* error;
  if ([self.repository resetFileInIndexToHEAD:path error:&error]) {
    [self.repository notifyWorkingDirectoryChanged];
  } else {
    [self presentError:error];
  }
}

- (void)unstageSelectedChangesForFile:(NSString*)path oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines {
  NSError* error;
  if ([self.repository resetLinesFromFileInIndexToHEAD:path error:&error usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
    
    if (change == kGCLineDiffChange_Added) {
      return [newLines containsIndex:newLineNumber];
    }
    if (change == kGCLineDiffChange_Deleted) {
      return [oldLines containsIndex:oldLineNumber];
    }
    return NO;
    
  }]) {
    [self.repository notifyWorkingDirectoryChanged];
  } else {
    [self presentError:error];
  }
}

- (BOOL)discardAllChangesForFile:(NSString*)path resetIndex:(BOOL)resetIndex error:(NSError**)error {
  BOOL success = NO;
  if (resetIndex) {
    GCCommit* commit;
    if ([self.repository lookupHEADCurrentCommit:&commit branch:NULL error:error] && [self.repository resetFileInIndexToHEAD:path error:error]) {
      if (commit && [self.repository checkTreeForCommit:commit containsFile:path error:NULL]) {
        success = [self.repository safeDeleteFileIfExists:path error:error] && [self.repository checkoutFileFromIndex:path error:error];
      } else {
        success = [self.repository safeDeleteFile:path error:error];
      }
    }
  } else {
    success = [self.repository safeDeleteFileIfExists:path error:error] && [self.repository checkoutFileFromIndex:path error:error];
  }
  return success;
}

- (void)discardAllChangesForFile:(NSString*)path resetIndex:(BOOL)resetIndex {
  [self confirmUserActionWithAlertType:kGIAlertType_Stop
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to discard all changes from the file \"%@\"?", nil), path.lastPathComponent]
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Discard", nil)
             suppressionUserDefaultKey:nil
                                 block:^{
    
    NSError* error;
    if (![self discardAllChangesForFile:path resetIndex:resetIndex error:&error]) {
      [self presentError:error];
    }
    [self.repository notifyWorkingDirectoryChanged];
    
  }];
}

- (BOOL)discardSelectedChangesForFile:(NSString*)path oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines resetIndex:(BOOL)resetIndex error:(NSError**)error {
  if (resetIndex && ![self.repository resetFileInIndexToHEAD:path error:error]) {
    return NO;
  }
  return [self.repository checkoutLinesFromFileFromIndex:path error:error usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
    
    if (change == kGCLineDiffChange_Added) {
      return [newLines containsIndex:newLineNumber];
    }
    if (change == kGCLineDiffChange_Deleted) {
      return [oldLines containsIndex:oldLineNumber];
    }
    return NO;
    
  }];
}

- (void)discardSelectedChangesForFile:(NSString*)path oldLines:(NSIndexSet*)oldLines newLines:(NSIndexSet*)newLines resetIndex:(BOOL)resetIndex {
  [self confirmUserActionWithAlertType:kGIAlertType_Stop
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to discard selected changed lines from the file \"%@\"?", nil), path.lastPathComponent]
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Discard", nil)
             suppressionUserDefaultKey:nil
                                 block:^{
    
    NSError* error;
    if (![self discardSelectedChangesForFile:path oldLines:oldLines newLines:newLines resetIndex:resetIndex error:&error]) {
      [self presentError:error];
    }
    [self.repository notifyWorkingDirectoryChanged];
    
  }];
}

- (void)deleteUntrackedFile:(NSString*)path {
  [self confirmUserActionWithAlertType:kGIAlertType_Stop
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the file \"%@\"?", nil), path.lastPathComponent]
                               message:NSLocalizedString(@"This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Delete", nil)
             suppressionUserDefaultKey:nil
                                 block:^{
    
    NSError* error;
    if ([self.repository safeDeleteFile:path error:&error]) {
      [self.repository notifyWorkingDirectoryChanged];
    } else {
      [self presentError:error];
    }
    
  }];
}

- (void)restoreFile:(NSString*)path toCommit:(GCCommit*)commit {
  [self confirmUserActionWithAlertType:kGIAlertType_Stop
                                 title:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to restore the file \"%@\" to the version from this commit?", nil), path.lastPathComponent]
                               message:NSLocalizedString(@"Any local changes will be overwritten. This action cannot be undone.", nil)
                                button:NSLocalizedString(@"Restore", nil)
             suppressionUserDefaultKey:nil
                                 block:^{
    
    NSError* error;
    if (![self.repository safeDeleteFileIfExists:path error:&error] || ![self.repository checkoutFileToWorkingDirectory:path fromCommit:commit skipIndex:YES error:&error]) {
      [self presentError:error];
    }
    [self.repository notifyWorkingDirectoryChanged];
    
  }];
}

- (void)openFileWithDefaultEditor:(NSString*)path {
  [[NSWorkspace sharedWorkspace] openFile:[self.repository absolutePathForFile:path]];  // This will silently fail if the file doesn't exist in the working directory
}

- (void)showFileInFinder:(NSString*)path {
  [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:[self.repository absolutePathForFile:path]]]];
}

- (void)openSubmoduleWithApp:(NSString*)path {
  NSError* error;
  GCSubmodule* submodule = [self.repository lookupSubmoduleWithName:path error:&error];
  if (submodule) {
    GCRepository* subrepo = [[GCRepository alloc] initWithSubmodule:submodule error:&error];
    if (subrepo) {
        [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:subrepo.workingDirectoryPath]
                                                                             display:YES
                                                                   completionHandler:^(NSDocument* document, BOOL documentWasAlreadyOpen, NSError* openError) {
        
        if (!document) {
          [[NSDocumentController sharedDocumentController] presentError:openError];
        }
        
      }];
    } else if ([error.domain isEqualToString:GCErrorDomain] && (error.code == kGCErrorCode_NotFound)) {
      [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning format:NSLocalizedString(@"Submodule \"%@\" is not initialized", nil), submodule.name];
    } else {
      [self presentError:error];
    }
  } else {
    [self presentError:error];
  }
}

- (void)_runTaskWithPath:(NSString*)path arguments:(NSArray*)arguments variables:(NSDictionary*)variables waitUntilExit:(BOOL)wait reportErrors:(BOOL)report {
  NSMutableDictionary* environment = [[NSMutableDictionary alloc] initWithDictionary:[[NSProcessInfo processInfo] environment]];
  [environment addEntriesFromDictionary:variables];
  @try {
    NSTask* task = [[NSTask alloc] init];
    task.launchPath = path;
    task.arguments = arguments;
    task.environment = environment;
    task.currentDirectoryPath = self.repository.workingDirectoryPath;
    [task launch];
    if (wait) {
      [task waitUntilExit];
      if (report && task.terminationStatus) {
        [self presentError:[NSError errorWithDomain:NSPOSIXErrorDomain code:task.terminationStatus userInfo:@{
          NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Tool exited with non-zero status (%i)", task.terminationStatus],
          NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:@"%@ %@", path, [arguments componentsJoinedByString:@" "]]
        }]];
      }
    } else {
      // TODO: How to report errors?
    }
  }
  @catch (NSException* exception) {
    XLOG_EXCEPTION(exception);
    [self presentError:GCNewError(kGCErrorCode_Generic, exception.reason)];
  }
}

- (void)_runFileMergeWithArguments:(NSArray*)arguments {
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:kOpenDiffPath]) {
    [self _runTaskWithPath:kOpenDiffPath arguments:arguments variables:nil waitUntilExit:NO reportErrors:NO];  // opendiff hangs for a couple seconds before exiting
  } else {
    [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"FileMerge is not available!", nil) message:NSLocalizedString(@"FileMerge tool doesn't appear to be installed.", nil)];
  }
}

- (void)_runKaleidoscopeWithArguments:(NSArray*)arguments {
  if (([[NSFileManager defaultManager] isExecutableFileAtPath:kKSDiffPath])) {
    [self _runTaskWithPath:kKSDiffPath arguments:arguments variables:nil waitUntilExit:YES reportErrors:NO];
  } else {
    [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"Kaleidoscope is not available!", nil) message:NSLocalizedString(@"Kaleidoscope tool doesn't appear to be installed.", nil)];
  }
}

- (void)_runBeyondCompareWithArguments:(NSArray*)arguments {
  if (([[NSFileManager defaultManager] isExecutableFileAtPath:kBComparePath])) {
    [self _runTaskWithPath:kBComparePath arguments:arguments variables:nil waitUntilExit:YES reportErrors:NO];
  } else {
    [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"Beyond Compare is not available!", nil) message:NSLocalizedString(@"Beyond Compare tool doesn't appear to be installed.", nil)];
  }
}

- (void)_runP4MergeWithArguments:(NSArray*)arguments {
  if (([[NSFileManager defaultManager] isExecutableFileAtPath:kP4MergePath])) {
    [self _runTaskWithPath:kP4MergePath arguments:arguments variables:nil waitUntilExit:NO reportErrors:NO];  // launchp4merge is blocking
  } else {
    [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"P4Merge is not available!", nil) message:NSLocalizedString(@"P4Merge app doesn't appear to be installed.", nil)];
  }
}


// http://git-scm.com/docs/git-difftool
- (void)_runDiffGitToolForFile:(NSString*)file withOldPath:(NSString*)oldPath newPath:(NSString*)newPath {
  NSString* tool = [[self.repository readConfigOptionForVariable:@"diff.guitool" error:NULL] value];
  if (tool == nil) {
    tool = [[self.repository readConfigOptionForVariable:@"diff.tool" error:NULL] value];
  }
  NSString* cmd = tool ? [[self.repository readConfigOptionForVariable:[NSString stringWithFormat:@"difftool.%@.cmd", tool] error:NULL] value] : nil;
  if (cmd) {
    NSMutableDictionary* variables = [NSMutableDictionary dictionaryWithObject:file forKey:@"MERGED"];
    [variables setValue:oldPath forKey:@"LOCAL"];
    [variables setValue:newPath forKey:@"REMOTE"];
    [self _runTaskWithPath:@"/bin/bash" arguments:@[@"-l", @"-c", cmd] variables:variables waitUntilExit:YES reportErrors:YES];
  } else {
    [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"Git custom diff tool not available!", nil) message:NSLocalizedString(@"Git diff tool requires both 'diff.tool' (or 'diff.guitool') and 'difftool.<tool>.cmd' to be defined in your Git configuration.", nil)];
  }
}

// http://git-scm.com/docs/git-mergetool
- (void)_runMergeGitToolForFile:(NSString*)file withOldPath:(NSString*)oldPath newPath:(NSString*)newPath basePath:(NSString*)basePath {
  NSString* tool = [[self.repository readConfigOptionForVariable:@"merge.tool" error:NULL] value];
  NSString* cmd = tool ? [[self.repository readConfigOptionForVariable:[NSString stringWithFormat:@"mergetool.%@.cmd", tool] error:NULL] value] : nil;
  if (cmd) {
    NSMutableDictionary* variables = [NSMutableDictionary dictionaryWithObject:file forKey:@"MERGED"];
    [variables setValue:basePath forKey:@"BASE"];
    [variables setValue:oldPath forKey:@"LOCAL"];
    [variables setValue:newPath forKey:@"REMOTE"];
    [self _runTaskWithPath:@"/bin/bash" arguments:@[@"-l", @"-c", cmd] variables:variables waitUntilExit:YES reportErrors:YES];
  } else {
    [self presentAlertWithType:kGIAlertType_Stop title:NSLocalizedString(@"Git custom merge tool not available!", nil) message:NSLocalizedString(@"Git merge tool requires both 'merge.tool' and 'mergetool.<tool>.cmd' to be defined in your Git configuration.", nil)];
  }
}

- (void)viewDeltasInDiffTool:(NSArray*)deltas {
  NSString* uuid = nil;
  NSError* error;
  for (GCDiffDelta* delta in deltas) {
    NSString* oldPath = [_diffTemporaryDirectoryPath stringByAppendingPathComponent:delta.oldFile.SHA1];
    NSString* oldExtension = delta.oldFile.path.pathExtension;
    if (oldExtension.length) {
      oldPath = [oldPath stringByAppendingPathExtension:oldExtension];
    }
    if (![self.repository exportBlobWithSHA1:delta.oldFile.SHA1 toPath:oldPath error:&error]) {
      [self presentError:error];
      return;
    }
    NSString* oldTitle = delta.oldFile.path;
    
    NSString* newPath;
    if ((delta.diff.type == kGCDiffType_WorkingDirectoryWithCommit) || (delta.diff.type == kGCDiffType_WorkingDirectoryWithIndex)) {
      newPath = [self.repository absolutePathForFile:delta.newFile.path];
    } else {
      newPath = [_diffTemporaryDirectoryPath stringByAppendingPathComponent:delta.newFile.SHA1];
      NSString* newExtension = delta.newFile.path.pathExtension;
      if (newExtension.length) {
        newPath = [newPath stringByAppendingPathExtension:newExtension];
      }
      if (![self.repository exportBlobWithSHA1:delta.newFile.SHA1 toPath:newPath error:&error]) {
        [self presentError:error];
        return;
      }
    }
    NSString* newTitle = delta.newFile.path;
    
    NSString* identifier = [[NSUserDefaults standardUserDefaults] stringForKey:GIViewController_DiffTool];
    if ([identifier isEqualToString:GIViewControllerTool_FileMerge]) {
      [self _runFileMergeWithArguments:@[oldPath, newPath]];
    } else if ([identifier isEqualToString:GIViewControllerTool_Kaleidoscope]) {
      if (uuid == nil) {
        uuid = [[NSUUID UUID] UUIDString];
      }
      [self _runKaleidoscopeWithArguments:@[@"--partial-changeset", @"--UUID", uuid, @"--no-wait", @"--label", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"], @"--relative-path", delta.canonicalPath, oldPath, newPath]];
    } else if ([identifier isEqualToString:GIViewControllerTool_BeyondCompare]) {
      [self _runBeyondCompareWithArguments:@[[NSString stringWithFormat:@"-title1=%@", oldTitle], [NSString stringWithFormat:@"-title2=%@", newTitle], oldPath, newPath]];
    } else if ([identifier isEqualToString:GIViewControllerTool_P4Merge]) {
      [self _runP4MergeWithArguments:@[@"-nl", oldTitle, @"-nr", newTitle, oldPath, newPath]];
    } else if ([identifier isEqualToString:GIViewControllerTool_GitTool]) {
      [self _runDiffGitToolForFile:delta.canonicalPath withOldPath:oldPath newPath:newPath];
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }
  }
  if (uuid) {
    [self _runKaleidoscopeWithArguments:@[@"--mark-changeset-as-closed", uuid]];
  }
}

- (void)resolveConflictInMergeTool:(GCIndexConflict*)conflict {
  NSString* basePath = [_diffTemporaryDirectoryPath stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString* extension = conflict.path.pathExtension;
  NSError* error;
  
  if (![[NSFileManager defaultManager] createDirectoryAtPath:basePath withIntermediateDirectories:NO attributes:nil error:&error]) {
    [self presentError:error];
    return;
  }
  
  NSString* ourPath = [basePath stringByAppendingPathComponent:@"ours"];
  if (extension.length) {
    ourPath = [ourPath stringByAppendingPathExtension:extension];
  }
  NSString* ourSHA1 = conflict.ourBlobSHA1;
  if ((ourSHA1 && ![self.repository exportBlobWithSHA1:ourSHA1 toPath:ourPath error:&error]) || (!ourSHA1 && ![[NSData data] writeToFile:ourPath options:0 error:&error])) {
    [self presentError:error];
    return;
  }
  NSString* ourTitle = @"Ours";
  
  NSString* theirPath = [basePath stringByAppendingPathComponent:@"theirs"];
  if (extension.length) {
    theirPath = [theirPath stringByAppendingPathExtension:extension];
  }
  NSString* theirSHA1 = conflict.theirBlobSHA1;
  if ((theirSHA1 && ![self.repository exportBlobWithSHA1:theirSHA1 toPath:theirPath error:&error]) || (!theirSHA1 && ![[NSData data] writeToFile:theirPath options:0 error:&error])) {
    [self presentError:error];
    return;
  }
  NSString* theirTitle = @"Theirs";
  
  NSString* ancestorPath = nil;
  NSString* ancestorSHA1 = conflict.ancestorBlobSHA1;
  if (ancestorSHA1) {
    ancestorPath = [basePath stringByAppendingPathComponent:@"ancestor"];
    if (extension.length) {
      ancestorPath = [ancestorPath stringByAppendingPathExtension:extension];
    }
    if (![self.repository exportBlobWithSHA1:ancestorSHA1 toPath:ancestorPath error:&error]) {
      [self presentError:error];
      return;
    }
  }
  NSString* ancestorTitle = @"Ancestor";
  
  NSString* mergePath = [self.repository absolutePathForFile:conflict.path];
  NSString* mergeTitle = conflict.path.lastPathComponent;
  
  NSMutableArray* arguments = [[NSMutableArray alloc] init];
  NSString* identifier = [[NSUserDefaults standardUserDefaults] stringForKey:GIViewController_MergeTool];
  if ([identifier isEqualToString:GIViewControllerTool_FileMerge]) {
    [arguments addObject:ourPath];
    [arguments addObject:theirPath];
    if (ancestorPath) {
      [arguments addObject:@"-ancestor"];
      [arguments addObject:ancestorPath];
    }
    [arguments addObject:@"-merge"];
    [arguments addObject:mergePath];
    [self _runFileMergeWithArguments:arguments];
  } else if ([identifier isEqualToString:GIViewControllerTool_Kaleidoscope]) {
    [arguments addObject:@"--merge"];
    [arguments addObject:@"--no-wait"];
    [arguments addObject:@"--output"];
    [arguments addObject:mergePath];
    if (ancestorPath) {
      [arguments addObject:@"--base"];
      [arguments addObject:ancestorPath];
    }
    [arguments addObject:ourPath];
    [arguments addObject:theirPath];
    [self _runKaleidoscopeWithArguments:arguments];
  } else if ([identifier isEqualToString:GIViewControllerTool_BeyondCompare]) {
    [arguments addObject:[NSString stringWithFormat:@"-title1=%@", ourTitle]];
    [arguments addObject:[NSString stringWithFormat:@"-title2=%@", theirTitle]];
    if (ancestorPath) {
      [arguments addObject:[NSString stringWithFormat:@"-title3=%@", ancestorTitle]];
    }
    [arguments addObject:[NSString stringWithFormat:@"-title4=%@", mergeTitle]];
    [arguments addObject:[NSString stringWithFormat:@"-mergeoutput=%@", mergePath]];
    [arguments addObject:ourPath];
    [arguments addObject:theirPath];
    if (ancestorPath) {
      [arguments addObject:ancestorPath];
    }
    [self _runBeyondCompareWithArguments:arguments];
  } else if ([identifier isEqualToString:GIViewControllerTool_P4Merge]) {
    [arguments addObject:@"-nl"];
    [arguments addObject:ourTitle];
    [arguments addObject:@"-nr"];
    [arguments addObject:theirTitle];
    if (ancestorPath) {
      [arguments addObject:@"-nb"];
      [arguments addObject:ancestorTitle];
    }
    [arguments addObject:@"-nm"];
    [arguments addObject:mergeTitle];
    if (ancestorPath) {
      [arguments addObject:ancestorPath];
    }
    [arguments addObject:ourPath];
    [arguments addObject:theirPath];
    [arguments addObject:mergePath];
    [self _runP4MergeWithArguments:arguments];
  } else if ([identifier isEqualToString:GIViewControllerTool_GitTool]) {
    [self _runMergeGitToolForFile:mergePath withOldPath:ourPath newPath:theirPath basePath:ancestorPath];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (void)markConflictAsResolved:(GCIndexConflict*)conflict {
  NSError* error;
  if ([self.repository resolveConflictAtPath:conflict.path error:&error]) {
    [self.repository notifyWorkingDirectoryChanged];
  } else {
    [self presentError:error];
  }
}

- (GCCommit*)resolveConflictsWithResolver:(id<GIMergeConflictResolver>)resolver
                                    index:(GCIndex*)index
                                ourCommit:(GCCommit*)ourCommit
                              theirCommit:(GCCommit*)theirCommit
                            parentCommits:(NSArray*)parentCommits
                                  message:(NSString*)message
                                    error:(NSError**)error {
  XLOG_DEBUG_CHECK(parentCommits.count <= 2);
  
  // Ensure repository is completely clean
  NSError* localError;
  if (![self.repository checkClean:0 error:&localError]) {
    if ([localError.domain isEqualToString:GCErrorDomain] && (localError.code == kGCErrorCode_RepositoryDirty)) {
      [self.windowController showOverlayWithStyle:kGIOverlayStyle_Warning message:NSLocalizedString(@"Operation results in merge conflicts and repository must be clean to resolve them", nil)];
      GC_SET_USER_CANCELLED_ERROR();
    } else if (error) {
      *error = localError;
    }
    return nil;
  }
  
  // Save HEAD
  GCCommit* headCommit;
  GCLocalBranch* headBranch;
  if (![self.repository lookupHEADCurrentCommit:&headCommit branch:&headBranch error:error]) {
    return nil;
  }
  
  // Detach HEAD to "ours" commit
  if (![self.repository checkoutCommit:parentCommits[0] options:0 error:error]) {
    return nil;
  }
  
  // Check out index with conflicts
  if (![self.repository checkoutIndex:index withOptions:kGCCheckoutOption_UpdateSubmodulesRecursively error:error]) {
    return nil;
  }
  
  // Have user resolve conflicts
  BOOL resolved = [resolver resolveMergeConflictsWithOurCommit:ourCommit theirCommit:theirCommit];
  
  // Unless user cancelled, create commit with "ours" and "theirs" parent commits (if applicable)
  GCCommit* commit = nil;
  if (resolved) {
    if (![self.repository syncIndexWithWorkingDirectory:error]) {
      return nil;
    }
    commit = [self.repository createCommitFromHEADAndOtherParent:(parentCommits.count > 1 ? parentCommits[1] : nil) withMessage:message error:error];
    if (commit == nil) {
      return nil;
    }
  }
  
  // Restore HEAD
  if ((headBranch && ![self.repository setHEADToReference:headBranch error:error]) || (!headBranch && ![self.repository setDetachedHEADToCommit:headCommit error:error])) {
    return nil;
  }
  if (![self.repository forceCheckoutHEAD:YES error:error]) {
    return nil;
  }
  
  // Check if user cancelled
  if (!resolved) {
    GC_SET_USER_CANCELLED_ERROR();
    return nil;
  }
  
  return commit;
}

// Keep logic in sync with method below!
- (NSMenu*)contextualMenuForDelta:(GCDiffDelta*)delta withConflict:(GCIndexConflict*)conflict allowOpen:(BOOL)allowOpen {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
  
  if (conflict) {
    [menu addItemWithTitle:NSLocalizedString(@"Resolve in Merge Tool…", nil) block:^{
      [self resolveConflictInMergeTool:conflict];
    }];
    [menu addItemWithTitle:NSLocalizedString(@"Mark as Resolved", nil) block:^{
      [self markConflictAsResolved:conflict];
    }];
  } else {
    if (GC_FILE_MODE_IS_FILE(delta.oldFile.mode) && GC_FILE_MODE_IS_FILE(delta.newFile.mode)) {
      [menu addItemWithTitle:NSLocalizedString(@"View in Diff Tool…", nil) block:^{
        [self viewDeltasInDiffTool:@[delta]];
      }];
    } else {
      [menu addItemWithTitle:NSLocalizedString(@"View in Diff Tool…", nil) block:NULL];
    }
  }
  
  if (allowOpen) {
    [menu addItem:[NSMenuItem separatorItem]];
    
    if (delta.submodule) {
      [menu addItemWithTitle:NSLocalizedString(@"Open Submodule…", nil) block:^{
        [self openSubmoduleWithApp:delta.canonicalPath];
      }];
    } else {
      [menu addItemWithTitle:NSLocalizedString(@"Open File…", nil) block:^{
        [self openFileWithDefaultEditor:delta.canonicalPath];
      }];
    }
    
    [menu addItemWithTitle:NSLocalizedString(@"Show in Finder…", nil) block:^{
      [self showFileInFinder:delta.canonicalPath];
    }];
  }
  
  return menu;
}

// Keep logic in sync with method above!
- (BOOL)handleKeyDownEvent:(NSEvent*)event forSelectedDeltas:(NSArray*)deltas withConflicts:(NSDictionary*)conflicts allowOpen:(BOOL)allowOpen {
  if (deltas.count) {
    NSString* characters = event.charactersIgnoringModifiers;
    if ([characters rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet] options:0].location != NSNotFound) {  // Skip if key event is for arrow keys, return key, etc...
      if (allowOpen && [characters isEqualToString:@"o"]) {
        for (GCDiffDelta* delta in deltas) {
          if (delta.submodule) {
            [self openSubmoduleWithApp:delta.canonicalPath];
          } else {
            [self openFileWithDefaultEditor:delta.canonicalPath];
          }
        }
        return YES;
      } else if ([characters isEqualToString:@"d"]) {
        NSMutableArray* array = [[NSMutableArray alloc] init];
        for (GCDiffDelta* delta in deltas) {
          GCIndexConflict* conflict = [conflicts objectForKey:delta.canonicalPath];
          if (!conflict && GC_FILE_MODE_IS_FILE(delta.oldFile.mode) && GC_FILE_MODE_IS_FILE(delta.newFile.mode)) {
            [array addObject:delta];
          }
        }
        if (array.count) {
          [self viewDeltasInDiffTool:array];
        }
        return YES;
      } else if ([characters isEqualToString:@"r"]) {
        for (GCDiffDelta* delta in deltas) {
          GCIndexConflict* conflict = [conflicts objectForKey:delta.canonicalPath];
          if (conflict) {
            [self resolveConflictInMergeTool:conflict];
          }
        }
        return YES;
      } else if ([characters isEqualToString:@"m"]) {
        for (GCDiffDelta* delta in deltas) {
          GCIndexConflict* conflict = [conflicts objectForKey:delta.canonicalPath];
          if (conflict) {
            [self markConflictAsResolved:conflict];
          }
        }
        return YES;
      }
    }
  }
  return NO;
}

// TODO: Use private app directory
- (void)launchDiffToolWithCommit:(GCCommit*)commit otherCommit:(GCCommit*)otherCommit {
  NSString* identifier = [[NSUserDefaults standardUserDefaults] stringForKey:GIViewController_DiffTool];
  NSString* uuid = nil;
  NSError* error;
  
  GCDiff* diff = [self.repository diffCommit:commit withCommit:otherCommit filePattern:nil options:0 maxInterHunkLines:0 maxContextLines:0 error:&error];
  if (diff == nil) {
    [self presentError:error];
    return;
  }
  
  NSString* newPath = [_diffTemporaryDirectoryPath stringByAppendingPathComponent:commit.shortSHA1];
  [[NSFileManager defaultManager] removeItemAtPath:newPath error:&error];
  if (![[NSFileManager defaultManager] createDirectoryAtPath:newPath withIntermediateDirectories:NO attributes:nil error:&error]) {
    [self presentError:error];
    return;
  }
  NSString* oldTitle = commit.shortSHA1;
  
  NSString* oldPath = [_diffTemporaryDirectoryPath stringByAppendingPathComponent:otherCommit.shortSHA1];
  [[NSFileManager defaultManager] removeItemAtPath:oldPath error:&error];
  if (![[NSFileManager defaultManager] createDirectoryAtPath:oldPath withIntermediateDirectories:NO attributes:nil error:&error]) {
    [self presentError:error];
    return;
  }
  NSString* newTitle = otherCommit.shortSHA1;
  
  for (GCDiffDelta* delta in diff.deltas) {
    switch (delta.change) {
      
      case kGCFileDiffChange_Added:
      case kGCFileDiffChange_Modified:
      case kGCFileDiffChange_Deleted: {
        NSString* oldPath2 = [oldPath stringByAppendingPathComponent:delta.canonicalPath];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:[oldPath2 stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error]) {
          [self presentError:error];
          return;
        }
        NSString* oldSHA1 = delta.oldFile.SHA1;
        XLOG_DEBUG_CHECK(oldSHA1 || (delta.change == kGCFileDiffChange_Added));
        if ((oldSHA1 && ![self.repository exportBlobWithSHA1:oldSHA1 toPath:oldPath2 error:&error]) || (!oldSHA1 && ![[NSData data] writeToFile:oldPath2 options:0 error:&error])) {
          [self presentError:error];
          return;
        }
        
        NSString* newPath2 = [newPath stringByAppendingPathComponent:delta.canonicalPath];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:[newPath2 stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error]) {
          [self presentError:error];
          return;
        }
        NSString* newSHA1 = delta.newFile.SHA1;
        XLOG_DEBUG_CHECK(newSHA1 || (delta.change == kGCFileDiffChange_Deleted));
        if ((newSHA1 && ![self.repository exportBlobWithSHA1:newSHA1 toPath:newPath2 error:&error]) || (!newSHA1 && ![[NSData data] writeToFile:newPath2 options:0 error:&error])) {
          [self presentError:error];
          return;
        }
        
        if ([identifier isEqualToString:GIViewControllerTool_Kaleidoscope]) {
          if (uuid == nil) {
            uuid = [[NSUUID UUID] UUIDString];
          }
          [self _runKaleidoscopeWithArguments:@[@"--partial-changeset", @"--UUID", uuid, @"--no-wait", @"--label", [NSString stringWithFormat:@"%@ ▶ %@", oldTitle, newTitle], @"--relative-path", delta.canonicalPath, oldPath2, newPath2]];
        } else if ([identifier isEqualToString:GIViewControllerTool_P4Merge]) {
          NSString* oldTitle2 = [NSString stringWithFormat:@"[%@] %@", oldTitle, delta.oldFile.path];
          NSString* newTitle2 = [NSString stringWithFormat:@"[%@] %@", newTitle, delta.newFile.path];
          [self _runP4MergeWithArguments:@[@"-nl", oldTitle2, @"-nr", newTitle2, oldPath2, newPath2]];
          usleep(250 * 1000);  // TODO: Calling launchp4merge too frequently drops diffs
        } else if ([identifier isEqualToString:GIViewControllerTool_GitTool]) {
          [self _runDiffGitToolForFile:delta.canonicalPath withOldPath:oldPath2 newPath:newPath2];
        }
        break;
      }
      
      default:
        XLOG_DEBUG_UNREACHABLE();
        break;
      
    }
  }
  
  if ([identifier isEqualToString:GIViewControllerTool_FileMerge]) {
    [self _runFileMergeWithArguments:@[oldPath, newPath]];
  } else if ([identifier isEqualToString:GIViewControllerTool_Kaleidoscope]) {
    if (uuid) {
      [self _runKaleidoscopeWithArguments:@[@"--mark-changeset-as-closed", uuid]];
    }
  } else if ([identifier isEqualToString:GIViewControllerTool_BeyondCompare]) {
    [self _runBeyondCompareWithArguments:@[[NSString stringWithFormat:@"-title1=%@", oldTitle], [NSString stringWithFormat:@"-title2=%@", newTitle], oldPath, newPath]];
  } else if ([identifier isEqualToString:GIViewControllerTool_P4Merge] || [identifier isEqualToString:GIViewControllerTool_GitTool]) {
    ;  // Handled above
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

@end
