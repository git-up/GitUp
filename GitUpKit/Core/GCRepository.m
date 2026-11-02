//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
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

#import <TargetConditionals.h>
#import <pthread.h>
#if !TARGET_OS_IPHONE
#import <git2/sys/filter.h>
#endif

#import "GCPrivate.h"

static inline BOOL _IsDirectoryWritable(const char* path) {
  int status = access(path, W_OK);
  if (status == 0) {
    return YES;
  }
  XLOG_DEBUG_CHECK(errno == EACCES);
  return NO;
}

static inline NSString* _MakeDirectoryPath(const char* path) {
  if (!path) {
    return nil;
  }
  size_t length = strlen(path);
  if (length && (path[length - 1] == '/')) {
    --length;
  }
  if (!length) {
    XLOG_DEBUG_UNREACHABLE();
    return nil;
  }
  return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:length];
}

#if !TARGET_OS_IPHONE

static NSString* _GetPATHUsingShell(NSString* shell, NSError** error) {
  GCTask* task = [[GCTask alloc] initWithExecutablePath:shell];
  NSData* data;
  // `-l` is not supported with `-c` in all shells (tcsh), so try without.
  // Some shells use quoting of $PATH to trigger POSIX compatibility behavior (fish).
  // Not all shells support `-n` on `echo`.
  if (![task runWithArguments:@[ @"-l", @"-c", @"echo \"$PATH\"" ] stdin:NULL stdout:&data stderr:NULL exitStatus:NULL error:error] && ![task runWithArguments:@[ @"-c", @"echo \"$PATH\"" ] stdin:NULL stdout:&data stderr:NULL exitStatus:NULL error:error]) {
    return nil;
  }
  return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

NSArray<NSString*>* GCDefaultExecutableDirectories(void) {
  return @[ @"/opt/homebrew/bin", @"/usr/local/bin", @"/opt/local/bin" ];
}

NSString* GCFindExecutableInPATH(NSString* name, NSString* PATH, NSArray<NSString*>* fallbackDirectories) {
  NSMutableArray* directories = [[NSMutableArray alloc] init];
  for (NSString* directory in [PATH componentsSeparatedByString:@":"]) {
    if (directory.length) {
      [directories addObject:directory];
    }
  }
  [directories addObjectsFromArray:fallbackDirectories];
  NSFileManager* fileManager = [NSFileManager defaultManager];
  for (NSString* directory in directories) {
    NSString* path = [directory stringByAppendingPathComponent:name];
    BOOL isDirectory;
    if ([fileManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory && [fileManager isExecutableFileAtPath:path]) {
      return path;
    }
  }
  return nil;
}

// GUI apps don't inherit the user's shell PATH, so git-lfs is looked up in the login shell PATH first
// and then in the usual install locations.
// This is resolved lazily the first time a file with the "lfs" filter attribute is processed.
static NSString* _GitLFSExecutablePath(NSString** outPATH) {
  static NSString* executablePath = nil;
  static NSString* PATH = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    @autoreleasepool {
      PATH = _GetPATHUsingShell(NSProcessInfo.processInfo.environment[@"SHELL"], NULL) ?: _GetPATHUsingShell(@"/bin/sh", NULL);
      executablePath = GCFindExecutableInPATH(@"git-lfs", PATH, GCDefaultExecutableDirectories());
      if (executablePath) {
        XLOG_VERBOSE(@"Using git-lfs tool at \"%@\"", executablePath);
      } else {
        XLOG_WARNING(@"git-lfs tool not found");
      }
    }
  });
  if (outPATH) {
    *outPATH = PATH;
  }
  return executablePath;
}

// Leave LFS files untouched (i.e. as pointer files) if git-lfs is not installed
static int _GitLFSCheck(git_filter* self, void** payload, const git_filter_source* src, const char** attr_values) {
  return _GitLFSExecutablePath(NULL) ? 0 : GIT_PASSTHROUGH;
}

#define kLFSFilterProcessIdleTimeout 10.0
#define kPacketMaxDataLength 65516

typedef NS_ENUM(NSUInteger, GCFilterProcessResult) {
  kGCFilterProcessResult_Success = 0,
  kGCFilterProcessResult_Error,  // The filter reported it couldn't process the file
  kGCFilterProcessResult_Broken  // Communicating with the filter process failed
};

// Executing "git-lfs clean" or "git-lfs smudge" costs ~200ms per file as git-lfs runs several git commands on startup,
// which adds up to minutes when checking out hundreds of LFS files. So like the git command line, use a single
// long-running "git-lfs filter-process" per working directory instead, talking the long-running filter protocol
// version 2 (see "Long Running Filter Process" in gitattributes(5)), and terminate it once idle.
@interface GCLFSFilterProcess : NSObject
@property(nonatomic) NSUInteger useCount;
- (instancetype)initWithExecutablePath:(NSString*)executablePath PATH:(NSString*)PATH workingDirectory:(NSString*)workingDirectory handshakeFailed:(BOOL*)handshakeFailed;
- (GCFilterProcessResult)runCommand:(NSString*)command pathname:(const char*)pathname input:(const git_buf*)input output:(git_buf*)output;
- (void)terminate;
@end

@implementation GCLFSFilterProcess {
  NSTask* _task;
  NSPipe* _inPipe;
  NSPipe* _outPipe;
  int _writeFD;
  int _readFD;
}

