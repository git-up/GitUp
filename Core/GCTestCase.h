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

#import <XCTest/XCTest.h>

#import "GCPrivate.h"

#pragma clang diagnostic ignored "-Wgnu-zero-variadic-macro-arguments"
#pragma clang diagnostic ignored "-Wsign-compare"

@interface GCTestCase : XCTestCase
@property(nonatomic, readonly, getter=isBotMode) BOOL botMode;
- (GCRepository*)createLocalRepositoryAtPath:(NSString*)path bare:(BOOL)bare;
- (void)destroyLocalRepository:(GCRepository*)repository;
- (NSString*)runGitCLTWithRepository:(GCRepository*)repository command:(NSString*)command, ... NS_REQUIRES_NIL_TERMINATION;
@end

@interface GCTestCase (Extensions)
- (void)assertGitCLTOutputEqualsString:(NSString*)string withRepository:(GCRepository*)repository command:(NSString*)command, ... NS_REQUIRES_NIL_TERMINATION;
- (void)assertGitCLTOutputContainsString:(NSString*)string withRepository:(GCRepository*)repository command:(NSString*)command, ... NS_REQUIRES_NIL_TERMINATION;
- (void)assertGitCLTOutputEndsWithString:(NSString*)string withRepository:(GCRepository*)repository command:(NSString*)command, ... NS_REQUIRES_NIL_TERMINATION;
@end

@interface GCTests : GCTestCase
@end

@interface GCEmptyRepositoryTestCase : GCTestCase
@property(nonatomic, readonly) NSString* temporaryPath;
@property(nonatomic, readonly) GCRepository* repository;
@end

@interface GCEmptyRepositoryTestCase (Extensions)
- (void)updateFileAtPath:(NSString*)path withString:(NSString*)string;
- (void)deleteFileAtPath:(NSString*)path;
- (GCCommit*)makeCommitWithUpdatedFileAtPath:(NSString*)path string:(NSString*)string message:(NSString*)message;
- (GCCommit*)makeCommitWithDeletedFileAtPath:(NSString*)path message:(NSString*)message;
- (void)assertContentsOfFileAtPath:(NSString*)path equalsString:(NSString*)string;
@end

@interface GCEmptyRepositoryTests : GCEmptyRepositoryTestCase
@end

/*
  c0 (master)
*/
@interface GCSingleCommitRepositoryTestCase : GCEmptyRepositoryTestCase
@property(nonatomic, readonly) GCLocalBranch* masterBranch;
@property(nonatomic, readonly) GCCommit* initialCommit;
@end

@interface GCSingleCommitRepositoryTests : GCSingleCommitRepositoryTestCase
@end

/*
  c0 -> c1 -> c2 -> c3 (master)
   \
    \-> cA (topic)
*/
@interface GCMultipleCommitsRepositoryTestCase : GCSingleCommitRepositoryTestCase
@property(nonatomic, readonly) GCLocalBranch* topicBranch;
@property(nonatomic, readonly) GCCommit* commit1;
@property(nonatomic, readonly) GCCommit* commit2;
@property(nonatomic, readonly) GCCommit* commit3;
@property(nonatomic, readonly) GCCommit* commitA;
@end

@interface GCMultipleCommitsRepositoryTests : GCMultipleCommitsRepositoryTestCase
@end

@interface GCSQLiteRepositoryTestCase : GCTestCase
@property(nonatomic, readonly) GCSQLiteRepository* repository;
@property(nonatomic, readonly) NSString* databasePath;
@property(nonatomic, readonly) NSString* configPath;
@end

@interface GCSQLiteRepositoryTests : GCSQLiteRepositoryTestCase
@end
