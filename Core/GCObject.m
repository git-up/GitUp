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

@implementation GCObject {
  __unsafe_unretained GCRepository* _repository;
  NSString* _sha1;
}

- (instancetype)initWithRepository:(GCRepository*)repository object:(git_object*)object {
  if ((self = [super init])) {
    _repository = repository;
    _private = object;
  }
  return self;
}

- (void)dealloc {
  git_object_free(_private);
}

- (instancetype)copyWithZone:(NSZone*)zone {
  return self;
}

- (NSString*)SHA1 {
  if (_sha1 == nil) {
    _sha1 = GCGitOIDToSHA1(git_object_id(_private));
  }
  return _sha1;
}

- (NSString*)shortSHA1 {
  return [self.SHA1 substringToIndex:7];
}

- (NSString*)description {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

@end

@implementation GCObject (Extensions)

- (NSUInteger)hash {
  const git_oid* oid = git_object_id(_private);
  return *((NSUInteger*)oid->id);  // Use the first bytes of the SHA1
}

static inline BOOL _EqualObjects(GCObject* object1, GCObject* object2) {
  return (object1 == object2) || git_oid_equal(git_object_id(object1->_private), git_object_id(object2->_private));
}

- (BOOL)isEqualToObject:(GCObject*)object {
  return _EqualObjects(self, object);
}

- (BOOL)isEqual:(id)object {
  if (![object isKindOfClass:[GCObject class]]) {
    return NO;
  }
  return _EqualObjects(self, object);
}

@end