- (instancetype)initWithExecutablePath:(NSString*)executablePath PATH:(NSString*)PATH workingDirectory:(NSString*)workingDirectory handshakeFailed:(BOOL*)handshakeFailed {
  if ((self = [super init])) {
    _inPipe = [[NSPipe alloc] init];
    _outPipe = [[NSPipe alloc] init];
    _task = [[NSTask alloc] init];
    _task.executableURL = [NSURL fileURLWithPath:executablePath];
    _task.arguments = @[ @"filter-process" ];
    _task.currentDirectoryURL = [NSURL fileURLWithPath:workingDirectory isDirectory:YES];
    if (PATH) {
      NSMutableDictionary* environment = [[NSMutableDictionary alloc] initWithDictionary:[[NSProcessInfo processInfo] environment]];
      environment[@"PATH"] = PATH;  // git-lfs runs git itself so use the same PATH as the command line
      _task.environment = environment;
    }
    _task.standardInput = _inPipe;
    _task.standardOutput = _outPipe;
    _task.standardError = [NSFileHandle fileHandleWithNullDevice];  // Not read so must not be a pipe that could fill up
    NSError* error;
    if (![_task launchAndReturnError:&error]) {
      XLOG_ERROR(@"Failed launching git-lfs filter process: %@", error);
      return nil;
    }
    _writeFD = _inPipe.fileHandleForWriting.fileDescriptor;
    _readFD = _outPipe.fileHandleForReading.fileDescriptor;
    fcntl(_writeFD, F_SETNOSIGPIPE, 1);  // Get EPIPE instead of a SIGPIPE if the process exits

    NSArray* lines;
    if (![self _writeTextPacket:@"git-filter-client"] || ![self _writeTextPacket:@"version=2"] || ![self _writeFlushPacket] ||
        !(lines = [self _readTextPacketList]) || ![lines containsObject:@"git-filter-server"] || ![lines containsObject:@"version=2"] ||
        ![self _writeTextPacket:@"capability=clean"] || ![self _writeTextPacket:@"capability=smudge"] || ![self _writeFlushPacket] ||
        !(lines = [self _readTextPacketList]) || ![lines containsObject:@"capability=clean"] || ![lines containsObject:@"capability=smudge"]) {
      XLOG_ERROR(@"Failed handshake with git-lfs filter process");
      [self terminate];
      *handshakeFailed = YES;
      return nil;
    }
  }
  return self;
}

- (void)dealloc {
  [self terminate];
}

// Closing stdin makes the process exit on its own
- (void)terminate {
  if (_inPipe) {
    [_inPipe.fileHandleForWriting closeFile];
    [_outPipe.fileHandleForReading closeFile];
    _inPipe = nil;
    _outPipe = nil;
  }
}

- (BOOL)_writeBytes:(const void*)bytes length:(size_t)length {
  while (length > 0) {
    ssize_t count = write(_writeFD, bytes, length);
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      return NO;
    }
    bytes = (const char*)bytes + count;
    length -= count;
  }
  return YES;
}

- (BOOL)_readBytes:(void*)bytes length:(size_t)length {
  while (length > 0) {
    ssize_t count = read(_readFD, bytes, length);
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      return NO;
    }
    if (count == 0) {  // EOF
      return NO;
    }
    bytes = (char*)bytes + count;
    length -= count;
  }
  return YES;
}

- (BOOL)_writePacket:(const void*)bytes length:(size_t)length {
  XLOG_DEBUG_CHECK((length > 0) && (length <= kPacketMaxDataLength));
  char header[5];
  snprintf(header, sizeof(header), "%04zx", length + 4);
  return [self _writeBytes:header length:4] && [self _writeBytes:bytes length:length];
}

- (BOOL)_writeFlushPacket {
  return [self _writeBytes:"0000" length:4];
}

