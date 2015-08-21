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

#import "GCCore.h"

@interface GCRepository (Index)
- (BOOL)resetIndexToHEAD:(NSError**)error;  // Like git reset --mixed HEAD but does not update reflog

- (BOOL)removeFileFromIndex:(NSString*)path error:(NSError**)error;  // git rm --cached {file} - Delete file from index

- (BOOL)addFileToIndex:(NSString*)path error:(NSError**)error;  // git add {file} - Copy file from workdir to index (aka stage file)
- (BOOL)resetFileInIndexToHEAD:(NSString*)path error:(NSError**)error;  // git reset --mixed {file} - Copy file from HEAD to index (aka unstage file)
- (BOOL)checkoutFileFromIndex:(NSString*)path error:(NSError**)error;  // git checkout {file} - Copy file from index to workdir (aka discard file)

- (BOOL)addLinesFromFileToIndex:(NSString*)path error:(NSError**)error usingFilter:(GCIndexLineFilter)filter;  // git add -p {file} - Copy only some lines of file from workdir to index (aka stage lines)
- (BOOL)resetLinesFromFileInIndexToHEAD:(NSString*)path error:(NSError**)error usingFilter:(GCIndexLineFilter)filter;  // git reset -p {file} - Copy only some lines of file from HEAD to index (aka unstage lines)
- (BOOL)checkoutLinesFromFileFromIndex:(NSString*)path error:(NSError**)error usingFilter:(GCIndexLineFilter)filter;  // git checkout -p {file} - Copy only some lines of file from index to workdir (aka discard lines)

- (BOOL)resolveConflictAtPath:(NSString*)path error:(NSError**)error;
@end
