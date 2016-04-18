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

// SPIs from libgit2
extern int git_reference__is_branch(const char *ref_name);
extern int git_reference__is_remote(const char *ref_name);
extern int git_reference__is_tag(const char *ref_name);

@implementation GCRemote {
  __unsafe_unretained GCRepository* _repository;
}

- (instancetype)initWithRepository:(GCRepository*)repository remote:(git_remote*)remote {
  if ((self = [super init])) {
    _repository = repository;
    [self _updateRemote:remote];
  }
  return self;
}

- (void)dealloc {
  git_remote_free(_private);
}

- (void)_updateRemote:(git_remote*)remote {
  git_remote_free(_private);
  _private = remote;
  [self _reload];
}

- (void)_reload {
  _name = [NSString stringWithUTF8String:git_remote_name(_private)];
  
  const char* URL = git_remote_url(_private);
  if (URL) {
    _URL = GCURLFromGitURL([NSString stringWithUTF8String:URL]);
  } else {
    _URL = nil;
  }
  
  const char* pushURL = git_remote_pushurl(_private);
  if (pushURL) {
    _pushURL = GCURLFromGitURL([NSString stringWithUTF8String:pushURL]);
  } else {
    _pushURL = nil;
  }
}

- (NSComparisonResult)compareWithRemote:(git_remote*)remote {
  return strcmp(git_remote_name(_private), git_remote_name(remote));
}

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@] %@ (%@)", self.class, _name, GCGitURLFromURL(_URL)];
}

@end

@implementation GCRemote (Extensions)

- (NSUInteger)hash {
  return _name.hash;
}

- (BOOL)isEqualToRemote:(GCRemote*)remote {
  return (self == remote) || ([self compareWithRemote:remote.private] == NSOrderedSame);
}

- (BOOL)isEqual:(id)object {
  if (![object isMemberOfClass:[GCRemote class]]) {
    return NO;
  }
  return [self isEqualToRemote:object];
}

- (NSComparisonResult)nameCompare:(GCRemote*)remote {
  return [_name localizedStandardCompare:remote->_name];
}

@end

@implementation GCRepository (GCRemote)

#pragma mark - Browsing

- (NSArray*)listRemotes:(NSError**)error {
  NSMutableArray* array = nil;
  git_strarray names = {0};
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_remote_list, &names, self.private);
  array = [[NSMutableArray alloc] init];
  for (size_t i = 0; i < names.count; ++i) {
    git_remote* loadedRemote;
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_remote_lookup, &loadedRemote, self.private, names.strings[i]);
    GCRemote* remote = [[GCRemote alloc] initWithRepository:self remote:loadedRemote];
    [array addObject:remote];
  }
  
cleanup:
  git_strarray_free(&names);
  return array;
}

- (GCRemote*)lookupRemoteWithName:(NSString*)name error:(NSError**)error {
  git_remote* remote;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_remote_lookup, &remote, self.private, name.UTF8String);
  return [[GCRemote alloc] initWithRepository:self remote:remote];
}

#pragma mark - Operations

- (GCRemote*)addRemoteWithName:(NSString*)name url:(NSURL*)url error:(NSError**)error {
  git_remote* remote;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_remote_create, &remote, self.private, name.UTF8String, GCGitURLFromURL(url).UTF8String);
  return [[GCRemote alloc] initWithRepository:self remote:remote];
}

- (BOOL)setName:(NSString*)name forRemote:(GCRemote*)remote error:(NSError**)error {
  const char* nameUTF8 = name.UTF8String;
  git_strarray problems;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_remote_rename, &problems, self.private, git_remote_name(remote.private), nameUTF8);
  XLOG_DEBUG_CHECK(problems.count == 0);  // TODO: What should we do in case of problems?
  git_strarray_free(&problems);
  git_remote* newRemote;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_remote_lookup, &newRemote, self.private, nameUTF8);
  [remote _updateRemote:newRemote];
  return YES;
}

- (BOOL)setURL:(NSURL*)url forRemote:(GCRemote*)remote error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_remote_set_url, self.private, git_remote_name(remote.private), GCGitURLFromURL(url).UTF8String);
  [remote _reload];
  return YES;
}

