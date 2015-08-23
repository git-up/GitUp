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

typedef NS_OPTIONS(NSUInteger, GCCommitDatabaseOptions) {
  kGCCommitDatabaseOptions_IndexDiffs = (1 << 0),
  kGCCommitDatabaseOptions_QueryOnly = (1 << 1)
};

typedef BOOL (^GCCommitDatabaseProgressHandler)(BOOL firstUpdate, NSUInteger addedCommits, NSUInteger removedCommits);

@class GCRepository;

extern NSString* const SQLiteErrorDomain;

// This class CANNOT be used from multiple threads simultaneously
@interface GCCommitDatabase : NSObject
@property(nonatomic, readonly) GCRepository* repository;  // NOT RETAINED
@property(nonatomic, readonly) NSString* databasePath;
@property(nonatomic, readonly) GCCommitDatabaseOptions options;
- (instancetype)initWithRepository:(GCRepository*)repository databasePath:(NSString*)path options:(GCCommitDatabaseOptions)options error:(NSError**)error;
- (BOOL)updateWithProgressHandler:(GCCommitDatabaseProgressHandler)handler error:(NSError**)error;  // Handler can be NULL - Return NO from handler to cancel
- (NSArray*)findCommitsMatching:(NSString*)match error:(NSError**)error;  // Search commit messages, authors and committers and orders results from newest to oldest - Returns nil on error
@end