- (BOOL)_writeTextPacket:(NSString*)text {
  NSData* data = [[text stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
  return [self _writePacket:data.bytes length:data.length];
}

// Returns -1 on error, 0 for a flush packet or the length of the data read into "buffer" which must be at least kPacketMaxDataLength long
- (ssize_t)_readPacket:(char*)buffer {
  char header[5] = {0};
  if (![self _readBytes:header length:4]) {
    return -1;
  }
  char* end;
  unsigned long length = strtoul(header, &end, 16);
  if ((end != header + 4) || ((length > 0) && (length < 4)) || (length > kPacketMaxDataLength + 4)) {
    XLOG_ERROR(@"Invalid packet from git-lfs filter process");
    return -1;
  }
  if (length == 0) {
    return 0;
  }
  length -= 4;
  if (![self _readBytes:buffer length:length]) {
    return -1;
  }
  return length;
}

// Returns nil on error
- (NSArray*)_readTextPacketList {
  NSMutableArray* lines = [[NSMutableArray alloc] init];
  char buffer[kPacketMaxDataLength];
  while (1) {
    ssize_t length = [self _readPacket:buffer];
    if (length < 0) {
      return nil;
    }
    if (length == 0) {
      break;
    }
    if (buffer[length - 1] == '\n') {
      --length;
    }
    NSString* line = [[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding];
    if (line) {
      [lines addObject:line];
    }
  }
  return lines;
}

// Returns the last status in the list or the empty string if there is none
static NSString* _StatusFromTextPacketList(NSArray* lines) {
  NSString* status = @"";
  for (NSString* line in lines) {
    if ([line hasPrefix:@"status="]) {
      status = [line substringFromIndex:7];
    }
  }
  return status;
}

- (GCFilterProcessResult)runCommand:(NSString*)command pathname:(const char*)pathname input:(const git_buf*)input output:(git_buf*)output {
  if (!_inPipe) {
    return kGCFilterProcessResult_Broken;
  }
  NSArray* lines;
  NSString* status;
  char* buffer;
  NSMutableData* data;

  NSMutableData* pathnameData = [[NSMutableData alloc] initWithBytes:"pathname=" length:9];
  [pathnameData appendBytes:pathname length:strlen(pathname)];
  [pathnameData appendBytes:"\n" length:1];
  if (pathnameData.length > kPacketMaxDataLength) {
    return kGCFilterProcessResult_Broken;
  }
  if (![self _writeTextPacket:[@"command=" stringByAppendingString:command]] || ![self _writePacket:pathnameData.bytes length:pathnameData.length] || ![self _writeFlushPacket]) {
    goto broken;
  }
  for (size_t offset = 0; offset < input->size; offset += kPacketMaxDataLength) {
    if (![self _writePacket:(input->ptr + offset) length:MIN(input->size - offset, kPacketMaxDataLength)]) {
      goto broken;
    }
  }
  if (![self _writeFlushPacket]) {
    goto broken;
  }

  lines = [self _readTextPacketList];
  if (!lines) {
    goto broken;
  }
  status = _StatusFromTextPacketList(lines);
  if (![status isEqualToString:@"success"]) {
    XLOG_ERROR(@"git-lfs filter process failed to %@ \"%s\" (%@)", command, pathname, status);
    return [status isEqualToString:@"error"] || [status isEqualToString:@"abort"] ? kGCFilterProcessResult_Error : kGCFilterProcessResult_Broken;
  }

  buffer = (char*)malloc(kPacketMaxDataLength);
  data = [[NSMutableData alloc] init];
  while (1) {
    ssize_t length = [self _readPacket:buffer];
    if (length < 0) {
      free(buffer);
      goto broken;
    }
    if (length == 0) {
      free(buffer);
      break;
    }
    [data appendBytes:buffer length:length];
  }

  lines = [self _readTextPacketList];  // An empty list means the status is unchanged
  if (!lines) {
    goto broken;
  }
  status = _StatusFromTextPacketList(lines);
  if (status.length && ![status isEqualToString:@"success"]) {
    XLOG_ERROR(@"git-lfs filter process failed to %@ \"%s\" (%@)", command, pathname, status);
    return kGCFilterProcessResult_Error;
  }
  if (git_buf_set(output, data.bytes, data.length) < 0) {  // TODO: Avoid copying data
    return kGCFilterProcessResult_Error;
  }
  return kGCFilterProcessResult_Success;

broken:
  XLOG_ERROR(@"Lost communication with git-lfs filter process");
  [self terminate];
  return kGCFilterProcessResult_Broken;
}

@end

static NSMutableDictionary<NSString*, GCLFSFilterProcess*>* _lfsFilterProcesses = nil;  // Idle processes keyed by working directory
static BOOL _lfsFilterProcessUnsupported = NO;  // git-lfs versions before 2.0 don't support "filter-process"

// Takes an idle process out of the cache so concurrent filtering in the same working directory gets its own process
static GCLFSFilterProcess* _CheckOutLFSFilterProcess(NSString* executablePath, NSString* PATH, NSString* workingDirectory) {
  GCLFSFilterProcess* process;
  @synchronized([GCLFSFilterProcess class]) {
    if (_lfsFilterProcessUnsupported) {
      return nil;
    }
    process = _lfsFilterProcesses[workingDirectory];
    [_lfsFilterProcesses removeObjectForKey:workingDirectory];
  }
  if (!process) {
    BOOL handshakeFailed = NO;
    process = [[GCLFSFilterProcess alloc] initWithExecutablePath:executablePath PATH:PATH workingDirectory:workingDirectory handshakeFailed:&handshakeFailed];
    if (handshakeFailed) {
      @synchronized([GCLFSFilterProcess class]) {
        _lfsFilterProcessUnsupported = YES;
      }
    }
  }
  return process;
}

static void _CheckInLFSFilterProcess(GCLFSFilterProcess* process, NSString* workingDirectory) {
  NSUInteger useCount;
  @synchronized([GCLFSFilterProcess class]) {
    useCount = ++process.useCount;
    if (!_lfsFilterProcesses) {
      _lfsFilterProcesses = [[NSMutableDictionary alloc] init];
    }
    if (_lfsFilterProcesses[workingDirectory]) {  // Another thread already checked in a process for this working directory
      [process terminate];
      return;
    }
    _lfsFilterProcesses[workingDirectory] = process;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLFSFilterProcessIdleTimeout * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @synchronized([GCLFSFilterProcess class]) {
      if ((_lfsFilterProcesses[workingDirectory] == process) && (process.useCount == useCount)) {
        [_lfsFilterProcesses removeObjectForKey:workingDirectory];
        [process terminate];
      }
    }
  });
}

// Fallback executing git-lfs for this file only
static int _GitLFSApplyWithTask(NSString* executablePath, NSString* PATH, NSString* workingDirectory, NSString* command, const git_buf* from, git_buf* to, const git_filter_source* src) {
  GCTask* task = [[GCTask alloc] initWithExecutablePath:executablePath];
  task.currentDirectoryPath = workingDirectory;
  if (PATH) {
    task.additionalEnvironment = @{@"PATH" : PATH};  // git-lfs runs git itself so use the same PATH as the command line
  }
  int status;
  NSData* stdinData = [[NSData alloc] initWithBytesNoCopy:from->ptr length:from->size freeWhenDone:NO];
  NSData* stdoutData;
  if (![task runWithArguments:@[ command, @"--", GCFileSystemPathFromGitPath(git_filter_source_path(src)) ] stdin:stdinData stdout:&stdoutData stderr:NULL exitStatus:&status error:NULL]) {
    XLOG_ERROR(@"git-lfs tool failed executing");
    giterr_set_str(GITERR_FILTER, "git-lfs tool failed executing");
    return -1;
  }
  if (status != 0) {
    XLOG_ERROR(@"git-lfs tool exited with non-zero status (%i)", status);
    giterr_set_str(GITERR_FILTER, "git-lfs tool exited with non-zero status");
    return -1;
  }
  if (git_buf_set(to, stdoutData.bytes, stdoutData.length) < 0) {  // TODO: Avoid copying data
    return -1;
  }
  return 0;
}

static int _GitLFSApply(git_filter* self, void** payload, git_buf* to, const git_buf* from, const git_filter_source* src) {
  if (from->size > 0) {
    @autoreleasepool {
      CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
      NSString* command;
      if (git_filter_source_mode(src) == GIT_FILTER_SMUDGE) {  // ODB -> Worktree
        command = @"smudge";
      } else if (git_filter_source_mode(src) == GIT_FILTER_CLEAN) {  // Worktree -> ODB
        command = @"clean";
      } else {
        XLOG_DEBUG_UNREACHABLE();
        return -1;
      }
      NSString* PATH;
      NSString* executablePath = _GitLFSExecutablePath(&PATH);
      if (!executablePath) {
        return GIT_PASSTHROUGH;
      }
      NSString* workingDirectory = _MakeDirectoryPath(git_repository_workdir(git_filter_source_repo(src)));
      if (!workingDirectory) {
        XLOG_DEBUG_UNREACHABLE();
        return -1;
      }

      GCLFSFilterProcess* process = _CheckOutLFSFilterProcess(executablePath, PATH, workingDirectory);
      if (process) {
        GCFilterProcessResult result = [process runCommand:command pathname:git_filter_source_path(src) input:from output:to];
        if (result != kGCFilterProcessResult_Broken) {
          _CheckInLFSFilterProcess(process, workingDirectory);
        }
        if (result == kGCFilterProcessResult_Error) {
          giterr_set_str(GITERR_FILTER, "git-lfs filter process failed");
          return -1;
        }
        if (result == kGCFilterProcessResult_Success) {
          XLOG_VERBOSE(@"Executed git-lfs filter process in %.3f seconds", CFAbsoluteTimeGetCurrent() - time);
          return 0;
        }
      }

      int status = _GitLFSApplyWithTask(executablePath, PATH, workingDirectory, command, from, to, src);
      if (status == 0) {
        XLOG_VERBOSE(@"Executed git-lfs tool in %.3f seconds", CFAbsoluteTimeGetCurrent() - time);
      }
      return status;
    }
  }
  return 0;
}

#endif

@implementation GCRepository {
#if !TARGET_OS_IPHONE
  BOOL _didTrySSHAgent;
  NSMutableArray* _privateKeyList;
  NSUInteger _privateKeyIndex;
#endif

  BOOL _hasFetchProgressDelegate;
  float _lastFetchProgress;
  BOOL _hasPushProgressDelegate;
  float _lastPushProgress;
}

// We can't guarantee XLFacility has been initialized yet as +load method can be called in arbitrary order
+ (void)load {
  assert(pthread_main_np() > 0);

  assert(git_libgit2_features() & GIT_FEATURE_THREADS);
  assert(git_libgit2_features() & GIT_FEATURE_HTTPS);
  assert(git_libgit2_features() & GIT_FEATURE_SSH);
  assert(git_libgit2_init() >= 1);

#if !TARGET_OS_IPHONE
  git_filter* filter = calloc(1, sizeof(git_filter));
  filter->version = GIT_FILTER_VERSION;
  filter->attributes = "filter=lfs";
  filter->check = _GitLFSCheck;
  filter->apply = _GitLFSApply;
  assert(git_filter_register("lfs", filter, -1) == 0);  // Priority must be lower than CRLF and IDENT built-in filters
#endif
}

+ (NSURL *)repositoryURLContainingURL:(NSURL *)url error:(NSError *__autoreleasing *)error {
  NSParameterAssert(url.isFileURL);

  git_buf repoBuffer = {0};

  int result = git_repository_discover(&repoBuffer, GCGitPathFromFileSystemPath(url.path), false, NULL);
  if (result == GIT_OK) {
    NSString* repoPath = [[NSString alloc] initWithBytes:repoBuffer.ptr length:repoBuffer.size encoding:NSUTF8StringEncoding];
    NSURL* repoURL = [NSURL fileURLWithPath:repoPath];
    git_buf_dispose(&repoBuffer);

    // Need to trim the .git from the path, otherwise it works but the document title is .git.

    if ([repoURL.lastPathComponent isEqualToString:@".git"]) {
      return [repoURL URLByDeletingLastPathComponent];
    } else {
      XLOG_WARNING(@"Discovered repository URL not ending in .git: “%@”", repoURL.path);
      return repoURL;
    }
  }

  if (result == GIT_ENOTFOUND) {
    GC_SET_ERROR(kGCErrorCode_NotFound, @"No repository found");
  } else {
    GC_SET_GENERIC_ERROR(@"Error %d", result);
  }
  return nil;
}

- (instancetype)initWithRepository:(git_repository*)repository error:(NSError**)error {
  if ((self = [super init])) {
    _private = repository;
    _repositoryPath = _MakeDirectoryPath(git_repository_path(_private));
    _workingDirectoryPath = _MakeDirectoryPath(git_repository_workdir(_private));
  }
  return self;
}

- (void)dealloc {
  git_repository_free(_private);
}

- (NSString*)description {
  return [NSString stringWithFormat:@"%@ at path \"%@\"", self.class, _repositoryPath];
}

#pragma mark - Initialization

- (instancetype)initWithExistingLocalRepository:(NSString*)path error:(NSError**)error {
  git_repository* repository;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_repository_open, &repository, path.fileSystemRepresentation);
  return [self initWithRepository:repository error:error];
}

- (instancetype)initWithNewLocalRepository:(NSString*)path bare:(BOOL)bare error:(NSError**)error {
  return [self initWithNewLocalRepository:path bare:bare defaultBranchName:nil error:error];
}

- (instancetype)initWithNewLocalRepository:(NSString*)path bare:(BOOL)bare defaultBranchName:(NSString*)defaultBranchName error:(NSError**)error {
  git_repository_init_options options = GIT_REPOSITORY_INIT_OPTIONS_INIT;
  options.flags = GIT_REPOSITORY_INIT_NO_REINIT | GIT_REPOSITORY_INIT_MKPATH;
  if (bare) {
    options.flags |= GIT_REPOSITORY_INIT_BARE;
  }

  if (defaultBranchName) {
    options.initial_head = defaultBranchName.UTF8String;
  }

  git_repository* repository;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_repository_init_ext, &repository, path.fileSystemRepresentation, &options);
  return [self initWithRepository:repository error:error];
}

