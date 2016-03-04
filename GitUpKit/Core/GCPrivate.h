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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wpadded"
#import <git2.h>
#import <git2/transaction.h>
#import <git2/sys/commit.h>
#import <git2/sys/odb_backend.h>
#import <git2/sys/openssl.h>
#import <git2/sys/refdb_backend.h>
#import <git2/sys/refs.h>
#import <git2/sys/repository.h>
#pragma clang diagnostic pop

#import "GCCore.h"

#import "XLFacilityMacros.h"

#define kRefsNamespace "refs/"
#define kTagsNamespace "refs/tags/"
#define kHeadsNamespace "refs/heads/"
#define kRemotesNamespace "refs/remotes/"

#define kHEADReferenceFullName "HEAD"
#define kStashReferenceFullName "refs/stash"

static inline NSString* GetLastGitErrorMessage() {
  const git_error* __git_error = giterr_last();
  return __git_error && __git_error->message ? [NSString stringWithUTF8String:__git_error->message] : @"<Unknown error>";
}

#define LOG_LIBGIT2_ERROR(__CODE__) \
  do { \
    XLOG_DEBUG_CHECK(__CODE__ != GIT_OK); \
    XLOG_ERROR(@"libgit2 error (%i): %@", __CODE__, GetLastGitErrorMessage()); \
  } \
  while (0)

#ifdef __clang_analyzer__

#define CHECK_LIBGIT2_FUNCTION_CALL(__FAIL_ACTION__, __STATUS__, __COMPARISON__) do { if (__STATUS__) NSLog(@"OK"); } while(0)

#else

#define CHECK_LIBGIT2_FUNCTION_CALL(__FAIL_ACTION__, __STATUS__, __COMPARISON__) \
  do { \
    if (!(__STATUS__ __COMPARISON__)) { \
      LOG_LIBGIT2_ERROR(__STATUS__); \
      if (error) { \
        *error = GCNewError(__STATUS__, GetLastGitErrorMessage()); \
      } \
      __FAIL_ACTION__; \
    } \
  } while(0)

#endif

#define CALL_LIBGIT2_FUNCTION_RETURN(__RETURN_VALUE_ON_ERROR__, __FUNCTION__, ...) \
  do { \
    int __callError = __FUNCTION__(__VA_ARGS__); \
    CHECK_LIBGIT2_FUNCTION_CALL(return __RETURN_VALUE_ON_ERROR__, __callError, == GIT_OK); \
  } while(0)

#define CALL_LIBGIT2_FUNCTION_GOTO(__GOTO_LABEL__, __FUNCTION__, ...) \
  do { \
    int __callError = __FUNCTION__(__VA_ARGS__); \
    CHECK_LIBGIT2_FUNCTION_CALL(goto __GOTO_LABEL__, __callError, == GIT_OK); \
  } while(0)

#define CHECK_POSIX_FUNCTION_CALL(__FAIL_ACTION__, __STATUS__, __COMPARISON__) \
  do { \
    if (!(__STATUS__ __COMPARISON__)) { \
      if (error) { \
        *error = GCNewPosixError(__STATUS__, [NSString stringWithUTF8String:strerror(errno)]); \
      } \
      __FAIL_ACTION__; \
    } \
  } while(0)

#define CALL_POSIX_FUNCTION_RETURN(__RETURN_VALUE_ON_ERROR__, __FUNCTION__, ...) \
  do { \
    int __callError = __FUNCTION__(__VA_ARGS__); \
    CHECK_POSIX_FUNCTION_CALL(return __RETURN_VALUE_ON_ERROR__, __callError, == 0); \
  } while(0)

#define CALL_POSIX_FUNCTION_GOTO(__GOTO_LABEL__, __FUNCTION__, ...) \
  do { \
    int __callError = __FUNCTION__(__VA_ARGS__); \
    CHECK_POSIX_FUNCTION_CALL(goto __GOTO_LABEL__, __callError, == 0); \
  } while(0)

typedef NS_OPTIONS(NSUInteger, GCReferenceEnumerationOptions) {
  kGCReferenceEnumerationOption_IncludeHEAD = (1 << 0),
  kGCReferenceEnumerationOption_RetainReferences = (1 << 1)
};

