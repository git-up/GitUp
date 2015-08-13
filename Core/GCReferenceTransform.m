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

typedef struct {
  const char* referenceName;
  const char* targetName;
  git_oid targetOID;
} Operation;

static void _ArrayReleaseCallBack(CFAllocatorRef allocator, const void* value) {
  const Operation* operation = (const Operation*)value;
  free((void*)operation->referenceName);
  if (operation->targetName) {
    free((void*)operation->targetName);
  }
  free((void*)operation);
}

static Boolean _ArrayEqualCallBack(const void* value1, const void* value2) {
  const Operation* operation1 = (const Operation*)value1;
  const Operation* operation2 = (const Operation*)value2;
  return !strcmp(operation1->referenceName, operation2->referenceName);
}

@implementation GCReferenceTransform {
  __unsafe_unretained GCRepository* _repository;
  NSString* _message;
  CFMutableArrayRef _operations;
}

- (instancetype)initWithRepository:(GCRepository*)repository reflogMessage:(NSString*)message {
  if ((self = [super init])) {
    _repository = repository;
    _message = message;
    CFArrayCallBacks callbacks = {0, NULL, _ArrayReleaseCallBack, NULL, _ArrayEqualCallBack};
    _operations = CFArrayCreateMutable(kCFAllocatorDefault, 0, &callbacks);
  }
  return self;
}

- (void)dealloc {
  CFRelease(_operations);
}

- (BOOL)isIdentity {
  return CFArrayGetCount(_operations) == 0;
}

- (void)_addOperation:(Operation*)operation {
  CFIndex index = CFArrayGetFirstIndexOfValue(_operations, CFRangeMake(0, CFArrayGetCount(_operations)), operation);
  if (index == kCFNotFound) {
    CFArrayAppendValue(_operations, operation);
  } else {
    CFArrayReplaceValues(_operations, CFRangeMake(index, 1), (const void**)&operation, 1);
  }
}

- (void)setSymbolicTarget:(const char*)target forReferenceWithName:(const char*)name {
  Operation* operation = calloc(1, sizeof(Operation));
  operation->referenceName = strdup(name);
  operation->targetName = strdup(target);
  [self _addOperation:operation];
}

- (void)setSymbolicTarget:(NSString*)target forReference:(GCReference*)reference {
  [self setSymbolicTarget:target.UTF8String forReferenceWithName:git_reference_name(reference.private)];
}

- (void)setDirectTarget:(const git_oid*)oid forReferenceWithName:(const char*)name {
  Operation* operation = calloc(1, sizeof(Operation));
  operation->referenceName = strdup(name);
  git_oid_cpy(&operation->targetOID, oid);
  [self _addOperation:operation];
}

- (void)setDirectTarget:(GCObject*)target forReference:(GCReference*)reference {
  [self setDirectTarget:git_object_id(target.private) forReferenceWithName:git_reference_name(reference.private)];
}

- (void)deleteReferenceWithName:(const char*)name {
  Operation* operation = calloc(1, sizeof(Operation));
  operation->referenceName = strdup(name);
  [self _addOperation:operation];
}

- (void)deleteReference:(GCReference*)reference {
  [self deleteReferenceWithName:git_reference_name(reference.private)];
}

- (void)setSymbolicTargetForHEAD:(NSString*)target {
  [self setSymbolicTarget:target.UTF8String forReferenceWithName:kHEADReferenceFullName];
}

- (void)setDirectTargetForHEAD:(GCObject*)target {
  [self setDirectTarget:git_object_id(target.private) forReferenceWithName:kHEADReferenceFullName];
}

- (BOOL)apply:(NSError**)error {
  BOOL success = NO;
  git_transaction* transaction = NULL;
  const char* message = _message.UTF8String;
  
  // Apply transform
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_transaction_new, &transaction, _repository.private);
  for (CFIndex i = 0; i < CFArrayGetCount(_operations); ++i) {
    const Operation* operation = CFArrayGetValueAtIndex(_operations, i);
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_transaction_lock_ref, transaction, operation->referenceName);
    if (operation->targetName) {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_transaction_set_symbolic_target, transaction, operation->referenceName, operation->targetName, NULL, message);
    } else if (!git_oid_iszero(&operation->targetOID)) {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_transaction_set_target, transaction, operation->referenceName, &operation->targetOID, NULL, message);
    } else {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_transaction_remove, transaction, operation->referenceName);
    }
  }
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_transaction_commit, transaction);
  success = YES;
  
cleanup:
  git_transaction_free(transaction);
  return success;
}

- (NSString*)description {
  NSMutableString* string = [[NSMutableString alloc] initWithFormat:@"%@ with %li operations", self.class, CFArrayGetCount(_operations)];
  for (CFIndex i = 0; i < CFArrayGetCount(_operations); ++i) {
    const Operation* operation = CFArrayGetValueAtIndex(_operations, i);
    if (operation->targetName) {
      [string appendFormat:@"\n  %s -> %s", operation->referenceName, operation->targetName];
    } else if (!git_oid_iszero(&operation->targetOID)) {
      [string appendFormat:@"\n  %s -> %s", operation->referenceName, git_oid_tostr_s(&operation->targetOID)];
    } else {
      [string appendFormat:@"\n  %s -> (NULL)", operation->referenceName];
    }
  }
  return string;
}

@end

@implementation GCRepository (GCReferenceTransform)

- (BOOL)applyReferenceTransform:(GCReferenceTransform*)transform error:(NSError**)error {
  return [transform apply:error];
}

@end