- (BOOL)setPushURL:(NSURL*)url forRemote:(GCRemote*)remote error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_remote_set_pushurl, self.private, git_remote_name(remote.private), GCGitURLFromURL(url).UTF8String);
  [remote _reload];
  return YES;
}

- (BOOL)removeRemote:(GCRemote*)remote error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_remote_delete, self.private, git_remote_name(remote.private));
  return YES;
}

#pragma mark - Transfer

- (NSUInteger)_transfer:(git_direction)direction withRemote:(git_remote*)remote refspecs:(const char**)refspecs count:(size_t)count tagMode:(GCFetchTagMode)tagMode prune:(BOOL)prune error:(NSError**)error {
  XLOG_DEBUG_CHECK(!git_remote_connected(remote));
  NSUInteger updatedTips = NSNotFound;
  const char* remoteURL = git_remote_url(remote);
  NSURL* url = remoteURL ? GCURLFromGitURL([NSString stringWithUTF8String:remoteURL]) : nil;
  [self willStartRemoteTransferWithURL:url];
  
  git_remote_callbacks callbacks = GIT_REMOTE_CALLBACKS_INIT;
  [self setRemoteCallbacks:&callbacks];
  int status = git_remote_connect(remote, direction, &callbacks, NULL);
  if (status != GIT_OK) {
    LOG_LIBGIT2_ERROR(status);
    if (error) {
      *error = GCNewError(status, [NSString stringWithFormat:@"Failed connecting to \"%s\" remote: %@", git_remote_name(remote), GetLastGitErrorMessage()]);  // We can't use CALL_LIBGIT2_FUNCTION_GOTO() as we need to customize the error message
    }
    goto cleanup;
  }
  if (refspecs) {
    git_strarray array = {(char**)refspecs, count};
    if (direction == GIT_DIRECTION_FETCH) {
      git_fetch_options options = GIT_FETCH_OPTIONS_INIT;
      options.callbacks = callbacks;
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_remote_download, remote, &array, &options);  // Passing NULL or 0 refspecs is equivalent to using the built-in "fetch" refspecs of the remote (typically "+refs/heads/*:refs/remotes/{REMOTE_NAME}/*")
      
      /*
       When fetching:
       - This only updates tips matching the active refspecs of the remote i.e. the ones passed to git_remote_download() and possibly some (GIT_REMOTE_DOWNLOAD_TAGS_AUTO) or *all* tags (GIT_REMOTE_DOWNLOAD_TAGS_ALL)
       - The force parameter of the refspecs is ignored and assume to always be true
       */
      git_remote_autotag_option_t mode = GIT_REMOTE_DOWNLOAD_TAGS_UNSPECIFIED;
      switch (tagMode) {
        case kGCFetchTagMode_Automatic: mode = GIT_REMOTE_DOWNLOAD_TAGS_AUTO; break;
        case kGCFetchTagMode_None: mode = GIT_REMOTE_DOWNLOAD_TAGS_NONE; break;
        case kGCFetchTagMode_All: mode = GIT_REMOTE_DOWNLOAD_TAGS_ALL; break;
      }
      NSString* message = [NSString stringWithFormat:kGCReflogMessageFormat_Git_Fetch, [NSString stringWithUTF8String:git_remote_name(remote)]];
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_remote_update_tips, remote, &callbacks, true, mode, message.UTF8String);
      
      if (prune) {
        // This only prunes based on the active refspecs i.e. the ones passed to git_remote_download()
        CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_remote_prune, remote, &callbacks);
      }
    } else {
      git_push_options options = GIT_PUSH_OPTIONS_INIT;
      options.callbacks = callbacks;
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_remote_upload, remote, &array, &options);  // Passing NULL or 0 refspecs is equivalent to using the built-in "push" refspecs of the remote (typically none)
      
      /*
       When pushing:
       - This only updates tips matching the ones passed to git_remote_upload() AND also matching the built-in refspecs of the remote
       - This behavior is due to the fact libgit2 needs to be able to convert the updated references remote-side to repository-side ones in order to update them, and this requires some "fetch" refspecs to do the transform
       */
      NSString* message = [NSString stringWithFormat:kGCReflogMessageFormat_Git_Push, [NSString stringWithUTF8String:git_remote_name(remote)]];
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_remote_update_tips, remote, &callbacks, false, 0, message.UTF8String);
    }
  }
  updatedTips = self.lastUpdatedTips;
  
