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

#import "GCBranch.h"
#import "GCCommit.h"
#import "GCCommitDatabase.h"
#import "GCDiff.h"
#import "GCError.h"
#import "GCFoundation.h"
#import "GCFunctions.h"
#import "GCHistory.h"
#import "GCIndex.h"
#if !TARGET_OS_IPHONE
#import "GCLiveRepository.h"
#endif
#import "GCMacros.h"
#import "GCObject.h"
#import "GCOrderedSet.h"
#import "GCReference.h"
#import "GCSnapshot.h"
#import "GCReferenceTransform.h"
#import "GCReflogMessages.h"
#import "GCRemote.h"
#import "GCRepository.h"
#import "GCRepository+Bare.h"
#import "GCRepository+Config.h"
#import "GCRepository+HEAD.h"
#import "GCRepository+Mock.h"
#import "GCRepository+Reflog.h"
#import "GCRepository+Reset.h"
#import "GCRepository+Status.h"
#import "GCSQLiteRepository.h"
#import "GCStash.h"
#import "GCSubmodule.h"
#import "GCTag.h"
