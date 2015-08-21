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

#import <objc/runtime.h>

#import "GCRepository+Utilities.h"
#import "GCRepository+Index.h"

#import "XLFacilityMacros.h"

#define kUserInfoFileName @"info.plist"

static const void* _associatedObjectKey = &_associatedObjectKey;

NSString* GCNameFromHostingService(GCHostingService service) {
  switch (service) {
    case kGCHostingService_Unknown: return nil;
    case kGCHostingService_GitHub: return @"GitHub";
    case kGCHostingService_GitLab: return @"GitLab";
    case kGCHostingService_BitBucket: return @"BitBucket";
  }
  XLOG_DEBUG_UNREACHABLE();
  return nil;
}

@implementation GCRepository (Utilities)

// TODO: Take into account @fetchRecurseMode
- (BOOL)_fetchRepository:(GCRepository*)repository recursive:(BOOL)recursive error:(NSError**)error block:(BOOL (^)(GCRepository* repository, NSArray* remotes, NSError** error))block {
  NSArray* remotes = [repository listRemotes:error];
  if (remotes == nil) {
    return NO;
  }
  if (!block(repository, remotes, error)) {
    return NO;
  }
  
  if (recursive) {
    NSArray* submodules = [repository listSubmodules:error];
    if (submodules == nil) {
      return NO;
    }
    for (GCSubmodule* submodule in submodules) {
      GCRepository* subRepository = [[GCRepository alloc] initWithSubmodule:submodule error:error];
      subRepository.delegate = self.delegate;
      if (subRepository == nil) {
        return NO;
      }
      if (![self _fetchRepository:subRepository recursive:recursive error:error block:block]) {
        return NO;
      }
    }
  }
  return YES;
}

- (BOOL)fetchDefaultRemoteBranchesFromAllRemotes:(GCFetchTagMode)mode recursive:(BOOL)recursive prune:(BOOL)prune updatedTips:(NSUInteger*)updatedTips error:(NSError**)error {
  __block NSUInteger total = 0;
  if (![self _fetchRepository:self recursive:recursive error:error block:^BOOL(GCRepository* repository, NSArray* remotes, NSError** blockError) {
    
    for (GCRemote* remote in remotes) {
      NSUInteger count;
      if (![repository fetchDefaultRemoteBranchesFromRemote:remote tagMode:mode prune:prune updatedTips:&count error:blockError]) {
        return NO;
      }
      total += count;
    }
    return YES;
    
  }]) {
    return NO;
  }
  if (updatedTips) {
    *updatedTips = total;
  }
  return YES;
}

- (BOOL)fetchAllTagsFromAllRemotes:(BOOL)recursive prune:(BOOL)prune updatedTips:(NSUInteger*)updatedTips error:(NSError**)error {
  __block NSUInteger total = 0;
  if (![self _fetchRepository:self recursive:recursive error:error block:^BOOL(GCRepository* repository, NSArray* remotes, NSError** blockError) {
    
    NSMutableArray* remoteTags = prune ? [[NSMutableArray alloc] init] : nil;
    for (GCRemote* remote in remotes) {
      NSUInteger count;
      NSArray* tags = [repository fetchTagsFromRemote:remote prune:NO updatedTips:&count error:blockError];  // Don't prune at this time!
      if (tags == nil) {
        return NO;
      }
      [remoteTags addObjectsFromArray:tags];
      total += count;
    }
    if (remoteTags) {
      NSArray* repositoryTags = [repository listTags:blockError];
      if (repositoryTags == nil) {
        return NO;
      }
      for (GCTag* tag in repositoryTags) {
        if (![remoteTags containsObject:tag]) {
          if (![repository deleteTag:tag error:blockError]) {
            return NO;
          }
          total += 1;
        }
      }
    }
    return YES;
    
  }]) {
    return NO;
  }
  if (updatedTips) {
    *updatedTips = total;
  }
  return YES;
}

- (BOOL)moveFileFromPath:(NSString*)fromPath toPath:(NSString*)toPath force:(BOOL)force error:(NSError**)error {
  NSString* sourcePath = [self absolutePathForFile:fromPath];
  NSString* destinationPath = [self absolutePathForFile:toPath];
  BOOL isDirectory;
  
  GCIndex* index = [self readRepositoryIndex:error];
  if (!index) {
    return NO;
  }
  
  if (![[NSFileManager defaultManager] fileExistsAtPath:sourcePath isDirectory:&isDirectory] || isDirectory) {
    GC_SET_GENERIC_ERROR(@"No file at \"%@\"", sourcePath);
    return NO;
  }
  
  if (force && ![self safeDeleteFileIfExists:toPath error:error]) {
    return NO;
  }
  
  if (![[NSFileManager defaultManager] moveItemAtPath:sourcePath toPath:destinationPath error:error]) {
    return NO;
  }
  
  return [self removeFile:fromPath fromIndex:index error:error] && [self addFileInWorkingDirectory:toPath toIndex:index error:error] && [self writeRepositoryIndex:index error:error];
}

