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

- (void)testRebaseConflict {
  // Initial setup: create a base commit on master.
  GCCommit* baseCommit = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\n" message:@"Base commit"];

  // Create a new branch from the base commit.
  XCTAssertTrue([self.liveRepository createLocalBranchFromCommit:baseCommit withName:@"other_branch" force:NO error:NULL]);

  GCLocalBranch* masterBranch = [self.liveRepository findLocalBranchWithName:@"master" error:NULL];
  GCLocalBranch* otherBranch = [self.liveRepository findLocalBranchWithName:@"other_branch" error:NULL];

  XCTAssertTrue([self.liveRepository checkoutLocalBranch:masterBranch options:0 error:NULL]);
  GCCommit* masterCommit = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\nMaster modification\n" message:@"Master commit"];
  XCTAssertNotNil(masterCommit);

  NSError* error;

  // Make a commit on the other branch that also modifies the same shared file.
  XCTAssertTrue([self.liveRepository checkoutLocalBranch:otherBranch options:0 error:NULL]);
  GCCommit* otherCommit = [self makeCommitWithUpdatedFileAtPath:@"shared.txt" string:@"Initial content\nOther modification\n" message:@"Other commit"];
  XCTAssertNotNil(otherCommit);

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
                                                                       argument:masterBranch.name
                                                                          error:&rebaseError
                                                                     usingBlock:^GCReferenceTransform*(GCLiveRepository* repository, NSError** outError1) {
    return [history rebaseBranch:otherHistoryBranch
                      fromCommit:fromCommit
                      ontoCommit:masterHistoryCommit
                 conflictHandler:^GCCommit*(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError2) {
      return [self.liveRepository resolveConflictsWithResolver:[[GCBlockConflictResolver alloc] initWithBlock:^BOOL(GCCommit *ourCommit, GCCommit *theirCommit) {
        NSLog(@"resolveConflict");
        XCTAssertTrue([index hasConflicts]);
        [index enumerateConflictsUsingBlock:^(GCIndexConflict* conflict, BOOL* stop) {
          [self updateFileAtPath:conflict.path withString:@"Conflict resolved\n"];
          NSError* conflictResolutionError;
          [self.liveRepository resolveConflictAtPath:conflict.path error:&conflictResolutionError];
          XCTAssertNil(conflictResolutionError);
        }];

        return YES;
      }]
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

  // Verify the results of the rebase.
  NSString* finalContent = [NSString stringWithContentsOfFile:[self.liveRepository.workingDirectoryPath stringByAppendingPathComponent:@"shared.txt"] encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertEqualObjects(finalContent, @"Conflict resolved\n", @"File content should reflect resolved conflict.");

  XCTAssertEqual(self.liveRepository.workingDirectoryStatus.deltas.count, 0);
}

@end
