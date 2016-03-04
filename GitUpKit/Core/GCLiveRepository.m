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

#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import <sys/stat.h>
#import <sys/attr.h>

#import "GCPrivate.h"

#import "XLFunctions.h"

#define kFSLatency 0.5
#define kUpdateLatency 0.5

#define kMaxSnapshots 100
#define kSnapshotsFileName @"snapshots.data"
#define kSnapshotKey_Date @"date"  // NSDate
#define kSnapshotKey_Reason @"reason"  // NSString
#define kSnapshotKey_Argument @"argument"  // id<NSCoding>

#define kAutomaticSnapshotDelay (5 - kFSLatency - kUpdateLatency)

#define kCommitDatabaseFileName @"cache.db"

#define kMinSearchLength 2  // SQLite FTS indexes tokens down to a single characters but it's just impractical to allow that in the UI

NSString* const GCLiveRepositoryDidChangeNotification = @"GCLiveRepositoryDidChangeNotification";
NSString* const GCLiveRepositoryWorkingDirectoryDidChangeNotification = @"GCLiveRepositoryWorkingDirectoryDidChangeNotification";

NSString* const GCLiveRepositoryStateDidUpdateNotification = @"GCLiveRepositoryStateDidUpdateNotification";
NSString* const GCLiveRepositoryHistoryDidUpdateNotification = @"GCLiveRepositoryHistoryDidUpdateNotification";
NSString* const GCLiveRepositoryStashesDidUpdateNotification = @"GCLiveRepositoryStashesDidUpdateNotification";
NSString* const GCLiveRepositoryStatusDidUpdateNotification = @"GCLiveRepositoryStatusDidUpdateNotification";
NSString* const GCLiveRepositorySnapshotsDidUpdateNotification = @"GCLiveRepositorySnapshotsDidUpdateNotification";
NSString* const GCLiveRepositorySearchDidUpdateNotification = @"GCLiveRepositorySearchDidUpdateNotification";

NSString* const GCLiveRepositoryCommitOperationReason = @"commit";
NSString* const GCLiveRepositoryAmendOperationReason = @"amend";

#if DEBUG
static int32_t _allocatedCount = 0;
#endif

@implementation GCLiveRepository {
  int _gitDirectory;
  FSEventStreamRef _gitDirectoryStream;
  BOOL _gitDirectoryChanged;
  FSEventStreamRef _workingDirectoryStream;
  BOOL _workingDirectoryChanged;
  CFRunLoopTimerRef _updateTimer;  // Can't use a NSTimer because of retain-cycle
  GCRepositoryState _state;
  NSInteger _historyUpdatesSuspended;
  BOOL _historyUpdatePending;
  
  NSMutableArray* _snapshots;
  CFRunLoopTimerRef _snapshotsTimer;
  GCSnapshot* _lastSnapshot;
  BOOL _snapshotPending;
  
  GCCommitDatabase* _database;
  BOOL _databaseIndexesDiffs;
  BOOL _updatingDatabase;
  BOOL _databaseUpdatePending;
  
  NSString* _undoActionName;
}

@dynamic delegate;

+ (instancetype)allocWithZone:(struct _NSZone*)zone {
  GCLiveRepository* repository = [super allocWithZone:zone];
  if (repository) {
    repository->_gitDirectory = -1;  // Prevents calling close(0) in -dealloc in case super returns nil
#if DEBUG
    OSAtomicIncrement32(&_allocatedCount);
#endif
  }
  return repository;
}

#if DEBUG

+ (NSUInteger)allocatedCount {
  return _allocatedCount;
}

#endif

