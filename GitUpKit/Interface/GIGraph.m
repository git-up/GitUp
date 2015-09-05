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

#if __GI_HAS_APPKIT__
#define __COLORIZE_BRANCHES__ 0
#endif

#define kStaleBranchInterval (60 * 24 * 3600)  // 60 days

#define COMMIT_SKIPPED(c) skipped[c.autoIncrementID]
#define MAP_COMMIT_TO_NODE(c) _mapping[c.autoIncrementID]

@implementation GIGraph {
  GINode** _mapping;
  CFMutableArrayRef _branches;
  CFMutableArrayRef _layers;
  CFMutableArrayRef _lines;
  CFMutableArrayRef _nodes;
  CFMutableArrayRef _nodesWithReferences;
}

static void _ReleaseCallBack(CFAllocatorRef allocator, const void* value) {
  [(id)value release];
}

- (instancetype)initWithHistory:(GCHistory*)history options:(GIGraphOptions)options {
  if ((self = [super init])) {
    _history = [history retain];
    _options = options;
    
    CFArrayCallBacks callbacks = {0, NULL, _ReleaseCallBack, NULL, NULL};
    _branches = CFArrayCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    _layers = CFArrayCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    _lines = CFArrayCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    _nodes = CFArrayCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    _nodesWithReferences = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    _mapping = calloc(_history.nextAutoIncrementID, sizeof(GINode*));
    
    [self _generateGraph];
#if DEBUG
    [self _validateTopology];
#endif
    
    [self _computeNodePositions];
#if __GI_HAS_APPKIT__
    [self _computeNodeAndLineColors];
#endif
#if DEBUG
    [self _validateStyle];
#endif
  }
  return self;
}

- (void)dealloc {
  free(_mapping);
  CFRelease(_nodesWithReferences);
  CFRelease(_nodes);
  CFRelease(_lines);
  CFRelease(_layers);
  CFRelease(_branches);
  
  [_history release];
  
  [super dealloc];
}

- (NSArray*)branches {
  return (NSArray*)_branches;
}

- (NSArray*)layers {
  return (NSArray*)_layers;
}

- (NSArray*)lines {
  return (NSArray*)_lines;
}

- (NSArray*)nodes {
  return (NSArray*)_nodes;
}

- (NSArray*)nodesWithReferences {
  return (NSArray*)_nodesWithReferences;
}

- (BOOL)isEmpty {
  return !CFArrayGetCount(_layers);
}

