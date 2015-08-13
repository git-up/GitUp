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

#import <AppKit/AppKit.h>

@class GIGraphView, GILayer, GINode, GIGraph, GCHistoryCommit;

@protocol GIGraphViewDelegate <NSObject>
- (void)graphViewDidChangeSelection:(GIGraphView*)graphView;
- (void)graphView:(GIGraphView*)graphView didDoubleClickOnNode:(GINode*)node;
- (NSMenu*)graphView:(GIGraphView*)graphView willShowContextualMenuForNode:(GINode*)node;
@end

@interface GIGraphView : NSView <NSUserInterfaceValidations>
@property(nonatomic, assign) id<GIGraphViewDelegate> delegate;
@property(nonatomic, strong) GIGraph* graph;
@property(nonatomic) BOOL showsTagLabels;
@property(nonatomic) BOOL showsBranchLabels;
@property(nonatomic, strong) NSColor* backgroundColor;

@property(nonatomic, assign) GINode* selectedNode;  // Setting this property directly does not call the delegate
@property(nonatomic, assign) GCHistoryCommit* selectedCommit;  // Convenience method that wraps @selectedNode

@property(nonatomic, readonly) NSSize minSize;

- (GILayer*)findLayerAtPosition:(CGFloat)position;
- (CGFloat)positionForLayer:(GILayer*)layer;
- (GINode*)findNodeAtPosition:(NSPoint)position;
- (NSPoint)positionForNode:(GINode*)node;

- (void)showContextualMenuForSelectedNode;
@end

// Requires GIGraphView to be embedded in a NSScrollView -> NSClipView hierarchy
@interface GIGraphView (NSScrollView)
@property(nonatomic, readonly) GINode* focusedNode;  // Closest node centered in visible area of scrollview
- (void)scrollToNode:(GINode*)node;
- (void)scrollToSelection;  // Convenience method that calls -scrollToNode:
- (void)scrollToTip;  // Scroll to tip of graph
@end
