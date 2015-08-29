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

#if __has_feature(objc_arc)
#error This file requires MRC
#endif

#import "GIPrivate.h"

@implementation GINode {
  GINode* _mainParent;
  void* _additionalParents;
}

- (instancetype)initWithLayer:(GILayer*)layer primaryLine:(GILine*)line commit:(GCHistoryCommit*)commit dummy:(BOOL)dummy alternateCommit:(GCHistoryCommit*)alternateCommit {
  if ((self = [super init])) {
    _primaryLine = line;
    _layer = layer;
    _commit = [commit retain];
    _dummy = dummy;
    _alternateCommit = [alternateCommit retain];
  }
  return self;
}

- (void)dealloc {
  if (_parentCount > 2) {
    CFRelease(_additionalParents);
  }
  [_alternateCommit release];
  [_commit release];
  
  [super dealloc];
}

- (GINode*)parentAtIndex:(NSUInteger)index {
  XLOG_DEBUG_CHECK(index < _parentCount);
  if (_parentCount == 1) {
    return _mainParent;
  }
  if (_parentCount == 2) {
    return index ? _additionalParents : _mainParent;
  }
  return CFArrayGetValueAtIndex(_additionalParents, index);
}

- (void)addParent:(GINode*)parent {
  if (_parentCount == 0) {
    _mainParent = parent;
  } else if (_parentCount == 1) {
    _additionalParents = parent;
  } else if (_parentCount == 2) {
    CFMutableArrayRef array = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    CFArrayAppendValue(array, _mainParent);
    CFArrayAppendValue(array, _additionalParents);
    CFArrayAppendValue(array, parent);
    _additionalParents = array;
  } else {
    XLOG_DEBUG_CHECK(CFArrayGetCount(_additionalParents) == (CFIndex)_parentCount);
    CFArrayAppendValue(_additionalParents, parent);
  }
  _parentCount += 1;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"%c%04lu%c %@", _dummy ? '(' : ' ', (unsigned long)_layer.index, _dummy ? ')' : ' ', _commit];
}

@end