- (void)_generateGraph {
  NSTimeInterval staleTime = [NSDate timeIntervalSinceReferenceDate] - kStaleBranchInterval;
  GCOrderedSet* tips = [[GCOrderedSet alloc] init];
  NSMutableSet* upstreamTips = [[NSMutableSet alloc] init];
  GC_POINTER_LIST_ALLOCATE(skipList, 32);
  GC_POINTER_LIST_ALLOCATE(newSkipList, 32);
  BOOL* skipped = NULL;
  if (_options & (kGIGraphOption_SkipStaleBranchTips | kGIGraphOption_SkipStandaloneTagTips | kGIGraphOption_SkipStandaloneRemoteBranchTips)) {
    skipped = calloc(_history.nextAutoIncrementID, sizeof(BOOL));
  }
  GCHistoryCommit* headCommit = _history.HEADCommit;
  
  // Add HEAD first to tips
  if (headCommit && (
      ((_options & kGIGraphOption_ShowVirtualTips) && !_history.HEADDetached) ||
      (headCommit.leaf && !headCommit.localBranches && !headCommit.remoteBranches && !headCommit.tags)
    )) {
    [tips addObject:headCommit];
  }
  
  // Add local branches to tips (with their upstreams first if applicable)
  for (GCHistoryLocalBranch* branch in _history.localBranches) {
    if (_options & kGIGraphOption_PreserveUpstreamRemoteBranchTips) {
      GCHistoryCommit* upstreamTip = [(GCHistoryLocalBranch*)branch.upstream tipCommit];
      if (upstreamTip && ((_options & kGIGraphOption_ShowVirtualTips) || upstreamTip.leaf)) {
        [upstreamTips addObject:upstreamTip];
        [tips addObject:upstreamTip];
      }
    }
    
    if (((_options & kGIGraphOption_ShowVirtualTips) || branch.tipCommit.leaf)) {
      [tips addObject:branch.tipCommit];
    }
  }
  
  // Add remote branches to tips
  for (GCHistoryRemoteBranch* branch in _history.remoteBranches) {
    if (((_options & kGIGraphOption_ShowVirtualTips) || branch.tipCommit.leaf)) {
      [tips addObject:branch.tipCommit];
    }
  }
  
  // Add leaf tags
  for (GCHistoryTag* tag in _history.tags) {
    if (tag.commit.leaf) {
      [tips addObject:tag.commit];
    }
  }
  
  // Verify all leaves are included in tips
  XLOG_DEBUG_CHECK([[NSSet setWithArray:_history.leafCommits] isSubsetOfSet:[NSSet setWithArray:tips.objects]]);
  
  // Remove stale branch tips if needed
  if (_options & kGIGraphOption_SkipStaleBranchTips) {
    for (GCHistoryLocalBranch* branch in _history.localBranches) {
      GCHistoryCommit* commit = branch.tipCommit;
      if ((commit.timeIntervalSinceReferenceDate < staleTime) && ![headCommit isEqualToCommit:commit]) {
        [tips removeObject:commit];
        if (commit.leaf && !COMMIT_SKIPPED(commit)) {
          GC_POINTER_LIST_APPEND(skipList, commit);
          COMMIT_SKIPPED(commit) = YES;
        }
      }
    }
    for (GCHistoryLocalBranch* branch in _history.remoteBranches) {
      GCHistoryCommit* commit = branch.tipCommit;
      if ((commit.timeIntervalSinceReferenceDate < staleTime) && ![headCommit isEqualToCommit:commit]) {
        [tips removeObject:commit];
        if (commit.leaf && !COMMIT_SKIPPED(commit)) {
          GC_POINTER_LIST_APPEND(skipList, commit);
          COMMIT_SKIPPED(commit) = YES;
        }
      }
    }
  }
  
  // Remove standalone tag tips if needed
  if (_options & kGIGraphOption_SkipStandaloneTagTips) {
    for (GCHistoryTag* tag in _history.tags) {
      GCHistoryCommit* commit = tag.commit;
      if (commit.leaf && !commit.localBranches && ![headCommit isEqualToCommit:commit]) {
        if (!commit.remoteBranches || (_options & kGIGraphOption_SkipStandaloneRemoteBranchTips)) {
          [tips removeObject:commit];
          if (!COMMIT_SKIPPED(commit)) {
            GC_POINTER_LIST_APPEND(skipList, commit);
            COMMIT_SKIPPED(commit) = YES;
          }
        }
      }
    }
  }
  
  // Remove remote standalone remote branch tips if needed (unless upstream)
  if (_options & kGIGraphOption_SkipStandaloneRemoteBranchTips) {
    for (GCHistoryRemoteBranch* branch in _history.remoteBranches) {
      GCHistoryCommit* commit = branch.tipCommit;
      if (!commit.localBranches && ![headCommit isEqualToCommit:commit]) {
        if (!commit.tags || (_options & kGIGraphOption_SkipStandaloneTagTips)) {
          if (!(_options & kGIGraphOption_PreserveUpstreamRemoteBranchTips) || ![upstreamTips containsObject:commit]) {
            [tips removeObject:commit];
            if (commit.leaf && !COMMIT_SKIPPED(commit)) {
              GC_POINTER_LIST_APPEND(skipList, commit);
              COMMIT_SKIPPED(commit) = YES;
            }
          }
        }
      }
    }
  }
  
  // Walk skipped commits ancestors
  void (^skipBlock)(BOOL) = ^(BOOL updateTips) {
    while (1) {
      // Iterate over commits from list
      GC_POINTER_LIST_FOR_LOOP(skipList, GCHistoryCommit*, commit) {
        for (GCHistoryCommit* parent in commit.parents) {
          // Check if commit was already skipped
          if (COMMIT_SKIPPED(parent)) {
            continue;
          }
          
          // If updating tips, make sure HEAD or references that are not leaves are not skipped
          if (updateTips) {
            XLOG_DEBUG_CHECK(!parent.leaf);
            if ([headCommit isEqualToCommit:parent]) {
              [tips addObject:parent];
              continue;
            }
            if (!(_options & kGIGraphOption_SkipStaleBranchTips) || (parent.timeIntervalSinceReferenceDate >= staleTime)) {
              if (parent.localBranches) {
                BOOL resuscitate = YES;
                for (GCHistoryCommit* child in parent.children) {
                  if (!COMMIT_SKIPPED(child)) {
                    resuscitate = NO;
                    break;
                  }
                }
                if (resuscitate) {
                  [tips addObject:parent];
                  continue;
                }
              }
              if (parent.remoteBranches && !(_options & kGIGraphOption_SkipStandaloneRemoteBranchTips)) {
                BOOL resuscitate = YES;
                for (GCHistoryCommit* child in parent.children) {
                  if (!COMMIT_SKIPPED(child)) {
                    resuscitate = NO;
                    break;
                  }
                }
                if (resuscitate) {
                  [tips addObject:parent];
                  continue;
                }
              }
              
              // Also make sure references that are upstream tips are not skipped
              if ((_options & kGIGraphOption_PreserveUpstreamRemoteBranchTips) && [upstreamTips containsObject:parent]) {
                continue;
              }
            }
          }
          
          // A commit can be skipped if all its children are skipped
          BOOL skip = YES;
          for (GCHistoryCommit* child in parent.children) {
            skip = COMMIT_SKIPPED(child);
            if (!skip) {
              break;
            }
          }
          
          // Skip commit if applicable
          if (skip) {
            XLOG_DEBUG_CHECK(!updateTips || ![tips containsObject:parent]);
            XLOG_DEBUG_CHECK(!GC_POINTER_LIST_CONTAINS(newSkipList, parent));
            GC_POINTER_LIST_APPEND(newSkipList, parent);
            COMMIT_SKIPPED(parent) = YES;
          }
        }
      }
      
      // If new list is empty we're done
      if (!GC_POINTER_LIST_COUNT(newSkipList)) {
        GC_POINTER_LIST_RESET(skipList);
        break;
      }
      
      // Replace current list with new list
      GC_POINTER_LIST_SWAP(newSkipList, skipList);
      GC_POINTER_LIST_RESET(newSkipList);
    }
  };
  if (skipped) {
    skipBlock(YES);
  }
  
  NSArray* tipsArray = tips.objects;
  
  // Make sure we have some tips left
  if (tipsArray.count == 0) {
    goto cleanup;
  }
  
  // Re-sort all tips in descending chronological order (this ensures virtual tips will be on the rightside of the tips descending from the same commits)
  if (_options & kGIGraphOption_ShowVirtualTips) {
    tipsArray = [tipsArray sortedArrayUsingSelector:@selector(reverseTimeCompare:)];
  }
  
  // Create initial layer made of tips
  GILayer* layer = [[GILayer alloc] initWithIndex:CFArrayGetCount(_layers)];
  @autoreleasepool {
    for (GCHistoryCommit* commit in tipsArray) {
      // Create new branch
      GIBranch* branch = [[GIBranch alloc] init];
      CFArrayAppendValue(_branches, branch);
#ifdef __clang_analyzer__
      [branch release];  // Release is actually handled by CFArray which doesn't retain
#endif
      
      // Create new line
      GILine* line = [[GILine alloc] initWithBranch:branch];
      CFArrayAppendValue(_lines, line);
      branch.mainLine = line;
      [layer addLine:line];
#ifdef __clang_analyzer__
      [line release];  // Release is actually handled by CFArray which doesn't retain
#endif
      
      // Create new node
      GINode* node;
      BOOL ready = YES;
      if (!commit.leaf) {
        // If skipping commits, a tip is ready only if all its children are skipped
        if (skipped) {
          for (GCHistoryCommit* child in commit.children) {
            if (!COMMIT_SKIPPED(child)) {
              ready = NO;
              break;
            }
          }
        }
        // Otherwise any non-leaf tip commit must be dummy
        else {
          ready = NO;
        }
      }
      if (ready) {
        node = [[GINode alloc] initWithLayer:layer primaryLine:line commit:commit dummy:NO alternateCommit:nil];
        MAP_COMMIT_TO_NODE(commit) = node;  // Associate node with commit
      } else {
        node = [[GINode alloc] initWithLayer:layer primaryLine:line commit:commit dummy:YES alternateCommit:nil];
        ++_numberOfDummyNodes;
      }
      CFArrayAppendValue(_nodes, node);
      [layer addNode:node];
      [line addNode:node];
    }
  }
  CFArrayAppendValue(_layers, layer);
#ifdef __clang_analyzer__
  [layer release];
#endif
  
  // Add next layers following commit parent hierarchy
  GILayer* previousLayer = layer;
  while (1) {
    @autoreleasepool {
      // Create a new empty layer
      layer = [[GILayer alloc] initWithIndex:CFArrayGetCount(_layers)];
      
      // Iterate over nodes from previous layer
      for (GINode* previousNode in previousLayer.nodes) {
        GINode* (^nodeBlock)(GILine*, GCHistoryCommit*, GCHistoryCommit*) = ^(GILine* line, GCHistoryCommit* commit, GCHistoryCommit* alternateCommit) {
          XLOG_DEBUG_CHECK(!MAP_COMMIT_TO_NODE(commit));
          
          // Check if this commit is "ready" to be a node i.e. all its children have non-dummy nodes associated (but not on the current layer)
          BOOL ready = YES;
          for (GCHistoryCommit* child in commit.children) {
            if (skipped && COMMIT_SKIPPED(child)) {
              continue;
            }
            GINode* node = MAP_COMMIT_TO_NODE(child);
            ready = node && (node.layer != layer);
            if (!ready) {
              break;
            }
          }
          
          // Create new node (dummy if the commit is not ready)
          GINode* node;
          if (ready) {
            node = [[GINode alloc] initWithLayer:layer primaryLine:line commit:commit dummy:NO alternateCommit:nil];
            MAP_COMMIT_TO_NODE(commit) = node;  // Associate node with commit
          } else {
            node = [[GINode alloc] initWithLayer:layer primaryLine:line commit:commit dummy:YES alternateCommit:alternateCommit];
            ++_numberOfDummyNodes;
          }
          CFArrayAppendValue(_nodes, node);
          [layer addNode:node];
          [line addNode:node];
          
          return node;
        };
        
        // If the previous node is a dummy one reprocess its commit
        GCHistoryCommit* commit = previousNode.commit;
        GILine* line = previousNode.primaryLine;
        if (previousNode.dummy) {
          XLOG_DEBUG_CHECK(!skipped || !COMMIT_SKIPPED(commit));
          GINode* node = MAP_COMMIT_TO_NODE(commit);  // Check if commit has already been reprocessed
          if (node) {
            XLOG_DEBUG_CHECK(node.layer == layer);
            [line addNode:node];
            [previousNode addParent:node];
          } else {
            [previousNode addParent:nodeBlock(line, commit, previousNode.alternateCommit)];
          }
          [layer addLine:line];
        }
        // Otherwise process its parent commit(s)
        else {
          NSUInteger index = 0;
          for (GCHistoryCommit* parent in commit.parents) {
            XLOG_DEBUG_CHECK(!skipped || !COMMIT_SKIPPED(parent));
            GINode* node = MAP_COMMIT_TO_NODE(parent);  // Check if commit has already been processed
            GILine* parentLine = line;
            if (index) {  // Start a new line if not the first parent
              GILine* newLine = [[GILine alloc] initWithBranch:line.branch];
              CFArrayAppendValue(_lines, newLine);
#ifdef __clang_analyzer__
              [newLine release];
#endif
              [newLine addNode:previousNode];
              [previousLayer addLine:newLine];
              parentLine = newLine;
            }
            if (node) {
              XLOG_DEBUG_CHECK(node.layer == layer);
              [parentLine addNode:node];
              [previousNode addParent:node];
            } else {
              [previousNode addParent:nodeBlock(parentLine, parent, commit)];
            }
            [layer addLine:parentLine];
            ++index;
          }
          
          // Cache node if it has references
          if (commit.hasReferences) {
            CFArrayAppendValue(_nodesWithReferences, previousNode);
          }
        }
      }
      
      // If new layer is empty, we're done
      if (layer.nodes.count == 0) {
        [layer release];
        break;
      }
      
#if DEBUG
      // Make sure new layer contains at least one non-dummy node
      BOOL found = NO;
      for (GINode* node in layer.nodes) {
        if (!node.dummy) {
          found = YES;
          break;
        }
      }
      XLOG_DEBUG_CHECK(found);
#endif
      
      // Save new layer
      CFArrayAppendValue(_layers, layer);
#ifdef __clang_analyzer__
      [layer release];
#endif
      previousLayer = layer;
    }
  }
  
cleanup:
  if (skipped) {
    free(skipped);
  }
  GC_POINTER_LIST_FREE(newSkipList);
  GC_POINTER_LIST_FREE(skipList);
  [upstreamTips release];
  [tips release];
}

