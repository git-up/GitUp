//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
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

#import "GCPrivate.h"

// SPIs from libgit2
extern int git_reference__is_branch(const char* ref_name);
extern int git_reference__is_remote(const char* ref_name);
extern int git_reference__is_tag(const char* ref_name);

@interface GCSnapshot ()
@property(nonatomic, readonly) CFMutableDictionaryRef cache;
@end

static inline NSData* _NSDataFromCString(const char* string) {
  return [NSData dataWithBytes:string length:(strlen(string) + 1)];
}

static inline const char* _NSDataToCString(NSData* data) {
  return data.bytes;
}

static inline BOOL _ShouldSkipReference(const char* referenceFullName, GCSnapshotOptions options) {
  if (!strcmp(referenceFullName, kHEADReferenceFullName)) {
    return options & kGCSnapshotOption_IncludeHEAD ? NO : YES;
  }
  if (git_reference__is_branch(referenceFullName)) {
    return options & kGCSnapshotOption_IncludeLocalBranches ? NO : YES;
  }
  if (git_reference__is_remote(referenceFullName)) {
    return options & kGCSnapshotOption_IncludeRemoteBranches ? NO : YES;
  }
  if (git_reference__is_tag(referenceFullName)) {
    return options & kGCSnapshotOption_IncludeTags ? NO : YES;
  }
  return options & kGCSnapshotOption_IncludeOthers ? NO : YES;
}

static BOOL _CompareSerializedReferences(GCSerializedReference* serializedReference1, GCSerializedReference* serializedReference2) {
  switch (serializedReference1.type) {
    case GIT_REF_OID: {
      if ((serializedReference2.type != GIT_REF_OID) || !git_oid_equal(serializedReference2.directTarget, serializedReference1.directTarget)) {
        return NO;
      }
      break;
    }

    case GIT_REF_SYMBOLIC: {
      if ((serializedReference2.type != GIT_REF_SYMBOLIC) || strcmp(serializedReference2.symbolicTarget, serializedReference1.symbolicTarget)) {
        return NO;
      }
      break;
    }

    default:
      XLOG_DEBUG_UNREACHABLE();
      return NO;
  }
  return YES;
}

