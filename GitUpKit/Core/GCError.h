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

typedef NS_ENUM(NSInteger, GCErrorCode) {
  kGCErrorCode_SubmoduleUninitialized = 3,
  kGCErrorCode_RepositoryDirty = 2,
  kGCErrorCode_Generic = 1,
  kGCErrorCode_UserCancelled = 0,
  kGCErrorCode_NotFound = -3, // GIT_ENOTFOUND,
  kGCErrorCode_User = -7,  // GIT_EUSER
  kGCErrorCode_NonFastForward = -11,  // GIT_ENONFASTFORWARD
  kGCErrorCode_CheckoutConflicts= -13,  // GIT_ECONFLICT
  kGCErrorCode_Authentication = -16  // GIT_EAUTH
};

// Negative errors are from libgit2 and positive errors from the API
extern NSString* const GCErrorDomain;
