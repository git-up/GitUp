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

#define kTruncatedDescriptionThreshold 50

@implementation GCCommit

@dynamic private;

- (instancetype)initWithRepository:(GCRepository*)repository commit:(git_commit*)commit {
  return [self initWithRepository:repository object:(git_object*)commit];
}

// TODO: Handle non-UTF-8 encodings
static inline NSString* _ConvertMessage(GCCommit* commit, const char* message, size_t length, const char* encoding) {
  NSString* string = encoding ? nil : [[NSString alloc] initWithBytesNoCopy:(void*)message length:length encoding:NSUTF8StringEncoding freeWhenDone:NO];  // Indicates UTF-8 if NULL
  if (string == nil) {
    string = [[NSString alloc] initWithBytesNoCopy:(void*)message length:length encoding:NSASCIIStringEncoding freeWhenDone:NO];
    if (string) {
      XLOG_WARNING(@"Using ASCII encoding instead of UTF-8 to interpret message for commit %@", commit.shortSHA1);
    } else {
      XLOG_WARNING(@"Failed interpreting message for commit %@ using ASCII encoding", commit.shortSHA1);
      XLOG_DEBUG_UNREACHABLE();
      string = @"";
    }
  }
  return string;
}

- (NSString*)message {
  const char* message = git_commit_message((git_commit*)_private);  // This already trims leading newlines
  size_t length = strlen(message);
  if (length) {
    while (message[length - 1] == '\n') {  // Trim trailing newlines
      --length;
    }
  } else {
    XLOG_WARNING(@"Empty message for commit %s", git_oid_tostr_s(git_commit_id((git_commit*)_private)));
  }
  return _ConvertMessage(self, message, length, git_commit_message_encoding((git_commit*)_private));
}

- (NSString*)summary {
  const char* summary = git_commit_summary((git_commit*)_private);
  return _ConvertMessage(self, summary, strlen(summary), git_commit_message_encoding((git_commit*)_private));
}

- (NSDate*)date {
  return self.committerDate;
}

// Reimplementation of git_commit_time_offset()
- (NSTimeZone*)timeZone {
  const git_signature* signature = git_commit_committer((git_commit*)_private);
  return [NSTimeZone timeZoneForSecondsFromGMT:(signature->when.offset * 60)];
}

- (NSString*)authorName {
  const git_signature* signature = git_commit_author((git_commit*)_private);
  return [NSString stringWithUTF8String:signature->name];
}

- (NSString*)authorEmail {
  const git_signature* signature = git_commit_author((git_commit*)_private);
  return [NSString stringWithUTF8String:signature->email];
}

- (NSDate*)authorDate {
  const git_signature* signature = git_commit_author((git_commit*)_private);
  return [NSDate dateWithTimeIntervalSince1970:signature->when.time];
}

- (NSString*)committerName {
  const git_signature* signature = git_commit_committer((git_commit*)_private);
  return [NSString stringWithUTF8String:signature->name];
}

- (NSString*)committerEmail {
  const git_signature* signature = git_commit_committer((git_commit*)_private);
  return [NSString stringWithUTF8String:signature->email];
}

// Reimplementation of git_commit_time()
- (NSDate*)committerDate {
  const git_signature* signature = git_commit_committer((git_commit*)_private);
  return [NSDate dateWithTimeIntervalSince1970:signature->when.time];
}

- (NSString*)treeSHA1 {
  return GCGitOIDToSHA1(git_commit_tree_id((git_commit*)_private));
}

- (NSString*)description {
  NSString* summary = self.summary;
  return [NSString stringWithFormat:@"[%@] %@ '%@' %@ '%@%@'", self.class,
          self.shortSHA1,
          self.date,
          [[self.author componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] firstObject],
          summary.length > kTruncatedDescriptionThreshold ? [summary substringToIndex:kTruncatedDescriptionThreshold] : summary,
          summary.length > kTruncatedDescriptionThreshold ? @"..." : @""];
}

@end

@implementation GCCommit (Extensions)

- (NSString*)author {
  return GCUserFromSignature(git_commit_author((git_commit*)_private));
}

