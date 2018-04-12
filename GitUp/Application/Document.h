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

#import <AppKit/AppKit.h>

typedef NS_ENUM(NSUInteger, CloneMode) {
  kCloneMode_None = 0,
  kCloneMode_Default,
  kCloneMode_Recursive
};

typedef NS_ENUM(NSUInteger, WindowModeID) {
  kWindowModeID_Map = 0,
  kWindowModeID_Commit,
  kWindowModeID_Stashes
};

@interface Document : NSDocument <NSUserInterfaceValidations>
@property(nonatomic, strong) IBOutlet NSWindow* mainWindow;
@property(nonatomic, strong) IBOutlet NSView* contentView;

@property(nonatomic, strong) IBOutlet NSToolbar* toolbar;

@property(nonatomic, weak) IBOutlet NSView* helpView;
@property(nonatomic, weak) IBOutlet NSTextField* helpTextField;
@property(nonatomic, weak) IBOutlet NSButton* helpContinueButton;
@property(nonatomic, weak) IBOutlet NSButton* helpDismissButton;
@property(nonatomic, weak) IBOutlet NSButton* helpOpenButton;

@property(nonatomic, weak) IBOutlet NSTabView* mainTabView;
@property(nonatomic, weak) IBOutlet NSView* mapContainerView;

@property(nonatomic, strong) IBOutlet NSView* titleView;
@property(nonatomic, weak) IBOutlet NSTextField* titleTextField;
@property(nonatomic, weak) IBOutlet NSTextField* infoTextField0;

@property(nonatomic, strong) IBOutlet NSView* leftView;
@property(nonatomic, weak) IBOutlet NSSegmentedControl* modeControl;
@property(nonatomic, weak) IBOutlet NSButton* previousButton;
@property(nonatomic, weak) IBOutlet NSButton* nextButton;

@property(nonatomic, strong) IBOutlet NSView* rightView;
@property(nonatomic, weak) IBOutlet NSButton* snapshotsButton;
@property(nonatomic, weak) IBOutlet NSSearchField* searchField;
@property(nonatomic, weak) IBOutlet NSButton* exitButton;

@property(nonatomic, strong) IBOutlet NSView* mapView;
@property(nonatomic, weak) IBOutlet NSView* mapControllerView;  // Temporary placeholder replaced by actual controller view at load time
@property(nonatomic, weak) IBOutlet NSView* bottomView;
@property(nonatomic, weak) IBOutlet NSMenu* showMenu;
@property(nonatomic, weak) IBOutlet NSTextField* infoTextField1;
@property(nonatomic, weak) IBOutlet NSTextField* infoTextField2;
@property(nonatomic, weak) IBOutlet NSTextField* progressTextField;
@property(nonatomic, weak) IBOutlet NSProgressIndicator* progressIndicator;
@property(nonatomic, weak) IBOutlet NSButton* pullButton;
@property(nonatomic, weak) IBOutlet NSButton* pushButton;
@property(nonatomic, weak) IBOutlet NSView* hiddenWarningView;

@property(nonatomic, strong) IBOutlet NSView* tagsView;
@property(nonatomic, weak) IBOutlet NSView* tagsControllerView;  // Temporary placeholder replaced by actual controller view at load time
@property(weak) IBOutlet NSView* tagsBottomView;

@property(nonatomic, strong) IBOutlet NSView* snapshotsView;
@property(nonatomic, weak) IBOutlet NSView* snapshotsControllerView;  // Temporary placeholder replaced by actual controller view at load time
@property(weak) IBOutlet NSView* snapshotsBottomView;

@property(nonatomic, strong) IBOutlet NSView* reflogView;
@property(nonatomic, weak) IBOutlet NSView* reflogControllerView;  // Temporary placeholder replaced by actual controller view at load time
@property(weak) IBOutlet NSView* reflogBottomView;

@property(nonatomic, strong) IBOutlet NSView* searchView;
@property(nonatomic, weak) IBOutlet NSView* searchControllerView;  // Temporary placeholder replaced by actual controller view at load time

@property(nonatomic, strong) IBOutlet NSView* ancestorsView;
@property(nonatomic, weak) IBOutlet NSView* ancestorsControllerView;  // Temporary placeholder replaced by actual controller view at load time
@property(nonatomic, weak) IBOutlet NSView* ancestorsBottomView;

@property(nonatomic, strong) IBOutlet NSView* rewriteView;
@property(nonatomic, weak) IBOutlet NSView* rewriteControllerView;  // Temporary placeholder replaced by actual controller view at load time

@property(nonatomic, strong) IBOutlet NSView* splitView;
@property(nonatomic, weak) IBOutlet NSView* splitControllerView;  // Temporary placeholder replaced by actual controller view at load time

@property(nonatomic, strong) IBOutlet NSView* resolveView;
@property(nonatomic, weak) IBOutlet NSView* resolveControllerView;  // Temporary placeholder replaced by actual controller view at load time

@property(nonatomic, strong) IBOutlet NSView* resetView;
@property(nonatomic, weak) IBOutlet NSButton* untrackedButton;

@property(nonatomic, strong) IBOutlet NSWindow* settingsWindow;
@property(nonatomic, weak) IBOutlet NSButton* indexDiffsButton;

@property(nonatomic) CloneMode cloneMode;
@property(nonatomic, readonly) NSString* windowMode;

- (BOOL)setWindowModeID:(WindowModeID)modeID;
- (BOOL)shouldCloseDocument;
@end