extern NSError* GCNewPosixError(int code, NSString* message);
extern NSString* GCGitOIDToSHA1(const git_oid* oid);
extern BOOL GCGitOIDFromSHA1(NSString* sha1, git_oid* oid, NSError** error);
extern BOOL GCGitOIDFromSHA1Prefix(NSString* prefix, git_oid* oid, NSError** error);
extern NSData* GCCleanedUpCommitMessage(NSString* message);
extern NSString* GCUserFromSignature(const git_signature* signature);
extern const void* GCOIDCopyCallBack(CFAllocatorRef allocator, const void* value);
extern Boolean GCOIDEqualCallBack(const void* value1, const void* value2);
extern CFHashCode GCOIDHashCallBack(const void* value);
extern Boolean GCCStringEqualCallBack(const void* value1, const void* value2);
extern CFHashCode GCCStringHashCallBack(const void* value);
extern const void* GCCStringCopyCallBack(CFAllocatorRef allocator, const void* value);
extern void GCFreeReleaseCallBack(CFAllocatorRef allocator, const void* value);
extern GCFileMode GCFileModeFromMode(git_filemode_t mode);

extern int git_revwalk_add_hide_block(git_revwalk* walk, int (^block)(const git_oid* commit_id));
extern int git_stash_foreach_block(git_repository* repo, int (^block)(size_t index, const char* message, const git_oid* stash_id));
extern int git_submodule_foreach_block(git_repository* repo, int (^block)(git_submodule* submodule, const char* name));

#if !TARGET_OS_IPHONE

@interface GCTask : NSObject
@property(nonatomic, readonly) NSString* executablePath;
@property(nonatomic) NSTimeInterval executionTimeOut;  // Default is 0.0 i.e. no timeout
@property(nonatomic, copy) NSDictionary* additionalEnvironment;
@property(nonatomic, copy) NSString* currentDirectoryPath;
- (instancetype)initWithExecutablePath:(NSString*)path;
- (BOOL)runWithArguments:(NSArray*)arguments stdin:(NSData*)stdin stdout:(NSData**)stdout stderr:(NSData**)stderr exitStatus:(int*)exitStatus error:(NSError**)error;  // Returns NO if "exitStatus" is NULL and executable exits with a non-zero status
@end

#endif

@interface GCObject () {
@public
  git_object* _private;
}
@property(nonatomic, readonly) git_object* private NS_RETURNS_INNER_POINTER;
- (instancetype)initWithRepository:(GCRepository*)repository object:(git_object*)object;
@end

@interface GCCommit ()
@property(nonatomic, readonly) git_commit* private NS_RETURNS_INNER_POINTER;
- (instancetype)initWithRepository:(GCRepository*)repository commit:(git_commit*)commit;
@end

@interface GCTagAnnotation ()
@property(nonatomic, readonly) git_tag* private NS_RETURNS_INNER_POINTER;
- (instancetype)initWithRepository:(GCRepository*)repository tag:(git_tag*)tag;
@end

@interface GCReference ()
@property(nonatomic, readonly) git_reference* private NS_RETURNS_INNER_POINTER;
- (instancetype)initWithRepository:(GCRepository*)repository reference:(git_reference*)reference;
- (void)updateReference:(git_reference*)reference;
- (NSComparisonResult)compareWithReference:(git_reference*)reference;
@end

@interface GCIndex ()
@property(nonatomic, readonly) git_index* private NS_RETURNS_INNER_POINTER;
- (instancetype)initWithRepository:(GCRepository*)repository index:(git_index*)index;
- (const git_oid*)OIDForFile:(NSString*)path NS_RETURNS_INNER_POINTER;  // Returns NULL if file is not in index
@end

@interface GCDiffFile ()
@property(nonatomic, readonly) const git_oid* OID NS_RETURNS_INNER_POINTER;
@end

@interface GCDiffPatch ()
@property(nonatomic, readonly) git_patch* private NS_RETURNS_INNER_POINTER;
@end

@interface GCDiffDelta ()
@property(nonatomic, readonly) const git_diff_delta* private NS_RETURNS_INNER_POINTER;
@end

@interface GCDiff ()
@property(nonatomic, readonly) git_diff* private NS_RETURNS_INNER_POINTER;
#if DEBUG
- (GCFileDiffChange)changeForFile:(NSString*)path;  // For unit tests only - Returns NSNotFound if file not in diff
#endif
@end