- (NSString*)committer {
  return GCUserFromSignature(git_commit_committer((git_commit*)_private));
}

- (NSTimeInterval)timeIntervalSinceReferenceDate {
  const git_signature* signature = git_commit_committer((git_commit*)_private);
  return signature->when.time - NSTimeIntervalSince1970;
}

- (BOOL)isEqualToCommit:(GCCommit*)commit {
  return [self isEqualToObject:commit];
}

static inline NSComparisonResult _TimeCompare(GCCommit* commit1, GCCommit* commit2) {
  XLOG_DEBUG_CHECK(commit1 != commit2);
  git_time_t time1 = git_commit_time((git_commit*)commit1->_private);
  git_time_t time2 = git_commit_time((git_commit*)commit2->_private);
  if (time1 < time2) {
    return NSOrderedAscending;
  } else if (time1 > time2) {
    return NSOrderedDescending;
  }
  const git_oid* oid1 = git_commit_id((git_commit*)commit1->_private);
  const git_oid* oid2 = git_commit_id((git_commit*)commit2->_private);
  return git_oid_cmp(oid1, oid2);  // Ensure stable ordering
}

- (NSComparisonResult)timeCompare:(GCCommit*)commit {
  return _TimeCompare(self, commit);
}

- (NSComparisonResult)reverseTimeCompare:(GCCommit*)commit {
  return _TimeCompare(commit, self);
}

@end

@implementation GCRepository (GCCommit)

- (NSString*)computeUniqueShortSHA1ForCommit:(GCCommit*)commit error:(NSError**)error {
  return [self computeUniqueOIDForCommit:commit.private error:error];
}

- (GCCommit*)findCommitWithSHA1:(NSString*)sha1 error:(NSError**)error {
  git_oid oid;
  if (!GCGitOIDFromSHA1(sha1, &oid, NULL)) {
    return nil;
  }
  git_commit* commit;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_lookup, &commit, self.private, &oid);
  return [[GCCommit alloc] initWithRepository:self commit:commit];
}

- (GCCommit*)findCommitWithSHA1Prefix:(NSString*)prefix error:(NSError**)error {
  size_t length = strlen(prefix.UTF8String);
  XLOG_DEBUG_CHECK(length >= GIT_OID_MINPREFIXLEN);
  git_oid oid;
  if (!GCGitOIDFromSHA1Prefix(prefix, &oid, error)) {
    return nil;
  }
  git_commit* commit;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_lookup_prefix, &commit, self.private, &oid, length);
  return [[GCCommit alloc] initWithRepository:self commit:commit];
}

- (NSArray*)lookupParentsForCommit:(GCCommit*)commit error:(NSError**)error {
  NSMutableArray* array = [[NSMutableArray alloc] init];
  for (unsigned int i = 0, count = git_commit_parentcount(commit.private); i < count; ++i) {
    git_commit* gitCommit;
    CALL_LIBGIT2_FUNCTION_RETURN(nil, git_commit_parent, &gitCommit, commit.private, i);
    GCCommit* parentCommit = [[GCCommit alloc] initWithRepository:self commit:gitCommit];
    [array addObject:parentCommit];
  }
  return array;
}

- (NSString*)checkTreeForCommit:(GCCommit*)commit containsFile:(NSString*)path error:(NSError**)error {
  NSString* sha1 = nil;
  git_tree* tree = NULL;
  git_tree_entry* entry = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_tree, &tree, commit.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_tree_entry_bypath, &entry, tree, GCGitPathFromFileSystemPath(path));
  sha1 = GCGitOIDToSHA1(git_tree_entry_id(entry));
  
cleanup:
  git_tree_entry_free(entry);
  git_tree_free(tree);
  return sha1;
}

@end

@implementation GCRepository (GCCommit_Private)

- (NSString*)computeUniqueOIDForCommit:(git_commit*)commit error:(NSError**)error {
  git_buf buffer = {0};
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_object_short_id, &buffer, (git_object*)commit);
  NSString* string = [NSString stringWithCString:buffer.ptr encoding:NSASCIIStringEncoding];
  git_buf_free(&buffer);
  return string;
}

@end