@implementation GCSerializedReference {
  NSData* _name;
  git_oid _OID;
  NSData* _symbol;
  git_otype _resolvedType;
  git_oid _resolvedOID;
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (id)initWithReference:(git_reference*)reference resolvedObject:(git_object*)object {
  if ((self = [super init])) {
    _name = _NSDataFromCString(git_reference_name(reference));
    _type = git_reference_type(reference);
    switch (_type) {
      case GIT_REF_OID: {
        git_oid_cpy(&_OID, git_reference_target(reference));
        XLOG_DEBUG_CHECK(!git_oid_iszero(&_OID));
        break;
      }

      case GIT_REF_SYMBOLIC: {
        _symbol = _NSDataFromCString(git_reference_symbolic_target(reference));
        XLOG_DEBUG_CHECK(_symbol.length);
        break;
      }

      default: {
        XLOG_DEBUG_UNREACHABLE();
        return nil;
      }
    }
    if (object) {
      XLOG_DEBUG_CHECK((_type == GIT_REF_SYMBOLIC) || git_oid_equal(git_object_id(object), &_OID));
      _resolvedType = git_object_type(object);
      XLOG_DEBUG_CHECK(_resolvedType != GIT_OBJ_BAD);
      git_oid_cpy(&_resolvedOID, git_object_id(object));
    } else {
      _resolvedType = GIT_OBJ_BAD;
    }
  }
  return self;
}

- (void)dealloc {
  _symbol = nil;
  _name = nil;
}

- (void)encodeWithCoder:(NSCoder*)coder {
  [coder encodeObject:_name forKey:@"name"];
  [coder encodeInt:_type forKey:@"type"];
  [coder encodeBytes:(const uint8_t*)&_OID length:sizeof(git_oid) forKey:@"oid"];
  [coder encodeObject:_symbol forKey:@"symbol"];
  [coder encodeInt:_resolvedType forKey:@"resolved_type"];
  [coder encodeBytes:(const uint8_t*)&_resolvedOID length:sizeof(git_oid) forKey:@"resolved_oid"];
}

- (id)initWithCoder:(NSCoder*)decoder {
  if ((self = [super init])) {
    _name = [decoder decodeObjectOfClass:[NSData class] forKey:@"name"];
    XLOG_DEBUG_CHECK(_name);
    _type = [decoder decodeIntForKey:@"type"];
    XLOG_DEBUG_CHECK((_type == GIT_REF_OID) || (_type == GIT_REF_SYMBOLIC));

    NSUInteger length1;
    const uint8_t* bytes1 = [decoder decodeBytesForKey:@"oid" returnedLength:&length1];
    if (bytes1 && (length1 == sizeof(git_oid))) {
      bcopy(bytes1, &_OID, sizeof(git_oid));
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }

    _symbol = [decoder decodeObjectOfClass:[NSData class] forKey:@"symbol"];

    _resolvedType = [decoder decodeIntForKey:@"resolved_type"];

    NSUInteger length2;
    const uint8_t* bytes2 = [decoder decodeBytesForKey:@"resolved_oid" returnedLength:&length2];
    if (bytes2 && (length2 == sizeof(git_oid))) {
      bcopy(bytes2, &_resolvedOID, sizeof(git_oid));
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }

    XLOG_DEBUG_CHECK(_symbol || (_type != GIT_REF_SYMBOLIC));
  }
  return self;
}

- (const char*)name {
  return _NSDataToCString(_name);
}

// Unfortunate reimplementation of git_reference_shorthand()
- (const char*)shortHand {
  const char* name = _NSDataToCString(_name);
  if (!strncmp(name, kHeadsNamespace, sizeof(kHeadsNamespace) - 1)) {
    return &name[sizeof(kHeadsNamespace) - 1];
  }
  if (!strncmp(name, kTagsNamespace, sizeof(kTagsNamespace) - 1)) {
    return &name[sizeof(kTagsNamespace) - 1];
  }
  if (!strncmp(name, kRemotesNamespace, sizeof(kRemotesNamespace) - 1)) {
    return &name[sizeof(kRemotesNamespace) - 1];
  }
  if (!strncmp(name, kRefsNamespace, sizeof(kRefsNamespace) - 1)) {
    return &name[sizeof(kRefsNamespace) - 1];
  }
  return name;
}

- (const git_oid*)directTarget {
  return &_OID;
}

- (const char*)symbolicTarget {
  return _NSDataToCString(_symbol);
}

- (const git_oid*)resolvedTarget {
  return git_oid_iszero(&_resolvedOID) ? NULL : &_resolvedOID;
}

- (BOOL)isHEAD {
  return !strcmp(_NSDataToCString(_name), kHEADReferenceFullName);
}

- (BOOL)isLocalBranch {
  return git_reference__is_branch(_NSDataToCString(_name));
}

- (BOOL)isRemoteBranch {
  return git_reference__is_remote(_NSDataToCString(_name));
}

- (BOOL)isTag {
  return git_reference__is_tag(_NSDataToCString(_name));
}

- (NSString*)description {
  return [NSString stringWithFormat:@"%@ %s = %s", self.class, _NSDataToCString(_name), _symbol ? _NSDataToCString(_symbol) : git_oid_tostr_s(&_OID)];
}

@end

@implementation GCSnapshot {
  NSMutableDictionary* _config;
  NSMutableArray* _serializedReferences;
  NSMutableDictionary* _info;
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

// TODO: Handle duplicate config entries for the same variable
static NSMutableDictionary* _LoadRepositoryConfig(GCRepository* repository, NSError** error) {
  NSMutableDictionary* dictionary = [NSMutableDictionary dictionary];
  BOOL success = NO;
  git_config* config1 = NULL;
  git_config* config2 = NULL;
  git_config_iterator* iterator = NULL;

  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_config, &config1, repository.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_open_level, &config2, config1, GIT_CONFIG_LEVEL_LOCAL);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_iterator_new, &iterator, config2);  // This takes a snapshot internally
  while (1) {
    git_config_entry* entry;
    int status = git_config_next(&entry, iterator);
    if (status == GIT_ITEROVER) {
      break;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
    [dictionary setObject:[NSString stringWithUTF8String:entry->value] forKey:[NSString stringWithUTF8String:entry->name]];
  }
  success = YES;

cleanup:
  git_config_iterator_free(iterator);
  git_config_free(config1);
  git_config_free(config2);
  return success ? dictionary : nil;
}

- (id)initWithRepository:(GCRepository*)repository error:(NSError**)error {
  if ((self = [super init])) {
    // Capture local config
    _config = _LoadRepositoryConfig(repository, error);
    if (_config == nil) {
      return nil;
    }

    // Capture all references
    _serializedReferences = [[NSMutableArray alloc] init];
    CFDictionaryKeyCallBacks callbacks = {0, NULL, NULL, NULL, GCCStringEqualCallBack, GCCStringHashCallBack};
    _cache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &callbacks, NULL);
    BOOL success = [repository enumerateReferencesWithOptions:kGCReferenceEnumerationOption_IncludeHEAD
                                                        error:error
                                                   usingBlock:^BOOL(git_reference* reference) {
                                                     git_object* object = NULL;
                                                     git_oid oid;
                                                     if ([repository loadTargetOID:&oid fromReference:reference error:NULL]) {  // Ignore errors since repositories can have invalid references
                                                       int status = git_object_lookup(&object, repository.private, &oid, GIT_OBJ_ANY);
                                                       if (status != GIT_OK) {
                                                         LOG_LIBGIT2_ERROR(status);  // Ignore errors since repositories can have invalid references
                                                       }
                                                     }

                                                     GCSerializedReference* serializedReference = [[GCSerializedReference alloc] initWithReference:reference resolvedObject:object];
                                                     [_serializedReferences addObject:serializedReference];
                                                     XLOG_DEBUG_CHECK(!CFDictionaryContainsKey(_cache, serializedReference.name));
      CFDictionarySetValue(_cache, serializedReference.name, (__bridge const void *)(serializedReference));

                                                     git_object_free(object);
                                                     return YES;
                                                   }];
    if (!success) {
      return nil;
    }

    _info = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)dealloc {
  CFRelease(_cache);
  _info = nil;
  _serializedReferences = nil;
  _config = nil;
}

- (void)encodeWithCoder:(NSCoder*)coder {
  [coder encodeObject:_config forKey:@"config"];
  [coder encodeObject:_serializedReferences forKey:@"serialized_references"];
  [coder encodeObject:_info forKey:@"info"];
}

- (id)initWithCoder:(NSCoder*)decoder {
  if ((self = [super init])) {
    _config = [decoder decodeObjectOfClass:[NSMutableDictionary class] forKey:@"config"];
    XLOG_DEBUG_CHECK(_config);
    _serializedReferences = [decoder decodeObjectOfClass:[NSMutableArray class] forKey:@"serialized_references"];
    XLOG_DEBUG_CHECK(_serializedReferences);
    _info = [decoder decodeObjectOfClass:[NSMutableDictionary class] forKey:@"info"];
    XLOG_DEBUG_CHECK(_info);

    CFDictionaryKeyCallBacks callbacks = {0, NULL, NULL, NULL, GCCStringEqualCallBack, GCCStringHashCallBack};
    _cache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &callbacks, NULL);
    for (GCSerializedReference* serializedReference in _serializedReferences) {
      XLOG_DEBUG_CHECK(!CFDictionaryContainsKey(_cache, serializedReference.name));
      CFDictionarySetValue(_cache, serializedReference.name, (__bridge const void *)(serializedReference));
    }
  }
  return self;
}

