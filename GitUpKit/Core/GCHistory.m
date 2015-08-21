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

#if __has_feature(objc_arc)
#error This file requires MRC
#endif

#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

#import "GCPrivate.h"

#define COMMIT_STATE(c) states[c->_autoIncrementID]
#define SET_COMMIT_PROCESSED(c) COMMIT_STATE(c) = iteration
#define COMMIT_IS_PROCESSED(c) (COMMIT_STATE(c) > 0)
#define COMMIT_WAS_JUST_PROCESSED(c) (COMMIT_STATE(c) == iteration)
#define SET_COMMIT_SKIPPED(c) COMMIT_STATE(c) = -iteration
#define COMMIT_WAS_JUST_SKIPPED(c) (COMMIT_STATE(c) == -iteration)

static const void* _associatedObjectCommitKey = &_associatedObjectCommitKey;
static const void* _associatedObjectAnnotationKey = &_associatedObjectAnnotationKey;
static const void* _associatedObjectUpstreamNameKey = &_associatedObjectUpstreamNameKey;

@interface GCHistoryCommit () {
@public
  NSUInteger generation;
}
@end

@implementation GCHistoryCommit {
@public
  NSUInteger _autoIncrementID;
  CFMutableArrayRef _parents;
  CFMutableArrayRef _children;
  CFMutableArrayRef _localBranches;
  CFMutableArrayRef _remoteBranches;
  CFMutableArrayRef _tags;
}

- (instancetype)initWithRepository:(GCRepository*)repository commit:(git_commit*)commit autoIncrementID:(NSUInteger)autoIncrementID {
  if ((self = [super initWithRepository:repository commit:commit])) {
    _autoIncrementID = autoIncrementID;
    _parents = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    _children = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
  }
  return self;
}

- (void)dealloc {
  if (_localBranches) {
    CFRelease(_localBranches);
  }
  if (_remoteBranches) {
    CFRelease(_remoteBranches);
  }
  if (_tags) {
    CFRelease(_tags);
  }
  CFRelease(_children);
  CFRelease(_parents);
  
  [super dealloc];
}

- (NSArray*)parents {
  return (NSArray*)_parents;
}

- (NSArray*)children {
  return (NSArray*)_children;
}

- (NSArray*)localBranches {
  return (NSArray*)_localBranches;
}

- (NSArray*)remoteBranches {
  return (NSArray*)_remoteBranches;
}

- (NSArray*)tags {
  return (NSArray*)_tags;
}

- (void)addParent:(GCHistoryCommit*)commit {
  CFArrayAppendValue(_parents, (const void*)commit);
}