- (void)_computeNodePositions {
  CGFloat maxX = 0.0;
  for (CFIndex i = 0, count = CFArrayGetCount(_layers); i < count; ++i) {
    GILayer* layer = CFArrayGetValueAtIndex(_layers, i);
    
    CGFloat lastX = 0.0;
    NSUInteger index = 0;
    for (GINode* node in layer.nodes) {
      if (index) {
        CGFloat x = node.primaryLine.x;
        if (node.primaryLine.branchMainLine) {
          lastX += 2;
        }
        if (x <= lastX) {
          x = lastX + 1;
        }
        node.x = x;
        node.primaryLine.x = x;
        maxX = MAX(x, maxX);
        lastX = x;
      }
      ++index;
    }
    
    layer.y = layer.index;
  }
  _size = CGSizeMake(maxX, CFArrayGetCount(_layers) - 1);
}

#if __GI_HAS_APPKIT__

- (void)_computeNodeAndLineColors {
  NSMutableArray* colors = [[NSMutableArray alloc] init];
#if 1  // Pol set
  [colors addObject:[NSColor colorWithDeviceHue:(0.0 / 8.0) saturation:0.45 brightness:0.90 alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceHue:(1.0 / 8.0) saturation:0.45 brightness:0.90 alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceHue:(2.0 / 8.0) saturation:0.45 brightness:0.90 alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceHue:(3.0 / 8.0) saturation:0.45 brightness:0.90 alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceHue:(4.0 / 8.0) saturation:0.45 brightness:0.90 alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceHue:(5.0 / 8.0) saturation:0.45 brightness:0.90 alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceHue:(6.0 / 8.0) saturation:0.45 brightness:0.90 alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceHue:(7.0 / 8.0) saturation:0.45 brightness:0.90 alpha:1.0]];
#else  // Wayne set
  [colors addObject:[NSColor colorWithDeviceRed:(75.0 / 255.0) green:(138.0 / 255.0) blue:(231.0 / 255.0) alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceRed:(179.0 / 255.0) green:(143.0 / 255.0) blue:(177.0 / 255.0) alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceRed:(240.0 / 255.0) green:(115.0 / 255.0) blue:(116.0 / 255.0) alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceRed:(140.0 / 255.0) green:(194.0 / 255.0) blue:(200.0 / 255.0) alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceRed:(100.0 / 255.0) green:(170.0 / 255.0) blue:(130.0 / 255.0) alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceRed:(250.0 / 255.0) green:(173.0 / 255.0) blue:(72.0 / 255.0) alpha:1.0]];
  [colors addObject:[NSColor colorWithDeviceRed:(134.0 / 255.0) green:(126 / 255.0) blue:(124.0 / 255.0) alpha:1.0]];
#endif
  NSUInteger numColors = colors.count;
  
#if __COLORIZE_BRANCHES__
  CFMutableDictionaryRef dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
  NSUInteger index = 0;
  for (CFIndex i = 0, count = CFArrayGetCount(_branches); i < count; ++i) {
    GIBranch* branch = CFArrayGetValueAtIndex(_branches, i);
    NSColor* color = colors[index];
    index = (index + 1) % numColors;
    CFDictionarySetValue(dictionary, branch, color);
  }
  for (CFIndex i = 0, count = CFArrayGetCount(_lines); i < count; ++i) {
    GILine* line = CFArrayGetValueAtIndex(_lines, i);
    line.color = CFDictionaryGetValue(dictionary, line.branch);
  }
  CFRelease(dictionary);
#else
  NSUInteger index = 0;
  for (CFIndex i = 0, count = CFArrayGetCount(_lines); i < count; ++i) {
    GILine* line = CFArrayGetValueAtIndex(_lines, i);
    NSColor* color;
    do {
      color = colors[index];
      index = (index + 1) % numColors;
    } while ((line.parentLine.color == color) || (line.childLine.color == color));
    line.color = color;
  }
#endif
  
  [colors release];
}