- (GCSerializedReference*)serializedReferenceWithName:(const char*)name {
  return CFDictionaryGetValue(_cache, name);
}

- (NSString*)description {
  NSMutableString* description = [[NSMutableString alloc] initWithFormat:@"%@", self.class];
  for (GCSerializedReference* serializedReference in _serializedReferences) {
    [description appendFormat:@"\n  %s = %s", serializedReference.name, serializedReference.symbolicTarget ? serializedReference.symbolicTarget : git_oid_tostr_s(serializedReference.directTarget)];
  }
  return description;
}

@end

@implementation GCSnapshot (Extensions)

// Mirror implementation of -[GCRepository isEmpty]
- (BOOL)isEmpty {
  BOOL empty = YES;
  GCSerializedReference* headReference = CFDictionaryGetValue(_cache, kHEADReferenceFullName);
  if (headReference == nil) {
    XLOG_DEBUG_UNREACHABLE();
    empty = NO;
  } else if (CFDictionaryGetCount(_cache) > 1) {
    empty = NO;
  } else {
    while (headReference.type == GIT_REF_SYMBOLIC) {
      headReference = CFDictionaryGetValue(_cache, headReference.symbolicTarget);
    }
    if (headReference) {
      empty = NO;
    }
  }
  return empty;
}

