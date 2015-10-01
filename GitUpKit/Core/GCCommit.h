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

#import "GCObject.h"
#import "GCRepository.h"

@interface GCCommit : GCObject
@property(nonatomic, readonly) NSString* message;
@property(nonatomic, readonly) NSString* summary;  // Cleaned first paragraph of the message
@property(nonatomic, readonly) NSDate* date;
@property(nonatomic, readonly) NSTimeZone* timeZone;
@property(nonatomic, readonly) NSString* authorName;
@property(nonatomic, readonly) NSString* authorEmail;
@property(nonatomic, readonly) NSDate* authorDate;
@property(nonatomic, readonly) NSString* committerName;
@property(nonatomic, readonly) NSString* committerEmail;
@property(nonatomic, readonly) NSDate* committerDate;
@property(nonatomic, readonly) NSString* treeSHA1;
@end

@interface GCCommit (Extensions)
@property(nonatomic, readonly) NSString* author;
@property(nonatomic, readonly) NSString* committer;
@property(nonatomic, readonly) NSTimeInterval timeIntervalSinceReferenceDate;  // Faster than -date
- (BOOL)isEqualToCommit:(GCCommit*)commit;
- (NSComparisonResult)timeCompare:(GCCommit*)commit;  // Sorts chronologically or by SHA1 if equal
- (NSComparisonResult)reverseTimeCompare:(GCCommit*)commit;  // Sorts reverse chronologically or by SHA1 if equal
@end

@interface GCRepository (GCCommit)
- (NSString*)computeUniqueShortSHA1ForCommit:(GCCommit*)commit error:(NSError**)error;  // (?)
- (GCCommit*)findCommitWithSHA1:(NSString*)sha1 error:(NSError**)error;  // (?)
- (GCCommit*)findCommitWithSHA1Prefix:(NSString*)prefix error:(NSError**)error;  // (?)
- (NSArray*)lookupParentsForCommit:(GCCommit*)commit error:(NSError**)error;  // git log -n 1 {commit_id}
- (NSString*)checkTreeForCommit:(GCCommit*)commit containsFile:(NSString*)path error:(NSError**)error;  // (?) - Returns SHA1 if present
@end