- (void)_timer:(CFRunLoopTimerRef)timer {
  if (timer == _updateTimer) {
    [self _notifyWorkingDirectoryChanged:_workingDirectoryChanged gitDirectoryChanged:_gitDirectoryChanged];
    _workingDirectoryChanged = NO;
    _gitDirectoryChanged = NO;
  } else if (timer == _snapshotsTimer) {
    [self _saveAutomaticSnapshotIfPending];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

static void _TimerCallBack(CFRunLoopTimerRef timer, void* info) {
  @autoreleasepool {
    [(__bridge GCLiveRepository*)info _timer:timer];
  }
}

- (void)_stream:(ConstFSEventStreamRef)stream didReceiveEvents:(size_t)numEvents withPaths:(void*)eventPaths flags:(const FSEventStreamEventFlags*)eventFlags {
  for (size_t i = 0; i < numEvents; ++i) {
    const char* path = ((const char**)eventPaths)[i];
    if (eventFlags[i] & kFSEventStreamEventFlagRootChanged) {
      
      XLOG_DEBUG_CHECK(stream == _gitDirectoryStream);
      char buffer[PATH_MAX];
      if (fcntl(_gitDirectory, F_GETPATH, buffer) >= 0) {
        XLOG_VERBOSE(@"Repository \"%s\" has moved to \"%s\"", git_repository_path(self.private), buffer);
        git_repository* repository;
        int status = git_repository_open(&repository, buffer);
        if (status == GIT_OK) {
          [self updateRepository:repository];  // TODO: Is this really safe?
          [self _reloadWorkingDirectoryStream];
        } else {
          LOG_LIBGIT2_ERROR(status);
        }
      } else {
        XLOG_DEBUG_UNREACHABLE();
        XLOG_ERROR(@"Failed retrieving directory path (%s)", strerror(errno));
      }
      
    } else if (eventFlags[i] & kFSEventStreamEventFlagMustScanSubDirs) {
      
      XLOG_WARNING(@"Ignoring event stream request to rescan \"%s\"", path);  // Note that this directory path can be missing the trailing slash
      
    } else {  // Documentation says "eventFlags" should be 0x0 for regular events but that's not the case on OS X 10.10 at least
      
      const char* gitDirectoryPath = git_repository_path(self.private);
      size_t length = strlen(gitDirectoryPath);
      XLOG_DEBUG_CHECK(gitDirectoryPath[length - 1] == '/');
      if (stream == _gitDirectoryStream) {
        if (!strncmp(path, gitDirectoryPath, length)) {
          const char* subPath = &path[length];
          if (!subPath[0] || !strncmp(subPath, "refs/", 5) || !strncmp(subPath, "logs/", 5)) {  // We only care about ".git/", ".git/refs/*" and ".git/logs/*"
            XLOG_DEBUG(@"Processed file system event for '%s'", path);
            _gitDirectoryChanged = YES;
            CFRunLoopTimerSetNextFireDate(_updateTimer, CFAbsoluteTimeGetCurrent() + kUpdateLatency);
          } else {
            XLOG_DEBUG(@"Dropped file system event for '%s'", path);
          }
        } else {
          XLOG_DEBUG_UNREACHABLE();
        }
      } else {
        if (strncmp(path, gitDirectoryPath, length)) {  // Make sure change is not inside ".git" directory if itself inside workdir
          int ignored = 0;
          int status = git_ignore_path_is_ignored(&ignored, self.private, path);  // Make sure path is not ignored
          if (status != GIT_OK) {
            LOG_LIBGIT2_ERROR(status);
          }
          if (!ignored) {
            XLOG_DEBUG(@"Processed file system event for '%s'", path);
            _workingDirectoryChanged = YES;
            CFRunLoopTimerSetNextFireDate(_updateTimer, CFAbsoluteTimeGetCurrent() + kUpdateLatency);
          } else {
            XLOG_DEBUG(@"Dropped file system event for '%s'", path);
          }
        }
      }
      
    }
  }
}

static void _StreamCallback(ConstFSEventStreamRef streamRef, void* clientCallBackInfo, size_t numEvents, void* eventPaths,
                            const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]) {
  @autoreleasepool {
    [(__bridge GCLiveRepository*)clientCallBackInfo _stream:streamRef didReceiveEvents:numEvents withPaths:eventPaths flags:eventFlags];
  }
}

- (void)_reloadWorkingDirectoryStream {
  if (_workingDirectoryStream) {
    FSEventStreamStop(_workingDirectoryStream);
    FSEventStreamInvalidate(_workingDirectoryStream);
    FSEventStreamRelease(_workingDirectoryStream);
    _workingDirectoryStream = NULL;
  }
  NSString* path = self.workingDirectoryPath;  // nil for bare repositories
  if (path) {
    FSEventStreamContext streamContext = {0, (__bridge void*)self, NULL, NULL, NULL};
    _workingDirectoryStream = FSEventStreamCreate(kCFAllocatorDefault, _StreamCallback, &streamContext,
                                                  (__bridge CFArrayRef)@[path], kFSEventStreamEventIdSinceNow,
                                                  kFSLatency, kFSEventStreamCreateFlagIgnoreSelf);  // This opens the path
    if (_workingDirectoryStream) {
      FSEventStreamScheduleWithRunLoop(_workingDirectoryStream, CFRunLoopGetMain(), kCFRunLoopCommonModes);
      if (!FSEventStreamStart(_workingDirectoryStream)) {
        XLOG_ERROR(@"Failed starting event stream at \"%@\"", path);
      }
    } else {
      XLOG_ERROR(@"Failed creating event stream at \"%@\"", path);
    }
  }
}

- (instancetype)initWithRepository:(git_repository*)repository error:(NSError**)error {
  if ((self = [super initWithRepository:repository error:error])) {
    _diffWhitespaceMode = kGCLiveRepositoryDiffWhitespaceMode_Normal;
    _diffMaxInterHunkLines = 0;
    _diffMaxContextLines = 3;
    
    _state = [super state];
    
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    _history = [self loadHistoryUsingSorting:[self.class historySorting] error:error];
    if (_history == nil) {
      return nil;
    }
    XLOG_VERBOSE(@"History loaded for \"%@\" (%lu commits scanned in %.3f seconds)", self.repositoryPath, _history.allCommits.count, CFAbsoluteTimeGetCurrent() - time);
    
    NSString* path = self.repositoryPath;
    _gitDirectory = open(path.fileSystemRepresentation, O_RDONLY);  // Don't use O_EVTONLY as we do want to prevent unmounting the volume that contains the directory
    CHECK_POSIX_FUNCTION_CALL(return nil, _gitDirectory, >= 0);
    
    CFRunLoopTimerContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
    _updateTimer = CFRunLoopTimerCreate(kCFAllocatorDefault, HUGE_VALF, HUGE_VALF, 0, 0, _TimerCallBack, &context);
    CFRunLoopAddTimer(CFRunLoopGetMain(), _updateTimer, kCFRunLoopCommonModes);
    
    FSEventStreamContext streamContext = {0, (__bridge void*)self, NULL, NULL, NULL};
    _gitDirectoryStream = FSEventStreamCreate(kCFAllocatorDefault, _StreamCallback, &streamContext,
                                              (__bridge CFArrayRef)@[path], kFSEventStreamEventIdSinceNow,
                                              kFSLatency, kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagIgnoreSelf);  // This opens the path
    if (_gitDirectoryStream == NULL) {
      XLOG_ERROR(@"Failed creating event stream at \"%@\"", path);
      return nil;
    }
    FSEventStreamScheduleWithRunLoop(_gitDirectoryStream, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    if (!FSEventStreamStart(_gitDirectoryStream)) {
      XLOG_ERROR(@"Failed starting event stream at \"%@\"", path);
      return nil;
    }
    
    [self _reloadWorkingDirectoryStream];
  }
  return self;
}

- (void)dealloc {
  [_undoManager removeAllActionsWithTarget:self];
  if (_workingDirectoryStream) {
    FSEventStreamStop(_workingDirectoryStream);
    FSEventStreamInvalidate(_workingDirectoryStream);
    FSEventStreamRelease(_workingDirectoryStream);
  }
  if (_gitDirectoryStream) {
    FSEventStreamStop(_gitDirectoryStream);
    FSEventStreamInvalidate(_gitDirectoryStream);
    FSEventStreamRelease(_gitDirectoryStream);
  }
  if (_snapshotsTimer) {
    CFRunLoopTimerInvalidate(_snapshotsTimer);
    CFRelease(_snapshotsTimer);
  }
  if (_updateTimer) {
    CFRunLoopTimerInvalidate(_updateTimer);
    CFRelease(_updateTimer);
  }
  if (_gitDirectory >= 0) {
    close(_gitDirectory);
  }
#if DEBUG
  OSAtomicDecrement32(&_allocatedCount);
#endif
}

- (void)_notifyWorkingDirectoryChanged:(BOOL)workingDirectoryChanged gitDirectoryChanged:(BOOL)gitDirectoryChanged {
  if (workingDirectoryChanged) {
    if (_statusMode != kGCLiveRepositoryStatusMode_Disabled) {
      [self _updateStatus:YES];
    }
    
    if ([self.delegate respondsToSelector:@selector(repositoryWorkingDirectoryDidChange:)]) {
      [self.delegate repositoryWorkingDirectoryDidChange:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:GCLiveRepositoryWorkingDirectoryDidChangeNotification object:self];
  }
  if (gitDirectoryChanged) {
    [self _updateState];
    if (_historyUpdatesSuspended > 0) {
      _historyUpdatePending = YES;
    } else {
      [self _updateHistory];
    }
    if (_stashesEnabled) {
      [self _updateStashes:YES];
    }
    if ((_statusMode != kGCLiveRepositoryStatusMode_Disabled) && !workingDirectoryChanged) {  // Don't update status twice!
      [self _updateStatus:YES];
    }
    
    if ([self.delegate respondsToSelector:@selector(repositoryDidChange:)]) {
      [self.delegate repositoryDidChange:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:GCLiveRepositoryDidChangeNotification object:self];
  }
}

- (void)notifyRepositoryChanged {
  [self _notifyWorkingDirectoryChanged:NO gitDirectoryChanged:YES];
}

- (void)notifyWorkingDirectoryChanged {
  [self _notifyWorkingDirectoryChanged:YES gitDirectoryChanged:NO];
}

#pragma mark - Diffs

- (void)setDiffWhitespaceMode:(GCLiveRepositoryDiffWhitespaceMode)mode {
  if (mode != _diffWhitespaceMode) {
    _diffWhitespaceMode = mode;
    if (_statusMode != kGCLiveRepositoryStatusMode_Disabled) {
      [self _updateStatus:YES];
    }
  }
}

- (void)setDiffMaxInterHunkLines:(NSUInteger)lines {
  if (lines != _diffMaxInterHunkLines) {
    _diffMaxInterHunkLines = lines;
    if (_statusMode != kGCLiveRepositoryStatusMode_Disabled) {
      [self _updateStatus:YES];
    }
  }
}

- (void)setDiffMaxContextLines:(NSUInteger)lines {
  if (lines != _diffMaxContextLines) {
    _diffMaxContextLines = lines;
    if (_statusMode != kGCLiveRepositoryStatusMode_Disabled) {
      [self _updateStatus:YES];
    }
  }
}

- (GCDiffOptions)diffBaseOptions {
  switch (_diffWhitespaceMode) {
    case kGCLiveRepositoryDiffWhitespaceMode_Normal: return 0;
    case kGCLiveRepositoryDiffWhitespaceMode_IgnoreChanges: return kGCDiffOption_IgnoreSpaceChanges;
    case kGCLiveRepositoryDiffWhitespaceMode_IgnoreAll: return kGCDiffOption_IgnoreAllSpaces;
  }
  XLOG_DEBUG_UNREACHABLE();
  return 0;
}

#pragma mark - State

- (void)_updateState {
  GCRepositoryState state = [super state];
  if (state != _state) {
    _state = state;
    
    if ([self.delegate respondsToSelector:@selector(repositoryDidUpdateState:)]) {
      [self.delegate repositoryDidUpdateState:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:GCLiveRepositoryStateDidUpdateNotification object:self];
  }
}

// Override super implementation and return cached state
- (GCRepositoryState)state {
  return _state;
}

#pragma mark - History

+ (GCHistorySorting)historySorting {
  return kGCHistorySorting_None;
}

- (BOOL)areHistoryUpdatesSuspended {
  return _historyUpdatesSuspended > 0;
}

- (void)suspendHistoryUpdates {
  _historyUpdatesSuspended += 1;
}

- (void)resumeHistoryUpdates {
  XLOG_DEBUG_CHECK(_historyUpdatesSuspended > 0);
  _historyUpdatesSuspended -= 1;
  if (_historyUpdatesSuspended == 0) {
    if (_historyUpdatePending) {
      [self _updateHistory];
      _historyUpdatePending = NO;
    }
  }
}

- (void)_updateHistory {
  NSError* error;
  BOOL referencesDidChange;
  CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
  if ([self reloadHistory:_history referencesDidChange:&referencesDidChange addedCommits:NULL removedCommits:NULL error:&error]) {
    if (referencesDidChange) {
      XLOG_VERBOSE(@"History updated for \"%@\" (%lu commits scanned in %.3f seconds)", self.repositoryPath, _history.allCommits.count, CFAbsoluteTimeGetCurrent() - time);
      
      if (_snapshotsTimer) {
        CFRunLoopTimerSetNextFireDate(_snapshotsTimer, CFAbsoluteTimeGetCurrent() + kAutomaticSnapshotDelay);
        _snapshotPending = YES;
      }
      
      if ([self.delegate respondsToSelector:@selector(repositoryDidUpdateHistory:)]) {
        [self.delegate repositoryDidUpdateHistory:self];
      }
      [[NSNotificationCenter defaultCenter] postNotificationName:GCLiveRepositoryHistoryDidUpdateNotification object:self];
      
      if (_database) {
        [self _updateSearch];
      }
    }
  } else {
    if ([self.delegate respondsToSelector:@selector(repository:historyUpdateDidFailWithError:)]) {
      [self.delegate repository:self historyUpdateDidFailWithError:error];
    }
  }
}

- (void)_updateDatabaseInBackgroundWithProgressHandler:(GCCommitDatabaseProgressHandler)handler
                                            completion:(void (^)(BOOL success, NSError* error))completion {
  XLOG_DEBUG_CHECK(!_updatingDatabase);
  NSString* path = [self.privateAppDirectoryPath stringByAppendingPathComponent:kCommitDatabaseFileName];
  _updatingDatabase = YES;
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    
    NSError* error;
    GCRepository* repository = [[GCRepository alloc] initWithExistingLocalRepository:self.repositoryPath error:&error];  // We cannot use self because we access the repo on a background thread
    GCCommitDatabase* database = repository ? [[GCCommitDatabase alloc] initWithRepository:repository
                                                                              databasePath:path
                                                                                   options:(_databaseIndexesDiffs ? kGCCommitDatabaseOptions_IndexDiffs : 0)
                                                                                     error:&error] : nil;
    BOOL success = [database updateWithProgressHandler:handler error:&error];
    database = nil;  // Release and close immediately
    dispatch_async(dispatch_get_main_queue(), ^{
      
      XLOG_DEBUG_CHECK(_updatingDatabase);
      _updatingDatabase = NO;
      completion(success, error);
      
    });
    
  });
}

- (void)_updateSearch {
  XLOG_DEBUG_CHECK(_database);
  if (_updatingDatabase) {
    _databaseUpdatePending = YES;
  } else {
    [self _updateDatabaseInBackgroundWithProgressHandler:NULL completion:^(BOOL success, NSError* error) {
      
      if (success) {
        if ([self.delegate respondsToSelector:@selector(repositoryDidUpdateSearch:)]) {
          [self.delegate repositoryDidUpdateSearch:self];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:GCLiveRepositorySearchDidUpdateNotification object:self];
        
        if (_databaseUpdatePending) {
          [self _updateSearch];
          _databaseUpdatePending = NO;
        }
      } else {
        if ([self.delegate respondsToSelector:@selector(repository:searchUpdateDidFailWithError:)]) {
          [self.delegate repository:self searchUpdateDidFailWithError:error];
        }
      }
      
    }];
  }
}

#pragma mark - Snapshots

- (void)_writeSnapshots {
  BOOL success = NO;
  NSString* path = [self.privateAppDirectoryPath stringByAppendingPathComponent:kSnapshotsFileName];
  if (path) {
    NSString* tempPath = [path stringByAppendingString:@"~"];
    if ([NSKeyedArchiver archiveRootObject:_snapshots toFile:tempPath]) {
      struct stat info;
      if (lstat(path.fileSystemRepresentation, &info) == 0) {
        if (exchangedata(tempPath.fileSystemRepresentation, path.fileSystemRepresentation, FSOPT_NOFOLLOW) == 0) {
          success = YES;
        }
      } else {
        if (rename(tempPath.fileSystemRepresentation, path.fileSystemRepresentation) == 0) {
          success = YES;
        }
      }
      if (!success) {
        XLOG_ERROR(@"Failed archiving snapshots: %s", strerror(errno));
      }
    }
  }
  if (!success && [self.delegate respondsToSelector:@selector(repository:snapshotsUpdateDidFailWithError:)]) {
    [self.delegate repository:self snapshotsUpdateDidFailWithError:GCNewError(kGCErrorCode_Generic, @"Failed writing snapshots")];
  }
}

- (void)_readSnapshots {
  NSString* path = [self.privateAppDirectoryPath stringByAppendingPathComponent:kSnapshotsFileName];
  if (path) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
      NSArray* array = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
      if (array) {
        [_snapshots addObjectsFromArray:array];
      } else if ([self.delegate respondsToSelector:@selector(repository:snapshotsUpdateDidFailWithError:)]) {
        [self.delegate repository:self snapshotsUpdateDidFailWithError:GCNewError(kGCErrorCode_Generic, @"Failed reading snapshots")];
      }
    }
  } else if ([self.delegate respondsToSelector:@selector(repository:snapshotsUpdateDidFailWithError:)]) {
    [self.delegate repository:self snapshotsUpdateDidFailWithError:GCNewError(kGCErrorCode_Generic, @"Failed accessing snapshots")];
  }
}

- (BOOL)_saveSnapshot:(GCSnapshot*)snapshot withReason:(NSString*)reason argument:(id<NSCoding>)argument {
  if ([_snapshots.firstObject isEqualToSnapshot:snapshot usingOptions:(kGCSnapshotOption_IncludeLocalBranches | kGCSnapshotOption_IncludeTags)]) {
    return NO;
  }
  snapshot[kSnapshotKey_Date] = [NSDate date];
  snapshot[kSnapshotKey_Reason] = reason;
  if (argument) {
    snapshot[kSnapshotKey_Argument] = argument;
  }
  [_snapshots insertObject:snapshot atIndex:0];
  if (_snapshots.count > kMaxSnapshots) {
    [_snapshots removeObjectsInRange:NSMakeRange(kMaxSnapshots, _snapshots.count - kMaxSnapshots)];
  }
  XLOG_VERBOSE(@"Saved snapshot with reason '%@' for \"%@\"", reason, self.repositoryPath);
  if ([self.delegate respondsToSelector:@selector(repositoryDidUpdateSnapshots:)]) {
    [self.delegate repositoryDidUpdateSnapshots:self];
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:GCLiveRepositorySnapshotsDidUpdateNotification object:self];
  
  [self _writeSnapshots];
  return YES;
}

- (BOOL)_saveAutomaticSnapshotIfNeeded:(BOOL)isFirst {
  NSError* error;
  GCSnapshot* snapshot = [self takeSnapshot:&error];
  if (snapshot) {
    if (![_snapshots.firstObject isEqualToSnapshot:snapshot usingOptions:(kGCSnapshotOption_IncludeLocalBranches | kGCSnapshotOption_IncludeTags)]) {
      NSString* reason = isFirst ? (_snapshots.count ? @"open" : @"initial") : @"automatic";
      [self _saveSnapshot:snapshot withReason:reason argument:nil];
      return YES;
    }
  } else if ([self.delegate respondsToSelector:@selector(repository:snapshotsUpdateDidFailWithError:)]) {
    [self.delegate repository:self snapshotsUpdateDidFailWithError:error];
  }
  return NO;
}

- (void)_saveAutomaticSnapshotIfPending {
  if (_snapshotPending) {
    [self _saveAutomaticSnapshotIfNeeded:NO];
    _snapshotPending = NO;
  }
}

- (void)setSnapshotsEnabled:(BOOL)flag {
  BOOL notify = NO;
  if (flag && !_snapshots) {
    _snapshots = [[NSMutableArray alloc] init];
    [self _readSnapshots];
    if (![self _saveAutomaticSnapshotIfNeeded:YES]) {
      notify = YES;
    }
  } else if (!flag && _snapshots) {
    _snapshots = nil;
    notify = YES;
  }
  if (notify) {
    if ([self.delegate respondsToSelector:@selector(repositoryDidUpdateSnapshots:)]) {
      [self.delegate repositoryDidUpdateSnapshots:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:GCLiveRepositorySnapshotsDidUpdateNotification object:self];
  }
}

- (BOOL)areSnapshotsEnabled {
  return _snapshots ? YES : NO;
}

- (void)setAutomaticSnapshotsEnabled:(BOOL)flag {
  if (flag && !_snapshotsTimer) {
    XLOG_DEBUG_CHECK(_snapshotPending == NO);
    CFRunLoopTimerContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
    _snapshotsTimer = CFRunLoopTimerCreate(kCFAllocatorDefault, HUGE_VALF, HUGE_VALF, 0, 0, _TimerCallBack, &context);
    CFRunLoopAddTimer(CFRunLoopGetMain(), _snapshotsTimer, kCFRunLoopCommonModes);
    _lastSnapshot = _snapshots.firstObject;
  } else if (!flag && _snapshotsTimer) {
    [self _saveAutomaticSnapshotIfPending];
    
    if (_lastSnapshot && ![_snapshots.firstObject isEqualToSnapshot:_lastSnapshot usingOptions:(kGCSnapshotOption_IncludeHEAD | kGCSnapshotOption_IncludeLocalBranches | kGCSnapshotOption_IncludeTags)]) {
      XLOG_DEBUG_CHECK(_undoActionName);
      [_undoManager setActionName:_undoActionName];
      [[_undoManager prepareWithInvocationTarget:self] _undoOperationWithReason:@"automatic" beforeSnapshot:_lastSnapshot afterSnapshot:_snapshots.firstObject checkoutIfNeeded:YES ignore:NO];
      _undoActionName = nil;
    }
    
    CFRunLoopTimerInvalidate(_snapshotsTimer);
    CFRelease(_snapshotsTimer);
    _snapshotsTimer = NULL;
  }
}

- (BOOL)areAutomaticSnapshotsEnabled {
  return _snapshotsTimer ? YES : NO;
}

#pragma mark - Status

- (void)setStatusMode:(GCLiveRepositoryStatusMode)mode {
  if (mode != _statusMode) {
    _statusMode = mode;
    if (_statusMode != kGCLiveRepositoryStatusMode_Disabled) {
      [self _updateStatus:NO];
    } else {
      _unifiedStatus = nil;
      _indexStatus = nil;
      _indexConflicts = nil;
      _workingDirectoryStatus = nil;
    }
  }
}

- (void)_updateStatus:(BOOL)notify {
  BOOL success = YES;
  GCDiff* unifiedDiff = nil;
  GCDiff* indexDiff = nil;
  GCDiff* workdirDiff = nil;
  NSDictionary* conflicts = nil;
  NSError* error;
  
  CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
  if (_statusMode == kGCLiveRepositoryStatusMode_Unified) {
    unifiedDiff = [self diffWorkingDirectoryWithHEAD:nil
                                             options:(self.diffBaseOptions | kGCDiffOption_IncludeUntracked | kGCDiffOption_FindRenames)
                                   maxInterHunkLines:_diffMaxInterHunkLines
                                     maxContextLines:_diffMaxContextLines
                                               error:&error];
    if (!unifiedDiff) {
      success = NO;
    }
  } else {
    XLOG_DEBUG_CHECK(_statusMode == kGCLiveRepositoryStatusMode_Normal);
    indexDiff = [self diffRepositoryIndexWithHEAD:nil
                                          options:(self.diffBaseOptions | kGCDiffOption_FindRenames)
                                maxInterHunkLines:_diffMaxInterHunkLines
                                  maxContextLines:_diffMaxContextLines
                                            error:&error];
    if (indexDiff) {
      workdirDiff = [self diffWorkingDirectoryWithRepositoryIndex:nil
                                                          options:(self.diffBaseOptions | kGCDiffOption_IncludeUntracked)
                                                maxInterHunkLines:_diffMaxInterHunkLines
                                                  maxContextLines:_diffMaxContextLines
                                                            error:&error];
    }
    if (!indexDiff || !workdirDiff) {
      success = NO;
    }
  }
  if (success) {
    conflicts = [self checkConflicts:&error];
    if (!conflicts) {
      success = NO;
    }
  }
  
  if (success) {
    if (((_statusMode == kGCLiveRepositoryStatusMode_Unified) && ![_unifiedStatus isEqualToDiff:unifiedDiff]) || ((_statusMode != kGCLiveRepositoryStatusMode_Unified) && (![_indexStatus isEqualToDiff:indexDiff] || ![_workingDirectoryStatus isEqualToDiff:workdirDiff])) || ![_indexConflicts isEqualToDictionary:conflicts]) {
      XLOG_VERBOSE(@"Status updated for \"%@\" in %.3f seconds", self.repositoryPath, CFAbsoluteTimeGetCurrent() - time);
      _unifiedStatus = unifiedDiff;
      _indexStatus = indexDiff;
      _indexConflicts = conflicts;
      _workingDirectoryStatus = workdirDiff;
      
      if (notify) {
        if ([self.delegate respondsToSelector:@selector(repositoryDidUpdateStatus:)]) {
          [self.delegate repositoryDidUpdateStatus:self];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:GCLiveRepositoryStatusDidUpdateNotification object:self];
      }
    } else {
      XLOG_VERBOSE(@"Status checked for \"%@\" in %.3f seconds", self.repositoryPath, CFAbsoluteTimeGetCurrent() - time);
    }
  } else {
    _unifiedStatus = nil;
    _indexStatus = nil;
    _indexConflicts = nil;
    _workingDirectoryStatus = nil;
    if ([self.delegate respondsToSelector:@selector(repository:statusUpdateDidFailWithError:)]) {
      [self.delegate repository:self statusUpdateDidFailWithError:error];
    }
  }
}

#pragma mark - Stashes

- (void)setStashesEnabled:(BOOL)flag {
  if (flag && !_stashesEnabled) {
    _stashesEnabled = YES;
    [self _updateStashes:NO];
  } else if (!flag && _stashesEnabled) {
    _stashes = nil;
    _stashesEnabled = NO;
  }
}

- (void)_updateStashes:(BOOL)notify {
  NSError* error;
  NSArray* stashes = [self listStashes:&error];
  if (stashes) {
    if (![_stashes isEqualToArray:stashes]) {
      XLOG_VERBOSE(@"Stashes updated for \"%@\"", self.repositoryPath);
      _stashes = stashes;
      
      if (notify) {
        if ([self.delegate respondsToSelector:@selector(repositoryDidUpdateStashes:)]) {
          [self.delegate repositoryDidUpdateStashes:self];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:GCLiveRepositoryStashesDidUpdateNotification object:self];
      }
    }
  } else {
    _stashes = nil;
    if ([self.delegate respondsToSelector:@selector(repository:stashesUpdateDidFailWithError:)]) {
      [self.delegate repository:self stashesUpdateDidFailWithError:error];
    }
  }
}

#pragma mark - Operations

- (void)setUndoManager:(NSUndoManager*)undoManager {
  if (_undoManager && !undoManager) {
    [_undoManager removeAllActionsWithTarget:self];
  }
  _undoManager = undoManager;
}

- (void)setUndoActionName:(NSString*)name {
  _undoActionName = name;
}

- (void)_undoOperationWithReason:(NSString*)reason beforeSnapshot:(GCSnapshot*)beforeSnapshot afterSnapshot:(GCSnapshot*)afterSnapshot checkoutIfNeeded:(BOOL)checkoutIfNeeded ignore:(BOOL)ignore {
  if (ignore) {
    [[_undoManager prepareWithInvocationTarget:self] _undoOperationWithReason:reason beforeSnapshot:beforeSnapshot afterSnapshot:afterSnapshot checkoutIfNeeded:checkoutIfNeeded ignore:NO];
    return;
  }
  
  BOOL success = NO;
  NSError* error;
  GCCommit* oldHeadCommit;
  if (!checkoutIfNeeded || [self lookupHEADCurrentCommit:&oldHeadCommit branch:NULL error:&error]) {
    NSString* message = [NSString stringWithFormat:(_undoManager.redoing ? kGCReflogMessageFormat_GitUp_Redo : kGCReflogMessageFormat_GitUp_Undo), reason, nil];
    if ([self applyDeltaFromSnapshot:afterSnapshot
                          toSnapshot:beforeSnapshot
                         withOptions:(kGCSnapshotOption_IncludeHEAD | kGCSnapshotOption_IncludeLocalBranches | kGCSnapshotOption_IncludeTags)
                       reflogMessage:message
                 didUpdateReferences:NULL
                               error:&error]) {
      GCCommit* newHeadCommit;
      if (!checkoutIfNeeded || [self lookupHEADCurrentCommit:&newHeadCommit branch:NULL error:&error]) {
        if (!checkoutIfNeeded || !newHeadCommit || (oldHeadCommit && [newHeadCommit isEqualToCommit:oldHeadCommit]) || [self checkoutTreeForCommit:nil withBaseline:oldHeadCommit options:kGCCheckoutOption_UpdateSubmodulesRecursively error:&error]) {
          [[_undoManager prepareWithInvocationTarget:self] _undoOperationWithReason:reason beforeSnapshot:afterSnapshot afterSnapshot:beforeSnapshot checkoutIfNeeded:checkoutIfNeeded ignore:NO];
          success = YES;
        }
      }
    }
    [self notifyRepositoryChanged];
  }
  
  if (!success) {  // In case of error, put a dummy operation on the undo stack since we *must* put something, but pop it at the next runloop iteration
    [[_undoManager prepareWithInvocationTarget:self] _undoOperationWithReason:reason beforeSnapshot:beforeSnapshot afterSnapshot:afterSnapshot checkoutIfNeeded:checkoutIfNeeded ignore:YES];
    [_undoManager performSelector:(self.undoManager.isRedoing ? @selector(undo) : @selector(redo)) withObject:nil afterDelay:0.0];
    if ([self.delegate respondsToSelector:@selector(repository:undoOperationDidFailWithError:)]) {
      [self.delegate repository:self undoOperationDidFailWithError:error];
    }
  }
}

- (void)_registerUndoWithReason:(NSString*)reason
                       argument:(id<NSCoding>)argument
                 beforeSnapshot:(GCSnapshot*)beforeSnapshot
                  afterSnapshot:(GCSnapshot*)afterSnapshot
               checkoutIfNeeded:(BOOL)checkoutIfNeeded {
  if (![_snapshots.firstObject isEqualToSnapshot:afterSnapshot usingOptions:(kGCSnapshotOption_IncludeLocalBranches | kGCSnapshotOption_IncludeTags)]) {
    [self _saveSnapshot:afterSnapshot withReason:reason argument:argument];  // Only save snapshot if different from last one (excluding HEAD)
  }
  
#if DEBUG
  if ([afterSnapshot isEqualToSnapshot:beforeSnapshot usingOptions:(kGCSnapshotOption_IncludeHEAD | kGCSnapshotOption_IncludeLocalBranches | kGCSnapshotOption_IncludeTags)]) {
    kill(getpid(), SIGSTOP);  // Break into debugger - only works on main thread
  }
#endif
  XLOG_DEBUG_CHECK(_undoActionName);
  [_undoManager setActionName:_undoActionName];
  [[_undoManager prepareWithInvocationTarget:self] _undoOperationWithReason:reason beforeSnapshot:beforeSnapshot afterSnapshot:afterSnapshot checkoutIfNeeded:checkoutIfNeeded ignore:NO];
  _undoActionName = nil;
}

- (BOOL)performOperationWithReason:(NSString*)reason
                          argument:(id<NSCoding>)argument
                skipCheckoutOnUndo:(BOOL)skipCheckout
                             error:(NSError**)error
                        usingBlock:(BOOL (^)(GCLiveRepository* repository, NSError** outError))block {
  XLOG_DEBUG_CHECK(!_hasBackgroundOperationInProgress);
  BOOL success = NO;
  GCSnapshot* beforeSnapshot = reason ? [self takeSnapshot:error] : nil;
  if (!reason || beforeSnapshot) {
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    if (block(self, error)) {
      XLOG_VERBOSE(@"Performed operation '%@' in \"%@\" in %.3f seconds", reason, self.repositoryPath, CFAbsoluteTimeGetCurrent() - time);
      GCSnapshot* afterSnapshot = reason ? [self takeSnapshot:error] : nil;
      if (!reason || afterSnapshot) {
        if (reason) {
          [self _registerUndoWithReason:reason argument:argument beforeSnapshot:beforeSnapshot afterSnapshot:afterSnapshot checkoutIfNeeded:!skipCheckout];
        }
        success = YES;
      }
    }
    [self notifyRepositoryChanged];
  }
  return success;
}

// In practice this should only be used for remote operations
- (void)performOperationInBackgroundWithReason:(NSString*)reason
                                      argument:(id<NSCoding>)argument
                           usingOperationBlock:(BOOL (^)(GCRepository* repository, NSError** outError))operationBlock
                               completionBlock:(void (^)(BOOL success, NSError* error))completionBlock {
  XLOG_DEBUG_CHECK(!_hasBackgroundOperationInProgress);
  __block NSError* error = nil;
  GCSnapshot* beforeSnapshot = reason ? [self takeSnapshot:&error] : nil;
  if (!reason || beforeSnapshot) {
    [[NSProcessInfo processInfo] disableSuddenTermination];
    _hasBackgroundOperationInProgress = YES;
    if ([self.delegate respondsToSelector:@selector(repositoryBackgroundOperationInProgressDidChange:)]) {
      [self.delegate repositoryBackgroundOperationInProgressDidChange:self];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      
      GCRepository* repository = [[GCRepository alloc] initWithExistingLocalRepository:self.repositoryPath error:&error];
      repository.delegate = self.delegate;
      __block BOOL success = repository && operationBlock(repository, &error);
      dispatch_async(dispatch_get_main_queue(), ^{
        
        if (success) {
          GCSnapshot* afterSnapshot = reason ? [self takeSnapshot:&error] : nil;
          if (!reason || afterSnapshot) {
            if (reason) {
              [self _registerUndoWithReason:reason argument:argument beforeSnapshot:beforeSnapshot afterSnapshot:afterSnapshot checkoutIfNeeded:YES];
            }
            success = YES;
          }
        }
        [self notifyRepositoryChanged];
        _hasBackgroundOperationInProgress = NO;
        if ([self.delegate respondsToSelector:@selector(repositoryBackgroundOperationInProgressDidChange:)]) {
          [self.delegate repositoryBackgroundOperationInProgressDidChange:self];
        }
        [[NSProcessInfo processInfo] enableSuddenTermination];
        completionBlock(success, error);
        
      });
      
    });
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      
      completionBlock(NO, error);
      
    });
  }
}

