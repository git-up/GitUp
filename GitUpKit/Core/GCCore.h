//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
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

#import <GitUpKit/GCBranch.h>
#import <GitUpKit/GCCommit.h>
#import <GitUpKit/GCCommitDatabase.h>
#import <GitUpKit/GCDiff.h>
#import <GitUpKit/GCError.h>
#import <GitUpKit/GCFoundation.h>
#import <GitUpKit/GCFunctions.h>
#import <GitUpKit/GCHistory.h>
#import <GitUpKit/GCIndex.h>
#if !TARGET_OS_IPHONE
#import <GitUpKit/GCLiveRepository.h>
#endif
#import <GitUpKit/GCMacros.h>
#import <GitUpKit/GCObject.h>
#import <GitUpKit/GCOrderedSet.h>
#import <GitUpKit/GCReference.h>
#import <GitUpKit/GCSnapshot.h>
#import <GitUpKit/GCReferenceTransform.h>
#import <GitUpKit/GCReflogMessages.h>
#import <GitUpKit/GCRemote.h>
#import <GitUpKit/GCRepository.h>
#import <GitUpKit/GCRepository+Bare.h>
#import <GitUpKit/GCRepository+Config.h>
#import <GitUpKit/GCRepository+HEAD.h>
#import <GitUpKit/GCRepository+Mock.h>
#import <GitUpKit/GCRepository+Reflog.h>
#import <GitUpKit/GCRepository+Reset.h>
#import <GitUpKit/GCRepository+Status.h>
#import <GitUpKit/GCSQLiteRepository.h>
#import <GitUpKit/GCStash.h>
#import <GitUpKit/GCSubmodule.h>
#import <GitUpKit/GCTag.h>
