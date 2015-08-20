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
@property(nonatomic, weak) IBOutlet GIWindow* window;
@end

@implementation AppDelegate {
  GCLiveRepository* _repository;
  GIWindowController* _windowController;
  GIStashListViewController* _viewController;
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
  
  // Create the stash view controller and add its view to the window
  _viewController = [[GIStashListViewController alloc] initWithRepository:_repository];
  _viewController.view.frame = [_window.contentView bounds];
  [_window.contentView addSubview:_viewController.view];
  
  // Show the window
  [_window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  return YES;
}

@end
