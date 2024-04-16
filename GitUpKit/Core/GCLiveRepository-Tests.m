//
//  GCLiveRepository-Tests.m
//  Tests
//
//  Created by Felix Lapalme on 2024-04-12.
//

#import <XCTest/XCTest.h>
#import "GCTestCase.h"
#import "GCHistory+Rewrite.h"
#import "GCRepository+Index.h"
#import "GCLiveRepository+Conflicts.h"
#import "GIViewController+Utilities.h"

// block based object that conforms to GCMergeConflictResolver
@interface GCBlockConflictResolver : NSObject <GCMergeConflictResolver>
@property(nonatomic, copy) BOOL (^resolveBlock)(GCCommit* ourCommit, GCCommit* theirCommit);

- (instancetype)initWithBlock:(BOOL (^)(GCCommit* ourCommit, GCCommit* theirCommit))resolveBlock;
@end

@implementation GCBlockConflictResolver

- (instancetype)initWithBlock:(BOOL (^)(GCCommit* ourCommit, GCCommit* theirCommit))resolveBlock {
  self = [super init];
  if (self) {
    self.resolveBlock = resolveBlock;
  }
  return self;
}

- (BOOL)resolveMergeConflictsWithOurCommit:(GCCommit*)ourCommit theirCommit:(GCCommit*)theirCommit {
  return self.resolveBlock(ourCommit, theirCommit);
}

@end

@implementation GCEmptyLiveRepositoryTestCase (GCLiveRepository)