cleanup:
  git_remote_disconnect(remote);  // Ignore error
  [self didFinishRemoteTransferWithURL:url success:(updatedTips != NSNotFound)];
  return updatedTips;
}

#pragma mark - Check

// TODO: Handle symbolic references (watch out for HEAD)
// Inspired from git_remote_prune()
- (BOOL)checkForChangesInRemote:(GCRemote*)remote
                    withOptions:(GCRemoteCheckOptions)options
                addedReferences:(NSDictionary**)addedReferences
             modifiedReferences:(NSDictionary**)modifiedReferences
              deletedReferences:(NSDictionary**)deletedReferences
                          error:(NSError**)error {
  BOOL success = NO;
  CFDictionaryKeyCallBacks keyCallbacks = {0, GCCStringCopyCallBack, GCFreeReleaseCallBack, NULL, GCCStringEqualCallBack, GCCStringHashCallBack};
  CFDictionaryValueCallBacks valueCallbacks = {0, GCOIDCopyCallBack, GCFreeReleaseCallBack, NULL, GCOIDEqualCallBack};
  CFMutableDictionaryRef localReferences = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &valueCallbacks);
  CFMutableDictionaryRef remoteReferences = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &valueCallbacks);
  
  // Build list of remote branches matching this remote's refspecs (excluding symbolic ones)
  if (![self enumerateReferencesWithOptions:0 error:error usingBlock:^BOOL(git_reference* reference) {
    
    const char* name = git_reference_name(reference);
    if (((options & kGCRemoteCheckOption_IncludeBranches) && git_reference__is_remote(name)) ||
        ((options & kGCRemoteCheckOption_IncludeTags) && git_reference__is_tag(name))) {
      if (git_reference_type(reference) == GIT_REF_OID) {
        for (size_t i = 0; i < git_remote_refspec_count(remote.private); ++i) {
          const git_refspec* refspec = git_remote_get_refspec(remote.private, i);
          if ((git_refspec_direction(refspec) == GIT_DIRECTION_FETCH) && git_refspec_dst_matches(refspec, name)) {
            CFDictionarySetValue(localReferences, name, git_reference_target(reference));
            break;
          }
        }
      }
    }
    return YES;
    
  }]) {
    goto cleanup;
  }
  
  // Build list of branches on remotes filtered by remote refspecs (excluding symbolic ones)
  if ([self _transfer:GIT_DIRECTION_FETCH withRemote:remote.private refspecs:NULL count:0 tagMode:kGCFetchTagMode_None prune:NO error:error] == NSNotFound) {
    goto cleanup;
  }
  const git_remote_head** headList;
  size_t headCount;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_remote_ls, &headList, &headCount, remote.private);
  for (size_t i = 0; i < headCount; ++i) {
    const git_remote_head* head = headList[i];
    if (((options & kGCRemoteCheckOption_IncludeBranches) && git_reference__is_branch(head->name)) ||
        ((options & kGCRemoteCheckOption_IncludeTags) && git_reference__is_tag(head->name))) {
      if (!head->symref_target) {
        for (size_t j = 0; j < git_remote_refspec_count(remote.private); ++j) {
          const git_refspec* refspec = git_remote_get_refspec(remote.private, j);
          if ((git_refspec_direction(refspec) == GIT_DIRECTION_FETCH) && git_refspec_src_matches(refspec, head->name)) {
            git_buf buffer = {0};
            CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_refspec_transform, &buffer, refspec, head->name);
            CFDictionarySetValue(remoteReferences, buffer.ptr, &head->oid);
            git_buf_free(&buffer);
          }
        }
      }
    }
  }
  
  // Compare lists
  if (addedReferences) {
    *addedReferences = [[NSMutableDictionary alloc] init];
  }
  if (modifiedReferences) {
    *modifiedReferences = [[NSMutableDictionary alloc] init];
  }
  if (deletedReferences) {
    *deletedReferences = [[NSMutableDictionary alloc] init];
  }
  GCDictionaryApplyBlock(remoteReferences, ^(const void* key, const void* value) {
    const char* name = key;
    const git_oid* remoteOID = value;
    const git_oid* localOID = CFDictionaryGetValue(localReferences, name);
    if (!localOID) {
      [(NSMutableDictionary*)*addedReferences setObject:GCGitOIDToSHA1(remoteOID) forKey:[NSString stringWithUTF8String:name]];  // Reference is in remote but not in repository
    } else {
      if (git_oid_cmp(localOID, remoteOID)) {
        [(NSMutableDictionary*)*modifiedReferences setObject:GCGitOIDToSHA1(remoteOID) forKey:[NSString stringWithUTF8String:name]];  // Reference is in remote and repository but with different targets
      }
      CFDictionaryRemoveValue(localReferences, name);
    }
  });
  GCDictionaryApplyBlock(localReferences, ^(const void* key, const void* value) {
    const char* name = key;
    const git_oid* localOID = value;
    [(NSMutableDictionary*)*deletedReferences setObject:GCGitOIDToSHA1(localOID) forKey:[NSString stringWithUTF8String:name]];  // Reference is not in remote anymore but still in repository
  });
  success = YES;
  
