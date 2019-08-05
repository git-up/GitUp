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

#import <Foundation/Foundation.h>
#import <libgen.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#import <git2.h>
#pragma clang diagnostic pop

#import "ToolProtocol.h"

#define kCommunicationTimeOut 3.0

static char* _help = "\
Usage: %s [command]\n\
\n\
Commands:\n\
\n\
" kToolCommand_Help "\n\
  Show this help.\n\
\n\
" kToolCommand_Open " (default)\n\
  Open the current Git repository in GitUp.\n\
\n\
" kToolCommand_Map "\n\
  Open the current Git repository in GitUp in Map view.\n\
\n\
" kToolCommand_Commit "\n\
  Open the current Git repository in GitUp in Commit view.\n\
\n\
" kToolCommand_Stash "\n\
  Open the current Git repository in GitUp in Stashes view.\n\
\n\
";

// We don't care about free'ing resources since the tool is one-shot
int main(int argc, const char* argv[]) {
  BOOL success = NO;
  @autoreleasepool {
    const char* command = argc >= 2 ? argv[1] : "open";

    if (!strcmp(command, kToolCommand_Help)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
      fprintf(stdout, _help, basename((char*)argv[0]));
#pragma clang diagnostic pop
      success = YES;
    }

    else {
      assert(git_libgit2_init() >= 1);

      // Find and open repo
      char wdBuffer[MAXPATHLEN];
      git_buf repoBuffer = {0};
      int result = git_repository_discover(&repoBuffer, getwd(wdBuffer), false, NULL);
      if (result == GIT_OK) {
        git_repository* repository;
        result = git_repository_open(&repository, repoBuffer.ptr);
        if (result == GIT_OK) {
          if (!git_repository_is_bare(repository)) {
            const char* path = git_repository_workdir(repository);
            NSString* repositoryPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:strlen(path)];

            // Launch app and / or bring it to front
            NSString* executablePath = [[[NSBundle mainBundle] executablePath] stringByResolvingSymlinksInPath];  // -executablePath is returning the symlink instead of the actual executable
            NSString* appPath = [[[executablePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];  // Remove "Contents/SharedSupport/{executable}"
            LSLaunchURLSpec spec = {0};
            spec.appURL = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath isDirectory:YES];
            spec.launchFlags = kLSLaunchNoParams | kLSLaunchAndDisplayErrors;
            OSStatus status = LSOpenFromURLSpec(&spec, NULL);
            if (status == noErr) {
              CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
              while (1) {
                CFMessagePortRef messagePort = CFMessagePortCreateRemote(kCFAllocatorDefault, CFSTR(kToolPortName));
                if (messagePort) {
                  // Send message
                  NSMutableDictionary* message = [[NSMutableDictionary alloc] init];
                  [message setObject:[NSString stringWithUTF8String:command] forKey:kToolDictionaryKey_Command];
                  [message setObject:repositoryPath forKey:kToolDictionaryKey_Repository];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
                  // The deprecation for this method in the macOS 10.14 SDK
                  // marks the incorrect version for its introduction. However,
                  // it is useful to keep availability guards on in general.
                  // FB6233110
                  NSData* sendData = [NSKeyedArchiver archivedDataWithRootObject:message];
#pragma clang diagnostic pop
                  CFDataRef returnData = NULL;
                  status = CFMessagePortSendRequest(messagePort, 0, (CFDataRef)sendData, kCommunicationTimeOut, kCommunicationTimeOut, kCFRunLoopDefaultMode, &returnData);
                  if (status == kCFMessagePortSuccess) {
                    NSDictionary* response = [NSKeyedUnarchiver unarchiveObjectWithData:(__bridge NSData*)returnData];
                    NSString* error = [response objectForKey:kToolDictionaryKey_Error];
                    if (error) {
                      fprintf(stderr, "%s\n", error.UTF8String);
                    } else {
                      success = YES;
                    }
                  } else {
                    fprintf(stderr, "Failed communicating with GitUp application (%i)\n", status);
                  }
                  CFMessagePortInvalidate(messagePort);
                  CFRelease(messagePort);
                  break;

                } else {
                  if (CFAbsoluteTimeGetCurrent() >= startTime + kCommunicationTimeOut) {
                    fprintf(stderr, "Failed connecting to GitUp application\n");
                    break;
                  }
                  usleep(100 * 1000);  // Sleep 100ms and try connecting again
                }
              }
            } else {
              fprintf(stderr, "Failed launching GitUp application (%i)\n", status);
            }

          } else {
            fprintf(stderr, "Bare repositories are not supported at this time\n");
          }
        } else {
          const git_error* error = giterr_last();
          fprintf(stderr, "Failed opening repository at current path (%s)\n", error ? error->message : NULL);
        }
      } else {
        fprintf(stderr, "No repository found at current path\n");
      }
    }
  }
  return success ? 0 : 1;
}
