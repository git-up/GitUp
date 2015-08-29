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

#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GCPrivate.h"

#if !TARGET_OS_IPHONE

@implementation NSFileManager (GCFoundation)

- (BOOL)moveItemAtPathToTrash:(NSString*)path error:(NSError**)error {
  NSString* trashPath = [NSSearchPathForDirectoriesInDomains(NSTrashDirectory, NSUserDomainMask, YES) firstObject];
  if (!trashPath) {
    GC_SET_GENERIC_ERROR(@"Unable to find Trash");
    return NO;
  }
  NSString* extension = path.pathExtension;
  NSString* name = [path.lastPathComponent stringByDeletingPathExtension];
  NSString* destinationPath = [trashPath stringByAppendingPathComponent:[name stringByAppendingPathExtension:extension]];
  NSUInteger counter = 0;
  while ([self fileExistsAtPath:destinationPath]) {
    destinationPath = [trashPath stringByAppendingPathComponent:[[NSString stringWithFormat:@"%@ (%lu)", name, ++counter] stringByAppendingPathExtension:extension]];
  }
  return [self moveItemAtPath:path toPath:destinationPath error:error];
}

@end

#endif