cleanup:
  CFRelease(remoteReferences);
  CFRelease(localReferences);
  return success;
}

#pragma mark - Fetch

- (NSUInteger)_fetchFromRemote:(git_remote*)remote refspecs:(const char**)refspecs count:(size_t)count tagMode:(GCFetchTagMode)tagMode prune:(BOOL)prune error:(NSError**)error {
  return [self _transfer:GIT_DIRECTION_FETCH withRemote:remote refspecs:refspecs count:count tagMode:tagMode prune:prune error:error];
}

- (BOOL)fetchRemoteBranch:(GCRemoteBranch*)branch tagMode:(GCFetchTagMode)mode updatedTips:(NSUInteger*)updatedTips error:(NSError**)error {
  NSUInteger result = NSNotFound;
  git_remote* remote = [self _loadRemoteForRemoteBranch:branch.private error:error];
  if (remote == NULL) {
    return NO;
  }
  
  const char* dstName = git_reference_name(branch.private);
  for (size_t i = 0; i < git_remote_refspec_count(remote); ++i) {
    const git_refspec* refspec = git_remote_get_refspec(remote, i);
    if ((git_refspec_direction(refspec) == GIT_DIRECTION_FETCH) && git_refspec_dst_matches(refspec, dstName)) {
      git_buf srcBuffer = {0};
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_refspec_rtransform, &srcBuffer, refspec, dstName);
      char* buffer;
      asprintf(&buffer, "%s:%s", srcBuffer.ptr, dstName);
      result = [self _fetchFromRemote:remote refspecs:(const char**)&buffer count:1 tagMode:mode prune:NO error:error];
      free(buffer);
      git_buf_free(&srcBuffer);
      goto cleanup;  // TODO: What if there is more than one match?
    }
  }
  GC_SET_GENERIC_ERROR(@"No matching refspec for \"%@\"", branch.name);
  
cleanup:
  git_remote_free(remote);
  if (result == NSNotFound) {
    return NO;
  }
  if (updatedTips) {
    *updatedTips = result;
  }
  return YES;
}

- (BOOL)fetchDefaultRemoteBranchesFromRemote:(GCRemote*)remote tagMode:(GCFetchTagMode)mode prune:(BOOL)prune updatedTips:(NSUInteger*)updatedTips error:(NSError**)error {
  git_strarray refspecs = {0};
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_remote_get_fetch_refspecs, &refspecs, remote.private);
  NSUInteger result = [self _fetchFromRemote:remote.private refspecs:(const char**)refspecs.strings count:refspecs.count tagMode:mode prune:prune error:error];
  git_strarray_free(&refspecs);
  if (result == NSNotFound) {
    return NO;
  }
  if (updatedTips) {
    *updatedTips = result;
  }
  return YES;
}