#endif

#if DEBUG

- (void)_validateTopology {
  // Validate nodes - TODO: Find a way to validate "alternateCommit"
  for (CFIndex i = 0, count = CFArrayGetCount(_nodes); i < count; ++i) {
    GINode* node = CFArrayGetValueAtIndex(_nodes, i);
    XLOG_DEBUG_CHECK(node.layer);
    XLOG_DEBUG_CHECK(node.primaryLine);
    XLOG_DEBUG_CHECK(node.commit);
    XLOG_DEBUG_CHECK((node.dummy && (node.parentCount == 1)) || (!node.dummy && (node.parentCount == node.commit.parents.count)));
  }
  
  // Validate lines
  for (CFIndex i = 0, count = CFArrayGetCount(_lines); i < count; ++i) {
    GILine* line = CFArrayGetValueAtIndex(_lines, i);
    XLOG_DEBUG_CHECK(line.branch);
    NSArray* nodes = line.nodes;
    XLOG_DEBUG_CHECK(nodes.count >= 1);
    XLOG_DEBUG_CHECK(![(GINode*)nodes.firstObject isDummy] || ![[(GINode*)nodes.firstObject commit] isLeaf]);
    XLOG_DEBUG_CHECK(![(GINode*)nodes.lastObject isDummy]);
    for (NSUInteger i2 = 0, count2 = nodes.count; i2 < count2; ++i2) {
      GINode* node = nodes[i2];
      if (i2 == 0) {
        XLOG_DEBUG_CHECK(node.commit.hasReferences || node.commit.leaf || (node.primaryLine == line.childLine) || [_history.HEADCommit isEqualToCommit:node.commit]);
      } else if (i2 == count2 - 1) {
        XLOG_DEBUG_CHECK(node.commit.root || (node.primaryLine == line.parentLine));
      } else {
        XLOG_DEBUG_CHECK(node.primaryLine == line);
      }
    }
  }
  
  // Validate branches
  for (CFIndex i = 0, count = CFArrayGetCount(_branches); i < count; ++i) {
    GIBranch* branch = CFArrayGetValueAtIndex(_branches, i);
    XLOG_DEBUG_CHECK(branch.mainLine);
    XLOG_DEBUG_CHECK(branch.mainLine.branch == branch);
  }
  
  // Validate layers - TODO: Find a way to validate lines in layers
  for (CFIndex i = 0, count = CFArrayGetCount(_layers); i < count; ++i) {
    GILayer* layer = CFArrayGetValueAtIndex(_layers, i);
    XLOG_DEBUG_CHECK(layer.index == (NSUInteger)i);
    XLOG_DEBUG_CHECK(layer.nodes.count >= 1);
    XLOG_DEBUG_CHECK([[NSSet setWithArray:layer.lines] count] == layer.lines.count);
  }
  
  // Make sure HEAD has an associated non-dummy node
  if (_history.HEADCommit) {
    GINode* node = MAP_COMMIT_TO_NODE(_history.HEADCommit);
    if (node) {
      XLOG_DEBUG_CHECK(!node.dummy);
    }
  }
  
  // Make sure all commits have a non-dummy node associated and that there are no orphan non-dummy nodes
  NSMutableSet* orphanNodes = [NSMutableSet setWithCapacity:CFArrayGetCount(_nodes)];
  for (CFIndex i = 0, count = CFArrayGetCount(_nodes); i < count; ++i) {
    GINode* node = CFArrayGetValueAtIndex(_nodes, i);
    if (!node.dummy) {
      [orphanNodes addObject:node];
    }
  }
  for (GCHistoryCommit* commit in _history.allCommits) {
    GINode* node = MAP_COMMIT_TO_NODE(commit);
    if (node) {
      XLOG_DEBUG_CHECK(!node.dummy);
      XLOG_DEBUG_CHECK(node.commit == commit);
      [orphanNodes removeObject:node];
    }
  }
  XLOG_DEBUG_CHECK(orphanNodes.count == 0);
  
  // Make sure global node list matches all line nodes
  NSMutableSet* lineNodes = [NSMutableSet setWithCapacity:CFArrayGetCount(_nodes)];
  for (CFIndex i = 0, count = CFArrayGetCount(_lines); i < count; ++i) {
    GILine* line = CFArrayGetValueAtIndex(_lines, i);
    [lineNodes addObjectsFromArray:line.nodes];
  }
  XLOG_DEBUG_CHECK([lineNodes isEqualToSet:[NSSet setWithArray:(NSArray*)_nodes]]);
  
  // Make sure global node list matches all layer nodes
  NSMutableSet* layerNodes = [NSMutableSet setWithCapacity:CFArrayGetCount(_nodes)];
  for (CFIndex i = 0, count = CFArrayGetCount(_layers); i < count; ++i) {
    GILayer* layer = CFArrayGetValueAtIndex(_layers, i);
    [layerNodes addObjectsFromArray:layer.nodes];
  }
  XLOG_DEBUG_CHECK([layerNodes isEqualToSet:[NSSet setWithArray:(NSArray*)_nodes]]);
  
  // Make sure all lines are a hierarchy of nodes and end with a non-dummy node
  for (CFIndex i = 0, count = CFArrayGetCount(_lines); i < count; ++i) {
    GILine* line = CFArrayGetValueAtIndex(_lines, i);
    NSArray* nodes = line.nodes;
    NSUInteger index = 0;
    while ([nodes[index] isDummy] && (index < nodes.count - 1)) {
      ++index;
    }
    while (index < nodes.count - 1) {
      GINode* node = nodes[index];
      GINode* nextNode;
      do {
        ++index;
        nextNode = nodes[index];
      } while (nextNode.dummy);
      XLOG_DEBUG_CHECK([node.commit.parents containsObject:nextNode.commit]);
    }
    XLOG_DEBUG_CHECK(![(GINode*)line.nodes.lastObject isDummy]);
  }
}

