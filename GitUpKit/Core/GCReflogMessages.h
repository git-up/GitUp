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

#import <Foundation/Foundation.h>

/***** These reflog messages are the ones used by Git as of version 1.9.3 *****/

#define kGCReflogMessagePrefix_Git_Checkout "checkout: "
#define kGCReflogMessageFormat_Git_Checkout @kGCReflogMessagePrefix_Git_Checkout "moving from %@ to %@"

#define kGCReflogMessagePrefix_Git_Commit "commit: "
#define kGCReflogMessageFormat_Git_Commit @kGCReflogMessagePrefix_Git_Commit "%@"

#define kGCReflogMessagePrefix_Git_Commit_Initial "commit (initial): "
#define kGCReflogMessageFormat_Git_Commit_Initial @kGCReflogMessagePrefix_Git_Commit_Initial "%@"

#define kGCReflogMessagePrefix_Git_Commit_Amend "commit (amend): "
#define kGCReflogMessageFormat_Git_Commit_Amend @kGCReflogMessagePrefix_Git_Commit_Amend "%@"

#define kGCReflogMessagePrefix_Git_Branch_Created "branch: Created "
#define kGCReflogMessageFormat_Git_Branch_Created @kGCReflogMessagePrefix_Git_Branch_Created "from %@"

#define kGCReflogMessagePrefix_Git_Branch_Renamed "Branch: renamed "
#define kGCReflogMessageFormat_Git_Branch_Renamed @kGCReflogMessagePrefix_Git_Branch_Renamed "%@ to %@"

#define kGCReflogMessagePrefix_Git_Revert "revert: "
#define kGCReflogMessageFormat_Git_Revert @kGCReflogMessagePrefix_Git_Revert "Revert \"%@\""

#define kGCReflogMessagePrefix_Git_Merge "merge "
#define kGCReflogMessageFormat_Git_Merge @kGCReflogMessagePrefix_Git_Merge "%@: Merge made by the 'recursive' strategy."
#define kGCReflogMessageFormat_Git_Merge_FastForward @kGCReflogMessagePrefix_Git_Merge "%@: Fast-forward"

#define kGCReflogMessagePrefix_Rebase "rebase"  // Could be "rebase: " or "rebase finished: " and maybe more

#define kGCReflogMessagePrefix_Git_CherryPick "cherry-pick: "
#define kGCReflogMessageFormat_Git_CherryPick @kGCReflogMessagePrefix_Git_CherryPick "%@"

#define kGCReflogMessagePrefix_Git_Reset "reset: "
#define kGCReflogMessageFormat_Git_Reset @kGCReflogMessagePrefix_Git_Reset "moving to %@"

#define kGCReflogMessagePrefix_Git_Fetch "fetch "
#define kGCReflogMessageFormat_Git_Fetch @kGCReflogMessagePrefix_Git_Fetch "%@"

#define kGCReflogMessagePrefix_Git_Push "push "
#define kGCReflogMessageFormat_Git_Push @kGCReflogMessagePrefix_Git_Push "%@"

#define kGCReflogMessagePrefix_Git_Pull "pull: "

#define kGCReflogMessagePrefix_Git_Clone "clone: "

/***** These reflog messages are used by GitUp *****/

#define kGCReflogCustomPrefix "[gitup] "

#define kGCReflogMessageFormat_GitUp_Merge @kGCReflogCustomPrefix @"merge %@"
#define kGCReflogMessageFormat_GitUp_Merge_FastForward @kGCReflogCustomPrefix "merge %@: Fast-forward"
#define kGCReflogMessageFormat_GitUp_Rebase @kGCReflogCustomPrefix @"rebase %@ onto %@"
#define kGCReflogMessageFormat_GitUp_Swap @kGCReflogCustomPrefix @"swap %@ with parent %@"
#define kGCReflogMessageFormat_GitUp_RestoreSnapshot @kGCReflogCustomPrefix @"restore snapshot"
#define kGCReflogMessageFormat_GitUp_Rewrite @kGCReflogCustomPrefix @"rewrite %@"
#define kGCReflogMessageFormat_GitUp_Delete @kGCReflogCustomPrefix @"delete %@"
#define kGCReflogMessageFormat_GitUp_Squash @kGCReflogCustomPrefix @"squash %@"
#define kGCReflogMessageFormat_GitUp_Fixup @kGCReflogCustomPrefix @"fixup %@"
#define kGCReflogMessageFormat_GitUp_Revert @kGCReflogCustomPrefix @"revert %@"
#define kGCReflogMessageFormat_GitUp_CherryPick @kGCReflogCustomPrefix @"cherry-pick %@"
#define kGCReflogMessageFormat_GitUp_SetTip @kGCReflogCustomPrefix @"set tip"
#define kGCReflogMessageFormat_GitUp_MoveTip @kGCReflogCustomPrefix @"move tip"

//#define kGCReflogMessageFormat_GitUp_HardReset @kGCReflogCustomPrefix @"hard reset for '%@'"
#define kGCReflogMessageFormat_GitUp_Undo @kGCReflogCustomPrefix @"undo '%@'"
#define kGCReflogMessageFormat_GitUp_Redo @kGCReflogCustomPrefix @"redo '%@'"