#pragma mark - Accessors

- (BOOL)isReadOnly {
  return !_IsDirectoryWritable(git_repository_path(_private));
}

- (BOOL)isBare {
  return (git_repository_is_bare(_private) > 0 ? YES : NO);
}

- (BOOL)isShallow {
  return (git_repository_is_shallow(_private) > 0 ? YES : NO);  // TODO: This could actually fail
}

static int _ReferenceForEachCallback(const char* refname, void* payload) {
  return GIT_PASSTHROUGH;
}

// Reimplementation of git_repository_is_empty() that accepts the unborn HEAD to point to any branch
- (BOOL)isEmpty {
  BOOL empty = YES;
  int status = git_reference_foreach_name(_private, _ReferenceForEachCallback, NULL);
  if (status == GIT_PASSTHROUGH) {
    empty = NO;
  } else if (status != GIT_OK) {
    XLOG_DEBUG_UNREACHABLE();
    LOG_LIBGIT2_ERROR(status);
    empty = NO;
  } else {
    status = git_repository_head_unborn(_private);
    if (status == 0) {
      empty = NO;
    } else if (status < 0) {
      XLOG_DEBUG_UNREACHABLE();
      LOG_LIBGIT2_ERROR(status);
      empty = NO;
    }
  }
  return empty;
}