- (void)_validateStyle {
  // Make sure there are no duplicate node positions
  for (CFIndex i = 0, count = CFArrayGetCount(_layers); i < count; ++i) {
    GILayer* layer = CFArrayGetValueAtIndex(_layers, i);
    NSMutableSet* set = [NSMutableSet set];
    for (GINode* node in layer.nodes) {
      [set addObject:@(node.x)];
    }
    XLOG_DEBUG_CHECK(set.count == layer.nodes.count);
  }
  
  // Make sure children nodes are above parent nodes
  for (GCHistoryCommit* commit in _history.allCommits) {
    GINode* node = MAP_COMMIT_TO_NODE(commit);
    if (node) {
      for (GCHistoryCommit* childCommit in commit.children) {
        GINode* childNode = MAP_COMMIT_TO_NODE(childCommit);
        if (childNode) {
          XLOG_DEBUG_CHECK(childNode.layer.y < node.layer.y);
        }
      }
    }
  }
  
  // Make sure all lines have a color and their nodes are laid out upwards
  for (CFIndex i = 0, count = CFArrayGetCount(_lines); i < count; ++i) {
    GILine* line = CFArrayGetValueAtIndex(_lines, i);
#if __GI_HAS_APPKIT__
    XLOG_DEBUG_CHECK(line.color);
#endif
    CGFloat lastY = -HUGE_VAL;
    for (GINode* node in line.nodes) {
      XLOG_DEBUG_CHECK(node.layer.y > lastY);
      lastY = node.layer.y;
    }
  }
}