// We need to pass the special tags refspec which matches the libgit2 behavior of GIT_REMOTE_DOWNLOAD_TAGS_ALL to avoid passing no refspec and having libgit2 fall back to the default ones
- (NSArray*)fetchTagsFromRemote:(GCRemote*)remote prune:(BOOL)prune updatedTips:(NSUInteger*)updatedTips error:(NSError**)error {
  const char* buffer = "refs/tags/*:refs/tags/*";
  NSUInteger result = [self _fetchFromRemote:remote.private refspecs:&buffer count:1 tagMode:kGCFetchTagMode_All prune:prune error:error];
  if (result == NSNotFound) {
    return nil;
  }
  
  const git_remote_head** headList;
  size_t headCount;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_remote_ls, &headList, &headCount, remote.private);
  NSMutableArray* array = [[NSMutableArray alloc] init];
  for (size_t i = 0; i < headCount; ++i) {
    const git_remote_head* head = headList[i];
    if (git_reference__is_tag(head->name)) {
      if (head->symref_target || !git_reference_is_valid_name(head->name)) {
        continue;
      }
      git_reference* reference;
      int status = git_reference_lookup(&reference, self.private, head->name);
      if (status == GIT_ENOTFOUND) {
        XLOG_DEBUG_UNREACHABLE();
        continue;
      }
      CHECK_LIBGIT2_FUNCTION_CALL(return nil, status, == GIT_OK);
      [array addObject:[[GCTag alloc] initWithRepository:self reference:reference]];
    }
  }
  if (updatedTips) {
    *updatedTips = result;
  }
  return array;
}

#pragma mark - Push

- (BOOL)_pushToRemote:(git_remote*)remote refspecs:(const char**)refspecs count:(size_t)count error:(NSError**)error {
  return ([self _transfer:GIT_DIRECTION_PUSH withRemote:remote refspecs:refspecs count:count tagMode:kGCFetchTagMode_None prune:NO error:error] != NSNotFound);
}

- (BOOL)_pushSourceReference:(const char*)srcName
                    toRemote:(git_remote*)remote
        destinationReference:(const char*)dstName
                       force:(BOOL)force
                       error:(NSError**)error {
  char* buffer;
  asprintf(&buffer, "%s%s:%s", force ? "+" : "", srcName, dstName);
  BOOL success = [self _pushToRemote:remote refspecs:(const char**)&buffer count:1 error:error];
  free(buffer);
  return success;
}

- (BOOL)pushLocalBranchToUpstream:(GCLocalBranch*)branch force:(BOOL)force usedRemote:(GCRemote**)usedRemote error:(NSError**)error {
  BOOL success = NO;
  const char* name = git_reference_name(branch.private);
  git_buf remoteBuffer = {0};
  git_buf mergeBuffer = {0};
  git_remote* remote = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_branch_upstream_remote, &remoteBuffer, self.private, name);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_branch_upstream_merge, &mergeBuffer, self.private, name);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_remote_lookup, &remote, self.private, remoteBuffer.ptr);
  if (![self _pushSourceReference:name toRemote:remote destinationReference:mergeBuffer.ptr force:force error:error]) {
    goto cleanup;
  }
  success = YES;
  
cleanup:
  if (remote && usedRemote) {
    *usedRemote = [[GCRemote alloc] initWithRepository:self remote:remote];  // Return even on error
    remote = NULL;
  }
  git_remote_free(remote);
  git_buf_free(&mergeBuffer);
  git_buf_free(&remoteBuffer);
  return success;
}

// TODO: Add low-level API to libgit2
static BOOL _SetBranchDefaultUpstream(git_repository* repository, git_remote* remote, git_reference* branch, NSError** error) {
  XLOG_DEBUG_CHECK(git_reference_is_branch(branch));
  const char* name = git_reference_name(branch);
  const char* shortName = git_reference_shorthand(branch);
  char* buffer1;
  char* buffer2;
  asprintf(&buffer1, "branch.%s.remote", shortName);
  asprintf(&buffer2, "branch.%s.merge", shortName);
  git_config* config;
  int status = git_repository_config(&config, repository);
  if (status == GIT_OK) {
    status = git_config_set_string(config, buffer1, git_remote_name(remote));
    if (status == GIT_OK) {
      status = git_config_set_string(config, buffer2, name);
    }
    git_config_free(config);
  }
  free(buffer2);
  free(buffer1);
  CHECK_LIBGIT2_FUNCTION_CALL(return NO, status, == GIT_OK);
  return YES;
}