- (BOOL)removeFile:(NSString*)path error:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (!index) {
    return NO;
  }
  if (![self safeDeleteFile:path error:error]) {
    return NO;
  }
  return [self removeFile:path fromIndex:index error:error] && [self writeRepositoryIndex:index error:error];
}

// We can't use git_index_update_all() in libgit2 which blindly calls git_index_add_bypath() on every file which is very slow
- (BOOL)syncIndexWithWorkingDirectory:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (!index) {
    return NO;
  }
  GCDiff* diff = [self diffWorkingDirectoryWithIndex:index filePattern:nil options:kGCDiffOption_IncludeUntracked maxInterHunkLines:0 maxContextLines:0 error:error];
  if (diff == nil) {
    return NO;
  }
  for (GCDiffDelta* delta in diff.deltas) {
    switch (delta.change) {
      
      case kGCFileDiffChange_Deleted: {
        if (![self clearConflictForFile:delta.canonicalPath inIndex:index error:error]) {
          return NO;
        }
        if (![self removeFile:delta.canonicalPath fromIndex:index error:error]) {
          return NO;
        }
        break;
      }
      
      case kGCFileDiffChange_Modified:
      case kGCFileDiffChange_Untracked:
      case kGCFileDiffChange_Conflicted: {
        if ((delta.change != kGCFileDiffChange_Untracked) && ![self clearConflictForFile:delta.canonicalPath inIndex:index error:error]) {
          return NO;
        }
        if (delta.submodule) {
          GCSubmodule* submodule = [self lookupSubmoduleWithName:delta.canonicalPath error:error];
          if (!submodule || ![self addSubmoduleToRepositoryIndex:submodule error:error]) {
            return NO;
          }
        } else {
          if (![self addFileInWorkingDirectory:delta.canonicalPath toIndex:index error:error]) {
            return NO;
          }
        }
        break;
      }
      
      default:
        XLOG_DEBUG_UNREACHABLE();
        break;
      
    }
  }
  return [self writeRepositoryIndex:index error:error];
}

- (BOOL)cleanWorkingDirectory:(NSError**)error {
  GCDiff* diff = [self diffWorkingDirectoryWithRepositoryIndex:nil options:kGCDiffOption_IncludeUntracked maxInterHunkLines:0 maxContextLines:0 error:error];
  if (diff == nil) {
    return NO;
  }
  for (GCDiffDelta* delta in diff.deltas) {
    if (delta.change == kGCFileDiffChange_Untracked) {
      if (![self safeDeleteFile:delta.canonicalPath error:error]) {
        return NO;
      }
    }
  }
  return YES;
}

// We can't use git_checkout_tree() because it updates the working directory according to the target not the index
- (BOOL)syncWorkingDirectoryWithIndex:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (!index) {
    return NO;
  }
  GCDiff* diff = [self diffWorkingDirectoryWithIndex:index filePattern:nil options:kGCDiffOption_IncludeUntracked maxInterHunkLines:0 maxContextLines:0 error:error];
  if (diff == nil) {
    return NO;
  }
  for (GCDiffDelta* delta in diff.deltas) {
    switch (delta.change) {
      
      case kGCFileDiffChange_Untracked:
        if (![self safeDeleteFile:delta.canonicalPath error:error]) {
          return NO;
        }
        break;
      
      case kGCFileDiffChange_Deleted:
      case kGCFileDiffChange_Modified:
      case kGCFileDiffChange_Conflicted:
        if (![self clearConflictForFile:delta.canonicalPath inIndex:index error:error]) {
          return NO;
        }
        if (delta.submodule) {
          GCSubmodule* submodule = [self lookupSubmoduleWithName:delta.canonicalPath error:error];
          if (!submodule || ![self updateSubmodule:submodule force:YES error:error]) {
            return NO;
          }
        } else {
          if (![self safeDeleteFileIfExists:delta.canonicalPath error:error] || ![self checkoutFileToWorkingDirectory:delta.canonicalPath fromIndex:index error:error]) {
            return NO;
          }
        }
        break;
      
      default:
        XLOG_DEBUG_UNREACHABLE();
        break;
      
    }
  }
  return YES;
}