- (GCRepositoryState)state {
  switch (git_repository_state(_private)) {
    case GIT_REPOSITORY_STATE_NONE:
      return kGCRepositoryState_None;
    case GIT_REPOSITORY_STATE_MERGE:
      return kGCRepositoryState_Merge;
    case GIT_REPOSITORY_STATE_REVERT:
      return kGCRepositoryState_Revert;
    case GIT_REPOSITORY_STATE_CHERRYPICK:
      return kGCRepositoryState_CherryPick;
    case GIT_REPOSITORY_STATE_BISECT:
      return kGCRepositoryState_Bisect;
    case GIT_REPOSITORY_STATE_REBASE:
      return kGCRepositoryState_Rebase;
    case GIT_REPOSITORY_STATE_REBASE_INTERACTIVE:
      return kGCRepositoryState_RebaseInteractive;
    case GIT_REPOSITORY_STATE_REBASE_MERGE:
      return kGCRepositoryState_RebaseMerge;
    case GIT_REPOSITORY_STATE_APPLY_MAILBOX:
      return kGCRepositoryState_ApplyMailbox;
    case GIT_REPOSITORY_STATE_APPLY_MAILBOX_OR_REBASE:
      return kGCRepositoryState_ApplyMailboxOrRebase;
  }
  XLOG_DEBUG_UNREACHABLE();
  return 0;
}

#pragma mark - Utilities

- (BOOL)cleanupState:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_repository_state_cleanup, _private);
  return YES;
}

- (BOOL)checkPathNotIgnored:(NSString*)path error:(NSError**)error {
  int ignored;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_ignore_path_is_ignored, &ignored, self.private, GCGitPathFromFileSystemPath(path));
  if (ignored) {
    GC_SET_GENERIC_ERROR(@"Path is ignored");
    return NO;
  }
  return YES;
}

- (NSURL*)absoluteURLForFile:(NSString*)path {
  NSString* absolutePath = [self absolutePathForFile:path];
  return [NSURL fileURLWithPath:absolutePath];
}

- (NSString*)absolutePathForFile:(NSString*)path {
  XLOG_CHECK(_workingDirectoryPath && path.length);
  return [_workingDirectoryPath stringByAppendingPathComponent:path];
}

- (BOOL)safeDeleteFile:(NSString*)path error:(NSError**)error {
#if TARGET_OS_IPHONE
  return [[NSFileManager defaultManager] removeItemAtPath:[self absolutePathForFile:path] error:error];
#else
  return [[NSFileManager defaultManager] moveItemAtPathToTrash:[self absolutePathForFile:path] error:error];
#endif
}

- (NSString*)privateAppDirectoryPath {
  NSString* path = [_repositoryPath stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];

  BOOL isDirectory;
  if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
    if (!isDirectory) {
      XLOG_DEBUG_UNREACHABLE();
      return nil;
    }
  } else {
    NSError* error;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
      XLOG_ERROR(@"Failed creating private app directory at \"%@\"", path);
      return nil;
    }
  }

  if (!_IsDirectoryWritable(path.fileSystemRepresentation)) {
    XLOG_ERROR(@"Private app directory at \"%@\" is not writable", path);
    return nil;
  }
  return path;
}

- (NSString*)privateTemporaryFilePath {
  return [self.privateAppDirectoryPath stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];  // Ignore errors
}

- (BOOL)exportBlobWithSHA1:(NSString*)sha1 toPath:(NSString*)path error:(NSError**)error {
  git_oid oid;
  if (!GCGitOIDFromSHA1(sha1, &oid, error)) {
    return NO;
  }
  return [self exportBlobWithOID:&oid toPath:path error:error];
}

#if !TARGET_OS_IPHONE

- (NSString*)pathForHookWithName:(NSString*)name {
  NSString* hooksPath = [[self readConfigOptionForVariable:@"core.hooksPath" error:NULL] value];
  if (hooksPath.length > 0) {
    hooksPath = hooksPath.stringByExpandingTildeInPath;
    if (!hooksPath.absolutePath) {
      hooksPath = [self.workingDirectoryPath stringByAppendingPathComponent:hooksPath];
    }
  } else {
    // Hooks live in the repository's common directory, which is shared by all
    // linked worktrees. self.repositoryPath is the per-worktree git directory,
    // which for a linked worktree never contains a hooks directory, so looking
    // it up there made hooks silently unavailable in worktrees (issue #1053).
    hooksPath = [_MakeDirectoryPath(git_repository_commondir(_private)) stringByAppendingPathComponent:@"hooks"];
  }
  NSString* path = [hooksPath stringByAppendingPathComponent:name];
  return [[NSFileManager defaultManager] isExecutableFileAtPath:path] ? path : nil;
}

- (NSString*)getPATHUsingShell:(NSString*)shell error:(NSError**)error {
  return _GetPATHUsingShell(shell, error);
}

