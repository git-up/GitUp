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

@implementation GCOrderedSet {
  NSMutableArray* _objects; // Contains all the objects, even removed ones
  CFMutableSetRef _actualObjectHashes; // Objects that were added but have not been removed
  CFMutableSetRef _removedObjectHashes;
}

- (instancetype)init {
  if ((self = [super init])) {
    _objects = [[NSMutableArray alloc] init];
    _actualObjectHashes = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
    _removedObjectHashes = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
  }
  return self;
}

- (void)dealloc {
  CFRelease(_actualObjectHashes);
  CFRelease(_removedObjectHashes);
}

- (void)addObject:(GCObject*)object {
  if (![self containsObject:object]) {
    if (CFSetContainsValue(_removedObjectHashes, (__bridge const void*)(object.SHA1))) {
      CFSetRemoveValue(_removedObjectHashes, (__bridge const void*)(object.SHA1));
    } else {
      [_objects addObject:object];
    }
    CFSetAddValue(_actualObjectHashes, (__bridge const void*)(object.SHA1));
  }
}

- (void)removeObject:(GCObject*)object {
  if ([self containsObject:object]) {
    // Removing object from NSMutableArray is expensive,
    // so we just moving SHA from one set to another.
    CFSetRemoveValue(_actualObjectHashes, (__bridge const void*)(object.SHA1));
    CFSetAddValue(_removedObjectHashes, (__bridge const void*)(object.SHA1));
  }
}

- (BOOL)containsObject:(GCObject*)object {
  return CFSetContainsValue(_actualObjectHashes, (__bridge const void*)(object.SHA1));
}

- (NSArray*)objects {
  NSMutableArray* result = [[NSMutableArray alloc] initWithCapacity:_objects.count];
  for (GCObject* object in _objects) {
    if ([self containsObject:object]) { // Return only objects that were not removed
      [result addObject:object];
    }
  }
  return result;
}

@end
