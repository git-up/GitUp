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

NSString* const GCErrorDomain = @"GCErrorDomain";

NSError* GCNewError(NSInteger code, NSString* message) {
  return [NSError errorWithDomain:GCErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSError* GCNewPosixError(int code, NSString* message) {
  return [NSError errorWithDomain:NSPOSIXErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSString* GCGitOIDToSHA1(const git_oid* oid) {
  if (git_oid_iszero(oid)) {
    return nil;
  }
  char sha1[GIT_OID_HEXSZ + 1];
  git_oid_tostr(sha1, sizeof(sha1), oid);
  return [NSString stringWithCString:sha1 encoding:NSASCIIStringEncoding];
}

BOOL GCGitOIDFromSHA1(NSString* sha1, git_oid* oid, NSError** error) {
  const char* string = sha1.UTF8String;
  if (strlen(string) != GIT_OID_HEXSZ) {
    if (error) {
      GC_SET_GENERIC_ERROR(@"Invalid SHA1 length");
    }
    return NO;
  }
  int status = git_oid_fromstr(oid, string);
  if (status != GIT_OK) {
    if (error) {
      CHECK_LIBGIT2_FUNCTION_CALL(return NO, status, == GIT_OK);  // Prevent logging unless "error" is set
    }
    return NO;
  }
  return YES;
}

BOOL GCGitOIDFromSHA1Prefix(NSString* prefix, git_oid* oid, NSError** error) {
  const char* string = prefix.UTF8String;
  int status = git_oid_fromstrp(oid, string);
  if (status != GIT_OK) {
    if (error) {
      CHECK_LIBGIT2_FUNCTION_CALL(return NO, status, == GIT_OK);  // Prevent logging unless "error" is set
    }
    return NO;
  }
  return YES;
}

NSData* GCCleanedUpCommitMessage(NSString* message) {
  NSData* data = nil;
  if (message.length) {
    git_buf buffer = {0};
    if (git_message_prettify(&buffer, message.UTF8String, 0, 0) == GIT_OK) {
      XLOG_DEBUG_CHECK(buffer.asize > buffer.size);
      XLOG_DEBUG_CHECK(buffer.ptr[buffer.size] == 0);
      data = [[NSData alloc] initWithBytes:buffer.ptr length:(buffer.size + 1)];
      git_buf_free(&buffer);
    }
  }
  return data;
}

NSString* GCUserFromSignature(const git_signature* signature) {
  return [NSString stringWithFormat:@"%@ <%s>", [NSString stringWithUTF8String:signature->name], signature->email];
}

// We can't use -[NSString fileSystemRepresentation] as it returns decomposed UTF8 while everything in Git is composed UTF8
// (unless the "core.precomposeUnicode" configuration option is false which shouldn't happen on OS X)
const char* GCGitPathFromFileSystemPath(NSString* string) {
  return string.UTF8String;
}

// We shouldn't use -[NSFileManager stringWithFileSystemRepresentation:length:] for the same reason as above
NSString* GCFileSystemPathFromGitPath(const char* string) {
  return string ? [NSString stringWithUTF8String:string] : nil;
}

/* Valid Git URLs from http://git-scm.com/docs/git-clone:
 - ssh://[user@]host.xz[:port]/path/to/repo.git/
 - [user@]host.xz:path/to/repo.git/
 - git://host.xz[:port]/path/to/repo.git/
 - http[s]://host.xz[:port]/path/to/repo.git/
 - ftp[s]://host.xz[:port]/path/to/repo.git/
 - rsync://host.xz/path/to/repo.git/
 - /path/to/repo.git/
 - \file:///path/to/repo.git/
 */
NSURL* GCURLFromGitURL(NSString* url) {
  NSURL* URL = nil;
  if (url.length) {
    if ([url characterAtIndex:0] == '/') {
      URL = [NSURL fileURLWithPath:url];
    } else {
      URL = [NSURL URLWithString:url];
    }
  }
  XLOG_DEBUG_CHECK(URL);
  return URL;
}

NSString* GCGitURLFromURL(NSURL* url) {
  if (url.isFileURL) {
    return url.path;
  }
  return url.absoluteString;
}

GCFileMode GCFileModeFromMode(git_filemode_t mode) {
  switch (mode) {
    case GIT_FILEMODE_UNREADABLE: return kGCFileMode_Unreadable;
    case GIT_FILEMODE_TREE: return kGCFileMode_Tree;
    case GIT_FILEMODE_BLOB: return kGCFileMode_Blob;
    case GIT_FILEMODE_BLOB_EXECUTABLE: return kGCFileMode_BlobExecutable;
    case GIT_FILEMODE_LINK: return kGCFileMode_Link;
    case GIT_FILEMODE_COMMIT: return kGCFileMode_Commit;
  }
  XLOG_DEBUG_UNREACHABLE();
  return 0;
}

static int _HideCallback(const git_oid* commit_id, void* payload) {
  int (^block)(const git_oid* commit_id) = (__bridge int (^)(const git_oid*))payload;
  return block(commit_id);
}

int git_revwalk_add_hide_block(git_revwalk* walk, int (^block)(const git_oid* commit_id)) {
  return git_revwalk_add_hide_cb(walk, _HideCallback, (__bridge void*)block);
}

static int _StashCallback(size_t index, const char* message, const git_oid* stash_id, void* payload) {
  int (^block)(size_t index, const char* message, const git_oid* stash_id) = (__bridge int (^)(size_t index, const char* message, const git_oid* stash_id))payload;
  return block(index, message, stash_id);
}

int git_stash_foreach_block(git_repository* repo, int (^block)(size_t index, const char* message, const git_oid* stash_id)) {
  return git_stash_foreach(repo, _StashCallback, (__bridge void*)block);
}

static int _SubmoduleCallback(git_submodule* sm, const char* name, void* payload) {
  int (^block)(git_submodule* submodule, const char* name) = (__bridge int (^)(git_submodule* submodule, const char* name))payload;
  return block(sm, name);
}

int git_submodule_foreach_block(git_repository* repo, int (^block)(git_submodule* submodule, const char* name)) {
  return git_submodule_foreach(repo, _SubmoduleCallback, (__bridge void*)block);
}

static void _ArrayApplierFunction(const void* value, void* context) {
  void (^block)(const void*) = (__bridge void (^)(const void*))context;
  block(value);
}

void GCArrayApplyBlock(CFArrayRef array, void (^block)(const void* value)) {
  CFArrayApplyFunction(array, CFRangeMake(0, CFArrayGetCount(array)), _ArrayApplierFunction, (void*)block);
}

static void _SetApplierFunction(const void* value, void* context) {
  void (^block)(const void*) = (__bridge void (^)(const void*))context;
  block(value);
}

void GCSetApplyBlock(CFSetRef set, void (^block)(const void* value)) {
  CFSetApplyFunction(set, _SetApplierFunction, (void*)block);
}

static void _DictionaryApplierFunction(const void* key, const void* value, void* context) {
  void (^block)(const void*, const void*) = (__bridge void (^)(const void*, const void*))context;
  block(key, value);
}

void GCDictionaryApplyBlock(CFDictionaryRef dict, void (^block)(const void* key, const void* value)) {
  CFDictionaryApplyFunction(dict, _DictionaryApplierFunction, (void*)block);
}

const void* GCOIDCopyCallBack(CFAllocatorRef allocator, const void* value) {
  void* oid = malloc(sizeof(git_oid));
  git_oid_cpy(oid, value);
  return oid;
}

Boolean GCOIDEqualCallBack(const void* value1, const void* value2) {
  const git_oid* oid1 = (const git_oid*)value1;
  const git_oid* oid2 = (const git_oid*)value2;
  return git_oid_equal(oid1, oid2);
}

CFHashCode GCOIDHashCallBack(const void* value) {
  const git_oid* oid = (const git_oid*)value;
  return *(CFHashCode*)oid->id;  // Use the first bytes
}

Boolean GCCStringEqualCallBack(const void* value1, const void* value2) {
  return !strcmp(value1, value2);
}

// From http://www.cse.yorku.ca/~oz/hash.html
CFHashCode GCCStringHashCallBack(const void* value) {
  const char* str = value;
  unsigned long hash = 5381;
  unsigned long c;
  while ((c = *str++)) {
    hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
  }
  return hash;
}

const void* GCCStringCopyCallBack(CFAllocatorRef allocator, const void* value) {
  return strdup(value);
}

void GCFreeReleaseCallBack(CFAllocatorRef allocator, const void* value) {
  free((void*)value);
}