// Use the same "default" behavior as Git i.e push to a branch with the same name on the remote
- (BOOL)pushLocalBranch:(GCLocalBranch*)branch toRemote:(GCRemote*)remote force:(BOOL)force setUpstream:(BOOL)setUpstream error:(NSError**)error {
  const char* name = git_reference_name(branch.private);
  if (![self _pushSourceReference:name toRemote:remote.private destinationReference:name force:force error:error]) {
    return NO;
  }
  if (setUpstream && !_SetBranchDefaultUpstream(self.private, remote.private, branch.private, error)) {
    return NO;
  }
  return YES;
}

// Use the same "default" behavior as Git i.e push to a tag with the same name on the remote
- (BOOL)pushTag:(GCTag*)tag toRemote:(GCRemote*)remote force:(BOOL)force error:(NSError**)error {
  const char* name = git_reference_name(tag.private);
  return [self _pushSourceReference:name toRemote:remote.private destinationReference:name force:force error:error];
}

// TODO: libgit2 doesn't support pattern based push refspecs like "refs/heads/*:refs/heads/*"
- (BOOL)_pushAllReferencesToRemote:(git_remote*)remote branches:(BOOL)branches tags:(BOOL)tags force:(BOOL)force error:(NSError**)error {
  GC_POINTER_LIST_ALLOCATE(buffers, 128);
  BOOL success = [self enumerateReferencesWithOptions:0 error:error usingBlock:^BOOL(git_reference* reference) {
    
    if ((branches && git_reference_is_branch(reference)) || (tags && git_reference_is_tag(reference))) {
      char* buffer;
      asprintf(&buffer, "%s%s:%s", force ? "+" : "", git_reference_name(reference), git_reference_name(reference));
      GC_POINTER_LIST_APPEND(buffers, buffer);
    }
    return YES;
    
  }];
  if (success) {
    success = [self _pushToRemote:remote refspecs:(const char**)GC_POINTER_LIST_ROOT(buffers) count:GC_POINTER_LIST_COUNT(buffers) error:error];
  }
  GC_POINTER_LIST_FOR_LOOP(buffers, char*, buffer) {
    free(buffer);
  }
  GC_POINTER_LIST_FREE(buffers);
  return success;
}

// Use the same "default" behavior as Git i.e push to branches with the same names on the remote
- (BOOL)pushAllLocalBranchesToRemote:(GCRemote*)remote force:(BOOL)force setUpstream:(BOOL)setUpstream error:(NSError**)error {
  if (![self _pushAllReferencesToRemote:remote.private branches:YES tags:NO force:force error:error]) {
    return NO;
  }
  if (setUpstream && ![self enumerateReferencesWithOptions:0 error:error usingBlock:^BOOL(git_reference* reference) {
    
    if (git_reference_is_branch(reference) && !_SetBranchDefaultUpstream(self.private, remote.private, reference, error)) {
      return NO;
    }
    return YES;
    
  }]) {
    return NO;
  }
  return YES;
}

// Use the same "default" behavior as Git i.e push to tags with the same names on the remote
- (BOOL)pushAllTagsToRemote:(GCRemote*)remote force:(BOOL)force error:(NSError**)error {
  return [self _pushAllReferencesToRemote:remote.private branches:NO tags:YES force:force error:error];
}

- (BOOL)deleteRemoteBranchFromRemote:(GCRemoteBranch*)branch error:(NSError**)error {
  BOOL success = NO;
  git_remote* remote = NULL;
  
  remote = [self _loadRemoteForRemoteBranch:branch.private error:error];
  if (remote == NULL) {
    goto cleanup;
  }
  const char* dstName = git_reference_name(branch.private);
  for (size_t i = 0; i < git_remote_refspec_count(remote); ++i) {
    const git_refspec* refspec = git_remote_get_refspec(remote, i);
    if ((git_refspec_direction(refspec) == GIT_DIRECTION_FETCH) && git_refspec_dst_matches(refspec, dstName)) {
      git_buf srcBuffer = {0};
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_refspec_rtransform, &srcBuffer, refspec, dstName);
      char* buffer;
      asprintf(&buffer, ":%s", srcBuffer.ptr);
      success = [self _pushToRemote:remote refspecs:(const char**)&buffer count:1 error:error];
      free(buffer);
      git_buf_free(&srcBuffer);
      goto cleanup;  // TODO: What if there is more than one match?
    }
  }
  
