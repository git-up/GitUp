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

#import "GCRepository+Index.h"

#import "XLFacilityMacros.h"

@implementation GCRepository (Index)

- (BOOL)resetIndexToHEAD:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (index == nil) {
    return NO;
  }
  GCCommit* headCommit;
  if (![self lookupHEADCurrentCommit:&headCommit branch:NULL error:error]) {
    return NO;
  }
  if ((headCommit && ![self resetIndex:index toTreeForCommit:headCommit error:error]) || (!headCommit && ![self clearIndex:index error:error])) {
    return NO;
  }
  return [self writeRepositoryIndex:index error:error];
}

- (BOOL)removeFileFromIndex:(NSString*)path error:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (index == nil) {
    return NO;
  }
  return [self removeFile:path fromIndex:index error:error] && [self writeRepositoryIndex:index error:error];
}

- (BOOL)addFileToIndex:(NSString*)path error:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (index == nil) {
    return NO;
  }
  return [self addFileInWorkingDirectory:path toIndex:index error:error] && [self writeRepositoryIndex:index error:error];
}

- (BOOL)resetFileInIndexToHEAD:(NSString*)path error:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (index == nil) {
    return NO;
  }
  GCCommit* headCommit;
  if (![self lookupHEADCurrentCommit:&headCommit branch:NULL error:error]) {
    return NO;
  }
  if (headCommit) {
    if (![self resetFile:path inIndex:index toCommit:headCommit error:error]) {
      return NO;
    }
  } else {
    if (![self removeFile:path fromIndex:index error:error]) {
      return NO;
    }
  }
  return [self writeRepositoryIndex:index error:error];
}

- (BOOL)checkoutFileFromIndex:(NSString*)path error:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (index == nil) {
    return NO;
  }
  return [self checkoutFileToWorkingDirectory:path fromIndex:index error:error];
}

- (BOOL)addLinesFromFileToIndex:(NSString*)path error:(NSError**)error usingFilter:(GCIndexLineFilter)filter {
  GCIndex* index = [self readRepositoryIndex:error];
  if (index == nil) {
    return NO;
  }
  return [self addLinesInWorkingDirectoryFile:path toIndex:index error:error usingFilter:filter] && [self writeRepositoryIndex:index error:error];
}

- (BOOL)resetLinesFromFileInIndexToHEAD:(NSString*)path error:(NSError**)error usingFilter:(GCIndexLineFilter)filter {
  GCIndex* index = [self readRepositoryIndex:error];
  if (index == nil) {
    return NO;
  }
  GCCommit* headCommit;
  if (![self lookupHEADCurrentCommit:&headCommit branch:NULL error:error]) {
    return NO;
  }
  return [self resetLinesInFile:path index:index toCommit:headCommit error:error usingFilter:filter] && [self writeRepositoryIndex:index error:error];
}

- (BOOL)checkoutLinesFromFileFromIndex:(NSString*)path error:(NSError**)error usingFilter:(GCIndexLineFilter)filter {
  GCIndex* index = [self readRepositoryIndex:error];
  if (index == nil) {
    return NO;
  }
  return [self checkoutLinesInFileToWorkingDirectory:path fromIndex:index error:error usingFilter:filter];
}

- (BOOL)resolveConflictAtPath:(NSString*)path error:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (index == nil) {
    return NO;
  }
  if ([[NSFileManager defaultManager] fileExistsAtPath:[self absolutePathForFile:path]] && ![self addFileInWorkingDirectory:path toIndex:index error:error]) {
    return NO;
  }
  return [self clearConflictForFile:path inIndex:index error:error] && [self writeRepositoryIndex:index error:error];
}

@end
