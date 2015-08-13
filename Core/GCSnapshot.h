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

typedef NS_OPTIONS(NSUInteger, GCSnapshotOptions) {
  kGCSnapshotOption_IncludeHEAD = (1 << 0),
  kGCSnapshotOption_IncludeLocalBranches = (1 << 1),
  kGCSnapshotOption_IncludeRemoteBranches = (1 << 2),
  kGCSnapshotOption_IncludeTags = (1 << 3),
  kGCSnapshotOption_IncludeOthers = (1 << 4),  // E.g. "refs/stash"
  kGCSnapshotOption_IncludeAll = 0xFF
};

@class GCCommit;

@interface GCSnapshot : NSObject <NSSecureCoding>
@end

@interface GCSnapshot (Extensions)
@property(nonatomic, readonly, getter=isEmpty) BOOL empty;  // Snapshot has no references and HEAD is unborn
@property(nonatomic, readonly) NSString* HEADBranchName;  // Nil if HEAD is detached

- (id)objectForKeyedSubscript:(NSString*)key;  // To retrieve arbitrary user info
- (void)setObject:(id)object forKeyedSubscript:(NSString*)key;  // To set arbitrary user info

- (BOOL)isEqualToSnapshot:(GCSnapshot*)snapshot usingOptions:(GCSnapshotOptions)options;
@end

@interface GCRepository (GCSnapshot)
- (GCSnapshot*)takeSnapshot:(NSError**)error;

- (BOOL)restoreSnapshot:(GCSnapshot*)snapshot
            withOptions:(GCSnapshotOptions)options
          reflogMessage:(NSString*)message
    didUpdateReferences:(BOOL*)didUpdateReferences
                  error:(NSError**)error;

- (BOOL)applyDeltaFromSnapshot:(GCSnapshot*)fromSnapshot
                    toSnapshot:(GCSnapshot*)toSnapshot
                   withOptions:(GCSnapshotOptions)options
                 reflogMessage:(NSString*)message
           didUpdateReferences:(BOOL*)didUpdateReferences
                         error:(NSError**)error;
@end