- (BOOL)runHookWithName:(NSString*)name arguments:(NSArray*)arguments standardInput:(NSString*)standardInput error:(NSError**)error {
  NSString* path = [self pathForHookWithName:name];
  if (path) {
    static NSString* cachedPATH = nil;
    if (cachedPATH == nil) {
      cachedPATH = [self getPATHUsingShell:NSProcessInfo.processInfo.environment[@"SHELL"] error:error] ?: [self getPATHUsingShell:@"/bin/sh" error:error];
      XLOG_DEBUG_CHECK(cachedPATH);
    }

    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    GCTask* task = [[GCTask alloc] initWithExecutablePath:path];
    task.currentDirectoryPath = self.workingDirectoryPath;  // TODO: Is this the right working directory?
    task.additionalEnvironment = @{@"PATH" : cachedPATH};
    task.fallBackToDefaultInterpreter = YES;
    int status;
    NSData* stdoutData;
    NSData* stderrData;
    if (![task runWithArguments:arguments stdin:[standardInput dataUsingEncoding:NSUTF8StringEncoding] stdout:&stdoutData stderr:&stderrData exitStatus:&status error:error]) {
      XLOG_ERROR(@"Failed executing '%@' hook", name);
      return NO;
    }
    XLOG_VERBOSE(@"Executed '%@' hook in %.3f seconds", name, CFAbsoluteTimeGetCurrent() - time);
    if (status != 0) {
      if (error) {
        NSString* string = [[[NSString alloc] initWithData:(stderrData.length ? stderrData : stdoutData) encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        XLOG_DEBUG_CHECK(string);
        NSDictionary* info = @{
          NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Hook '%@' exited with non-zero status (%i)", name, status],
          NSLocalizedRecoverySuggestionErrorKey : (string ? string : @"")
        };
        *error = [NSError errorWithDomain:GCErrorDomain code:status userInfo:info];
      }
      return NO;
    }
  }
  return YES;
}

#endif

#if DEBUG

- (GCDiff*)checkUnifiedStatus:(NSError**)error {
  return [self diffWorkingDirectoryWithHEAD:nil options:(kGCDiffOption_IncludeUntracked | kGCDiffOption_FindRenames) maxInterHunkLines:0 maxContextLines:0 error:error];
}

- (GCDiff*)checkIndexStatus:(NSError**)error {
  return [self diffRepositoryIndexWithHEAD:nil options:kGCDiffOption_FindRenames maxInterHunkLines:0 maxContextLines:0 error:error];
}

- (GCDiff*)checkWorkingDirectoryStatus:(NSError**)error {
  return [self diffWorkingDirectoryWithRepositoryIndex:nil options:kGCDiffOption_IncludeUntracked maxInterHunkLines:0 maxContextLines:0 error:error];
}

- (BOOL)checkRepositoryDirty:(BOOL)includeUntracked {
  git_status_options options = GIT_STATUS_OPTIONS_INIT;
  options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
  options.flags = includeUntracked ? GIT_STATUS_OPT_INCLUDE_UNTRACKED : 0;
  git_status_list* list;
  int status = git_status_list_new(&list, self.private, &options);
  if (status != GIT_OK) {
    LOG_LIBGIT2_ERROR(status);
    XLOG_DEBUG_UNREACHABLE();
    return NO;
  }
  BOOL dirty = git_status_list_entrycount(list) > 0;
  git_status_list_free(list);
  return dirty;
}

- (instancetype)initWithClonedRepositoryFromURL:(NSURL*)url toPath:(NSString*)path usingDelegate:(id<GCRepositoryDelegate>)delegate recursive:(BOOL)recursive error:(NSError**)error {
  if ((self = [self initWithNewLocalRepository:path bare:NO error:error])) {
    _delegate = delegate;
    GCRemote* remote = [self addRemoteWithName:@"origin" url:url error:error];
    if (!remote || ![self cloneUsingRemote:remote recursive:recursive error:error]) {
      return nil;
    }
  }
  return self;
}

#endif

#pragma mark Remote Callbacks

- (void)willStartRemoteTransferWithURL:(NSURL*)url {
  if ([_delegate respondsToSelector:@selector(repository:willStartTransferWithURL:)]) {
    if ([NSThread isMainThread]) {
      [_delegate repository:self willStartTransferWithURL:url];
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate repository:self willStartTransferWithURL:url];
      });
    }
  }
}

- (void)didFinishRemoteTransferWithURL:(NSURL*)url success:(BOOL)success {
  if ([_delegate respondsToSelector:@selector(repository:didFinishTransferWithURL:success:)]) {
    if ([NSThread isMainThread]) {
      [_delegate repository:self didFinishTransferWithURL:url success:success];
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate repository:self didFinishTransferWithURL:url success:success];
      });
    }
  }
}

