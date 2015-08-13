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

@implementation GCTagAnnotation

@dynamic private;

- (instancetype)initWithRepository:(GCRepository*)repository tag:(git_tag*)tag {
  return [self initWithRepository:repository object:(git_object*)tag];
}

- (NSString*)name {
  const char* name = git_tag_name((git_tag*)_private);
  return [[NSString alloc] initWithBytesNoCopy:(void*)name length:strlen(name) encoding:NSUTF8StringEncoding freeWhenDone:NO];
}

- (NSString*)message {
  const char* message = git_tag_message((git_tag*)_private);
  return [[NSString alloc] initWithBytesNoCopy:(void*)message length:strlen(message) encoding:NSUTF8StringEncoding freeWhenDone:NO];
}

- (NSString*)tagger {
  return GCUserFromSignature(git_tag_tagger((git_tag*)_private));
}

- (NSString*)description {
  NSString* message = [self.message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];  // Trim ending newline
  return [NSString stringWithFormat:@"[%@] '%@' %@ '%@%@'", self.class,
          self.shortSHA1,
          [[self.tagger componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] firstObject],
          message.length > kTruncatedDescriptionThreshold ? [message substringToIndex:kTruncatedDescriptionThreshold] : message,
          message.length > kTruncatedDescriptionThreshold ? @"..." : @""];
}

@end

@implementation GCTagAnnotation (Extensions)

- (BOOL)isEqualToTagAnnotation:(GCTagAnnotation*)annotation {
  return [self isEqualToObject:annotation];
}

@end

@implementation GCTag

#if DEBUG

- (void)updateReference:(git_reference*)reference {
  XLOG_DEBUG_CHECK(git_reference_is_tag(reference));
  XLOG_DEBUG_CHECK(git_reference_type(reference) == GIT_REF_OID);
  [super updateReference:reference];
}

#endif

@end

@implementation GCTag (Extensions)

- (BOOL)isEqualToTag:(GCTag*)tag {
  return [self isEqualToReference:tag];
}

@end

@implementation GCRepository (GCTag)

+ (BOOL)isValidTagName:(NSString*)name {
  return (git_reference_is_valid_name([[@kTagsNamespace stringByAppendingString:name] UTF8String]) == 1);
}

#pragma mark - Browsing

- (GCTag*)findTagWithName:(NSString*)name error:(NSError**)error {
  return [self findReferenceWithFullName:[@kTagsNamespace stringByAppendingString:name] class:[GCTag class] error:error];
}

- (NSArray*)listTags:(NSError**)error {
  NSMutableArray* array = [[NSMutableArray alloc] init];
  BOOL success = [self enumerateReferencesWithOptions:kGCReferenceEnumerationOption_RetainReferences error:error usingBlock:^BOOL(git_reference* reference) {
    
    if (git_reference_is_tag(reference)) {
      GCTag* tag = [[GCTag alloc] initWithRepository:self reference:reference];
      [array addObject:tag];
    } else {
      git_reference_free(reference);
    }
    return YES;
    
  }];
  return success ? array : nil;
}

#pragma mark - Utilities

- (GCCommit*)lookupCommitForTag:(GCTag*)tag annotation:(GCTagAnnotation**)annotation error:(NSError**)error {
  git_object* object = NULL;
  GCCommit* commit = nil;
  
  if (![self refreshReference:tag error:error]) {
    goto cleanup;
  }
  git_oid oid;
  if (![self loadTargetOID:&oid fromReference:tag.private error:error]) {
    goto cleanup;
  }
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_object_lookup, &object, self.private, &oid, GIT_OBJ_ANY);
  if (git_object_type(object) == GIT_OBJ_COMMIT) {
    commit = [[GCCommit alloc] initWithRepository:self commit:(git_commit*)object];
    object = NULL;
    if (annotation) {
      *annotation = nil;
    }
  } else if (git_object_type(object) == GIT_OBJ_TAG) {
    git_object* peeledObject;
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_object_peel, &peeledObject, object, GIT_OBJ_COMMIT);
    commit = [[GCCommit alloc] initWithRepository:self commit:(git_commit*)peeledObject];
    if (annotation) {
      *annotation = [[GCTagAnnotation alloc] initWithRepository:self tag:(git_tag*)object];
      object = NULL;
    }
  } else {
    XLOG_DEBUG_UNREACHABLE();
    GC_SET_GENERIC_ERROR(@"Unexpected reference target");
  }
  
cleanup:
  git_object_free(object);
  return commit;
}

#pragma mark - Editing

- (GCTag*)_createTagReference:(const git_oid*)oid name:(NSString*)name force:(BOOL)force error:(NSError**)error {
  const char* refName = [[@kTagsNamespace stringByAppendingString:name] UTF8String];
  git_reference* reference;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_reference_create, &reference, self.private, refName, oid, force, NULL);  // Use default reflog message for tag references
  return [[GCTag alloc] initWithRepository:self reference:reference];
}

// Re-implementation of git_tag_create_lightweight()
- (GCTag*)createLightweightTagWithCommit:(GCCommit*)commit name:(NSString*)name force:(BOOL)force error:(NSError**)error {
  return [self _createTagReference:git_commit_id(commit.private) name:name force:force error:error];
}

- (GCTag*)createAnnotatedTagWithAnnotation:(GCTagAnnotation*)annotation force:(BOOL)force error:(NSError**)error {
  return [self _createTagReference:git_tag_id(annotation.private) name:annotation.name force:force error:error];
}

// Re-implementation of git_tag_create()
- (GCTag*)createAnnotatedTagWithCommit:(GCCommit*)commit name:(NSString*)name message:(NSString*)message force:(BOOL)force annotation:(GCTagAnnotation**)annotation error:(NSError**)error {
  if (message.length == 0) {
    GC_SET_GENERIC_ERROR(@"Message cannot be an empty string");
    return nil;
  }
  
  git_oid oid;
  git_signature* signature;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_signature_default, &signature, self.private);
  int status = git_tag_annotation_create(&oid, self.private, name.UTF8String, (git_object*)commit.private, signature, GCCleanedUpCommitMessage(message).bytes);  // Use default signature - This uses the tag name not reference name
  git_signature_free(signature);
  CHECK_LIBGIT2_FUNCTION_CALL(return nil, status, == GIT_OK);
  git_tag* object;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_tag_lookup, &object, self.private, &oid);
  GCTag* tag = [self _createTagReference:&oid name:name force:force error:error];
  if (annotation) {
    *annotation = [[GCTagAnnotation alloc] initWithRepository:self tag:object];
  } else {
    git_tag_free(object);
  }
  return tag;
}

// Contrary to branches, tags don't carry extra metadata so we can use git_reference_rename()
- (BOOL)setName:(NSString*)name forTag:(GCTag*)tag force:(BOOL)force error:(NSError**)error {
  const char* refName = [[@kTagsNamespace stringByAppendingString:name] UTF8String];
  git_reference* reference;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_reference_rename, &reference, tag.private, refName, force, NULL);  // Use default reflog message for tag reference renames
  [tag updateReference:reference];
  return YES;  // No need to deal with reflog since we are updating a tag
}

// Re-implementation of git_tag_delete()
- (BOOL)deleteTag:(GCTag*)tag error:(NSError**)error {
  if (![self refreshReference:tag error:error]) {  // Works around "old reference value does not match" errors if underlying reference is out of sync
    return NO;
  }
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_reference_delete, tag.private);
  return YES;
}

@end