@end

@implementation GCLiveRepository (Extensions)

- (BOOL)performReferenceTransformWithReason:(NSString*)reason
                                   argument:(id<NSCoding>)argument
                                      error:(NSError**)error
                                 usingBlock:(GCReferenceTransform* (^)(GCLiveRepository* repository, NSError** outError))block {
  return [self performOperationWithReason:reason argument:argument skipCheckoutOnUndo:NO error:error usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    GCReferenceTransform* transform = block(repository, outError);
    if (!transform) {
      return NO;
    }
    GCCommit* oldHeadCommit;
    if (![repository lookupHEADCurrentCommit:&oldHeadCommit branch:NULL error:error]) {
      return NO;
    }
    if (![repository applyReferenceTransform:transform error:outError]) {
      return NO;
    }
    GCCommit* newHeadCommit;
    if (![repository lookupHEADCurrentCommit:&newHeadCommit branch:NULL error:error]) {
      return NO;
    }
    if (newHeadCommit && (!oldHeadCommit || ![newHeadCommit isEqualToCommit:oldHeadCommit])) {
      return [self checkoutTreeForCommit:nil withBaseline:oldHeadCommit options:kGCCheckoutOption_UpdateSubmodulesRecursively error:outError];
    }
    return YES;
    
  }];
}