cleanup:
  git_remote_free(remote);
  return success;
}

- (BOOL)deleteTag:(GCTag*)tag fromRemote:(GCRemote*)remote error:(NSError**)error {
  const char* name = git_reference_name(tag.private);
  char* buffer;
  asprintf(&buffer, ":%s", name);
  BOOL success = [self _pushToRemote:remote.private refspecs:(const char**)&buffer count:1 error:error];
  free(buffer);
  return success;
}

#pragma mark - Utilities

- (git_remote*)_loadRemoteForRemoteBranch:(git_reference*)branch error:(NSError**)error {
  git_buf buffer = {0};
  CALL_LIBGIT2_FUNCTION_RETURN(NULL, git_branch_remote_name, &buffer, self.private, git_reference_name(branch));
  git_remote* remote;
  int status = git_remote_lookup(&remote, self.private, buffer.ptr);
  git_buf_free(&buffer);
  CHECK_LIBGIT2_FUNCTION_CALL(return NULL, status, == GIT_OK);
  return remote;
}

- (GCRemote*)lookupRemoteForRemoteBranch:(GCRemoteBranch*)branch sourceBranchName:(NSString**)name error:(NSError**)error {
  git_remote* remote = [self _loadRemoteForRemoteBranch:branch.private error:error];
  if (remote == NULL) {
    return nil;
  }
  if (name) {
    *name = nil;
    const char* dstName = git_reference_name(branch.private);
    for (size_t i = 0; i < git_remote_refspec_count(remote); ++i) {
      const git_refspec* refspec = git_remote_get_refspec(remote, i);
      if ((git_refspec_direction(refspec) == GIT_DIRECTION_FETCH) && git_refspec_dst_matches(refspec, dstName)) {
        git_buf srcBuffer = {0};
        int status = git_refspec_rtransform(&srcBuffer, refspec, dstName);
        if ((status == GIT_OK) && !strncmp(srcBuffer.ptr, "refs/heads/", 11)) {
          *name = [NSString stringWithUTF8String:(srcBuffer.ptr + 11)];
        }
        git_buf_free(&srcBuffer);
        if (status != GIT_OK) {
          git_remote_free(remote);
          CHECK_LIBGIT2_FUNCTION_CALL(return nil, status, == GIT_OK);
        }
        break;
      }
    }
    XLOG_DEBUG_CHECK(*name);
  }
  return [[GCRemote alloc] initWithRepository:self remote:remote];
}

- (BOOL)cloneUsingRemote:(GCRemote*)remote recursive:(BOOL)recursive error:(NSError**)error {
  [self willStartRemoteTransferWithURL:remote.URL];
  
  git_fetch_options fetchOptions = GIT_FETCH_OPTIONS_INIT;
  [self setRemoteCallbacks:&fetchOptions.callbacks];
  git_checkout_options checkoutOptions = GIT_CHECKOUT_OPTIONS_INIT;
  checkoutOptions.checkout_strategy = GIT_CHECKOUT_SAFE;
  int status = git_clone_into(self.private, remote.private, &fetchOptions, &checkoutOptions, NULL);  // This will fail if the repository is not empty
  
  [self didFinishRemoteTransferWithURL:remote.URL success:(status == GIT_OK)];
  CHECK_LIBGIT2_FUNCTION_CALL(return NO, status, == GIT_OK);
  
  return recursive ? [self initializeAllSubmodules:YES error:error] : YES;
}

@end

#if DEBUG

@implementation GCRepository (Remote_Private)

- (NSUInteger)checkForChangesInRemote:(GCRemote*)remote withOptions:(GCRemoteCheckOptions)options error:(NSError**)error {
  NSDictionary* added;
  NSDictionary* modified;
  NSDictionary* deleted;
  if (![self checkForChangesInRemote:remote withOptions:options addedReferences:&added modifiedReferences:&modified deletedReferences:&deleted error:error]) {
    return NSNotFound;
  }
  return added.count + modified.count + deleted.count;
}

@end

#endif