- (NSString*)HEADBranchName {
  GCSerializedReference* headReference = CFDictionaryGetValue(_cache, kHEADReferenceFullName);
  if (headReference) {
    if (headReference.type == GIT_REF_SYMBOLIC) {
      GCSerializedReference* branchReference = CFDictionaryGetValue(_cache, headReference.symbolicTarget);
      if (branchReference) {
        XLOG_DEBUG_CHECK(branchReference.type == GIT_REF_OID);
        return [NSString stringWithUTF8String:branchReference.shortHand];
      }
      return nil;  // Unborn HEAD
    }
    return nil;  // Detached HEAD
  }
  XLOG_DEBUG_UNREACHABLE();
  return nil;  // No HEAD
}

- (id)objectForKeyedSubscript:(NSString*)key {
  return [_info objectForKey:key];
}

- (void)setObject:(id)object forKeyedSubscript:(NSString*)key {
  [_info setValue:object forKey:key];
}

static inline BOOL _EqualSnapshots(GCSnapshot* snapshot1, GCSnapshot* snapshot2, GCSnapshotOptions options) {
  if ((options == kGCSnapshotOption_IncludeAll) && (snapshot1->_serializedReferences.count != snapshot2->_serializedReferences.count)) {
    return NO;
  }

  // Make sure all non-skippable references in "self" are in "snapshot" and equal
  for (GCSerializedReference* reference1 in snapshot1->_serializedReferences) {
    if (_ShouldSkipReference(reference1.name, options)) {
      continue;
    }
    GCSerializedReference* reference2 = CFDictionaryGetValue(snapshot2->_cache, reference1.name);
    if (!reference2 || !_CompareSerializedReferences(reference1, reference2)) {
      return NO;
    }
  }

  // Make sure all non-skippable references in "snapshot" are in "self"
  for (GCSerializedReference* reference2 in snapshot2->_serializedReferences) {
    if (_ShouldSkipReference(reference2.name, options)) {
      continue;
    }
    if (!CFDictionaryContainsKey(snapshot1->_cache, reference2.name)) {
      return NO;
    }
  }

  // Make sure branch config variables are the same
  if (options & kGCSnapshotOption_IncludeLocalBranches) {
    for (NSString* variable in snapshot1->_config) {
      if (![variable hasPrefix:@"branch."]) {
        continue;
      }
      NSString* value1 = snapshot1->_config[variable];
      NSString* value2 = snapshot2->_config[variable];
      if (!value2 || ![value1 isEqualToString:value2]) {
        return NO;
      }
    }
    for (NSString* variable in snapshot2->_config) {
      if (![variable hasPrefix:@"branch."]) {
        continue;
      }
      if (!snapshot1->_config[variable]) {
        return NO;
      }
    }
  }

  return YES;
}

- (BOOL)isEqualToSnapshot:(GCSnapshot*)snapshot usingOptions:(GCSnapshotOptions)options {
  return (self == snapshot) || _EqualSnapshots(self, snapshot, options);
}