- (void)removeParent:(GCHistoryCommit*)commit {
  CFIndex index = CFArrayGetFirstIndexOfValue(_parents, CFRangeMake(0, CFArrayGetCount(_parents)), (const void*)commit);
  if (index != kCFNotFound) {
    CFArrayRemoveValueAtIndex(_parents, index);
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (void)addChild:(GCHistoryCommit*)commit {
  CFArrayAppendValue(_children, (const void*)commit);
}

- (void)removeChild:(GCHistoryCommit*)commit {
  CFIndex index = CFArrayGetFirstIndexOfValue(_children, CFRangeMake(0, CFArrayGetCount(_children)), (const void*)commit);
  if (index != kCFNotFound) {
    CFArrayRemoveValueAtIndex(_children, index);
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (void)addLocalBranch:(GCHistoryLocalBranch*)branch {
  if (_localBranches == NULL) {
    _localBranches = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
  }
  CFArrayAppendValue(_localBranches, (const void*)branch);
}

- (void)addRemoteBranch:(GCHistoryRemoteBranch*)branch {
  if (_remoteBranches == NULL) {
    _remoteBranches = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
  }
  CFArrayAppendValue(_remoteBranches, (const void*)branch);
}

- (void)addTag:(GCHistoryTag*)tag {
  if (_tags == NULL) {
    _tags = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
  }
  CFArrayAppendValue(_tags, (const void*)tag);
}

- (void)removeAllReferences {
  if (_localBranches) {
    CFRelease(_localBranches);
    _localBranches = NULL;
  }
  if (_remoteBranches) {
    CFRelease(_remoteBranches);
    _remoteBranches = NULL;
  }
  if (_tags) {
    CFRelease(_tags);
    _tags = NULL;
  }
}

- (BOOL)isRoot {
  return CFArrayGetCount(_parents) ? NO : YES;
}

- (BOOL)isLeaf {
  return CFArrayGetCount(_children) ? NO : YES;
}

- (BOOL)hasReferences {
  return _localBranches || _remoteBranches || _tags;
}

@end

@interface GCHistoryTag ()
@property(nonatomic, assign) GCHistoryCommit* commit;
@property(nonatomic, strong) GCTagAnnotation* annotation;
@end

@implementation GCHistoryTag

- (void)dealloc {
  [_annotation release];
  
  [super dealloc];
}

@end

@interface GCHistoryLocalBranch ()
@property(nonatomic, assign) GCHistoryCommit* tipCommit;
@property(nonatomic, assign) GCBranch* upstream;
@end

@implementation GCHistoryLocalBranch
@end

@interface GCHistoryRemoteBranch ()
@property(nonatomic, assign) GCHistoryCommit* tipCommit;
@end

@implementation GCHistoryRemoteBranch
@end

@interface GCHistory ()
@property(nonatomic) NSUInteger nextGeneration;
@property(nonatomic, strong) NSArray* tags;
@property(nonatomic, strong) NSArray* localBranches;
@property(nonatomic, strong) NSArray* remoteBranches;
@property(nonatomic) NSUInteger nextAutoIncrementID;
@property(nonatomic, readonly) NSMutableArray* commits;
@property(nonatomic, readonly) NSMutableArray* roots;
@property(nonatomic, readonly) NSMutableArray* leaves;
@property(nonatomic, readonly) CFMutableDictionaryRef lookup;
@property(nonatomic, strong) NSSet* tips;
@property(nonatomic, assign) GCHistoryCommit* HEADCommit;
@property(nonatomic, assign) GCHistoryLocalBranch* HEADBranch;
@property(nonatomic, strong) NSData* md5;
@end

@implementation GCHistory {
  GCSearchIndex* _searchIndex;
}

- (instancetype)initWithRepository:(GCRepository*)repository sorting:(GCHistorySorting)sorting {
  if ((self = [super init])) {
    _repository = repository;
    _sorting = sorting;
    _commits = [[NSMutableArray alloc] initWithCapacity:4096];
    _roots = [[NSMutableArray alloc] init];
    _leaves = [[NSMutableArray alloc] init];
    CFDictionaryKeyCallBacks callbacks = {0, NULL, NULL, NULL, GCOIDEqualCallBack, GCOIDHashCallBack};
    _lookup = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &callbacks, NULL);
  }
  return self;
}

- (void)dealloc {
  [_tags release];
  [_localBranches release];
  [_remoteBranches release];
  [_tips release];
  [_md5 release];
  
  CFRelease(_lookup);
  [_leaves release];
  [_roots release];
  [_commits release];
  
  [super dealloc];
}

#pragma mark - Accessors

- (BOOL)isEmpty {
  return !_commits.count;
}

- (NSArray*)allCommits {
  return _commits;
}

- (NSArray*)rootCommits {
  return _roots;
}

- (NSArray*)leafCommits {
  return _leaves;
}

- (BOOL)isHEADDetached {
  return _HEADBranch ? NO : YES;
}

#pragma mark - Utilities

- (GCHistoryCommit*)historyCommitForOID:(const git_oid*)oid {
  return CFDictionaryGetValue(_lookup, oid);
}

- (GCHistoryCommit*)historyCommitWithSHA1:(NSString*)sha1 {
  git_oid oid;
  if (!GCGitOIDFromSHA1(sha1, &oid, NULL)) {
    XLOG_DEBUG_UNREACHABLE();
    return nil;
  }
  return [self historyCommitForOID:&oid];
}

- (GCHistoryCommit*)historyCommitForCommit:(GCCommit*)commit {
  return [self historyCommitForOID:git_commit_id(commit.private)];
}

- (GCHistoryLocalBranch*)historyLocalBranchForLocalBranch:(GCLocalBranch*)branch {
  for (GCHistoryLocalBranch* localBranch in _localBranches) {
    if ([localBranch isEqualToBranch:branch]) {
      return localBranch;
    }
  }
  return nil;
}

- (GCHistoryLocalBranch*)historyLocalBranchWithName:(NSString*)name {
  for (GCHistoryLocalBranch* localBranch in _localBranches) {
    if ([localBranch.name isEqualToString:name]) {
      return localBranch;
    }
  }
  return nil;
}

- (GCHistoryRemoteBranch*)historyRemoteBranchForRemoteBranch:(GCRemoteBranch*)branch {
  for (GCHistoryRemoteBranch* remoteBranch in _remoteBranches) {
    if ([remoteBranch isEqualToBranch:branch]) {
      return remoteBranch;
    }
  }
  return nil;
}

- (GCHistoryRemoteBranch*)historyRemoteBranchWithName:(NSString*)name {
  for (GCHistoryRemoteBranch* remoteBranch in _remoteBranches) {
    if ([remoteBranch.name isEqualToString:name]) {
      return remoteBranch;
    }
  }
  return nil;
}

#pragma mark - Misc

- (NSUInteger)countAncestorCommitsFromCommit:(GCHistoryCommit*)fromCommit toCommit:(GCHistoryCommit*)toCommit {
  if (![fromCommit isEqualToCommit:toCommit]) {
    __block NSUInteger counter = 1;
    BOOL* states = calloc(_nextAutoIncrementID, sizeof(BOOL));
    
    COMMIT_STATE(toCommit) = YES;
    GCHistoryWalker* walker = [self walkerForAncestorsOfCommits:@[fromCommit]];
    while (1) {
      NSUInteger oldCounter = counter;
      if (![walker iterateWithCommitBlock:^(GCHistoryCommit* commit, BOOL* stop) {
        
        if (!COMMIT_STATE(commit)) {
          BOOL skip = NO;
          CFArrayRef children = commit->_children;
          for (CFIndex i = 0, count = CFArrayGetCount(children); i < count; ++i) {
            GCHistoryCommit* childCommit = CFArrayGetValueAtIndex(children, i);
            if (COMMIT_STATE(childCommit)) {
              skip = YES;
              break;
            }
          }
          if (skip) {
            COMMIT_STATE(commit) = YES;
          } else {
            ++counter;
          }
        }
        
      }] || (counter == oldCounter)) {
        break;
      }
    }
    
    free(states);
    return counter;
  }
  XLOG_DEBUG_UNREACHABLE();
  return 0;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@] %lu commits\n HEAD Commit: %@\nHEAD Branch: %@\nRoots: %@\nLeafs:\n%@", self.class, (unsigned long)_commits.count, _HEADCommit, _HEADBranch, _roots, _leaves];
}

@end

@implementation GCHistoryWalker {
  GCHistory* _history;
  NSUInteger _nextGeneration;
  NSArray* _commits;
  BOOL _followParents;
  BOOL _entireHistory;
  BOOL _done;
  
  int* states;
  GCPointerList row;
  GCPointerList previousRow;
  GCPointerList candidates;
  int iteration;
}

- (id)initWithHistory:(GCHistory*)history
              commits:(NSArray*)commits
        followParents:(BOOL)followParents
        entireHistory:(BOOL)entireHistory {
  if ((self = [super init])) {
    _history = [history retain];
    _nextGeneration = history.nextGeneration;
    _commits = [commits retain];
    _followParents = followParents;
    _entireHistory = entireHistory;
    
    states = calloc(history.nextAutoIncrementID, sizeof(int));
    GC_POINTER_LIST_INITIALIZE(row, 32);
    GC_POINTER_LIST_INITIALIZE(previousRow, GC_POINTER_LIST_MAX(row));
    GC_POINTER_LIST_INITIALIZE(candidates, 4);
    iteration = 1;
  }
  return self;
}

- (void)dealloc {
  GC_POINTER_LIST_FREE(candidates);
  GC_POINTER_LIST_FREE(previousRow);
  GC_POINTER_LIST_FREE(row);
  free(states);
  
  [_commits release];
  [_history release];
  
  [super dealloc];
}

- (BOOL)iterateWithCommitBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block {
  if (_done) {
    XLOG_DEBUG_UNREACHABLE();  // We were already done iterating before!
    return NO;
  }
  
  if (_history.nextGeneration != _nextGeneration) {
    XLOG_DEBUG_UNREACHABLE();  // The history has changed from under us!
    return NO;
  }
  
  // Seed first row with initial commits
  if (_commits) {
    for (GCHistoryCommit* commit in _commits) {
      if (_entireHistory) {
        BOOL stop = NO;
        block(commit, &stop);
        if (stop) {
          _done = YES;
          return NO;
        }
      }
      SET_COMMIT_PROCESSED(commit);
      GC_POINTER_LIST_APPEND(previousRow, commit);
    }
    [_commits release];
    _commits = nil;
    if (GC_POINTER_LIST_COUNT(previousRow) == 0) {
      XLOG_DEBUG_UNREACHABLE();
      _done = YES;
      return NO;
    }
    if (_entireHistory) {
      return YES;
    }
  }
  
  // Keep generating commit rows following parents (respectively children)
  if (GC_POINTER_LIST_COUNT(previousRow)) {
    __block BOOL success = NO;
    BOOL (^commitBlock)(GCHistoryCommit*) = ^(GCHistoryCommit* commit) {
      XLOG_DEBUG_CHECK(!COMMIT_IS_PROCESSED(commit));
      BOOL ready = YES;
      
      // Check if this commit is "ready" i.e. all its children (respectively parents) have been processed (but not on the current iteration)
      CFArrayRef relations = _followParents ? commit->_children : commit->_parents;
      for (CFIndex j = 0, jMax = CFArrayGetCount(relations); j < jMax; ++j) {
        GCHistoryCommit* relation = CFArrayGetValueAtIndex(relations, j);
        ready = COMMIT_IS_PROCESSED(relation) && !COMMIT_WAS_JUST_PROCESSED(relation);
        if (!ready) {
          break;
        }
      }
      
      // Process commit if ready or skip it otherwise
      if (ready) {
        BOOL stop = NO;
        block(commit, &stop);
        if (stop) {
          return NO;
        }
        SET_COMMIT_PROCESSED(commit);
        success = YES;
      } else {
        SET_COMMIT_SKIPPED(commit);
      }
      GC_POINTER_LIST_APPEND(row, commit);
      return YES;
    };
    ++iteration;
    
    // Iterate over commits from previous row
    GC_POINTER_LIST_FOR_LOOP(previousRow, GCHistoryCommit*, previousCommit) {
      
      // If commit was processed, attempt to process its parents (respectively children)
      if (COMMIT_IS_PROCESSED(previousCommit)) {
        if (!COMMIT_WAS_JUST_PROCESSED(previousCommit)) {
          CFArrayRef relations = _followParents ? previousCommit->_parents : previousCommit->_children;
          for (CFIndex i = 0, iMax = CFArrayGetCount(relations); i < iMax; ++i) {
            GCHistoryCommit* relation = CFArrayGetValueAtIndex(relations, i);
            if (!COMMIT_WAS_JUST_PROCESSED(relation) && !COMMIT_WAS_JUST_SKIPPED(relation)) {
              XLOG_DEBUG_CHECK(!GC_POINTER_LIST_CONTAINS(row, relation));
              if (!commitBlock(relation)) {
                _done = YES;
                return NO;
              }
            }
          }
        }
      }
      // Otherwise, commit was skipped, attempt to reprocess it
      else {
        if (!COMMIT_WAS_JUST_SKIPPED(previousCommit)) {
          XLOG_DEBUG_CHECK(!GC_POINTER_LIST_CONTAINS(row, previousCommit));
          if (!commitBlock(previousCommit)) {
            _done = YES;
            return NO;
          }
        }
      }
      
    }
    
    // If row is empty we're done
    if (!GC_POINTER_LIST_COUNT(row)) {
      _done = YES;
      return NO;
    }
    
    // If row only contains only skipped commits (this can only happen when not walking the entire history),
    // break the deadlock by force processing the newest (respectively oldest) skipped commit
    if (!success) {
      XLOG_DEBUG_CHECK(!_entireHistory);
      XLOG_DEBUG_CHECK(sizeof(git_time_t) == sizeof(int64_t));
      
      // Find newest (respectively oldest) skipped commit(s)
      git_time_t boundaryTime = _followParents ? LONG_LONG_MIN : LONG_LONG_MAX;
      GC_POINTER_LIST_FOR_LOOP(row, GCHistoryCommit*, timeCommit) {
        git_time_t time = git_commit_time(timeCommit.private);
        if (time == boundaryTime) {
          GC_POINTER_LIST_APPEND(candidates, timeCommit);
        } else if ((_followParents && (time > boundaryTime)) || (!_followParents && (time < boundaryTime))) {
          GC_POINTER_LIST_RESET(candidates);
          GC_POINTER_LIST_APPEND(candidates, timeCommit);
          boundaryTime = time;
        }
      }
      
      // If we have multiple candidates, remove the ones that are parents (respectively children) of the others
      if (GC_POINTER_LIST_COUNT(candidates) > 1) {
        GC_POINTER_LIST_ALLOCATE(temp, GC_POINTER_LIST_MAX(candidates));
        GC_POINTER_LIST_FOR_LOOP(candidates, GCHistoryCommit*, candidate1) {
          BOOL isParent = NO;
          GC_POINTER_LIST_FOR_LOOP(candidates, GCHistoryCommit*, candidate2) {
            if (candidate2 != candidate1) {
              CFArrayRef relations = _followParents ? candidate2->_parents : candidate2->_children;
              if (CFArrayContainsValue(relations, CFRangeMake(0, CFArrayGetCount(relations)), candidate1)) {
                isParent = YES;
                break;
              }
            }
          }
          if (!isParent) {
            GC_POINTER_LIST_APPEND(temp, candidate1);
          }
        }
        GC_POINTER_LIST_SWAP(temp, candidates);
        GC_POINTER_LIST_FREE(temp);
        
        // Bail if we still have more than a single candidate since it's not possible to guarantee the following commits won't be processed out-of-order
        if (GC_POINTER_LIST_COUNT(candidates) != 1) {
          XLOG_ERROR(@"Unable to continue walking history in \"%@\" due to unsolvable deadlock", _history.repository.repositoryPath);
          _done = YES;
          return NO;
        }
      }
      
      // Force process commit
      GCHistoryCommit* commit = GC_POINTER_LIST_GET(candidates, 0);
      BOOL stop = NO;
      block(commit, &stop);
      if (stop) {
        _done = YES;
        return NO;
      }
      SET_COMMIT_PROCESSED(commit);
    }
    
    // Save row
    GC_POINTER_LIST_SWAP(row, previousRow);
    GC_POINTER_LIST_RESET(row);
  } else {
    _done = YES;
    return NO;
  }
  
  return YES;
}

@end

@implementation GCHistory (GCHistoryWalker)

- (void)walkAncestorsOfCommits:(NSArray*)commits usingBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block {
  GCHistoryWalker* walker = [[GCHistoryWalker alloc] initWithHistory:self commits:commits followParents:YES entireHistory:NO];
  while ([walker iterateWithCommitBlock:block]) {
    ;
  }
  [walker release];
}

- (void)walkDescendantsOfCommits:(NSArray*)commits usingBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block {
  GCHistoryWalker* walker = [[GCHistoryWalker alloc] initWithHistory:self commits:commits followParents:NO entireHistory:NO];
  while ([walker iterateWithCommitBlock:block]) {
    ;
  }
  [walker release];
}

- (void)walkAllCommitsFromLeavesUsingBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block {
  GCHistoryWalker* walker = [[GCHistoryWalker alloc] initWithHistory:self commits:_leaves followParents:YES entireHistory:YES];
  while ([walker iterateWithCommitBlock:block]) {
    ;
  }
  [walker release];
}

- (void)walkAllCommitsFromRootsUsingBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block {
  GCHistoryWalker* walker = [[GCHistoryWalker alloc] initWithHistory:self commits:_roots followParents:NO entireHistory:YES];
  while ([walker iterateWithCommitBlock:block]) {
    ;
  }
  [walker release];
}

- (GCHistoryWalker*)walkerForAncestorsOfCommits:(NSArray*)commits {
  return [[[GCHistoryWalker alloc] initWithHistory:self commits:commits followParents:YES entireHistory:NO] autorelease];
}

- (GCHistoryWalker*)walkerForDescendantsOfCommits:(NSArray*)commits {
  return [[[GCHistoryWalker alloc] initWithHistory:self commits:commits followParents:NO entireHistory:NO] autorelease];
}

@end

@implementation GCRepository (GCHistory)

#pragma mark - Repository

- (void)_walkAncestorsFromCommit:(GCHistoryCommit*)commit usingBlock:(BOOL (^)(GCHistoryCommit* commit, GCHistoryCommit* childCommit))block {
  GC_POINTER_LIST_ALLOCATE(parentsCommits, 32);
  GC_POINTER_LIST_ALLOCATE(childrenCommits, 32);
  GC_POINTER_LIST_APPEND(parentsCommits, commit);
  GC_POINTER_LIST_APPEND(childrenCommits, NULL);
  while (1) {
    size_t count = GC_POINTER_LIST_COUNT(parentsCommits);
    XLOG_DEBUG_CHECK(GC_POINTER_LIST_COUNT(childrenCommits) == count);
    if (count == 0) {
      break;
    }
    GCHistoryCommit* parentCommit = GC_POINTER_LIST_POP(parentsCommits);
    GCHistoryCommit* childCommit = GC_POINTER_LIST_POP(childrenCommits);
    while (1) {
      if (!block(parentCommit, childCommit)) {
        break;
      }
      CFArrayRef grandParents = parentCommit->_parents;
      CFIndex grandCount = CFArrayGetCount(grandParents);
      if (grandCount) {
        childCommit = parentCommit;
        parentCommit = CFArrayGetValueAtIndex(grandParents, 0);
        for (CFIndex i = 1; i < grandCount; ++i) {
          GC_POINTER_LIST_APPEND(parentsCommits, (GCHistoryCommit*)CFArrayGetValueAtIndex(grandParents, i));
          GC_POINTER_LIST_APPEND(childrenCommits, childCommit);
        }
      } else {
        break;
      }
    }
  }
  GC_POINTER_LIST_FREE(parentsCommits);
  GC_POINTER_LIST_FREE(childrenCommits);
}

- (BOOL)_reloadHistory:(GCHistory*)history
         usingSnapshot:(GCSnapshot*)snapshot
   referencesDidChange:(BOOL*)outReferencesDidChange
          addedCommits:(NSArray**)outAddedCommits
        removedCommits:(NSArray**)outRemovedCommits
                 error:(NSError**)error {
  XLOG_DEBUG_CHECK([NSThread isMainThread]);  // This could work from any thread but it really shouldn't happen in practice
  BOOL success = NO;
  NSUInteger nextAutoIncrementID = history.nextAutoIncrementID;
  NSUInteger generation = history.nextGeneration;
  GCCommit* headTip = nil;
  __block GCHistoryLocalBranch* headBranch = nil;
  git_reference* headReference = NULL;
  NSMutableSet* tips = [[NSMutableSet alloc] init];
  NSSet* historyTips = history.tips;
  NSMutableArray* tags = [[NSMutableArray alloc] init];
  NSMutableArray* localBranches = [[NSMutableArray alloc] init];
  NSMutableArray* remoteBranches = [[NSMutableArray alloc] init];
  git_revwalk* walker = NULL;
  CFMutableDictionaryRef lookup = history.lookup;
  NSMutableArray* commits = historyTips ? [NSMutableArray array] : history.commits;
  NSMutableArray* roots = history.roots;
  NSMutableArray* leaves = history.leaves;
  NSMutableArray* addedCommits = nil;
  NSMutableArray* removedCommits = nil;
  NSDictionary* config = nil;
  
  // Reset output arguments
  if (outReferencesDidChange) {
    *outReferencesDidChange = NO;
  }
  if (outAddedCommits) {
    *outAddedCommits = nil;
  }
  if (outRemovedCommits) {
    *outRemovedCommits = nil;
  }
  
  // Load local config
  if (snapshot) {
    config = snapshot.config;
  } else {
    NSArray* options = [self readConfigForLevel:kGCConfigLevel_Local error:error];
    if (options == nil) {
      goto cleanup;
    }
    config = [NSMutableDictionary dictionary];
    for (GCConfigOption* option in options) {
      [(NSMutableDictionary*)config setObject:option.value forKey:option.variable];  // TODO: Handle duplicate config entries for the same variable
    }
  }
  
  // Initialize MD5
  CC_MD5_CTX md5Context;
  CC_MD5_CTX* md5ContextPtr = &md5Context;  // Required for use within block
  CC_MD5_Init(md5ContextPtr);
  
  // Find HEAD tip
  git_commit* headCommit = NULL;
  if (snapshot) {
    for (GCSerializedReference* serializedReference in snapshot.serializedReferences) {
      if ([serializedReference isHEAD]) {
        GCSerializedReference* resolvedReference = serializedReference;
        while (resolvedReference.type == GIT_REF_SYMBOLIC) {
          resolvedReference = [snapshot serializedReferenceWithName:resolvedReference.symbolicTarget];
        }
        if (resolvedReference) {  // Allow unborn HEAD
          CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &headCommit, self.private, resolvedReference.resolvedTarget);
          headTip = [[GCCommit alloc] initWithRepository:self commit:headCommit];
          if (resolvedReference != serializedReference) {
            CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_create_virtual, &headReference, self.private, resolvedReference.name, resolvedReference.resolvedTarget);
          }
        }
        break;
      }
    }
  } else {
    if (![self loadHEADCommit:&headCommit resolvedReference:&headReference error:error]) {  // Allow unborn HEAD
      goto cleanup;
    }
    if (headCommit) {
      headTip = [[GCCommit alloc] initWithRepository:self commit:headCommit];
    }
  }
  if (headTip) {
    [tips addObject:headTip];
  }
  if (headReference) {
    CC_MD5_Update(md5ContextPtr, git_reference_name(headReference), (CC_LONG)strlen(git_reference_name(headReference)));
  }
  if (headCommit) {
    CC_MD5_Update(md5ContextPtr, git_commit_id(headCommit), sizeof(git_oid));
  }
  
  // Find all other tips
  BOOL (^enumerateBlock)(git_reference*) = ^(git_reference* reference) {
    
    GCReference* referenceObject = nil;
    if (git_reference_type(reference) != GIT_REF_SYMBOLIC) {  // Skip symbolic refs like "remote/origin/HEAD"
      git_commit* commit = NULL;
      git_tag* tag = NULL;
      git_oid oid;
      if ([self loadTargetOID:&oid fromReference:reference error:NULL]) {  // Ignore errors since repositories can have invalid references
        git_object* object;
        int status = git_object_lookup(&object, self.private, &oid, GIT_OBJ_ANY);
        if (status == GIT_OK) {
          if (git_object_type(object) == GIT_OBJ_COMMIT) {
            commit = (git_commit*)object;
            object = NULL;
          } else if (git_object_type(object) == GIT_OBJ_TAG) {
            status = git_object_peel((git_object**)&commit, object, GIT_OBJ_COMMIT);
            if (status == GIT_OK) {
              tag = (git_tag*)object;
            } else {
              git_object_free(object);
            }
          } else {
            XLOG_DEBUG_UNREACHABLE();
            git_object_free(object);
          }
        }
        if (status != GIT_OK) {
          LOG_LIBGIT2_ERROR(status);
        }
      }
      if (commit) {
        GCCommit* referenceCommit = [[GCCommit alloc] initWithRepository:self commit:commit];
        GCTagAnnotation* referenceAnnotation = tag ? [[GCTagAnnotation alloc] initWithRepository:self tag:tag] : nil;
        git_buf upstreamName = {0};
        if (git_reference_is_tag(reference)) {
          referenceObject = [[GCHistoryTag alloc] initWithRepository:self reference:reference];
          [tags addObject:referenceObject];
        } else if (git_reference_is_branch(reference)) {
          referenceObject = [[GCHistoryLocalBranch alloc] initWithRepository:self reference:reference];
          [localBranches addObject:referenceObject];
          if (headReference && ([referenceObject compareWithReference:headReference] == NSOrderedSame)) {
            XLOG_DEBUG_CHECK(headBranch == nil);
            headBranch = (GCHistoryLocalBranch*)referenceObject;
          }
          NSString* remoteName = [config objectForKey:[NSString stringWithFormat:@"branch.%s.remote", git_reference_shorthand(reference)]];
          NSString* mergeName = [config objectForKey:[NSString stringWithFormat:@"branch.%s.merge", git_reference_shorthand(reference)]];
          if (remoteName.length && mergeName.length) {
            int status = git_branch_upstream_name_from_merge_remote_names(&upstreamName, self.private, remoteName.UTF8String, mergeName.UTF8String);
            if ((status != GIT_OK) && (status != GIT_ENOTFOUND)) {
              LOG_LIBGIT2_ERROR(status);  // Don't fail because of corrupted config
            }
          }
        } else if (git_reference_is_remote(reference)) {
          referenceObject = [[GCHistoryRemoteBranch alloc] initWithRepository:self reference:reference];
          [remoteBranches addObject:referenceObject];
        } else {
          XLOG_VERBOSE(@"Ignoring reference \"%s\" for history of \"%@\"", git_reference_name(reference), self.repositoryPath);
        }
        if (referenceObject) {
          [tips addObject:referenceCommit];
          objc_setAssociatedObject(referenceObject, _associatedObjectCommitKey, referenceCommit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);  // Must be retained since commit is not necessarily retained by tips set
          objc_setAssociatedObject(referenceObject, _associatedObjectAnnotationKey, referenceAnnotation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);  // Must be retained since commit is not necessarily retained by tips set
          if (upstreamName.ptr) {
            objc_setAssociatedObject(referenceObject, _associatedObjectUpstreamNameKey, [NSString stringWithUTF8String:upstreamName.ptr], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          }
          
          CC_MD5_Update(md5ContextPtr, git_reference_name(reference), (CC_LONG)strlen(git_reference_name(reference)));
          CC_MD5_Update(md5ContextPtr, git_commit_id(commit), sizeof(git_oid));
          if (upstreamName.ptr) {
            CC_MD5_Update(md5ContextPtr, upstreamName.ptr, (CC_LONG)upstreamName.size);
          }
        }
        git_buf_free(&upstreamName);
        if (referenceAnnotation) {
          [referenceAnnotation release];
        }
        [referenceCommit release];
      } else {
        XLOG_WARNING(@"Dangling direct reference \"%s\" without commit in \"%@\"", git_reference_name(reference), self.repositoryPath);
      }
    }
    if (referenceObject) {
      [referenceObject release];
    } else {
      git_reference_free(reference);
    }
    return YES;
    
  };
  if (snapshot) {
    for (GCSerializedReference* serializedReference in snapshot.serializedReferences) {
      if ([serializedReference isHEAD]) {
        continue;
      }
      git_reference* reference = NULL;
      switch (serializedReference.type) {
        
        case GIT_REF_OID:
          CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_create_virtual, &reference, self.private, serializedReference.name, serializedReference.directTarget);
          break;
        
        case GIT_REF_SYMBOLIC:
          CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_symbolic_create_virtual, &reference, self.private, serializedReference.name, serializedReference.symbolicTarget);
          break;
        
        default:
          XLOG_DEBUG_UNREACHABLE();
          goto cleanup;
        
      }
      if (!enumerateBlock(reference)) {
        git_reference_free(reference);
        goto cleanup;
      }
    }
  } else {
    if (![self enumerateReferencesWithOptions:kGCReferenceEnumerationOption_RetainReferences error:error usingBlock:enumerateBlock]) {
      goto cleanup;
    }
  }
  
  // Check if there were any modified references compared to previous version of history
  NSMutableData* md5 = [NSMutableData dataWithLength:CC_MD5_DIGEST_LENGTH];
  CC_MD5_Final(md5.mutableBytes, md5ContextPtr);
  if ([history.md5 isEqualToData:md5]) {
    success = YES;
    goto cleanup;
  }
  
  // Configure commit tree walker to start from tips
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_revwalk_new, &walker, self.private);
  git_revwalk_sorting(walker, GIT_SORT_NONE);
  if (historyTips) {
    for (GCCommit* tip in tips) {
      if (![historyTips containsObject:tip]) {
        const git_oid* oid = git_commit_id(tip.private);
        if (CFDictionaryContainsKey(lookup, oid)) {
          CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_revwalk_hide, walker, oid);
        } else {
          CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_revwalk_push, walker, oid);
        }
      }
    }
    for (GCCommit* historyTip in historyTips) {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_revwalk_hide, walker, git_commit_id(historyTip.private));
    }
  } else {
    for (GCCommit* tip in tips) {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_revwalk_push, walker, git_commit_id(tip.private));
    }
  }
  
  // Generate commits by walking commit tree
  while (1) {
    git_oid oid;
    int status = git_revwalk_next(&oid, walker);
    if (status == GIT_ITEROVER) {
      break;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
    if (historyTips && CFDictionaryContainsKey(lookup, &oid)) {
      continue;
    }
    git_commit* walkCommit;
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &walkCommit, self.private, &oid);
    GCHistoryCommit* commit = [[GCHistoryCommit alloc] initWithRepository:self commit:walkCommit autoIncrementID:nextAutoIncrementID++];
    [commits addObject:commit];
    [commit release];
    CFDictionarySetValue(lookup, git_commit_id(walkCommit), (const void*)commit);  // Use the git_oid stored in the object itself (and retained by GCHistoryCommit) as the key, so no need to copy it
  }
  
  // Add parent / child relations to commits
  for (GCHistoryCommit* commit in commits) {
    git_commit* walkCommit = commit.private;
    for (unsigned int i = 0, count = git_commit_parentcount(walkCommit); i < count; ++i) {
      const git_oid* parentOID = git_commit_parent_id(walkCommit, i);
      GCHistoryCommit* parent = (GCHistoryCommit*)CFDictionaryGetValue(lookup, parentOID);
      if (parent) {  // We can't distinguish between a commit missing from the Git database and one that was hidden explicitly
        [commit addParent:parent];
        [parent addChild:commit];  // TODO: Find a way to make this ordering deterministic
      }
    }
  }
  
  // Merge newfound commits into old history
  if (historyTips) {
    [history.commits addObjectsFromArray:commits];
    addedCommits = commits;
    commits = history.commits;
  }
  
  // Clear old references
  if (historyTips) {
    for (GCHistoryTag* tag in history.tags) {
      [tag.commit removeAllReferences];
    }
    for (GCHistoryLocalBranch* branch in history.localBranches) {
      [branch.tipCommit removeAllReferences];
    }
    for (GCHistoryRemoteBranch* branch in history.remoteBranches) {
      [branch.tipCommit removeAllReferences];
    }
  }
  
  // Find and remove orphan commits from old history
  if (historyTips) {
    
    // Update generation for all commits reachable from new tips
    for (GCCommit* tip in tips) {
      GCHistoryCommit* tipCommit = (GCHistoryCommit*)CFDictionaryGetValue(lookup, git_commit_id(tip.private));
      XLOG_DEBUG_CHECK(tipCommit);
      [self _walkAncestorsFromCommit:tipCommit usingBlock:^BOOL(GCHistoryCommit* commit, GCHistoryCommit* previousCommit) {
        
        if (commit->generation == generation) {
          return NO;
        }
        commit->generation = generation;
        return YES;
        
      }];
    }
    
    // Scan all commits reachable from old tips and check if still reachable from new tips
    removedCommits = [[NSMutableArray alloc] init];  // Make sure to retain removed commits as they can be accessed several times through the scan
    for (GCCommit* tip in historyTips) {
      GCHistoryCommit* tipCommit = (GCHistoryCommit*)CFDictionaryGetValue(lookup, git_commit_id(tip.private));
      if (tipCommit == nil) {
        continue;  // Commit might have already been removed
      }
      [self _walkAncestorsFromCommit:tipCommit usingBlock:^BOOL(GCHistoryCommit* commit, GCHistoryCommit* childCommit) {
        
        if (commit->generation == generation) {
          if (childCommit) {
            [childCommit removeParent:commit];
            [commit removeChild:childCommit];
          }
          return NO;
        }
        if (CFDictionaryContainsKey(lookup, git_commit_id(commit.private))) {  // Using -indexOfObjectIdenticalTo: on a large array can be quite slow so make sure the commit is in there first
          NSUInteger index = [commits indexOfObjectIdenticalTo:commit];  // Pointer comparison is enough here, no need for -isEqual
          if (index != NSNotFound) {
            [removedCommits addObject:commit];
            CFDictionaryRemoveValue(lookup, git_commit_id(commit.private));
            [commits removeObjectAtIndex:index];  // Should be a bit faster than calling -removeObjectIdenticalTo: since it will stop on the first (and unique) match
            XLOG_DEBUG_CHECK(![commits containsObject:commit]);
          } else {
            XLOG_DEBUG_UNREACHABLE();
          }
        }
        return YES;
        
      }];
    }
    
  }
  
  // Sort commits
  if (history.sorting == kGCHistorySorting_ReverseChronological) {
    [commits sortUsingSelector:@selector(reverseTimeCompare:)];  // Newest first
  } else {
    XLOG_DEBUG_CHECK(history.sorting == kGCHistorySorting_None);
  }
  
  // Update roots and leaves
  if (historyTips) {
    [roots removeAllObjects];
    [leaves removeAllObjects];
  }
  for (GCHistoryCommit* commit in commits) {
    if (commit.root) {
      [roots addObject:commit];
    }
    if (commit.leaf) {
      XLOG_DEBUG_CHECK([tips containsObject:commit]);
      [leaves addObject:commit];
    }
  }
  
  // Add new references
  for (NSUInteger i = 0, count = tags.count; i < count; ++i) {
    GCHistoryTag* tag = tags[i];
    GCCommit* referenceCommit = objc_getAssociatedObject(tag, _associatedObjectCommitKey);
    GCHistoryCommit* commit = CFDictionaryGetValue(lookup, git_commit_id(referenceCommit.private));
    objc_setAssociatedObject(tag, _associatedObjectCommitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (commit) {
      tag.commit = commit;
      tag.annotation = objc_getAssociatedObject(tag, _associatedObjectAnnotationKey);
      [commit addTag:tag];
      objc_setAssociatedObject(tag, _associatedObjectAnnotationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
      XLOG_WARNING(@"Missing commit for tag \"%@\" in \"%@\"", tag.name, self.repositoryPath);
      [tags removeObjectAtIndex:i];
      --i;
      --count;
    }
  }
  [tags sortUsingSelector:@selector(nameCompare:)];
  for (NSUInteger i = 0, count = localBranches.count; i < count; ++i) {
    GCHistoryLocalBranch* branch = localBranches[i];
    GCCommit* referenceCommit = objc_getAssociatedObject(branch, _associatedObjectCommitKey);
    XLOG_DEBUG_CHECK(!objc_getAssociatedObject(branch, _associatedObjectAnnotationKey));
    GCHistoryCommit* commit = CFDictionaryGetValue(lookup, git_commit_id(referenceCommit.private));
    objc_setAssociatedObject(branch, _associatedObjectCommitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (commit) {
      branch.tipCommit = commit;
      [commit addLocalBranch:branch];
    } else {
      XLOG_WARNING(@"Missing commit for branch \"%@\" in \"%@\"", branch.name, self.repositoryPath);
      if (branch == headBranch) {
        headBranch = nil;
      }
      [localBranches removeObjectAtIndex:i];
      --i;
      --count;
    }
  }
  [localBranches sortUsingSelector:@selector(nameCompare:)];
  for (NSUInteger i = 0, count = remoteBranches.count; i < count; ++i) {
    GCHistoryRemoteBranch* branch = remoteBranches[i];
    GCCommit* referenceCommit = objc_getAssociatedObject(branch, _associatedObjectCommitKey);
    XLOG_DEBUG_CHECK(!objc_getAssociatedObject(branch, _associatedObjectAnnotationKey));
    GCHistoryCommit* commit = CFDictionaryGetValue(lookup, git_commit_id(referenceCommit.private));
    objc_setAssociatedObject(branch, _associatedObjectCommitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (commit) {
      branch.tipCommit = commit;
      [commit addRemoteBranch:branch];
    } else {
      XLOG_WARNING(@"Missing commit for branch \"%@\" in \"%@\"", branch.name, self.repositoryPath);
      [remoteBranches removeObjectAtIndex:i];
      --i;
      --count;
    }
  }
  [remoteBranches sortUsingSelector:@selector(nameCompare:)];
  for (GCHistoryLocalBranch* branch in localBranches) {
    NSString* upstreamName = objc_getAssociatedObject(branch, _associatedObjectUpstreamNameKey);
    if (upstreamName) {
      for (GCHistoryRemoteBranch* remoteBranch in remoteBranches) {
        if ([remoteBranch.fullName isEqualToString:upstreamName]) {
          branch.upstream = remoteBranch;
          break;
        }
      }
      if (branch.upstream == nil) {
        for (GCHistoryLocalBranch* localBranch in localBranches) {
          if ([localBranch.fullName isEqualToString:upstreamName]) {
            branch.upstream = localBranch;
            break;
          }
        }
      }
      objc_setAssociatedObject(branch, _associatedObjectUpstreamNameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  }
  
  // Finish saving state in history
  history.nextAutoIncrementID = nextAutoIncrementID;
  history.nextGeneration = generation + 1;
  history.tags = tags;
  history.localBranches = localBranches;
  history.remoteBranches = remoteBranches;
  history.tips = tips;
  if (headTip) {
    history.HEADCommit = (GCHistoryCommit*)CFDictionaryGetValue(lookup, git_commit_id(headTip.private));
    if (history.HEADCommit == nil) {
      XLOG_WARNING(@"Missing commit for HEAD in \"%@\"", self.repositoryPath);
    }
  } else {
    history.HEADCommit = nil;
  }
  history.HEADBranch = headBranch;
  XLOG_DEBUG_CHECK(!headReference || !history.HEADCommit || history.HEADBranch);
  history.md5 = md5;
  
  // We're done!
  if (outReferencesDidChange) {
    *outReferencesDidChange = YES;
  }
  if (outAddedCommits) {
    *outAddedCommits = addedCommits;
  }
  if (outRemovedCommits) {
    *outRemovedCommits = removedCommits;
  }
  [removedCommits autorelease];  // Don't release remove commits immediately as client may still depend on them!
  success = YES;
  
#if DEBUG
  // Check history consistency
  XLOG_DEBUG_CHECK((NSUInteger)CFDictionaryGetCount(lookup) == commits.count);
  for (GCHistoryCommit* commit in commits) {
    XLOG_DEBUG_CHECK(CFDictionaryContainsKey(lookup, git_commit_id(commit.private)));
    for (GCHistoryCommit* parent in commit.parents) {
      XLOG_DEBUG_CHECK(CFDictionaryContainsKey(lookup, git_commit_id(parent.private)));
    }
    for (GCHistoryCommit* child in commit.children) {
      XLOG_DEBUG_CHECK(CFDictionaryContainsKey(lookup, git_commit_id(child.private)));
    }
    for (GCHistoryLocalBranch* branch in commit.localBranches) {
      XLOG_DEBUG_CHECK(branch.tipCommit == commit);
    }
    for (GCHistoryRemoteBranch* branch in commit.remoteBranches) {
      XLOG_DEBUG_CHECK(branch.tipCommit == commit);
    }
    for (GCHistoryTag* tag in commit.tags) {
      XLOG_DEBUG_CHECK(tag.commit == commit);
    }
  }
#endif
  
cleanup:
  [headTip release];
  [tips release];
  [tags release];
  [localBranches release];
  [remoteBranches release];
  git_revwalk_free(walker);
  git_reference_free(headReference);
  return success;
}

- (GCHistory*)loadHistoryUsingSorting:(GCHistorySorting)sorting error:(NSError**)error {
  GCHistory* history = [[[GCHistory alloc] initWithRepository:self sorting:sorting] autorelease];
  return [self _reloadHistory:history usingSnapshot:nil referencesDidChange:NULL addedCommits:NULL removedCommits:NULL error:error] ? history : nil;
}

- (BOOL)reloadHistory:(GCHistory*)history referencesDidChange:(BOOL*)referencesDidChange addedCommits:(NSArray**)addedCommits removedCommits:(NSArray**)removedCommits error:(NSError**)error {
  return [self _reloadHistory:history usingSnapshot:nil referencesDidChange:referencesDidChange addedCommits:addedCommits removedCommits:removedCommits error:error];
}

- (GCHistory*)loadHistoryFromSnapshot:(GCSnapshot*)snapshot usingSorting:(GCHistorySorting)sorting error:(NSError**)error {
  GCHistory* history = [[[GCHistory alloc] initWithRepository:self sorting:sorting] autorelease];
  return [self _reloadHistory:history usingSnapshot:snapshot referencesDidChange:NULL addedCommits:NULL removedCommits:NULL error:error] ? history : nil;
}

#pragma mark - File

- (NSArray*)lookupCommitsForFile:(NSString*)path followRenames:(BOOL)follow error:(NSError**)error {
  NSMutableArray* commits = nil;
  char* fileName = strdup(GCGitPathFromFileSystemPath(path));
  git_revwalk* walker = NULL;
  git_oid oid;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_revwalk_new, &walker, self.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_revwalk_push_head, walker);
  git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL);
  commits = [[NSMutableArray alloc] init];
  git_diff_options diffOptions = GIT_DIFF_OPTIONS_INIT;
  diffOptions.flags = GIT_DIFF_SKIP_BINARY_CHECK;  // This should not be needed since not generating patches anyway
  git_diff_find_options findOptions = GIT_DIFF_FIND_OPTIONS_INIT;
  findOptions.flags = GIT_DIFF_FIND_RENAMES;
  while (1) {
    int status = git_revwalk_next(&oid, walker);
    if (status == GIT_OK) {
      git_commit* commit;
      status = git_commit_lookup(&commit, self.private, &oid);
      if (status == GIT_OK) {
        git_tree* tree;
        status = git_commit_tree(&tree, commit);
        if (status == GIT_OK) {
          git_tree_entry* entry;
          status = git_tree_entry_bypath(&entry, tree, fileName);
          if (status == GIT_OK) {
            for (unsigned int i = 0, count = git_commit_parentcount(commit); i < count; ++i) {
              git_commit* parentCommit;
              status = git_commit_parent(&parentCommit, commit, i);
              if (status == GIT_OK) {
                git_tree* parentTree;
                status = git_commit_tree(&parentTree, parentCommit);
                if (status == GIT_OK) {
                  git_diff* diff = NULL;
                  status = git_diff_tree_to_tree(&diff, self.private, parentTree, tree, &diffOptions);
                  if ((status == GIT_OK) && follow) {
                    status = git_diff_find_similar(diff, &findOptions);
                  }
                  if (status == GIT_OK) {
                    for (size_t i2 = 0, count2 = git_diff_num_deltas(diff); i2 < count2; ++i2) {
                      const git_diff_delta* delta = git_diff_get_delta(diff, i2);
                      if (strcmp(delta->new_file.path, fileName) == 0) {
                        GCCommit* newCommit = [[GCCommit alloc] initWithRepository:self commit:commit];
                        [commits addObject:newCommit];
                        [newCommit release];
                        commit = NULL;
                        if (delta->status == GIT_DELTA_RENAMED) {
                          free(fileName);
                          fileName = strdup(delta->old_file.path);
                        } else if (delta->status == GIT_DELTA_ADDED) {
                          status = GIT_ITEROVER;
                        } else {
                          XLOG_DEBUG_CHECK(delta->status == GIT_DELTA_MODIFIED);
                        }
                      }
                    }
                  }
                  git_diff_free(diff);
                  git_tree_free(parentTree);
                }
                git_commit_free(parentCommit);
              }
            }
            git_tree_entry_free(entry);
          } else if (status == GIT_ENOTFOUND) {
            status = GIT_ITEROVER;
          }
          git_tree_free(tree);
        }
        git_commit_free(commit);
      }
    }
    if (status == GIT_ITEROVER) {
      break;
    }
    if (status != GIT_OK) {
      [commits release];
      commits = nil;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
  }
  
cleanup:
  git_revwalk_free(walker);
  free(fileName);
  return [commits autorelease];
}

@end
