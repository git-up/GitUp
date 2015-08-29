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

@implementation GCRepository (Mock)

static const git_oid* _CommitParentCallback(size_t idx, void* payload) {
  void** params = (void**)payload;
  CFDictionaryRef commits = params[0];
  NSArray* parents = (__bridge NSArray*)params[1];
  if (idx < parents.count) {
    GCCommit* commit = CFDictionaryGetValue(commits, (__bridge void*)parents[idx]);
    XLOG_DEBUG_CHECK(commit);
    return git_commit_id(commit.private);
  }
  return NULL;
}

- (NSArray*)createMockCommitHierarchyFromNotation:(NSString*)notation force:(BOOL)force error:(NSError**)error {
  BOOL success = NO;
  NSMutableArray* commits = [[NSMutableArray alloc] init];
  CFMutableDictionaryRef cache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, NULL);
  git_signature* signature = NULL;
  git_treebuilder* builder = NULL;
  git_oid treeOID;
  
  // Create empty tree
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_treebuilder_new, &builder, self.private, NULL);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_treebuilder_write, &treeOID, builder);
  
  // Parse notation lines
  for (NSString* line in [notation componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
    if (!line.length || ([line characterAtIndex:0] == '#')) {
      continue;
    }
    NSScanner* scanner = [[NSScanner alloc] initWithString:line];
    scanner.charactersToBeSkipped = nil;
    while (1) {
      [scanner scanUpToCharactersFromSet:[NSCharacterSet alphanumericCharacterSet] intoString:NULL];
      NSString* string;
      if (![scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&string]) {
        break;
      }
      
      // Parse commit description
      NSString* message = nil;
      NSString* tag = nil;
      NSString* localBranch = nil;
      NSString* remoteBranch = nil;
      NSMutableArray* parents = [[NSMutableArray alloc] init];
      NSRange range = [string rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
      if (range.location != NSNotFound) {
        message = [string substringToIndex:range.location];
        NSUInteger index = range.location;
        while (index < string.length) {
          switch ([string characterAtIndex:index]) {
            
            // Parents
            case '(': {
              range = [string rangeOfString:@")" options:0 range:NSMakeRange(index, string.length - index)];
              if (range.location == NSNotFound) {
                GC_SET_GENERIC_ERROR(@"Missing closing token");
                goto cleanup;
              }
              for (NSString* parent in [[string substringWithRange:NSMakeRange(index + 1, range.location - index - 1)] componentsSeparatedByString:@","]) {
                [parents addObject:[parent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
              }
              index = range.location + range.length;
              break;
            }
            
            // Tag
            case '{': {
              range = [string rangeOfString:@"}" options:0 range:NSMakeRange(index, string.length - index)];
              if (range.location == NSNotFound) {
                GC_SET_GENERIC_ERROR(@"Missing closing token");
                goto cleanup;
              }
              tag = [string substringWithRange:NSMakeRange(index + 1, range.location - index - 1)];
              index = range.location + range.length;
              break;
            }
            
            // Local branch
            case '<': {
              range = [string rangeOfString:@">" options:0 range:NSMakeRange(index, string.length - index)];
              if (range.location == NSNotFound) {
                GC_SET_GENERIC_ERROR(@"Missing closing token");
                goto cleanup;
              }
              localBranch = [string substringWithRange:NSMakeRange(index + 1, range.location - index - 1)];
              index = range.location + range.length;
              break;
            }
            
            // Remote branch
            case '[': {
              range = [string rangeOfString:@"]" options:0 range:NSMakeRange(index, string.length - index)];
              if (range.location == NSNotFound) {
                GC_SET_GENERIC_ERROR(@"Missing closing token");
                goto cleanup;
              }
              remoteBranch = [string substringWithRange:NSMakeRange(index + 1, range.location - index - 1)];
              index = range.location + range.length;
              break;
            }
            
            default: {
              XLOG_DEBUG_UNREACHABLE();
              GC_SET_GENERIC_ERROR(@"Invalid token");
              goto cleanup;
            }
            
          }
        }
      } else {
        message = string;
      }
      if (!parents.count) {
        range = [message rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]];
        if (range.location != NSNotFound) {
          NSInteger index = [[message substringFromIndex:range.location] integerValue];
          if (index) {
            [parents addObject:[NSString stringWithFormat:@"%@%li", [message substringToIndex:range.location], (long)(index - 1)]];
          }
        }
      }
      
      // Create commit with empty tree
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_signature_new, &signature, "user", "user@domain.com", NSTimeIntervalSince1970 + commits.count, 0);
      git_oid oid;
      void* params[] = {cache, (__bridge void*)parents};
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_create_from_callback, &oid, self.private, NULL, signature, signature, NULL, message.UTF8String, &treeOID, _CommitParentCallback, params);
      git_signature_free(signature);
      signature = NULL;
      git_commit* emptyCommit;
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &emptyCommit, self.private, &oid);
      GCCommit* commit = [[GCCommit alloc] initWithRepository:self commit:emptyCommit];
      [commits addObject:commit];
      XLOG_DEBUG_CHECK(!CFDictionaryContainsValue(cache, (__bridge const void*)message));
      CFDictionarySetValue(cache, (__bridge const void*)message, (__bridge const void*)commit);
      
      // Create lightweight tag if necessary
      if (tag) {
        const char* refName = [[@kTagsNamespace stringByAppendingString:tag] UTF8String];
        git_reference* reference;
        CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_create, &reference, self.private, refName, &oid, force, NULL);
        git_reference_free(reference);
      }
      
      // Create local branch if necessary
      if (localBranch) {
        const char* refName = [[@kHeadsNamespace stringByAppendingString:localBranch] UTF8String];
        git_reference* reference;
        CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_create, &reference, self.private, refName, &oid, force, NULL);
        git_reference_free(reference);
      }
      
      // Create remote branch if necessary
      if (remoteBranch) {
        const char* refName = [[@kRemotesNamespace stringByAppendingString:remoteBranch] UTF8String];
        git_reference* reference;
        CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_create, &reference, self.private, refName, &oid, force, NULL);
        git_reference_free(reference);
      }
    }
  }
  success = YES;
  
