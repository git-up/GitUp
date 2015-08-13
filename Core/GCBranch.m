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

@implementation GCBranch
@end

@implementation GCLocalBranch

#if DEBUG

- (void)updateReference:(git_reference*)reference {
  XLOG_DEBUG_CHECK(git_reference_is_branch(reference));
  [super updateReference:reference];
}

#endif

@end

@implementation GCRemoteBranch

#if DEBUG

- (void)updateReference:(git_reference*)reference {
  XLOG_DEBUG_CHECK(git_reference_is_remote(reference));
  [super updateReference:reference];
}

#endif

@end

@implementation GCBranch (Extensions)

- (BOOL)isEqualToBranch:(GCBranch*)branch {
  return [self isEqualToReference:branch];
}

@end

@implementation GCRemoteBranch (Extensions)

- (NSString*)remoteName {
  NSString* name = self.name;
  NSRange range = [name rangeOfString:@"/"];
  if (range.location == NSNotFound) {
    return nil;
  }
  return [name substringToIndex:range.location];
}

- (NSString*)branchName {
  NSString* name = self.name;
  NSRange range = [name rangeOfString:@"/"];
  if (range.location == NSNotFound) {
    return nil;
  }
  return [name substringFromIndex:(range.location + 1)];
}

@end

@implementation GCRepository (GCBranch)

+ (BOOL)isValidBranchName:(NSString*)name {
  return (git_reference_is_valid_name([[@kHeadsNamespace stringByAppendingString:name] UTF8String]) == 1);
}

#pragma mark - Browsing

- (GCLocalBranch*)findLocalBranchWithName:(NSString*)name error:(NSError**)error {
  return [self findReferenceWithFullName:[@kHeadsNamespace stringByAppendingString:name] class:[GCLocalBranch class] error:error];
}

- (GCRemoteBranch*)findRemoteBranchWithName:(NSString*)name error:(NSError**)error {
  return [self findReferenceWithFullName:[@kRemotesNamespace stringByAppendingString:name] class:[GCRemoteBranch class] error:error];
}

- (NSArray*)_listBranches:(NSError**)error flags:(git_branch_t)flags {
  NSMutableArray* array = [[NSMutableArray alloc] init];
  BOOL success = [self enumerateReferencesWithOptions:kGCReferenceEnumerationOption_RetainReferences error:error usingBlock:^BOOL(git_reference* reference) {
    
    if ((flags & GIT_BRANCH_LOCAL) && git_reference_is_branch(reference)) {
      GCLocalBranch* branch = [[GCLocalBranch alloc] initWithRepository:self reference:reference];
      [array addObject:branch];
    } else if ((flags & GIT_BRANCH_REMOTE) && git_reference_is_remote(reference)) {
      GCRemoteBranch* branch = [[GCRemoteBranch alloc] initWithRepository:self reference:reference];
      [array addObject:branch];
    } else {
      git_reference_free(reference);
    }
    return YES;
    
  }];
  return success ? array : nil;
}

- (NSArray*)listLocalBranches:(NSError**)error {
  return [self _listBranches:error flags:GIT_BRANCH_LOCAL];
}

- (NSArray*)listRemoteBranches:(NSError**)error {
  return [self _listBranches:error flags:GIT_BRANCH_REMOTE];
}

- (NSArray*)listAllBranches:(NSError**)error {
  return [self _listBranches:error flags:GIT_BRANCH_ALL];
}

#pragma mark - Utilities

- (GCCommit*)lookupTipCommitForBranch:(GCBranch*)branch error:(NSError**)error {
  if (![self refreshReference:branch error:error]) {
    return nil;
  }
  git_commit* commit = [self loadCommitFromBranchReference:branch.private error:error];
  return commit ? [[GCCommit alloc] initWithRepository:self commit:commit] : nil;
}

#pragma mark - Editing

- (GCLocalBranch*)createLocalBranchFromCommit:(GCCommit*)commit withName:(NSString*)name force:(BOOL)force error:(NSError**)error {
  git_reference* reference;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_branch_create, &reference, self.private, name.UTF8String, commit.private, force);
  return [[GCLocalBranch alloc] initWithRepository:self reference:reference];
}

- (BOOL)setTipCommit:(GCCommit*)commit forBranch:(GCBranch*)branch reflogMessage:(NSString*)message error:(NSError**)error {
  git_reference* reference;
  if (![self setTargetOID:git_commit_id(commit.private) forReference:branch.private reflogMessage:message newReference:&reference error:error]) {  // TODO: Should we pass a reflog message?
    return NO;
  }
  [branch updateReference:reference];
  return YES;
}

// We have to use the official API instead of directly git_reference_rename() as renaming a branch reference requires a lot of additional bookkeeping
- (BOOL)setName:(NSString*)name forLocalBranch:(GCLocalBranch*)branch force:(BOOL)force error:(NSError**)error {
  git_reference* reference;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_branch_move, &reference, branch.private, name.UTF8String, force);  // This uses git_reference_rename() under the hood
  [branch updateReference:reference];
  return YES;
}

- (BOOL)deleteLocalBranch:(GCLocalBranch*)branch error:(NSError**)error {
  if (![self refreshReference:branch error:error]) {  // Works around "old reference value does not match" errors if underlying reference is out of sync
    return NO;
  }
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_branch_delete, branch.private);  // This uses git_reference_delete() under the hood
  return YES;
}

#pragma mark - Upstream

- (GCBranch*)lookupUpstreamForLocalBranch:(GCLocalBranch*)branch error:(NSError**)error {
  git_reference* upstream;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_branch_upstream, &upstream, branch.private);
  if (git_reference_is_branch(upstream)) {
    return [[GCLocalBranch alloc] initWithRepository:self reference:upstream];
  } else if (git_reference_is_remote(upstream)) {
    return [[GCRemoteBranch alloc] initWithRepository:self reference:upstream];
  }
  git_reference_free(upstream);
  GC_SET_GENERIC_ERROR(@"Unexpected branch upstream");
  XLOG_DEBUG_UNREACHABLE();
  return nil;
}

- (BOOL)setUpstream:(GCBranch*)upstreamBranch forLocalBranch:(GCLocalBranch*)branchBranch error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_branch_set_upstream, branchBranch.private, git_reference_shorthand(upstreamBranch.private));
  return YES;
}

- (BOOL)unsetUpstreamForLocalBranch:(GCLocalBranch*)branchBranch error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_branch_set_upstream, branchBranch.private, NULL);
  return YES;
}

@end

@implementation GCRepository (GCBranch_Private)

- (git_commit*)loadCommitFromBranchReference:(git_reference*)reference error:(NSError**)error {
  git_oid oid;
  if (![self loadTargetOID:&oid fromReference:reference error:error]) {
    return nil;
  }
  git_commit* commit;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_lookup, &commit, self.private, &oid);
  return commit;
}

@end
