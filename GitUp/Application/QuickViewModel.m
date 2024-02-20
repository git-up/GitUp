//
//  QuickViewModel.m
//  Application
//
//  Created by Dmitry Lobanov on 15/09/2019.
//

@import GitUpKit;
#import <GitUpKit/XLFacilityMacros.h>
#import "QuickViewModel.h"

@interface QuickViewModel ()

@property (weak, nonatomic) GCLiveRepository *repository;

@property (assign, nonatomic) NSUInteger index;
@property (strong, nonatomic) NSMutableArray *commits;

@property (strong, nonatomic) GCHistoryWalker *ancestors;
@property (strong, nonatomic) GCHistoryWalker *descendants;

#pragma mark - Protected
- (void)loadMoreAncestors;
- (void)loadMoreDescendants;
@end

@implementation QuickViewModel

#pragma mark - Initialization
- (instancetype)initWithRepository:(GCLiveRepository *)repository {
  if ((self = [super init])) {
    self.repository = repository;
  }
  return self;
}

#pragma mark - Loading
- (void)loadMoreAncestors {
  if (![_ancestors iterateWithCommitBlock:^(GCHistoryCommit* commit, BOOL* stop) {
    [_commits addObject:commit];
  }]) {
    _ancestors = nil;
  }
}

- (void)loadMoreDescendants {
  if (![_descendants iterateWithCommitBlock:^(GCHistoryCommit* commit, BOOL* stop) {
    [_commits insertObject:commit atIndex:0];
    _index += 1;  // We insert commits before the index too!
  }]) {
    _descendants = nil;
  }
}

#pragma mark - Checking
- (BOOL)hasPrevious {
  return _index + 1 < _commits.count;
}

- (BOOL)hasNext {
  return _index > 0;
}

- (BOOL)hasPaging {
  return _commits != nil;
}

// TODO: Rename them appropriately.
// Blowing mind.
// Moving backward means moving to the end of array. ( or back to origin )
// Moving forward means moving to the beginning of array. ( or to recent commits )
// Also, these checks for end of array should be done __after__ increment or decrement of index.
#pragma mark - Moving
- (void)moveBackward {
  _index += 1;
  if (_index == _commits.count - 1) {
    [self loadMoreAncestors];
  }
}

- (void)moveForward {
  _index -= 1;
  if (_index == 0) {
    [self loadMoreDescendants];
  }
}

#pragma mark - State
- (void)enterWithHistoryCommit:(GCHistoryCommit *)commit commitList:(NSArray *)commitList onResult:(void(^)(GCHistoryCommit *,  NSArray * _Nullable))result {

  // actually, we need to cleanup state if we reenter this function.
  [self exit];
  
  [_repository suspendHistoryUpdates]; // We don't want the the history to change while in QuickView because of the walkers
  
  _commits = [NSMutableArray new];
  if (commitList) {
    [_commits addObjectsFromArray:commitList];
    _index = [_commits indexOfObjectIdenticalTo:commit];
    if (result) {
      result(commit, commitList);
    }
    XLOG_DEBUG_CHECK(_index != NSNotFound);
  }
  else {
    [_commits addObject:commit];
    _index = 0;
    _ancestors = [_repository.history walkerForAncestorsOfCommits:@[ commit ]];
    [self loadMoreAncestors];
    _descendants = [_repository.history walkerForDescendantsOfCommits:@[ commit ]];
    [self loadMoreDescendants];
    if (result) {
      result(commit, nil);
    }
  }
}

- (void)cleanup {
  _commits = nil;
  _ancestors = nil;
  _descendants = nil;
}

- (void)exit {
  [self cleanup];
  // resume history updates for repository.
  if ([_repository areHistoryUpdatesSuspended]) {
    [_repository resumeHistoryUpdates];
  }
}

- (GCHistoryCommit *)currentCommit {
  return _commits[_index];
}

- (void)setSelectedCommit:(GCHistoryCommit *)selectedCommit {
  NSUInteger index = [_commits indexOfObjectIdenticalTo:selectedCommit];
  if (index == NSNotFound) {
    // set index to zero.
    _index = 0;
  }
  else {
    _index = index;
  }
}

- (GCHistoryCommit *)selectedCommit {
  return self.currentCommit;
}

@end
