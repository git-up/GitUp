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

@implementation GILine {
  GIBranch* _branch;
  CFMutableArrayRef _nodes;
}

- (instancetype)initWithBranch:(GIBranch*)branch {
  if ((self = [super init])) {
    _branch = branch;
    
    _nodes = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
  }
  return self;
}

- (void)dealloc {
#if __GI_HAS_APPKIT__
  [_color release];
#endif
  CFRelease(_nodes);
  
  [super dealloc];
}

- (NSArray*)nodes {
  return (NSArray*)_nodes;
}

- (void)addNode:(GINode*)node {
  CFArrayAppendValue(_nodes, (const void*)node);
}

- (BOOL)isVirtual {
  GINode* firstNode = self.nodes.firstObject;
  return firstNode.dummy;
}

- (GILine*)childLine {
  GINode* firstNode = self.nodes.firstObject;
  GILine* line = firstNode.primaryLine;
  return (line != self ? line : nil);
}

- (GILine*)parentLine {
  GINode* lastNode = self.nodes.lastObject;
  GILine* line = lastNode.primaryLine;
  return (line != self ? line : nil);
}

- (BOOL)isBranchMainLine {
  return (_branch.mainLine == self);
}

- (NSString*)description {
  GINode* firstNode = self.nodes.firstObject;
  GINode* lastNode = self.nodes.lastObject;
  return [NSString stringWithFormat:@"[%@] Range=%lu-%lu Nodes=%lu", self.class, (unsigned long)firstNode.layer.index, (unsigned long)lastNode.layer.index, (unsigned long)self.nodes.count];
}

@end
