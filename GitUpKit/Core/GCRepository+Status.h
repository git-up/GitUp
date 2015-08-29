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

#import "GCRepository.h"

@class GCDiff;

// The cases "Both Deleted", "Added by Us" and "Added by Them" are not possible in practice as they are automatically resolved by the trivial merge machinery
// http://permalink.gmane.org/gmane.comp.version-control.git/245661
typedef NS_ENUM(NSUInteger, GCIndexConflictStatus) {
  kGCIndexConflictStatus_None = 0,
  kGCIndexConflictStatus_BothModified,
  kGCIndexConflictStatus_BothAdded,
  kGCIndexConflictStatus_DeletedByUs,
  kGCIndexConflictStatus_DeletedByThem
};

typedef NS_OPTIONS(NSUInteger, GCCleanCheckOptions) {
  kGCCleanCheckOption_IgnoreState = (1 << 0),
  kGCCleanCheckOption_IgnoreIndexConflicts = (1 << 1),
  kGCCleanCheckOption_IgnoreIndexChanges = (1 << 2),
  kGCCleanCheckOption_IgnoreWorkingDirectoryChanges = (1 << 3),
  kGCCleanCheckOption_IgnoreUntrackedFiles = (1 << 4)
};

@interface GCIndexConflict : NSObject
@property(nonatomic, readonly) NSString* path;
@property(nonatomic, readonly) GCIndexConflictStatus status;
@property(nonatomic, readonly) NSString* ancestorBlobSHA1;  // May be nil
@property(nonatomic, readonly) GCFileMode ancestorFileMode;
@property(nonatomic, readonly) NSString* ourBlobSHA1;  // May be nil
@property(nonatomic, readonly) GCFileMode ourFileMode;
@property(nonatomic, readonly) NSString* theirBlobSHA1;  // May be nil
@property(nonatomic, readonly) GCFileMode theirFileMode;
@end

@interface GCRepository (Status)
- (NSDictionary<NSString*, GCIndexConflict*>*)checkConflicts:(NSError**)error;

- (BOOL)checkClean:(GCCleanCheckOptions)options error:(NSError**)error;  // git status
@end