@interface GCReflogEntry ()
@property(nonatomic, readonly) const git_oid* fromOID NS_RETURNS_INNER_POINTER;
@property(nonatomic, readonly) const git_oid* toOID NS_RETURNS_INNER_POINTER;
@end

@interface GCReferenceTransform ()
- (void)setSymbolicTarget:(const char*)target forReferenceWithName:(const char*)name;
- (void)setDirectTarget:(const git_oid*)oid forReferenceWithName:(const char*)name;
- (void)deleteReferenceWithName:(const char*)name;
@end

@interface GCSerializedReference : NSObject <NSSecureCoding>
@property(nonatomic, readonly) const char* name NS_RETURNS_INNER_POINTER;
@property(nonatomic, readonly) const char* shortHand NS_RETURNS_INNER_POINTER;
@property(nonatomic, readonly) git_ref_t type;
@property(nonatomic, readonly) const git_oid* directTarget NS_RETURNS_INNER_POINTER;
@property(nonatomic, readonly) const char* symbolicTarget NS_RETURNS_INNER_POINTER;
@property(nonatomic, readonly) git_otype resolvedType;
@property(nonatomic, readonly) const git_oid* resolvedTarget NS_RETURNS_INNER_POINTER;  // May be NULL
- (BOOL)isHEAD;
- (BOOL)isLocalBranch;
- (BOOL)isRemoteBranch;
- (BOOL)isTag;
@end

@interface GCSnapshot ()
@property(nonatomic, readonly) NSDictionary* config;
@property(nonatomic, readonly) NSArray* serializedReferences;
- (id)initWithRepository:(GCRepository*)repository error:(NSError**)error;
- (GCSerializedReference*)serializedReferenceWithName:(const char*)name;
@end

@interface GCRemote ()
@property(nonatomic, readonly) git_remote* private NS_RETURNS_INNER_POINTER;
- (NSComparisonResult)compareWithRemote:(git_remote*)remote;
@end

@interface GCSubmodule ()
- (instancetype)initWithRepository:(GCRepository*)repository submodule:(git_submodule*)submodule;
@property(nonatomic, readonly) git_submodule* private NS_RETURNS_INNER_POINTER;
@end

@interface GCIndexConflict ()
@property(nonatomic, readonly) const git_oid* ancestorOID NS_RETURNS_INNER_POINTER;
@property(nonatomic, readonly) const git_oid* ourOID NS_RETURNS_INNER_POINTER;
@property(nonatomic, readonly) const git_oid* theirOID NS_RETURNS_INNER_POINTER;
- (BOOL)isEqualToIndexConflict:(GCIndexConflict*)conflict;
@end

@interface GCRepository ()
@property(nonatomic, readonly) git_repository* private NS_RETURNS_INNER_POINTER;
@property(nonatomic, readonly) NSUInteger lastUpdatedTips;  // Reset before fetching and updated during fetching
- (instancetype)initWithRepository:(git_repository*)repository error:(NSError**)error;
- (void)updateRepository:(git_repository*)repository;
- (NSString*)privateTemporaryFilePath;
#if DEBUG
- (GCDiff*)checkUnifiedStatus:(NSError**)error;
- (GCDiff*)checkIndexStatus:(NSError**)error;
- (GCDiff*)checkWorkingDirectoryStatus:(NSError**)error;
- (BOOL)checkRepositoryDirty:(BOOL)includeUntracked;
- (instancetype)initWithClonedRepositoryFromURL:(NSURL*)url toPath:(NSString*)path usingDelegate:(id<GCRepositoryDelegate>)delegate recursive:(BOOL)recursive error:(NSError**)error;
#endif
- (void)willStartRemoteTransferWithURL:(NSURL*)url;
- (void)didFinishRemoteTransferWithURL:(NSURL*)url success:(BOOL)success;
- (void)setRemoteCallbacks:(git_remote_callbacks*)callbacks;
- (NSData*)exportBlobWithOID:(const git_oid*)oid error:(NSError**)error;
- (BOOL)exportBlobWithOID:(const git_oid*)oid toPath:(NSString*)path error:(NSError**)error;
@end

