//
//  GCLiveRepository-Tests.m
//  Tests
//
//  Created by Felix Lapalme on 2024-04-12.
//

#import <XCTest/XCTest.h>
#import "GCTestCase.h"
#import <GitUpKit/GCHistory+Rewrite.h>
#import <GitUpKit/GCRepository+Index.h>
#import <GitUpKit/GCLiveRepository+Conflicts.h>
#import <GitUpKit/GIViewController+Utilities.h>

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

@implementation GCMultipleCommitsRepositoryTests (GCLiveRepository)

// Adds the worktree from this process because live repositories ignore file system events of their own process, so only changes made by other processes get observed
- (BOOL)addWorktreeFromThisProcessAtPath:(NSString*)path branchName:(NSString*)branchName {
  if (![[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]) {
    return NO;
  }
  git_reference* reference;
  if (git_reference_lookup(&reference, self.repository.private, [@"refs/heads/" stringByAppendingString:branchName].UTF8String) != GIT_OK) {
    return NO;
  }
  git_worktree_add_options options = GIT_WORKTREE_ADD_OPTIONS_INIT;
  options.ref = reference;
  git_worktree* worktree;
  int status = git_worktree_add(&worktree, self.repository.private, path.lastPathComponent.UTF8String, path.fileSystemRepresentation, &options);
  git_reference_free(reference);
  if (status != GIT_OK) {
    return NO;
  }
  git_worktree_free(worktree);
  return YES;
}

// Removing one of several linked worktrees only changes ".git/worktrees/*" and the open repository must still drop the mark from the freed branch
- (void)testLiveHistoryUnmarksBranchWhenItsLinkedWorktreeIsRemoved {
  XCTAssertNotNil([self.repository createLocalBranchFromCommit:self.commit1 withName:@"other" force:NO error:NULL]);
  NSString* worktreePath = [self temporaryWorktreePathWithName:@"IOS-7533"];
  XCTAssertTrue([self addWorktreeFromThisProcessAtPath:worktreePath branchName:@"topic"]);
  NSString* removedWorktreePath = [self temporaryWorktreePathWithName:@"IOS-7600"];
  XCTAssertTrue([self addWorktreeFromThisProcessAtPath:removedWorktreePath branchName:@"other"]);

  GCLiveRepository* liveRepository = [[GCLiveRepository alloc] initWithExistingLocalRepository:self.repository.workingDirectoryPath error:NULL];
  XCTAssertNotNil(liveRepository);
  XCTAssertEqualObjects([liveRepository.history historyLocalBranchWithName:@"other"].worktreePath, removedWorktreePath);
  XCTNSNotificationExpectation* historyUpdated = [[XCTNSNotificationExpectation alloc] initWithName:GCLiveRepositoryHistoryDidUpdateNotification object:liveRepository];
  historyUpdated.expectationDescription = @"History of the open repository is updated after a linked worktree is removed";

  XCTAssertNotNil(([self runGitCLTWithRepository:self.repository command:@"worktree", @"remove", removedWorktreePath, nil]));
  [self waitForExpectations:@[ historyUpdated ] timeout:10];

  XCTAssertNil([liveRepository.history historyLocalBranchWithName:@"other"].worktreePath);
  XCTAssertEqualObjects([liveRepository.history historyLocalBranchWithName:@"topic"].worktreePath, worktreePath);
}

@end
