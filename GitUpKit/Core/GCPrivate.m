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

#import "GCPrivate.h"

#if !TARGET_OS_IPHONE

@implementation GCTask {
  NSFileHandle* _outFileHandle;
  NSMutableData* _outData;
  NSFileHandle* _errorFileHandle;
  NSMutableData* _errorData;
}

- (instancetype)initWithExecutablePath:(NSString*)path {
  if ((self = [super init])) {
    _executablePath = [path copy];
  }
  return self;
}

- (void)_timer:(NSTimer*)timer {
  [(NSTask*)timer.userInfo terminate];
  [(NSTask*)timer.userInfo interrupt];
}

- (void)_fileHandleDataAvailable:(NSNotification*)notification {
  @autoreleasepool {
    NSFileHandle* fileHandle = notification.object;
    NSData* data = fileHandle.availableData;
    
    if (fileHandle == _outFileHandle) {
      if (data.length) {
        [_outData appendData:data];
      } else {
        _outFileHandle = nil;
      }
    } else if (fileHandle == _errorFileHandle) {
      if (data.length) {
        [_errorData appendData:data];
      } else {
        _errorFileHandle = nil;
      }
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }
    
    if (data.length) {
      [fileHandle waitForDataInBackgroundAndNotify];
    }
  }
}

- (BOOL)runWithArguments:(NSArray*)arguments stdin:(NSData*)stdin stdout:(NSData**)stdout stderr:(NSData**)stderr exitStatus:(int*)exitStatus error:(NSError**)error {
  BOOL success = NO;
  NSPipe* inPipe = nil;
  NSPipe* outPipe = nil;
  NSPipe* errorPipe = nil;
  NSTimer* timer = nil;
  
  NSTask* task = [[NSTask alloc] init];
  task.launchPath = _executablePath;
  NSMutableDictionary* environment = [[NSMutableDictionary alloc] initWithDictionary:[[NSProcessInfo processInfo] environment]];
  [environment addEntriesFromDictionary:_additionalEnvironment];
  task.environment = environment;
  task.currentDirectoryPath = _currentDirectoryPath ? _currentDirectoryPath : [[NSFileManager defaultManager] currentDirectoryPath];
  task.arguments = arguments ? arguments : @[];
  
  if (stdin) {
    inPipe = [[NSPipe alloc] init];
    XLOG_DEBUG_CHECK(inPipe);
    task.standardInput = inPipe;
  }
  if (stdout) {
    outPipe = [[NSPipe alloc] init];
    XLOG_DEBUG_CHECK(outPipe);
    task.standardOutput = outPipe;
  }
  if (stderr) {
    errorPipe = [[NSPipe alloc] init];
    XLOG_DEBUG_CHECK(errorPipe);
    task.standardError = errorPipe;
  }
  
  @try {
    [task launch];
  }
  @catch (NSException* exception) {
    GC_SET_GENERIC_ERROR(@"%@", exception.reason);
    goto cleanup;
  }
  
  if (inPipe) {
    NSFileHandle* fileHandle = inPipe.fileHandleForWriting;
    @try {
      [fileHandle writeData:stdin];
      [fileHandle closeFile];
    }
    @catch (NSException* exception) {
      [task terminate];
      [task interrupt];
      GC_SET_GENERIC_ERROR(@"%@", exception.reason);
      goto cleanup;
    }
  }
  
  if (_executionTimeOut > 0.0) {
    timer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:_executionTimeOut] interval:0.0 target:self selector:@selector(_timer:) userInfo:task repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
  }
  if (outPipe) {
    _outFileHandle = outPipe.fileHandleForReading;
    _outData = [NSMutableData data];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileHandleDataAvailable:) name:NSFileHandleDataAvailableNotification object:_outFileHandle];
    [_outFileHandle waitForDataInBackgroundAndNotify];
    *stdout = _outData;
  }
  if (errorPipe) {
    _errorFileHandle = errorPipe.fileHandleForReading;
    _errorData = [NSMutableData data];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileHandleDataAvailable:) name:NSFileHandleDataAvailableNotification object:_errorFileHandle];
    [_errorFileHandle waitForDataInBackgroundAndNotify];
    *stderr = _errorData;
  }
  [task waitUntilExit];
  while (_outFileHandle || _errorFileHandle) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, true);
  }
  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleDataAvailableNotification object:nil];
  [timer invalidate];
  if (exitStatus) {
    *exitStatus = task.terminationStatus;
  } else if (task.terminationStatus) {
    GC_SET_GENERIC_ERROR(@"Non-zero exit status (%i)", task.terminationStatus);
    goto cleanup;
  }
  success = YES;
  
cleanup:
  if (inPipe) {
    [inPipe.fileHandleForReading closeFile];
    [inPipe.fileHandleForWriting closeFile];
  }
  if (outPipe) {
    [outPipe.fileHandleForReading closeFile];
    [outPipe.fileHandleForWriting closeFile];
  }
  if (errorPipe) {
    [errorPipe.fileHandleForReading closeFile];
    [errorPipe.fileHandleForWriting closeFile];
  }
  _outData = nil;
  _errorData = nil;
  return success;
}

@end

#endif