cleanup:
  git_treebuilder_free(builder);
  git_signature_free(signature);
  CFRelease(cache);
  return success ? commits : nil;
}

@end

@implementation GCHistory (Mock)

- (NSString*)notationFromMockCommitHierarchy {
  NSMutableArray* array = [[NSMutableArray alloc] init];
  for (GCHistoryCommit* commit in self.allCommits) {
    NSMutableString* string = [[NSMutableString alloc] init];
    [string appendString:commit.summary];
    
    NSArray* parents = commit.parents;
    if (parents.count) {
      [string appendString:@"("];
      for (NSUInteger i = 0; i < parents.count; ++i) {
        GCHistoryCommit* parent = parents[i];
        if (i > 0) {
          [string appendString:@","];
        }
        [string appendString:parent.summary];
      }
      [string appendString:@")"];
    }
    
    for (GCHistoryTag* tag in commit.tags) {
      [string appendFormat:@"{%@}", tag.name];
    }
    for (GCHistoryLocalBranch* localBranch in commit.localBranches) {
      [string appendFormat:@"<%@>", localBranch.name];
    }
    for (GCHistoryRemoteBranch* remoteBranch in commit.remoteBranches) {
      [string appendFormat:@"[%@]", remoteBranch.name];
    }
    
    [array addObject:string];
  }
  return [[array sortedArrayUsingSelector:@selector(localizedStandardCompare:)] componentsJoinedByString:@" "];
}

// TODO: Should we optimize this?
- (GCHistoryCommit*)mockCommitWithName:(NSString*)name {
  for (GCHistoryCommit* commit in self.allCommits) {
    if ([commit.summary isEqualToString:name]) {
      return commit;
    }
  }
  return nil;
}

@end