- (void)testRebase {
  // Initial setup: create a base commit on master.
  GCCommit* baseCommit = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\n" message:@"Base commit"];

  // Create a new branch from the base commit.
  XCTAssertTrue([self.liveRepository createLocalBranchFromCommit:baseCommit withName:@"other_branch" force:NO error:NULL]);

  GCLocalBranch* masterBranch = [self.liveRepository findLocalBranchWithName:@"master" error:NULL];
  GCLocalBranch* otherBranch = [self.liveRepository findLocalBranchWithName:@"other_branch" error:NULL];

  XCTAssertTrue([self.liveRepository checkoutLocalBranch:masterBranch options:0 error:NULL]);
  GCCommit* masterCommit = [self makeCommitWithUpdatedFileAtPath:@"shared2.txt" string:@"new text file\n" message:@"Master commit 1"];
  XCTAssertNotNil(masterCommit);

  NSError* error;

  // Make a commit on the other branch that also modifies the same shared file.
  XCTAssertTrue([self.liveRepository checkoutLocalBranch:otherBranch options:0 error:NULL]);
  GCCommit* otherCommit1 = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\nAnd a new line\n" message:@"Other commit 1"];
  XCTAssertNotNil(otherCommit1);

  XCTAssertNil(error);

  [self rebaseAndSolveConflictsWithBaseCommit:baseCommit expectedCommitTotalCount:3];

  // Verify the results of the rebase.
  NSString* finalContent = [NSString stringWithContentsOfFile:[self.liveRepository.workingDirectoryPath stringByAppendingPathComponent:@"shared.txt"] encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertEqualObjects(finalContent, @"Initial content\nAnd a new line\n");
}

- (void)testRebaseConflict {
  // Initial setup: create a base commit on master.
  GCCommit* baseCommit = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\n" message:@"Base commit"];

  // Create a new branch from the base commit.
  XCTAssertTrue([self.liveRepository createLocalBranchFromCommit:baseCommit withName:@"other_branch" force:NO error:NULL]);

  GCLocalBranch* masterBranch = [self.liveRepository findLocalBranchWithName:@"master" error:NULL];
  GCLocalBranch* otherBranch = [self.liveRepository findLocalBranchWithName:@"other_branch" error:NULL];

  XCTAssertTrue([self.liveRepository checkoutLocalBranch:masterBranch options:0 error:NULL]);
  GCCommit* masterCommit = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\nMaster modification 1\n" message:@"Master commit 1"];
  XCTAssertNotNil(masterCommit);

  NSError* error;

  // Make a commit on the other branch that also modifies the same shared file.
  XCTAssertTrue([self.liveRepository checkoutLocalBranch:otherBranch options:0 error:NULL]);
  GCCommit* otherCommit1 = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\nOther modification 1\n" message:@"Other commit 1"];
  XCTAssertNotNil(otherCommit1);

  XCTAssertNil(error);

  [self rebaseAndSolveConflictsWithBaseCommit:baseCommit expectedCommitTotalCount:3];

  // Verify the results of the rebase.
  NSString* finalContent = [NSString stringWithContentsOfFile:[self.liveRepository.workingDirectoryPath stringByAppendingPathComponent:@"shared.txt"] encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertEqualObjects(finalContent, @"Conflict resolved\n", @"File content should reflect resolved conflict.");
}

- (void)testMultipleCommitsRebaseWithConflict {
  // Initial setup: create a base commit on master.
  GCCommit* baseCommit = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\n" message:@"Base commit"];

  // Create a new branch from the base commit.
  XCTAssertTrue([self.liveRepository createLocalBranchFromCommit:baseCommit withName:@"other_branch" force:NO error:NULL]);

  GCLocalBranch* masterBranch = [self.liveRepository findLocalBranchWithName:@"master" error:NULL];
  GCLocalBranch* otherBranch = [self.liveRepository findLocalBranchWithName:@"other_branch" error:NULL];

  XCTAssertTrue([self.liveRepository checkoutLocalBranch:masterBranch options:0 error:NULL]);
  GCCommit* masterCommit = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\nMaster modification 1\n" message:@"Master commit 1"];
  XCTAssertNotNil(masterCommit);

  // create other changed files
  GCCommit* masterCommit2 = [self makeCommitWithUpdatedFileAtPath:@"shared2.txt" string:@"Initial content\nMaster modification 2\n" message:@"Master commit 2"];
  XCTAssertNotNil(masterCommit2);

  GCCommit* masterCommit3 = [self makeCommitWithUpdatedFileAtPath:@"shared3.txt" string:@"Initial content\nMaster modification 3\n" message:@"Master commit 3"];
  XCTAssertNotNil(masterCommit3);

  NSError* error;

  // Make a commit on the other branch that also modifies the same shared file.
  XCTAssertTrue([self.liveRepository checkoutLocalBranch:otherBranch options:0 error:NULL]);
  GCCommit* otherCommit1 = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\nOther modification 1\n" message:@"Other commit 1"];
  XCTAssertNotNil(otherCommit1);

  // create other changed files
  GCCommit* otherCommit2 = [self makeCommitWithUpdatedFileAtPath:@"shared4.txt" string:@"Initial content\nOther modification 2\n" message:@"Other commit 2"];
  XCTAssertNotNil(otherCommit2);

  GCCommit* otherCommit3 = [self makeCommitWithUpdatedFileAtPath:@"shared5.txt" string:@"Initial content\nOther modification 3\n" message:@"Other commit 3"];
  XCTAssertNotNil(otherCommit3);

  XCTAssertNil(error);

  [self rebaseAndSolveConflictsWithBaseCommit:baseCommit expectedCommitTotalCount:7];

  // Verify the results of the rebase.
  NSString* finalContent = [NSString stringWithContentsOfFile:[self.liveRepository.workingDirectoryPath stringByAppendingPathComponent:@"shared.txt"] encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertEqualObjects(finalContent, @"Conflict resolved\n", @"File content should reflect resolved conflict.");
}

- (void)rebaseAndSolveConflictsWithBaseCommit:(GCCommit*)baseCommit expectedCommitTotalCount:(int)expectedTotalCommitCount {
  NSError* error;
  GCHistory* history = [self.liveRepository loadHistoryUsingSorting:kGCHistorySorting_ReverseChronological error:&error];
  GCHistoryLocalBranch* otherHistoryBranch = history.HEADBranch;
  GCHistoryLocalBranch* masterHistoryBranch = [history.localBranches filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(GCHistoryLocalBranch* _Nullable localBranch, NSDictionary<NSString*, id>* _Nullable bindings) {
                                                                       return [localBranch.name isEqualToString:@"master"];
                                                                     }]]
                                                  .firstObject;
  GCHistoryCommit* otherHistoryCommit = otherHistoryBranch.tipCommit;
  GCHistoryCommit* masterHistoryCommit = masterHistoryBranch.tipCommit;

  GCCommit* foundBaseCommit = [self.liveRepository findMergeBaseForCommits:@[ otherHistoryCommit, masterHistoryCommit ] error:&error];
  XCTAssertNotNil(foundBaseCommit);
  GCHistoryCommit* fromCommit = [history historyCommitForCommit:baseCommit];

  // Attempt to rebase the other branch onto master.
  NSError* rebaseError = NULL;
  [self.liveRepository suspendHistoryUpdates];

  [self.liveRepository setStatusMode:kGCLiveRepositoryStatusMode_Normal];

  __block GCCommit* newCommit = nil;
  [self.liveRepository setUndoActionName:NSLocalizedString(@"Rebase test", nil)];

  BOOL rebaseSuccess = [self.liveRepository performReferenceTransformWithReason:@"rebase_branch"
                                                                       argument:masterHistoryBranch.name
                                                                          error:&rebaseError
                                                                     usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
                                                                       return [history rebaseBranch:otherHistoryBranch
                                                                                         fromCommit:fromCommit
                                                                                         ontoCommit:masterHistoryCommit
                                                                                    conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError2) {
                                                                                      GCBlockConflictResolver* blockResolver = [[GCBlockConflictResolver alloc] initWithBlock:^BOOL(GCCommit* ourCommit, GCCommit* theirCommit) {
                                                                                        XCTAssertTrue([index hasConflicts]);
                                                                                        [index enumerateConflictsUsingBlock:^(GCIndexConflict* conflict, BOOL* stop) {
                                                                                          [self updateFileAtPath:conflict.path withString:@"Conflict resolved\n"];
                                                                                          NSError* conflictResolutionError;
                                                                                          [self.liveRepository resolveConflictAtPath:conflict.path error:&conflictResolutionError];
                                                                                          XCTAssertNil(conflictResolutionError);
                                                                                        }];

                                                                                        return YES;
                                                                                      }];

                                                                                      return [self.liveRepository resolveConflictsWithResolver:blockResolver
                                                                                                                                         index:index
                                                                                                                                     ourCommit:ourCommit
                                                                                                                                   theirCommit:theirCommit
                                                                                                                                 parentCommits:parentCommits
                                                                                                                                       message:message
                                                                                                                                         error:outError2];
                                                                                    }
                                                                                       newTipCommit:&newCommit
                                                                                              error:outError1];
                                                                     }];
  [self.liveRepository resumeHistoryUpdates];

  XCTAssertNil(rebaseError, @"Rebase should not error out with proper conflict handling.");
  XCTAssertTrue(rebaseSuccess, @"Rebase should complete successfully.");

  // make sure the working directory is still clean
  XCTAssertEqual(self.liveRepository.workingDirectoryStatus.deltas.count, 0);

  //  count to make sure the number of parents makes sense
  GCHistoryCommit* currentCommit = self.liveRepository.history.HEADCommit;
  int numberOfCommits = 0;
  while (true) {
    numberOfCommits++;
    currentCommit = currentCommit.parents.firstObject;
    if (!currentCommit) {
      break;
    }
  }

  XCTAssertEqual(numberOfCommits, expectedTotalCommitCount);
}

@end