// Partial reimplementation of git_reset(GIT_RESET_HARD)
- (BOOL)forceCheckoutHEAD:(BOOL)recursive error:(NSError**)error {
  GCIndex* index = [self readRepositoryIndex:error];
  if (!index) {
    return NO;
  }
  GCCommit* headCommit;
  if (![self lookupHEADCurrentCommit:&headCommit branch:NULL error:error]) {
    return NO;
  }
  GCCheckoutOptions options = kGCCheckoutOption_Force;
  if (recursive) {
    options |= kGCCheckoutOption_UpdateSubmodulesRecursively;
  }
  return [self resetIndex:index toTreeForCommit:headCommit error:error] && [self checkoutTreeForCommit:nil withBaseline:nil options:options error:error];
}

/*
 - GitHub: https://github.com/git-up/git-up.github.io
 - BitBucket: https://bitbucket.org/gitup/test
 - GitLab: https://gitlab.com/gitup/GitUp-Mac
*/
- (NSURL*)_projectHostingURLForRemote:(GCRemote*)remote service:(GCHostingService*)service error:(NSError**)error {
  NSString* value = GCGitURLFromURL(remote.URL);
  if (value == nil) {
    XLOG_DEBUG_UNREACHABLE();
    GC_SET_GENERIC_ERROR(@"Invalid remote URL");
    return nil;
  }
  if ([value hasSuffix:@".git"]) {
    if ([value hasPrefix:@"ssh://"]) {
      value = [value substringFromIndex:6];
    }
    if ([value hasPrefix:@"git@"]) {
      
      if ([value hasPrefix:@"git@github.com:"] && [value hasSuffix:@".git"]) {  // git@github.com:git-up/git-up.github.io.git
        if (service) {
          *service = kGCHostingService_GitHub;
        }
        return [NSURL URLWithString:[@"https://github.com/" stringByAppendingString:[value substringWithRange:NSMakeRange(15, value.length - 15 - 4)]]];
      }
      if ([value hasPrefix:@"git@bitbucket.org:"] && [value hasSuffix:@".git"]) {  // git@bitbucket.org:gitup/test.git
        if (service) {
          *service = kGCHostingService_BitBucket;
        }
        return [NSURL URLWithString:[@"https://bitbucket.org/" stringByAppendingString:[value substringWithRange:NSMakeRange(18, value.length - 18 - 4)]]];
      }
      if ([value hasPrefix:@"git@gitlab.com:"] && [value hasSuffix:@".git"]) {  // git@gitlab.com:gitup/GitUp-Mac.git
        if (service) {
          *service = kGCHostingService_GitLab;
        }
        return [NSURL URLWithString:[@"https://gitlab.com/" stringByAppendingString:[value substringWithRange:NSMakeRange(15, value.length - 15 - 4)]]];
      }
      
    }
    if ([value hasPrefix:@"https://"]) {
      NSURL* url = [NSURL URLWithString:value];
      
      if ([url.host isEqualToString:@"github.com"]) {  // https://github.com/git-up/git-up.github.io.git
        if (service) {
          *service = kGCHostingService_GitHub;
        }
        return [NSURL URLWithString:[NSString stringWithFormat:@"https://github.com%@", [url.path substringToIndex:(url.path.length - 4)]]];
      }
      if ([url.host isEqualToString:@"bitbucket.org"]) {  // https://user@bitbucket.org/gitup/test.git
        if (service) {
          *service = kGCHostingService_BitBucket;
        }
        return [NSURL URLWithString:[NSString stringWithFormat:@"https://bitbucket.org%@", [url.path substringToIndex:(url.path.length - 4)]]];
      }
      if ([url.host isEqualToString:@"gitlab.com"]) {  // https://gitlab.com/gitup/GitUp-Mac.git
        if (service) {
          *service = kGCHostingService_GitLab;
        }
        return [NSURL URLWithString:[NSString stringWithFormat:@"https://gitlab.com%@", [url.path substringToIndex:(url.path.length - 4)]]];
      }
      
    }
  }
  
  GC_SET_GENERIC_ERROR(@"Origin remote on unknown service");
  return nil;
}

- (NSURL*)hostingURLForProject:(GCHostingService*)service error:(NSError**)error {
  GCRemote* remote = [self lookupRemoteWithName:@"origin" error:error];
  return remote ? [self _projectHostingURLForRemote:remote service:service error:error] : nil;
}