static int _CredentialsCallback(git_cred** cred, const char* url, const char* user, unsigned int allowed_types, void* payload) {
  GCRepository* repository = (__bridge GCRepository*)payload;
  if (allowed_types & GIT_CREDTYPE_SSH_KEY) {
#if !TARGET_OS_IPHONE
    if (!repository->_didTrySSHAgent) {
      repository->_didTrySSHAgent = YES;
      return git_cred_ssh_key_from_agent(cred, user);
    }
#endif

#if !TARGET_OS_IPHONE
    if (repository->_privateKeyList == nil) {
      XLOG_WARNING(@"SSH Agent did not find any key for \"%s\"", url);
      NSMutableArray* array = [[NSMutableArray alloc] init];
      NSString* basePath = [NSHomeDirectory() stringByAppendingPathComponent:@".ssh"];
      for (NSString* file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:basePath error:NULL]) {
        if ([file hasPrefix:@"."]) {
          continue;
        }
        if ([file hasSuffix:@".pub"]) {
          continue;
        }
        if ([file isEqualToString:@"authorized_keys"] || [file isEqualToString:@"config"] || [file isEqualToString:@"known_hosts"]) {
          continue;
        }
        NSString* path = [basePath stringByAppendingPathComponent:file];
        if ([[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileType] isEqualToString:NSFileTypeRegular]) {
          [array addObject:path];
        }
      }
      repository->_privateKeyList = array;
    }
    if (repository->_privateKeyIndex < [repository->_privateKeyList count]) {
      const char* path = [[repository->_privateKeyList objectAtIndex:repository->_privateKeyIndex++] fileSystemRepresentation];
      XLOG_VERBOSE(@"Trying SSH key \"%s\" for \"%s\"", path, url);
      return git_cred_ssh_key_new(cred, user, NULL, path, NULL);  // TODO: Handle passphrases
    }
#endif

    __block NSString* username = nil;
    __block NSString* publicPath = nil;
    __block NSString* privatePath = nil;
    __block NSString* passphrase = nil;
    __block BOOL success;
    if ([repository.delegate respondsToSelector:@selector(repository:requiresSSHAuthenticationForURL:user:username:publicKeyPath:privateKeyPath:passphrase:)]) {  // Must use sync dispatch
      if ([NSThread isMainThread]) {
        success = [repository.delegate repository:repository
                  requiresSSHAuthenticationForURL:GCURLFromGitURL([NSString stringWithUTF8String:url])
                                             user:[NSString stringWithUTF8String:user]
                                         username:&username
                                    publicKeyPath:&publicPath
                                   privateKeyPath:&privatePath
                                       passphrase:&passphrase];
      } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
          success = [repository.delegate repository:repository
                    requiresSSHAuthenticationForURL:GCURLFromGitURL([NSString stringWithUTF8String:url])
                                               user:[NSString stringWithUTF8String:user]
                                           username:&username
                                      publicKeyPath:&publicPath
                                     privateKeyPath:&privatePath
                                         passphrase:&passphrase];
        });
      }
      if (success) {
        return git_cred_ssh_key_new(cred, username.UTF8String, publicPath.fileSystemRepresentation, privatePath.fileSystemRepresentation, passphrase.UTF8String);
      }
      return GIT_EUSER;
    }
  }
  if (allowed_types & GIT_CREDTYPE_USERPASS_PLAINTEXT) {
    if ([repository.delegate respondsToSelector:@selector(repository:requiresPlainTextAuthenticationForURL:user:username:password:)]) {  // Must use sync dispatch
      __block NSString* username = nil;
      __block NSString* password = nil;
      __block BOOL success;
      if ([NSThread isMainThread]) {
        success = [repository.delegate repository:repository
            requiresPlainTextAuthenticationForURL:GCURLFromGitURL([NSString stringWithUTF8String:url])
                                             user:(user ? [NSString stringWithUTF8String:user] : nil)
                                             username:&username
                                         password:&password];
      } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
          success = [repository.delegate repository:repository
              requiresPlainTextAuthenticationForURL:GCURLFromGitURL([NSString stringWithUTF8String:url])
                                               user:(user ? [NSString stringWithUTF8String:user] : nil)
                                               username:&username
                                           password:&password];
        });
      }
      if (success) {
        return git_cred_userpass_plaintext_new(cred, username.UTF8String, password.UTF8String);
      }
      return GIT_EUSER;
    }
  }
  return GIT_PASSTHROUGH;
}

