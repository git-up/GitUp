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

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, GCRepositoryState) {
  kGCRepositoryState_None = 0,
  kGCRepositoryState_Merge,
  kGCRepositoryState_Revert,
  kGCRepositoryState_CherryPick,
  kGCRepositoryState_Bisect,
  kGCRepositoryState_Rebase,
  kGCRepositoryState_RebaseInteractive,
  kGCRepositoryState_RebaseMerge,
  kGCRepositoryState_ApplyMailbox,
  kGCRepositoryState_ApplyMailboxOrRebase
};

typedef NS_ENUM(NSUInteger, GCFileMode) {
  kGCFileMode_Unreadable = 0,
  kGCFileMode_Tree,
  kGCFileMode_Blob,
  kGCFileMode_BlobExecutable,
  kGCFileMode_Link,
  kGCFileMode_Commit
};

#define GC_FILE_MODE_IS_FILE(m) (((m) == kGCFileMode_Blob) || ((m) == kGCFileMode_BlobExecutable) || ((m) == kGCFileMode_Link))
#define GC_FILE_MODE_IS_SUBMODULE(m) (((m) == kGCFileMode_Tree) || ((m) == kGCFileMode_Commit))

@class GCRepository;

@protocol GCRepositoryDelegate <NSObject>
@optional
- (void)repository:(GCRepository*)repository willStartTransferWithURL:(NSURL*)url;
- (BOOL)repository:(GCRepository*)repository requiresPlainTextAuthenticationForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password;
- (BOOL)repository:(GCRepository*)repository requiresSSHAuthenticationForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username publicKeyPath:(NSString**)publicPath privateKeyPath:(NSString**)privatePath passphrase:(NSString**)passphrase;
- (void)repository:(GCRepository*)repository updateTransferProgress:(float)progress transferredBytes:(NSUInteger)bytes;  // Progress is in [0,1] range
- (void)repository:(GCRepository*)repository didFinishTransferWithURL:(NSURL*)url success:(BOOL)success;
@end

@interface GCRepository : NSObject
@property(nonatomic, assign) id<GCRepositoryDelegate> delegate;
@property(nonatomic, readonly) NSString* repositoryPath;
@property(nonatomic, readonly) NSString* workingDirectoryPath;  // nil for a bare repository
@property(nonatomic, readonly, getter=isReadOnly) BOOL readOnly;
@property(nonatomic, readonly, getter=isBare) BOOL bare;
@property(nonatomic, readonly, getter=isShallow) BOOL shallow;
@property(nonatomic, readonly, getter=isEmpty) BOOL empty;  // Repository has no references and HEAD is unborn
@property(nonatomic, readonly) GCRepositoryState state;  // Do NOT use on a bare repository
- (instancetype)initWithExistingLocalRepository:(NSString*)path error:(NSError**)error;
- (instancetype)initWithNewLocalRepository:(NSString*)path bare:(BOOL)bare error:(NSError**)error;  // git init {path}

- (BOOL)cleanupState:(NSError**)error;  // Do NOT use on a bare repository

- (BOOL)checkPathNotIgnored:(NSString*)path error:(NSError**)error;

- (NSString*)absolutePathForFile:(NSString*)path;

- (BOOL)safeDeleteFile:(NSString*)path error:(NSError**)error;  // Moves file to Trash (OS X only)

- (NSString*)privateAppDirectoryPath;  // May return nil e.g. if repository is read-only

- (BOOL)exportBlobWithSHA1:(NSString*)sha1 toPath:(NSString*)path error:(NSError**)error;

#if !TARGET_OS_IPHONE
- (NSString*)pathForHookWithName:(NSString*)name;  // Returns nil if hook doesn't exist
- (BOOL)runHookWithName:(NSString*)name arguments:(NSArray*)arguments standardInput:(NSString*)standardInput error:(NSError**)error;  // Silently ignores non-existing hooks
#endif
@end
