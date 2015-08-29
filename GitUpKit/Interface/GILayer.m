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

@implementation GILayer {
  CFMutableArrayRef _nodes;
  CFMutableArrayRef _lines;
}

- (instancetype)initWithIndex:(NSUInteger)index {
  if ((self = [super init])) {
    _index = index;
    
    _nodes = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    _lines = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
  }
  return self;
}

- (void)dealloc {
  CFRelease(_lines);
  CFRelease(_nodes);
  
  [super dealloc];
}

- (NSArray*)nodes {
  return (NSArray*)_nodes;
}

- (NSArray*)lines {
  return (NSArray*)_lines;
}

- (void)addNode:(GINode*)node {
  CFArrayAppendValue(_nodes, (const void*)node);
}

- (void)addLine:(GILine*)line {
  CFArrayAppendValue(_lines, (const void*)line);
}

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@] Index=%lu Y=%g Nodes=%lu Lines=%lu", self.class, (unsigned long)_index, _y, (unsigned long)self.nodes.count, (unsigned long)self.lines.count];
}

@end
