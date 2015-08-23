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

#define kMaxReferenceNestingLevels 10  // Same as MAX_NESTING_LEVEL in libgit2 source

@implementation GCReference {
  __unsafe_unretained GCRepository* _repository;
}

- (instancetype)initWithRepository:(GCRepository*)repository reference:(git_reference*)reference {
  if ((self = [super init])) {
    _repository = repository;
    [self updateReference:reference];
  }
  return self;
}

- (void)dealloc {
  git_reference_free(_private);
}

- (void)updateReference:(git_reference*)reference {
  git_reference_free(_private);
  _private = reference;
  _fullName = [NSString stringWithUTF8String:git_reference_name(reference)];
  _name = [NSString stringWithUTF8String:git_reference_shorthand(reference)];
}

- (BOOL)isSymbolic {
  return (git_reference_type(_private) == GIT_REF_SYMBOLIC);
}

- (NSComparisonResult)compareWithReference:(git_reference*)reference {
  return strcmp(git_reference_name(_private), git_reference_name(reference));
}

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@] %@ (%@)", self.class, _fullName, _name];
}

@end

@implementation GCReference (Extensions)

- (NSUInteger)hash {
  return _name.hash;
}

- (BOOL)isEqualToReference:(GCReference*)reference {
  return (self == reference) || ([self compareWithReference:reference->_private] == NSOrderedSame);
}

- (BOOL)isEqual:(id)object {
  if (![object isKindOfClass:[GCReference class]]) {
    return NO;
  }
  return [self isEqualToReference:object];
}

- (NSComparisonResult)nameCompare:(GCReference*)reference {
  return [_name localizedStandardCompare:reference->_name];
}

@end

@implementation GCRepository (GCReference_Private)

- (id)findReferenceWithFullName:(NSString*)fullname class:(Class)class error:(NSError**)error {
  XLOG_DEBUG_CHECK([class isSubclassOfClass:[GCReference class]]);
  git_reference* reference;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_reference_lookup, &reference, self.private, fullname.UTF8String);
  return [[class alloc] initWithRepository:self reference:reference];
}

- (BOOL)refreshReference:(GCReference*)reference error:(NSError**)error {
  git_reference* newReference;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_reference_lookup, &newReference, self.private, git_reference_name(reference.private));
  [reference updateReference:newReference];
  return YES;
}

- (BOOL)enumerateReferencesWithOptions:(GCReferenceEnumerationOptions)options error:(NSError**)error usingBlock:(BOOL (^)(git_reference* reference))block {
  BOOL success = NO;
  git_reference_iterator* iterator = NULL;
  
  if (options & kGCReferenceEnumerationOption_IncludeHEAD) {
    git_reference* headReference;
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_lookup, &headReference, self.private, kHEADReferenceFullName);
    BOOL result = block(headReference);
    if (!(options & kGCReferenceEnumerationOption_RetainReferences)) {
      git_reference_free(headReference);
    }
    if (!result) {
      goto cleanup;
    }
  }
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_iterator_new, &iterator, self.private);
  while (1) {
    git_reference* reference;
    int status = git_reference_next(&reference, iterator);
    if (status == GIT_ITEROVER) {
      break;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
    BOOL result = block(reference);
    if (!(options & kGCReferenceEnumerationOption_RetainReferences)) {
      git_reference_free(reference);
    }
    if (!result) {
      goto cleanup;
    }
  }
  success = YES;
  
cleanup:
  git_reference_iterator_free(iterator);
  return success;
}

- (BOOL)loadTargetOID:(git_oid*)oid fromReference:(git_reference*)reference error:(NSError**)error  {
  BOOL success = NO;
  git_reference* resolvedReference = reference;
  
  if (git_reference_type(reference) == GIT_REF_SYMBOLIC) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_resolve, &resolvedReference, reference);
  }
  XLOG_DEBUG_CHECK(git_reference_type(resolvedReference) == GIT_REF_OID);
  git_oid_cpy(oid, git_reference_target(resolvedReference));
  success = YES;
  
cleanup:
  if (resolvedReference != reference) {
    git_reference_free(resolvedReference);
  }
  return success;
}

// Reimplementation of the SPI git_reference__update_for_commit()
- (BOOL)setTargetOID:(const git_oid*)oid forReference:(git_reference*)reference reflogMessage:(NSString*)message newReference:(git_reference**)newReference error:(NSError**)error {
  BOOL success = NO;
  NSUInteger level = 0;
  git_reference* currentReference = reference;
  const char* referenceName = NULL;
  git_reference* localNewReference = NULL;
  
  while (1) {
    if (git_reference_type(currentReference) == GIT_REF_OID) {
      referenceName = git_reference_name(currentReference);
      break;
    }
    
    XLOG_DEBUG_CHECK(git_reference_type(currentReference) == GIT_REF_SYMBOLIC);
    const char* targetName = git_reference_symbolic_target(currentReference);
    git_reference* targetReference;
    int status = git_reference_lookup(&targetReference, self.private, targetName);
    if (status == GIT_ENOTFOUND) {
      referenceName = targetName;
      break;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
    if (currentReference != reference) {
      git_reference_free(currentReference);
    }
    currentReference = targetReference;
    
    ++level;
    if (level > kMaxReferenceNestingLevels) {
      GC_SET_GENERIC_ERROR(@"Too many reference nesting levels");
      break;
    }
  }
  if (referenceName) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_create, &localNewReference, self.private, referenceName, oid, true, message.UTF8String);  // This actually calls git_reference_create_matching() passing NULL for "current_id"
    success = YES;
  }
  
cleanup:
  if (success && newReference) {
    *newReference = localNewReference;
    localNewReference = NULL;
  }
  git_reference_free(localNewReference);
  if (currentReference != reference) {
    git_reference_free(currentReference);
  }
  return success;
}

- (GCReference*)createDirectReferenceWithFullName:(NSString*)name target:(GCObject*)target force:(BOOL)force error:(NSError**)error {
  git_reference* reference;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_reference_create, &reference, self.private, name.UTF8String, git_object_id(target.private), force, NULL);
  return [[GCReference alloc] initWithRepository:self reference:reference];
}

- (GCReference*)createSymbolicReferenceWithFullName:(NSString*)name target:(NSString*)target force:(BOOL)force error:(NSError**)error {
  git_reference* reference;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_reference_symbolic_create, &reference, self.private, name.UTF8String, target.UTF8String, force, NULL);
  return [[GCReference alloc] initWithRepository:self reference:reference];
}

@end