- (BOOL)isEqual:(id)object {
  if (![object isKindOfClass:[GCSnapshot class]]) {
    return NO;
  }
  return [self isEqualToSnapshot:object usingOptions:kGCSnapshotOption_IncludeAll];
}

@end

@implementation GCRepository (GCSnapshot)

- (GCSnapshot*)takeSnapshot:(NSError**)error {
  return [[GCSnapshot alloc] initWithRepository:self error:error];
}

static BOOL _UpdateRepositoryConfig(GCRepository* repository, NSDictionary* changes, NSError** error) {
  BOOL success = NO;
  git_config* config1 = NULL;
  git_config* config2 = NULL;

  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_config, &config1, repository.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_open_level, &config2, config1, GIT_CONFIG_LEVEL_LOCAL);
  for (NSString* variable in changes) {
    id value = changes[variable];
    if ([value isEqual:[NSNull null]]) {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_delete_entry, config2, variable.UTF8String);
    } else {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_set_string, config2, variable.UTF8String, [value UTF8String]);  // git_config_set_string() is the primitive
    }
  }
  success = YES;

cleanup:
  git_config_free(config1);
  git_config_free(config2);
  return success;
}

static void _DiffConfigsForLocalBranch(const char* name, NSDictionary* fromConfig, NSDictionary* toConfig, NSMutableDictionary* changes) {
  NSString* prefix = [NSString stringWithFormat:@"branch.%s.", name];
  NSMutableDictionary* copy = [[NSMutableDictionary alloc] initWithDictionary:toConfig];

  // Compare variables between "from" and "to"
  for (NSString* fromVariable in fromConfig) {
    if ([fromVariable hasPrefix:prefix]) {
      NSString* fromValue = fromConfig[fromVariable];
      NSString* toValue = toConfig[fromVariable];
      // If variable is present in both "from" and "to", compare both versions and update "from" to "to" if they differ
      if (toValue) {
        if (![toValue isEqualToString:fromValue]) {
          [changes setObject:toValue forKey:fromVariable];
        }
        [copy removeObjectForKey:fromVariable];
      }
      // Otherwise variable is present in "from" but missing from "to" so it needs to be deleted
      else {
        [changes setObject:[NSNull null] forKey:fromVariable];
      }
    }
  }

  // Finally recreate variables present in "to" but missing in "from"
  for (NSString* toVariable in copy) {
    if ([toVariable hasPrefix:prefix]) {
      [changes setObject:copy[toVariable] forKey:toVariable];
    }
  }
}

