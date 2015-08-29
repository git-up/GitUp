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

// Core
#import <GitUpKit/GCCore.h>

// Extensions
#import <GitUpKit/GCHistory+Rewrite.h>
#import <GitUpKit/GCRepository+Index.h>
#import <GitUpKit/GCRepository+Utilities.h>

// Interface
#import <GitUpKit/GIInterface.h>

#if __GI_HAS_APPKIT__

// Utilities
#import <GitUpKit/GIAppKit.h>
#import <GitUpKit/GIColorView.h>
#import <GitUpKit/GILinkButton.h>
#import <GitUpKit/GIModalView.h>
#import <GitUpKit/GIViewController.h>
#import <GitUpKit/GIViewController+Utilities.h>
#import <GitUpKit/GIWindowController.h>

// Components
#import <GitUpKit/GICommitListViewController.h>
#import <GitUpKit/GIDiffContentsViewController.h>
#import <GitUpKit/GIDiffFilesViewController.h>
#import <GitUpKit/GISnapshotListViewController.h>
#import <GitUpKit/GIUnifiedReflogViewController.h>

// Views
#import <GitUpKit/GIAdvancedCommitViewController.h>
#import <GitUpKit/GICommitRewriterViewController.h>
#import <GitUpKit/GICommitSplitterViewController.h>
#import <GitUpKit/GICommitViewController.h>
#import <GitUpKit/GIConfigViewController.h>
#import <GitUpKit/GIConflictResolverViewController.h>
#import <GitUpKit/GIDiffViewController.h>
#import <GitUpKit/GIMapViewController.h>
#import <GitUpKit/GIMapViewController+Operations.h>
#import <GitUpKit/GIQuickViewController.h>
#import <GitUpKit/GISimpleCommitViewController.h>
#import <GitUpKit/GIStashListViewController.h>

#endif
