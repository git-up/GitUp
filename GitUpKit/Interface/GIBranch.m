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

@implementation GIBranch

- (GINode*)tipNode {
  return _mainLine.nodes[0];
}

- (NSArray*)localBranches {
  return self.tipNode.commit.localBranches;
}

- (NSArray*)remoteBranches {
  return self.tipNode.commit.remoteBranches;
}

- (NSArray*)tags {
  return self.tipNode.commit.tags;
}

- (GIBranch*)parentBranch {
  GINode* lastNode = _mainLine.nodes.lastObject;
  GIBranch* branch = lastNode.primaryLine.branch;
  return (branch != self ? branch : nil);
}

- (NSString*)description {
  GINode* firstNode = _mainLine.nodes.firstObject;
  GINode* lastNode = _mainLine.nodes.lastObject;
  GCHistoryCommit* tipCommit = self.tipNode.commit;
  return [NSString stringWithFormat:@"[%@] Range=%lu-%lu TIP=%@", self.class, (unsigned long)firstNode.layer.index, (unsigned long)lastNode.layer.index, tipCommit];
}

@end