@interface GCHistory ()
- (GCHistoryCommit*)historyCommitForOID:(const git_oid*)oid;
@end

@interface GCCommitDatabase ()
- (NSArray*)findCommitsUsingHistory:(GCHistory*)history matching:(NSString*)match error:(NSError**)error;
#if DEBUG
- (NSUInteger)countCommits;  // Returns NSNotFound on error
- (NSUInteger)countTips;  // Returns NSNotFound on error
- (NSUInteger)countRelations;  // Returns NSNotFound on error
- (NSUInteger)totalCommitRetainCount;  // Returns NSNotFound on error
#endif
@end

@interface GCRepository (Bare_Private)
- (GCCommit*)createCommitFromTree:(git_tree*)tree
                      withParents:(const git_commit**)parents
                            count:(NSUInteger)count
                           author:(const git_signature*)author
                          message:(NSString*)message
                            error:(NSError**)error;

- (GCCommit*)createCommitFromIndex:(git_index*)index
                       withParents:(const git_commit**)parents
                             count:(NSUInteger)count
                            author:(const git_signature*)author
                           message:(NSString*)message
                             error:(NSError**)error;

- (GCCommit*)createCommitFromCommit:(git_commit*)commit
                          withIndex:(git_index*)index
                     updatedMessage:(NSString*)message
                     updatedParents:(NSArray*)parents
                    updateCommitter:(BOOL)updateCommitter
                              error:(NSError**)error;

- (GCCommit*)createCommitFromCommit:(git_commit*)commit
                           withTree:(git_tree*)tree
                     updatedMessage:(NSString*)message
                     updatedParents:(NSArray*)parents
                    updateCommitter:(BOOL)updateCommitter
                              error:(NSError**)error;
@end

@interface GCRepository (GCCommit_Private)
- (NSString*)computeUniqueOIDForCommit:(git_commit*)commit error:(NSError**)error;
@end

@interface GCRepository (GCBranch_Private)
- (git_commit*)loadCommitFromBranchReference:(git_reference*)reference error:(NSError**)error;
@end

@interface GCRepository (GCReference_Private)
- (id)findReferenceWithFullName:(NSString*)fullname class:(Class)class error:(NSError**)error;
- (BOOL)refreshReference:(GCReference*)reference error:(NSError**)error;
- (BOOL)enumerateReferencesWithOptions:(GCReferenceEnumerationOptions)options error:(NSError**)error usingBlock:(BOOL (^)(git_reference* reference))block;
- (BOOL)loadTargetOID:(git_oid*)oid fromReference:(git_reference*)reference error:(NSError**)error;
- (BOOL)setTargetOID:(const git_oid*)oid forReference:(git_reference*)reference reflogMessage:(NSString*)message newReference:(git_reference**)newReference error:(NSError**)error;  // Follows reference chain until a direct reference and force update its target
- (GCReference*)createDirectReferenceWithFullName:(NSString*)name target:(GCObject*)target force:(BOOL)force error:(NSError**)error;
- (GCReference*)createSymbolicReferenceWithFullName:(NSString*)name target:(NSString*)target force:(BOOL)force error:(NSError**)error;
@end

@interface GCRepository (GCIndex_Private)
- (git_index*)reloadRepositoryIndex:(NSError**)error;
#if DEBUG
- (BOOL)addAllFilesToIndex:(NSError**)error;  // For unit tests only
#endif
@end

@interface GCRepository (HEAD_Private)
- (git_commit*)loadHEADCommit:(git_reference**)resolvedReference error:(NSError**)error;  // "resolvedReference" is optional and will be set to NULL if HEAD is detached
- (BOOL)loadHEADCommit:(git_commit**)commit resolvedReference:(git_reference**)resolvedReference error:(NSError**)error;  // "commit" is optional and will be set to NULL if HEAD is unborn and "resolvedReference" is optional and will be set to NULL if HEAD is unborn or detached
#if DEBUG
- (BOOL)mergeCommitToHEAD:(GCCommit*)commit error:(NSError**)error;  // For unit tests only
#endif
@end

#if DEBUG

@interface GCRepository (Remote_Private)
- (NSUInteger)checkForChangesInRemote:(GCRemote*)remote withOptions:(GCRemoteCheckOptions)options error:(NSError**)error;
@end

#endif
