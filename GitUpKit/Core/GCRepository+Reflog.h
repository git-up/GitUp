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

@class GCCommit;

typedef NS_OPTIONS(NSUInteger, GCReflogActions) {
  kGCReflogAction_GitUp = (1 << 0),
  kGCReflogAction_InitialCommit = (1 << 1),
  kGCReflogAction_Commit = (1 << 2),
  kGCReflogAction_AmendCommit = (1 << 3),
  kGCReflogAction_Checkout = (1 << 4),
  kGCReflogAction_CreateBranch = (1 << 5),
  kGCReflogAction_RenameBranch = (1 << 6),
  kGCReflogAction_Merge = (1 << 7),
  kGCReflogAction_Reset = (1 << 8),
  kGCReflogAction_Rebase = (1 << 9),
  kGCReflogAction_CherryPick = (1 << 10),
  kGCReflogAction_Revert = (1 << 11),
  kGCReflogAction_Fetch = (1 << 12),
  kGCReflogAction_Push = (1 << 13),
  kGCReflogAction_Pull = (1 << 14),
  kGCReflogAction_Clone = (1 << 15)
};

@interface GCReflogEntry : NSObject
@property(nonatomic, readonly) GCRepository* repository;  // NOT RETAINED
@property(nonatomic, readonly) NSString* fromSHA1;  // May be nil
@property(nonatomic, readonly) GCCommit* fromCommit;  // May be nil
@property(nonatomic, readonly) NSString* toSHA1;
@property(nonatomic, readonly) GCCommit* toCommit;  // May be nil
@property(nonatomic, readonly) NSDate* date;
@property(nonatomic, readonly) NSTimeZone* timeZone;
@property(nonatomic, readonly) NSString* committerName;
@property(nonatomic, readonly) NSString* committerEmail;
@property(nonatomic, readonly) NSArray* references;  // Matches @messages
@property(nonatomic, readonly) NSArray* messages;  // Matches @references
@property(nonatomic, readonly) GCReflogActions actions;  // Guessed from messages (might not be reliable)
@end

@interface GCReflogEntry (Extensions)
- (BOOL)isEqualToReflogEntry:(GCReflogEntry*)entry;
@end

@interface GCRepository (Reflog)
- (NSArray*)loadReflogEntriesForReference:(GCReference*)reference error:(NSError**)error;  // git reflog {reference}
- (NSArray*)loadAllReflogEntries:(NSError**)error;  // This deduplicate entries
@end
