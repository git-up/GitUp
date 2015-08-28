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

#import "GCDiff.h"

typedef BOOL (^GCIndexLineFilter)(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber);

@interface GCIndex : NSObject
@property(nonatomic, readonly) GCRepository* repository;  // NOT RETAINED - nil if in-memory index
@property(nonatomic, readonly, getter=isInMemory) BOOL inMemory;
@property(nonatomic, readonly, getter=isEmpty) BOOL empty;
- (NSString*)SHA1ForFile:(NSString*)path mode:(GCFileMode*)mode;  // Returns nil if file is not in index
- (void)enumerateFilesUsingBlock:(void (^)(NSString* path, GCFileMode mode, NSString* sha1, BOOL* stop))block;
@end

@interface GCRepository (GCIndex)
- (GCIndex*)createInMemoryIndex:(NSError**)error;
- (GCIndex*)readRepositoryIndex:(NSError**)error;
- (BOOL)writeRepositoryIndex:(GCIndex*)index error:(NSError**)error;

- (BOOL)resetIndex:(GCIndex*)index toTreeForCommit:(GCCommit*)commit error:(NSError**)error;
- (BOOL)clearIndex:(GCIndex*)index error:(NSError**)error;

- (BOOL)addFile:(NSString*)path withContents:(NSData*)contents toIndex:(GCIndex*)index error:(NSError**)error;
- (BOOL)addFileInWorkingDirectory:(NSString*)path toIndex:(GCIndex*)index error:(NSError**)error;
- (BOOL)addLinesInWorkingDirectoryFile:(NSString*)path toIndex:(GCIndex*)index error:(NSError**)error usingFilter:(GCIndexLineFilter)filter;

- (BOOL)resetFile:(NSString*)path inIndex:(GCIndex*)index toCommit:(GCCommit*)commit error:(NSError**)error;
- (BOOL)resetLinesInFile:(NSString*)path index:(GCIndex*)index toCommit:(GCCommit*)commit error:(NSError**)error usingFilter:(GCIndexLineFilter)filter;

- (BOOL)checkoutFileToWorkingDirectory:(NSString*)path fromIndex:(GCIndex*)index error:(NSError**)error;
- (BOOL)checkoutLinesInFileToWorkingDirectory:(NSString*)path fromIndex:(GCIndex*)index error:(NSError**)error usingFilter:(GCIndexLineFilter)filter;

- (BOOL)clearConflictForFile:(NSString*)path inIndex:(GCIndex*)index error:(NSError**)error;
- (BOOL)removeFile:(NSString*)path fromIndex:(GCIndex*)index error:(NSError**)error;

- (BOOL)copyFile:(NSString*)path fromOtherIndex:(GCIndex*)otherIndex toIndex:(GCIndex*)index error:(NSError**)error;
- (BOOL)copyLinesInFile:(NSString*)path fromOtherIndex:(GCIndex*)otherIndex toIndex:(GCIndex*)index error:(NSError**)error usingFilter:(GCIndexLineFilter)filter;
@end