// Called when fetching only
static int _TransportMessageCallback(const char* str, int len, void* payload) {
  XLOG_VERBOSE(@"Remote transport message: %@", [[[NSString alloc] initWithBytes:str length:len encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
  return GIT_OK;
}

// Called when fetching only
static int _FetchTransferProgressCallback(const git_transfer_progress* stats, void* payload) {
  XLOG_DEBUG(@"Remote fetched %u / %u objects (%zu bytes)", stats->received_objects, stats->total_objects, stats->received_bytes);
  GCRepository* repository = (__bridge GCRepository*)payload;
  if (repository->_hasFetchProgressDelegate) {
    float progress = roundf(100.0 * (float)(stats->received_objects + stats->indexed_objects) / (float)(2 * stats->total_objects));
    if (progress > repository->_lastFetchProgress) {
      if ([NSThread isMainThread]) {
        [repository.delegate repository:repository updateTransferProgress:(progress / 100.0) transferredBytes:stats->received_bytes];
      } else {
        dispatch_async(dispatch_get_main_queue(), ^{
          [repository.delegate repository:repository updateTransferProgress:(progress / 100.0) transferredBytes:stats->received_bytes];
        });
      }
      repository->_lastFetchProgress = progress;
    }
  }
  return GIT_OK;
}

// Called when fetching or pushing
static int _UpdateTipsCallback(const char* refname, const git_oid* a, const git_oid* b, void* data) {
  char bufferA[8];
  char bufferB[8];
  XLOG_VERBOSE(@"Remote updated \"%s\" from %s to %s", refname, git_oid_tostr(bufferA, sizeof(bufferA), a), git_oid_tostr(bufferB, sizeof(bufferB), b));
  GCRepository* repository = (__bridge GCRepository*)data;
  repository->_lastUpdatedTips += 1;
  return GIT_OK;
}

// Called when pushing only
static int _PackbuilderProgressCallback(int stage, unsigned int current, unsigned int total, void* payload) {
  XLOG_DEBUG(@"Remote packed %u / %u objects", current, total);
  return GIT_OK;
}

// Called when pushing only
static int _PushTransferProgressCallback(unsigned int current, unsigned int total, size_t bytes, void* payload) {
  XLOG_DEBUG(@"Pushed %u / %u objects (%zu bytes)", current, total, bytes);
  GCRepository* repository = (__bridge GCRepository*)payload;
  if (repository->_hasPushProgressDelegate) {
    float progress = roundf(100.0 * (float)current / (float)total);
    if (progress > repository->_lastPushProgress) {
      if ([NSThread isMainThread]) {
        [repository.delegate repository:repository updateTransferProgress:(progress / 100.0) transferredBytes:bytes];
      } else {
        dispatch_async(dispatch_get_main_queue(), ^{
          [repository.delegate repository:repository updateTransferProgress:(progress / 100.0) transferredBytes:bytes];
        });
      }
      repository->_lastPushProgress = progress;
    }
  }
  return GIT_OK;
}

// Called when pushing only
static int _PushUpdateReferenceCallback(const char* refspec, const char* message, void* data) {
  if (message) {
    XLOG_ERROR(@"Failed updating remote reference '%s': %s", refspec, message);
    giterr_set_str(GITERR_NET, [[NSString stringWithFormat:@"remote reference '%s' failed to update: %s", refspec, message] UTF8String]);
    return GIT_ERROR;
  }
  return GIT_OK;
}

// Called when pushing only
static int _PushNegotiationCallback(git_remote* remote, const git_push_update** updates, size_t len, void* payload) {
#if !TARGET_OS_IPHONE
  GCRepository* repository = (__bridge GCRepository*)payload;
  if ([repository pathForHookWithName:@"pre-push"]) {
    NSMutableString* string = [[NSMutableString alloc] init];  // Format is "<local ref> SP <local sha1> SP <remote ref> SP <remote sha1> LF"
    for (size_t i = 0; i < len; ++i) {
      const git_push_update* update = updates[i];
      if (update->src_refname[0]) {
        XLOG_DEBUG_CHECK(update->dst_refname[0] && !git_oid_iszero(&update->dst));
        if (git_oid_iszero(&update->src)) {  // Adding ref: "'src_refname' 0 'dst_refname' OID" -> "refs/heads/master 67890 refs/heads/foreign 0"
          [string appendFormat:@"%s %s ", update->src_refname, git_oid_tostr_s(&update->dst)];
          [string appendFormat:@"%s %s\n", update->dst_refname, git_oid_tostr_s(&update->src)];
        } else {  // Updating ref: "'src_refname' OID 'dst_refname' OID" -> "refs/heads/master 67890 refs/heads/foreign 12345"
          [string appendFormat:@"%s %s ", update->src_refname, git_oid_tostr_s(&update->dst)];
          [string appendFormat:@"%s %s\n", update->dst_refname, git_oid_tostr_s(&update->src)];
        }
      } else {  // Deleting ref: "'' OID 'dst_refname' 0" -> "(delete) 0 refs/heads/foreign 12345"
        XLOG_DEBUG_CHECK(!git_oid_iszero(&update->src) && update->dst_refname[0] && git_oid_iszero(&update->dst));
        [string appendFormat:@"(delete) %s ", git_oid_tostr_s(&update->dst)];
        [string appendFormat:@"%s %s\n", update->dst_refname, git_oid_tostr_s(&update->src)];
      }
    }

    NSError* error;
    const char* remoteURL = git_remote_url(remote);
    if (![repository runHookWithName:@"pre-push"
                           arguments:@[ [NSString stringWithUTF8String:git_remote_name(remote)], remoteURL ? [NSString stringWithUTF8String:remoteURL] : @"" ]
                       standardInput:string
                               error:&error]) {
      const char* message = error.localizedRecoverySuggestion.UTF8String;
      if (message == NULL) {
        message = "pre-push hook exited with non-zero status";
      }
      giterr_set_str(GITERR_NET, message);
      return GIT_ERROR;
    }
  }
#endif
  return GIT_OK;
}

- (void)setRemoteCallbacks:(git_remote_callbacks*)callbacks {
  callbacks->sideband_progress = _TransportMessageCallback;
  // callbacks->completion =
  callbacks->credentials = _CredentialsCallback;
  // callbacks->certificate_check =
  callbacks->transfer_progress = _FetchTransferProgressCallback;
  callbacks->update_tips = _UpdateTipsCallback;
  callbacks->pack_progress = _PackbuilderProgressCallback;
  callbacks->push_transfer_progress = _PushTransferProgressCallback;
  callbacks->push_update_reference = _PushUpdateReferenceCallback;
  callbacks->push_negotiation = _PushNegotiationCallback;
  callbacks->payload = (__bridge void*)self;

#if !TARGET_OS_IPHONE
  _didTrySSHAgent = NO;
  _privateKeyList = nil;
  _privateKeyIndex = 0;
#endif

  _hasFetchProgressDelegate = [_delegate respondsToSelector:@selector(repository:updateTransferProgress:transferredBytes:)];
  _lastFetchProgress = -1.0;
  _hasPushProgressDelegate = [_delegate respondsToSelector:@selector(repository:updateTransferProgress:transferredBytes:)];
  _lastPushProgress = -1.0;

  _lastUpdatedTips = 0;
}

- (NSData*)exportBlobWithOID:(const git_oid*)oid error:(NSError**)error {
  git_blob* blob;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_blob_lookup, &blob, self.private, oid);
  NSData* data = [[NSData alloc] initWithBytes:git_blob_rawcontent(blob) length:(NSUInteger)git_blob_rawsize(blob)];
  git_blob_free(blob);
  return data;
}

- (BOOL)exportBlobWithOID:(const git_oid*)oid toPath:(NSString*)path error:(NSError**)error {
  BOOL success = NO;
  git_blob* blob = NULL;
  int fd = -1;

  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_blob_lookup, &blob, self.private, oid);
  fd = open(path.fileSystemRepresentation, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR);
  CHECK_POSIX_FUNCTION_CALL(goto cleanup, fd, >= 0);
  if (write(fd, git_blob_rawcontent(blob), (size_t)git_blob_rawsize(blob)) == git_blob_rawsize(blob)) {
    success = YES;
  } else {
    GC_SET_GENERIC_ERROR(@"%s", strerror(errno));
    XLOG_DEBUG_UNREACHABLE();
  }

cleanup:
  if (fd >= 0) {
    close(fd);
  }
  git_blob_free(blob);
  return success;
}

@end