/*
 - GitHub: https://github.com/git-up/libgit2/commit/53f05c1c471a30a69a5bf2a6684fe713b2a87051
 - BitBucket: https://bitbucket.org/gitup/test/commits/27ecc64aacbdded365e2d4624aa32fad1a46a73d
 - GitLab: https://gitlab.com/gitup/GitUp-Mac/commit/ff9de47bc9a6aea05a96d5352701966b6928d949
*/
// TODO: This assumes the commit is available on the "origin" remote
- (NSURL*)hostingURLForCommit:(GCCommit*)commit service:(GCHostingService*)service error:(NSError**)error {
  GCHostingService localService;
  NSURL* url = [self hostingURLForProject:&localService error:error];
  if (url == nil) {
    return nil;
  }
  switch (localService) {
    
    case kGCHostingService_GitHub:
    case kGCHostingService_GitLab:
      url = [NSURL URLWithString:[url.absoluteString stringByAppendingFormat:@"/commit/%@", commit.SHA1]];  // Using relative URLs doesn't work
      break;
    
    case kGCHostingService_BitBucket:
      url = [NSURL URLWithString:[url.absoluteString stringByAppendingFormat:@"/commits/%@", commit.SHA1]];  // Using relative URLs doesn't work
      break;
    
    case kGCHostingService_Unknown:
      XLOG_DEBUG_UNREACHABLE();
      break;
    
  }
  if (service) {
    *service = localService;
  }
  return url;
}

/*
 - GitHub: https://github.com/git-up/libgit2/tree/gitup
 - BitBucket: https://bitbucket.org/gitup/test/branch/topic
 - GitLab: https://gitlab.com/gitup/GitUp-Mac/tree/igraph
*/
- (NSURL*)hostingURLForRemoteBranch:(GCRemoteBranch*)branch service:(GCHostingService*)service error:(NSError**)error {
  NSString* name;
  GCRemote* remote = [self lookupRemoteForRemoteBranch:branch sourceBranchName:&name error:error];
  if (remote == nil) {
    return nil;
  }
  GCHostingService localService;
  NSURL* url = [self _projectHostingURLForRemote:remote service:&localService error:error];
  if (url == nil) {
    return nil;
  }
  switch (localService) {
    
    case kGCHostingService_GitHub:
    case kGCHostingService_GitLab:
      url = [NSURL URLWithString:[url.absoluteString stringByAppendingFormat:@"/tree/%@", name]];  // Using relative URLs doesn't work
      break;
    
    case kGCHostingService_BitBucket:
      url = [NSURL URLWithString:[url.absoluteString stringByAppendingFormat:@"/branch/%@", name]];  // Using relative URLs doesn't work
      break;
    
    case kGCHostingService_Unknown:
      XLOG_DEBUG_UNREACHABLE();
      break;
    
  }
  if (service) {
    *service = localService;
  }
  return url;
}