- (BOOL)_restoreFromReferences:(NSArray*)fromReferences
                     andConfig:(NSDictionary*)config
                    toSnapshot:(GCSnapshot*)toSnapshot
                   withOptions:(GCSnapshotOptions)options
                 reflogMessage:(NSString*)message
           didUpdateReferences:(BOOL*)didUpdateReferences
                         error:(NSError**)error {
  BOOL success = NO;
  GCReferenceTransform* transform = [[GCReferenceTransform alloc] initWithRepository:self reflogMessage:message];
  CFMutableDictionaryRef copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, toSnapshot.cache);
  NSMutableDictionary* changes = [[NSMutableDictionary alloc] init];

  // Compare references between "from" and "to"
  for (GCSerializedReference* fromSerializedReference in fromReferences) {
    if (!_ShouldSkipReference(fromSerializedReference.name, options)) {
      GCSerializedReference* toSerializedReference = [toSnapshot serializedReferenceWithName:fromSerializedReference.name];

      // If reference is present in both "from" and "to", compare both versions and update "from" to "to" if they differ
      if (toSerializedReference) {
        if (!_CompareSerializedReferences(fromSerializedReference, toSerializedReference)) {
          switch (toSerializedReference.type) {
            case GIT_REF_OID:
              [transform setDirectTarget:toSerializedReference.directTarget forReferenceWithName:toSerializedReference.name];
              break;

            case GIT_REF_SYMBOLIC:
              [transform setSymbolicTarget:toSerializedReference.symbolicTarget forReferenceWithName:toSerializedReference.name];
              break;

            default:
              XLOG_DEBUG_UNREACHABLE();
              break;
          }
        }
        if ([toSerializedReference isLocalBranch]) {
          _DiffConfigsForLocalBranch(toSerializedReference.shortHand, config, toSnapshot.config, changes);
        }
        CFDictionaryRemoveValue(copy, toSerializedReference.name);
      }
      // Otherwise reference is present in "from" but missing from "to" so it needs to be deleted
      else {
        [transform deleteReferenceWithName:fromSerializedReference.name];
        if ([fromSerializedReference isLocalBranch]) {
          _DiffConfigsForLocalBranch(fromSerializedReference.shortHand, config, nil, changes);
        }
      }
    }
  }

  // Finally recreate references present in "to" but missing in "from"
  GCDictionaryApplyBlock(copy, ^(const void* key, const void* value) {
    GCSerializedReference* toSerializedReference = (__bridge GCSerializedReference *)value;
    if (!_ShouldSkipReference(toSerializedReference.name, options)) {
      switch (toSerializedReference.type) {
        case GIT_REF_OID:
          [transform setDirectTarget:toSerializedReference.directTarget forReferenceWithName:toSerializedReference.name];
          break;

        case GIT_REF_SYMBOLIC:
          [transform setSymbolicTarget:toSerializedReference.symbolicTarget forReferenceWithName:toSerializedReference.name];
          break;

        default:
          XLOG_DEBUG_UNREACHABLE();
          break;
      }
      if ([toSerializedReference isLocalBranch]) {
        _DiffConfigsForLocalBranch(toSerializedReference.shortHand, nil, toSnapshot.config, changes);
      }
    }
  });

  // Apply transform if necessary
  if (transform.identity) {
    if (didUpdateReferences) {
      *didUpdateReferences = NO;
    }
  } else {
    if (![self applyReferenceTransform:transform error:error]) {
      goto cleanup;
    }
    if (didUpdateReferences) {
      *didUpdateReferences = YES;
    }
  }

  // Update config if necessary
  if (changes.count) {
    _UpdateRepositoryConfig(self, changes, NULL);  // TODO: Should we really ignore errors here?
  }

  // We're done
  success = YES;

cleanup:
  changes = nil;
  CFRelease(copy);
  transform = nil;
  return success;
}

- (BOOL)restoreSnapshot:(GCSnapshot*)snapshot
            withOptions:(GCSnapshotOptions)options
          reflogMessage:(NSString*)message
    didUpdateReferences:(BOOL*)didUpdateReferences
                  error:(NSError**)error {
  NSMutableDictionary* config = _LoadRepositoryConfig(self, error);
  if (config == nil) {
    return NO;
  }
  NSMutableArray* references = [[NSMutableArray alloc] init];
  BOOL result = [self enumerateReferencesWithOptions:kGCReferenceEnumerationOption_IncludeHEAD
                                               error:error
                                          usingBlock:^BOOL(git_reference* reference) {
                                            GCSerializedReference* serializedReference = [[GCSerializedReference alloc] initWithReference:reference resolvedObject:NULL];
                                            [references addObject:serializedReference];
                                            return YES;
                                          }];
  if (result) {
    result = [self _restoreFromReferences:references andConfig:config toSnapshot:snapshot withOptions:options reflogMessage:message didUpdateReferences:didUpdateReferences error:error];
  }
  references = nil;
  return result;
}

- (BOOL)applyDeltaFromSnapshot:(GCSnapshot*)fromSnapshot
                    toSnapshot:(GCSnapshot*)toSnapshot
                   withOptions:(GCSnapshotOptions)options
                 reflogMessage:(NSString*)message
           didUpdateReferences:(BOOL*)didUpdateReferences
                         error:(NSError**)error {
  return [self _restoreFromReferences:fromSnapshot.serializedReferences andConfig:fromSnapshot.config toSnapshot:toSnapshot withOptions:options reflogMessage:message didUpdateReferences:didUpdateReferences error:error];
}

@end