- (GCCommit*)performCommitCreationFromHEADAndOtherParent:(GCCommit*)parent withMessage:(NSString*)message error:(NSError**)error {
  __block GCCommit* newCommit = nil;
  if (![self performOperationWithReason:GCLiveRepositoryCommitOperationReason
                               argument:nil
                     skipCheckoutOnUndo:YES
                                  error:error
                             usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    newCommit = [repository createCommitFromHEADAndOtherParent:parent withMessage:message error:outError];
    return newCommit ? YES : NO;
    
  }]) {
    return nil;
  }
  return newCommit;
}

- (GCCommit*)performHEADCommitAmendingWithMessage:(NSString*)message error:(NSError**)error {
  __block GCCommit* newCommit = nil;
  if (![self performOperationWithReason:GCLiveRepositoryAmendOperationReason
                               argument:nil
                     skipCheckoutOnUndo:YES
                                  error:error
                             usingBlock:^BOOL(GCLiveRepository* repository, NSError** outError) {
    
    newCommit = [repository createCommitByAmendingHEADWithMessage:message error:error];
    return newCommit ? YES : NO;
    
  }]) {
    return nil;
  }
  return newCommit;
}

@end

@implementation GCLiveRepository (GCCommitDatabase)

- (void)prepareSearchInBackground:(BOOL)indexDiffs
              withProgressHandler:(GCCommitDatabaseProgressHandler)handler
                       completion:(void (^)(BOOL success, NSError* error))completion {
  if (_database == nil) {
    _databaseIndexesDiffs = indexDiffs;
    [self _updateDatabaseInBackgroundWithProgressHandler:handler completion:^(BOOL success, NSError* error) {
      
      if (success) {
        NSString* path = [self.privateAppDirectoryPath stringByAppendingPathComponent:kCommitDatabaseFileName];
        _database = [[GCCommitDatabase alloc] initWithRepository:self
                                                    databasePath:path
                                                         options:((_databaseIndexesDiffs ? kGCCommitDatabaseOptions_IndexDiffs : 0) | kGCCommitDatabaseOptions_QueryOnly)
                                                           error:&error];
        if (_database) {
          if (_databaseUpdatePending) {
            [self _updateSearch];
            _databaseUpdatePending = NO;
          }
        } else {
          success = NO;
        }
      }
      completion(success, error);
      
    }];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

static BOOL _MatchReference(NSString* match, NSString* name) {
  NSRange range = [name rangeOfString:match options:NSCaseInsensitiveSearch];
  return range.location != NSNotFound;
}

- (NSArray*)findCommitsMatching:(NSString*)match {
  XLOG_DEBUG_CHECK(_database);
  NSMutableArray* results = [[NSMutableArray alloc] init];
  match = [match stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if (match.length >= kMinSearchLength) {
    
    // Search SHA1s directly
    NSArray* words = [match componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (NSString* prefix in words) {
      if (prefix.length >= GIT_OID_MINPREFIXLEN) {
        GCCommit* commit = [_history.repository findCommitWithSHA1Prefix:prefix error:NULL];
        if (commit) {
          GCHistoryCommit* historyCommit = [_history historyCommitForCommit:commit];
          if (historyCommit) {
            [results addObject:historyCommit];
          } else {
            XLOG_DEBUG_UNREACHABLE();
          }
        }
      }
    }
    
    // Search references
    for (GCHistoryLocalBranch* branch in _history.localBranches) {
      if (_MatchReference(match, branch.name)) {
        if (branch.tipCommit) {
          [results addObject:branch];
        } else {
          XLOG_DEBUG_UNREACHABLE();
        }
      }
    }
    for (GCHistoryRemoteBranch* branch in _history.remoteBranches) {
      if (_MatchReference(match, branch.name)) {
        if (branch.tipCommit) {
          [results addObject:branch];
        } else {
          XLOG_DEBUG_UNREACHABLE();
        }
      }
    }
    for (GCHistoryTag* tag in _history.tags) {
      if (_MatchReference(match, tag.name)) {
        if (tag.commit) {
          [results addObject:tag];
        } else {
          XLOG_DEBUG_UNREACHABLE();
        }
      }
    }
    
    // Search commits
    [results addObjectsFromArray:[_database findCommitsUsingHistory:_history matching:match error:NULL]];  // Ignore errors
    
  }
  return results;
}

@end

@implementation GCSnapshot (GCLiveRepository)

- (NSDate*)date {
  return self[kSnapshotKey_Date];
}

- (NSString*)reason {
  return self[kSnapshotKey_Reason];
}

- (id<NSCoding>)argument {
  return self[kSnapshotKey_Argument];
}

@end
