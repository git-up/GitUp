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

#import "GCError.h"

#define GC_SET_ERROR(code, ...) \
  do { \
    NSString* __message = [NSString stringWithFormat:__VA_ARGS__]; \
    if (error) { \
      *error = GCNewError(code, __message); \
    } \
  } while (0)

#define GC_SET_GENERIC_ERROR(...) GC_SET_ERROR(kGCErrorCode_Generic, __VA_ARGS__)

#define GC_SET_USER_CANCELLED_ERROR() GC_SET_ERROR(kGCErrorCode_UserCancelled, @"")

#ifdef __cplusplus
extern "C" {
#endif

NSError* GCNewError(NSInteger code, NSString* message);

const char* GCGitPathFromFileSystemPath(NSString* string);
NSString* GCFileSystemPathFromGitPath(const char* string);

NSURL* GCURLFromGitURL(NSString* url);
NSString* GCGitURLFromURL(NSURL* url);

void GCArrayApplyBlock(CFArrayRef array, void (^block)(const void* value));
void GCSetApplyBlock(CFSetRef set, void (^block)(const void* value));
void GCDictionaryApplyBlock(CFDictionaryRef dict, void (^block)(const void* key, const void* value));
  
#ifdef __cplusplus
}
#endif
