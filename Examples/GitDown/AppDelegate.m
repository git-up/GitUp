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

#import <GitUpKit/GitUpKit.h>

#import "AppDelegate.h"

@interface AppDelegate ()
@property(nonatomic, strong) IBOutlet GIWindow* window;
@end

// GIDiffContentsViewController is a view controller that displays the contents of an arbitrary diff
// This subclass automatically sets the diff to the one between HEAD and workdir (like 'git diff HEAD') and live updates it
@interface LiveDiffViewController : GIDiffContentsViewController
@end

@implementation LiveDiffViewController

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithRepository:repository])) {
    // Customize the text displayed when the diff is empty
    self.emptyLabel = NSLocalizedString(@"Working directory and index are clean", nil);
  }
  return self;
}

- (void)viewWillShow {
  // Configure the repo to automatically compute the HEAD to workdir diff (aka "unified status")
  self.repository.statusMode = kGCLiveRepositoryStatusMode_Unified;
  
  // Refresh contents immediately
  [self _reloadContents];
}

- (void)viewDidHide {
  // Unload the diff to save memory
  [self setDeltas:nil usingConflicts:nil];
  
  // Stop watching the repo status as it's not needed anymore
  self.repository.statusMode = kGCLiveRepositoryStatusMode_Disabled;
}

- (void)_reloadContents {
  // Simply set the diff to display to the unified status one, taking into account any conflicts
  GCDiff* status = self.repository.unifiedStatus;
  NSDictionary* conflicts = self.repository.indexConflicts;
  [self setDeltas:status.deltas usingConflicts:conflicts];
}

- (void)repositoryStatusDidUpdate {
  // Refresh the diff if the repo status has been updated
  if (self.viewVisible) {
    [self _reloadContents];
  }
}

@end

@implementation AppDelegate {
  GCLiveRepository* _repository;
  GIWindowController* _windowController;
  GIViewController* _viewController;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  NSError* error;
  
  // Prompt user for a directory
  NSOpenPanel* openPanel = [NSOpenPanel openPanel];
  openPanel.canChooseDirectories = YES;
  openPanel.canChooseFiles = NO;
  if ([openPanel runModal] != NSFileHandlingPanelOKButton) {
    [NSApp terminate:nil];
  }
  NSString* path = openPanel.URL.path;
  
  // Attempt to open the directory as a Git repo
  _repository = [[GCLiveRepository alloc] initWithExistingLocalRepository:path error:&error];
  if (_repository == nil) {
    [NSApp presentError:error];
    [NSApp terminate:nil];
  }
  
  // A repo must have an associated NSUndoManager for the undo/redo system to work
  // We simply use the one of the window
  _repository.undoManager = _window.undoManager;
  
  // Each GIWindow expects a GIWindowController around
  _windowController = [[GIWindowController alloc] initWithWindow:_window];
  
  // Create the view controller and add its view to the window
#if 1
  _viewController = [[GIStashListViewController alloc] initWithRepository:_repository];
#elif 0
  _viewController = [[GIAdvancedCommitViewController alloc] initWithRepository:_repository];
#else
  _viewController = [[LiveDiffViewController alloc] initWithRepository:_repository];
#endif
  _viewController.view.frame = [_window.contentView bounds];
  [_window.contentView addSubview:_viewController.view];
  
  // Show the window
  [_window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  return YES;
}

@end
