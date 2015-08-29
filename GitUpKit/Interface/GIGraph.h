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

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class GCHistory, GCHistoryCommit, GILayer, GINode;

typedef NS_OPTIONS(NSUInteger, GIGraphOptions) {
  kGIGraphOption_ShowVirtualTips = (1 << 0),
  kGIGraphOption_SkipStaleBranchTips = (1 << 1),
  kGIGraphOption_SkipStandaloneTagTips = (1 << 2),
  kGIGraphOption_SkipStandaloneRemoteBranchTips = (1 << 3),
  kGIGraphOption_PreserveUpstreamRemoteBranchTips = (1 << 4)
};

@interface GIGraph : NSObject
- (instancetype)initWithHistory:(GCHistory*)history options:(GIGraphOptions)options;  // The history sorting order is irrelevant as the graph is generated starting from the leaves
@property(nonatomic, readonly) GCHistory* history;
@property(nonatomic, readonly) GIGraphOptions options;
@property(nonatomic, readonly, getter=isEmpty) BOOL empty;

@property(nonatomic, readonly) NSArray* branches;
@property(nonatomic, readonly) NSArray* layers;
@property(nonatomic, readonly) NSArray* lines;
@property(nonatomic, readonly) NSArray* nodes;

@property(nonatomic, readonly) NSUInteger numberOfDummyNodes;
@property(nonatomic, readonly) NSArray* nodesWithReferences;
@property(nonatomic, readonly) CGSize size;

- (GINode*)nodeForCommit:(GCHistoryCommit*)commit;

- (void)walkMainLineForAncestorsOfNode:(GINode*)node usingBlock:(void (^)(GINode* node, BOOL* stop))block;
- (void)walkAncestorsOfNode:(GINode*)node
            layerBeginBlock:(void (^)(GILayer* layer, BOOL* stop))beginBlock  // May be NULL
             layerNodeBlock:(void (^)(GILayer* layer, GINode* node, BOOL* stop))nodeBlock
              layerEndBlock:(void (^)(GILayer* layer, BOOL* stop))endBlock;  // May be NULL
@end