#endif

- (GINode*)nodeForCommit:(GCHistoryCommit*)commit {
  XLOG_DEBUG_CHECK(commit);
  return MAP_COMMIT_TO_NODE(commit);
}

- (void)walkMainLineForAncestorsOfNode:(GINode*)node usingBlock:(void (^)(GINode* node, BOOL* stop))block {
  while (1) {
    if (node.parentCount) {
      node = [node parentAtIndex:0];
      BOOL stop = NO;
      block(node, &stop);
      if (stop) {
        break;
      }
    } else {
      break;
    }
  }
}

- (void)walkAncestorsOfNode:(GINode*)node
            layerBeginBlock:(void (^)(GILayer* layer, BOOL* stop))beginBlock
             layerNodeBlock:(void (^)(GILayer* layer, GINode* node, BOOL* stop))nodeBlock
              layerEndBlock:(void (^)(GILayer* layer, BOOL* stop))endBlock {
  GC_POINTER_LIST_ALLOCATE(row, 32);
  GC_POINTER_LIST_ALLOCATE(tempRow, 32);
  
  __block CFIndex index = node.layer.index;
  CFIndex maxIndex = CFArrayGetCount(_layers);
  GC_POINTER_LIST_APPEND(row, node);
  while (1) {
    ++index;
    if (index == maxIndex) {
      break;
    }
    GILayer* layer = CFArrayGetValueAtIndex(_layers, index);
    if (beginBlock) {
      BOOL stop = NO;
      beginBlock(layer, &stop);
      if (stop) {
        goto cleanup;
      }
    }
    GC_POINTER_LIST_FOR_LOOP(row, GINode*, previousNode) {
      for (NSUInteger i = 0, count = previousNode.parentCount; i < count; ++i) {
        GINode* parent = [previousNode parentAtIndex:i];
        XLOG_DEBUG_CHECK(parent.layer == layer);
        if (!GC_POINTER_LIST_CONTAINS(tempRow, parent)) {
          BOOL stop = NO;
          nodeBlock(layer, parent, &stop);
          if (stop) {
            goto cleanup;
          }
          GC_POINTER_LIST_APPEND(tempRow, parent);
        }
      }
    }
    if (endBlock) {
      BOOL stop = NO;
      endBlock(layer, &stop);
      if (stop) {
        goto cleanup;
      }
    }
    if (!GC_POINTER_LIST_COUNT(tempRow)) {
      break;
    }
    GC_POINTER_LIST_SWAP(tempRow, row);
    GC_POINTER_LIST_RESET(tempRow);
  }
  
cleanup:
  GC_POINTER_LIST_FREE(tempRow);
  GC_POINTER_LIST_FREE(row);
}

- (NSString*)description {
  NSMutableString* description = [[NSMutableString alloc] initWithString:[super description]];
  for (CFIndex i = 0, count = CFArrayGetCount(_layers); i < count; ++i) {
    GILayer* layer = CFArrayGetValueAtIndex(_layers, i);
    [description appendFormat:@"\nLayer %lu", (unsigned long)layer.index];
    for (GINode* node in layer.nodes) {
      [description appendFormat:@"\n [%c] %@ \"%@\" (%@)", node.dummy ? ' ' : 'X', node.commit.shortSHA1, node.commit.summary, node.alternateCommit.shortSHA1];
    }
  }
  return [description autorelease];
}

@end
