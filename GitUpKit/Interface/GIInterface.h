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

#ifndef __GI_HAS_APPKIT__
// clang-format off
#if defined(__has_include) && __has_include(<AppKit/AppKit.h>)
// clang-format on
#define __GI_HAS_APPKIT__ 1
#else
#define __GI_HAS_APPKIT__ 0
#endif
#endif

#import "GCCore.h"

#import "GIBranch.h"
#import "GIConstants.h"
#import "GIFunctions.h"
#import "GIGraph.h"
#import "GILayer.h"
#import "GILine.h"
#import "GINode.h"

#if __GI_HAS_APPKIT__
#import "GIDiffView.h"
#import "GIGraphView.h"
#import "GISplitDiffView.h"
#import "GIUnifiedDiffView.h"
#endif