/*
 - GitHub: https://github.com/git-up/libgit2/pull/new/gitup
           https://github.com/git-up/libgit2/compare/gitup?expand=1
           https://github.com/git-up/libgit2/compare/master...gitup?expand=1
           https://github.com/libgit2/libgit2/compare/master...git-up:gitup?expand=1
 - BitBucket: https://bitbucket.org/gitup/test/pull-request/new?source=gitup/test%3A%3Atopic&dest=gitup/test%3A%3Amaster
              https://bitbucket.org/gitup/test/pull-request/new?source=gitup/test::topic&dest=gitup/test::master
 - GitLab: https://gitlab.com/gitup/GitUp-Mac/merge_requests/new?merge_request%5Bsource_branch%5D=igraph&merge_request%5Btarget_branch%5D=master
           https://gitlab.com/gitup/GitUp-Mac/merge_requests/new?merge_request[source_branch]=igraph&merge_request[target_branch]=master
           https://gitlab.com/gitup/GitUp-Mac/merge_requests/new?merge_request%5Bsource_branch%5D=new_graph&merge_request%5Bsource_project_id%5D=251119&merge_request%5Btarget_branch%5D=&merge_request%5Btarget_project_id%5D=251119
           https://gitlab.com/gitup/GitUp-Mac/merge_requests/new?merge_request[source_branch]=new_graph&merge_request[source_project_id]=251119&merge_request[target_branch]=&merge_request[target_project_id]=251119
*/
- (NSURL*)hostingURLForPullRequestFromRemoteBranch:(GCRemoteBranch*)fromBranch toBranch:(GCRemoteBranch*)toBranch service:(GCHostingService*)service error:(NSError**)error {
  NSString* fromName;
  GCRemote* fromRemote = [self lookupRemoteForRemoteBranch:fromBranch sourceBranchName:&fromName error:error];
  if (fromRemote == nil) {
    return nil;
  }
  GCHostingService fromService;
  NSURL* fromURL = [self _projectHostingURLForRemote:fromRemote service:&fromService error:error];
  if (fromURL == nil) {
    return nil;
  }
  
  NSString* toName;
  GCRemote* toRemote = [self lookupRemoteForRemoteBranch:toBranch sourceBranchName:&toName error:error];
  if (toRemote == nil) {
    return nil;
  }
  GCHostingService toService;
  NSURL* toURL = [self _projectHostingURLForRemote:toRemote service:&toService error:error];
  if (toURL == nil) {
    return nil;
  }
  
  if (fromService != toService) {
    GC_SET_GENERIC_ERROR(@"Branches are on different hosting services");
    return nil;
  }
  
  NSURL* url = nil;
  switch (fromService) {
    
    case kGCHostingService_GitHub:
      url = [NSURL URLWithString:[toURL.absoluteString stringByAppendingFormat:@"/compare/%@...%@:%@?expand=1", toName, fromURL.path.pathComponents[1], fromName]];  // Using relative URLs doesn't work
      break;
    
    case kGCHostingService_BitBucket:
      url = [NSURL URLWithString:[fromURL.absoluteString stringByAppendingFormat:@"/pull-request/new?source=%@%%3A%%3A%@&dest=%@%%3A%%3A%@", [fromURL.path substringFromIndex:1], fromName, [toURL.path substringFromIndex:1], toName]];  // Using relative URLs doesn't work
      break;
    
    case kGCHostingService_GitLab:
      if (![toURL.path isEqualToString:fromURL.path]) {
        GC_SET_GENERIC_ERROR(@"Branches for GitLab merge request are not in the same project");  // TODO: GitLab supports cross-project merge requests but we need to know the project IDs
        return nil;
      }
      url = [NSURL URLWithString:[fromURL.absoluteString stringByAppendingFormat:@"/merge_requests/new?merge_request%%5Bsource_branch%%5D=%@&merge_request%%5Btarget_branch%%5D=%@", fromName, toName]];  // Using relative URLs doesn't work
      break;
    
    case kGCHostingService_Unknown:
      XLOG_DEBUG_UNREACHABLE();
      break;
    
  }
  if (service) {
    *service = fromService;
  }
  return url;
}

- (BOOL)safeDeleteFileIfExists:(NSString*)path error:(NSError**)error {
  return ![[NSFileManager defaultManager] fileExistsAtPath:[self absolutePathForFile:path]] || [self safeDeleteFile:path error:error];
}

- (NSMutableDictionary*)_readUserInfo {
  NSMutableDictionary* dictionary = objc_getAssociatedObject(self, _associatedObjectKey);
  if (dictionary == nil) {
    dictionary = [[NSMutableDictionary alloc] init];
    objc_setAssociatedObject(self, _associatedObjectKey, dictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    NSString* path = [self.privateAppDirectoryPath stringByAppendingPathComponent:kUserInfoFileName];
    if (path) {
      NSData* data = [NSData dataWithContentsOfFile:path];
      if (data) {
        NSError* error;
        NSDictionary* plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
        if (plist) {
          [dictionary addEntriesFromDictionary:plist];
        } else {
          XLOG_ERROR(@"Failed reading user info for repository \"%@\": %@", self.repositoryPath, error);
        }
      }
    }
  }
  return dictionary;
}

- (void)_writeUserInfo {
  NSMutableDictionary* dictionary = objc_getAssociatedObject(self, _associatedObjectKey);
  NSString* path = [self.privateAppDirectoryPath stringByAppendingPathComponent:kUserInfoFileName];
  if (path) {
    NSError* error;
    NSData* data = [NSPropertyListSerialization dataWithPropertyList:dictionary format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
      XLOG_ERROR(@"Failed writing user info for repository \"%@\": %@", self.repositoryPath, error);
    }
  }
}

- (void)setUserInfo:(id)info forKey:(NSString*)key {
  [[self _readUserInfo] setValue:info forKey:key];
  [self _writeUserInfo];
}

- (id)userInfoForKey:(NSString*)key {
  return [[self _readUserInfo] objectForKey:key];
}

@end
