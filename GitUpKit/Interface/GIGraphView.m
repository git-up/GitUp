//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
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

#import <objc/runtime.h>

#import "GIPrivate.h"

#define __SHIFT_CORNERS__ 0

#define __DEBUG_DRAWING__ 0
#define __DEBUG_BOXES__ 0
#define __DEBUG_TITLE_CORNERS__ 0
#define __DEBUG_MAIN_LINE__ 0
#define __DEBUG_DESCENDANTS__ 0
#define __DEBUG_ANCESTORS__ 0

#define kSpacingX 30
#define kSpacingY 30

#define kMainLineWidth 8
#define kMainLineNodeSmallDiameter 6
#define kMainLineNodeLargeDiameter 10

#define kSubLineWidth 2
#define kSubNodeDiameter 8

#define kEpsilon 0.001
#define kLineCornerSize 6
#define kOverdrawMargin (kSpacingY / 2)
#if __SHIFT_CORNERS__
#define kFocusBranchCornerSize 0.5  // Must be <= 0.5
#endif

#define kTitleSpacing 200
#define kTitleOffsetX 7
#define kTitleOffsetY 7

#define kLabelOffsetX 18
#define kLabelOffsetY 10

#define kSelectedOffsetX 28
#define kSelectedCornerRadius 5.0
#define kSelectedTipHeight 8.0
#define kSelectedBorderWidth 2.0

#define kContextualMenuOffsetX 10
#define kContextualMenuOffsetY -10

#define kSelectedLabelMaxWidth 400
#define kSelectedLabelMaxHeight 80

#define kNodeLabelMaxWidth 200
#define kNodeLabelMaxHeight 50

#define kMaxBranchTitleWidth 250

#define kScrollingInset kSpacingY

#define CONVERT_X(x) (kSpacingX + (x)*kSpacingX)
#define CONVERT_Y(y) (kSpacingY + (y)*kSpacingY)
#define SQUARE(x) ((x) * (x))
#define SELECTED_NODE_BOUNDS(x, y) NSMakeRect(x - kSpacingX / 2, y - (kSelectedLabelMaxHeight / 2) - kSelectedBorderWidth, kSelectedLabelMaxWidth + kSpacingX / 2 + 40, kSelectedLabelMaxHeight + (kSelectedBorderWidth * 2))
#define NODE_LABEL_BOUNDS(x, y) NSMakeRect(x - kSpacingX / 2, y - kSpacingY / 2, kNodeLabelMaxWidth + kSpacingX / 2 + 30, kNodeLabelMaxHeight + kSpacingY / 2)
#define HEAD_BOUNDS(x, y) NSMakeRect(x - 20, y - 10, 40, 20)

@interface GIGraphView (Private)
- (void)_scrollToTop;
- (void)_scrollToBottom;
- (void)_scrollToLeft;
- (void)_scrollToRight;
@end

static const void* _associatedObjectDataKey = &_associatedObjectDataKey;

@implementation GIGraphView {
  NSDateFormatter* _dateFormatter;
}

#pragma mark Initialization

- (void)_initialize {
  _dateFormatter = [[NSDateFormatter alloc] init];
  _dateFormatter.dateStyle = NSDateFormatterShortStyle;
  _dateFormatter.timeStyle = NSDateFormatterShortStyle;

  self.graph = nil;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  if ((self = [super initWithFrame:frameRect])) {
    [self _initialize];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
  if ((self = [super initWithCoder:coder])) {
    [self _initialize];
  }
  return self;
}

- (void)dealloc {
  [self _setSelectedNode:nil display:NO scroll:NO notify:NO];

  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResignKeyNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidBecomeKeyNotification object:nil];

  _graph = nil;
  _dateFormatter = nil;
}

#pragma mark - Subclassing

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (BOOL)becomeFirstResponder {
  if (_selectedNode) {
    NSPoint point = [self positionForNode:_selectedNode];
    [self setNeedsDisplayInRect:SELECTED_NODE_BOUNDS(point.x, point.y)];
  }
  return YES;
}

- (BOOL)resignFirstResponder {
  if (_selectedNode) {
    NSPoint point = [self positionForNode:_selectedNode];
    [self setNeedsDisplayInRect:SELECTED_NODE_BOUNDS(point.x, point.y)];
  }
  return YES;
}

- (void)_windowKeyDidChange:(NSNotification*)notification {
  if (_selectedNode) {
    NSPoint point = [self positionForNode:_selectedNode];
    [self setNeedsDisplayInRect:SELECTED_NODE_BOUNDS(point.x, point.y)];
  }
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];

  if (self.window) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_windowKeyDidChange:) name:NSWindowDidBecomeKeyNotification object:self.window];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_windowKeyDidChange:) name:NSWindowDidResignKeyNotification object:self.window];
  } else {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResignKeyNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidBecomeKeyNotification object:nil];
  }
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
  NSRect bounds = self.superview.bounds;
  if (_graph) {
    self.frame = NSMakeRect(0, 0, MAX(_minSize.width, bounds.size.width), MAX(_minSize.height, bounds.size.height));
  } else {
    self.frame = NSMakeRect(0, 0, bounds.size.width, bounds.size.height);
  }
}

#pragma mark - Actions

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  if (item.action == @selector(copy:)) {
    return _selectedNode ? YES : NO;
  }

  return NO;
}

- (void)copy:(id)sender {
  [[NSPasteboard generalPasteboard] declareTypes:@[ NSPasteboardTypeString ] owner:nil];
  [[NSPasteboard generalPasteboard] setString:_selectedNode.commit.SHA1 forType:NSPasteboardTypeString];
}

#pragma mark - Properties

- (void)_updateView {
  _minSize = NSMakeSize(CONVERT_X(_graph.size.width + 1) + kSelectedLabelMaxWidth, CONVERT_Y(_graph.size.height + 1) + kTitleSpacing);
  [self resizeWithOldSuperviewSize:NSZeroSize];
  [self setNeedsDisplay:YES];
}

- (void)setGraph:(GIGraph*)graph {
  if (graph != _graph) {
    _selectedNode = nil;
    _graph = graph;

    [self _updateView];

    [self _setSelectedNode:nil display:NO scroll:NO notify:YES];
  }
}

- (void)setShowsTagLabels:(BOOL)flag {
  _showsTagLabels = flag;

  [self setNeedsDisplay:YES];
}

- (void)setShowsBranchLabels:(BOOL)flag {
  _showsBranchLabels = flag;

  [self setNeedsDisplay:YES];
}

#pragma mark - Utilities

- (GILayer*)_findLayerAtPosition:(CGFloat)position closest:(BOOL)closest {
  NSArray* layers = _graph.layers;
  if (layers.count) {
    CGFloat offset = _graph.size.height;

    GILayer* firstLayer = layers.firstObject;
    if (position > CONVERT_Y(offset - firstLayer.y) + kSpacingY / 2) {
      return closest ? firstLayer : nil;
    }

    GILayer* lastLayer = layers.lastObject;
    if (position < CONVERT_Y(offset - lastLayer.y) - kSpacingY / 2) {
      return closest ? lastLayer : nil;
    }

    NSRange range = NSMakeRange(0, layers.count);
    while (range.length) {
      NSUInteger index = range.location + range.length / 2;
      GILayer* layer = layers[index];
      CGFloat y = CONVERT_Y(offset - layer.y);
      if (position > y + kSpacingY / 2) {
        range = NSMakeRange(range.location, index - range.location);
      } else if (position < y - kSpacingY / 2) {
        if (range.length == 1) {
          break;
        }
        range = NSMakeRange(index, range.location + range.length - index);
      } else {
        return layer;
      }
    }
  }
  return nil;
}

- (GILayer*)findLayerAtPosition:(CGFloat)position {
  return [self _findLayerAtPosition:position closest:NO];
}

- (CGFloat)positionForLayer:(GILayer*)layer {
  return CONVERT_Y(_graph.size.height - layer.y);
}

- (GINode*)_findNodeAtPosition:(NSPoint)position closest:(BOOL)closest {
  GILayer* layer = [self _findLayerAtPosition:position.y closest:closest];
  if (layer) {
    NSArray* nodes = layer.nodes;

    GINode* firstNode = nodes.firstObject;
    if (position.x < CONVERT_X(firstNode.x) - kSpacingX / 2) {
      return closest ? firstNode : nil;
    }

    GINode* lastNode = nodes.lastObject;
    if (position.x > CONVERT_X(lastNode.x) + kSpacingX / 2) {
      return closest ? lastNode : nil;
    }

    for (GINode* node in nodes) {
      CGFloat x = CONVERT_X(node.x);
      if ((position.x >= x - kSpacingX / 2) && (position.x <= x + kSpacingX / 2)) {
        return node;
      }
    }
  }
  return nil;
}

- (GINode*)findNodeAtPosition:(NSPoint)position {
  return [self _findNodeAtPosition:position closest:NO];
}

- (NSPoint)positionForNode:(GINode*)node {
  CGFloat x = CONVERT_X(node.x);
  CGFloat y = CONVERT_Y(_graph.size.height - node.layer.y);
  return CGPointMake(x, y);
}

- (void)showContextualMenuForSelectedNode {
  if (_selectedNode) {
    [self _showContextualMenuForNode:_selectedNode];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

#pragma mark - Selection

- (void)setSelectedCommit:(GCHistoryCommit*)commit {
  [self setSelectedNode:(commit ? [_graph nodeForCommit:commit] : nil)];
}

- (GCHistoryCommit*)selectedCommit {
  return _selectedNode.commit;
}

- (void)setSelectedNode:(GINode*)node {
  [self _setSelectedNode:node display:YES scroll:NO notify:YES];
}

// We need to retain the underlying commit for later as GINode doesn't retain its commit
- (void)_setSelectedNode:(GINode*)node display:(BOOL)display scroll:(BOOL)scroll notify:(BOOL)notify {
  XLOG_DEBUG_CHECK(!node.dummy);
  if (display && _lastSelectedNode) {
    NSPoint point = [self positionForNode:_lastSelectedNode];
    [self setNeedsDisplayInRect:SELECTED_NODE_BOUNDS(point.x, point.y)];
  }
  _lastSelectedNode = nil;
  if (node != _selectedNode) {
    if (display && _selectedNode) {
      NSPoint point = [self positionForNode:_selectedNode];
      [self setNeedsDisplayInRect:SELECTED_NODE_BOUNDS(point.x, point.y)];
    }
    _selectedNode = node;
    if (display && _selectedNode) {
      NSPoint point = [self positionForNode:_selectedNode];
      [self setNeedsDisplayInRect:SELECTED_NODE_BOUNDS(point.x, point.y)];
    }
#if __DEBUG_MAIN_LINE__ || __DEBUG_DESCENDANTS__ || __DEBUG_ANCESTORS__
    [self setNeedsDisplay:YES];
#endif
    if (scroll) {
      XLOG_DEBUG_CHECK(_selectedNode);
      [self scrollToSelection];
    }
    if (notify) {
      [_delegate graphViewDidChangeSelection:self];
    }
  }
}

- (void)_selectParentNode {
  NSArray* nodes = _selectedNode.primaryLine.nodes;
  NSUInteger index = [nodes indexOfObject:_selectedNode];
  while (index < nodes.count - 1) {
    GINode* node = nodes[++index];
    if (!node.dummy) {
      [self _setSelectedNode:node display:YES scroll:YES notify:YES];
      break;
    }
  }
}

- (void)_selectChildNode {
  NSArray* nodes = _selectedNode.primaryLine.nodes;
  NSUInteger index = [nodes indexOfObject:_selectedNode];
  while (index > 0) {
    GINode* node = nodes[--index];
    if (!node.dummy) {
      [self _setSelectedNode:node display:YES scroll:YES notify:YES];
      break;
    }
  }
}

- (void)_selectSideNodeAtPosition:(NSPoint)point {
  GILayer* layer = [self findLayerAtPosition:point.y];
  if (layer == nil) {
    return;
  }
  NSUInteger index = [layer.nodes indexOfObjectPassingTest:^BOOL(GINode* _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
    return obj != _selectedNode && !obj.dummy;
  }];
  if (index != NSNotFound) {
    [self _setSelectedNode:layer.nodes[index] display:YES scroll:YES notify:YES];
  }
}

- (void)_selectUncleNode {
  NSPoint position = [self positionForNode:_selectedNode];
  NSPoint targetPosition = NSMakePoint(position.x + kSpacingX, position.y - kSpacingY);
  [self _selectSideNodeAtPosition:targetPosition];
}

- (void)_selectNephewNode {
  NSPoint position = [self positionForNode:_selectedNode];
  NSPoint targetPosition = NSMakePoint(position.x + kSpacingX, position.y + kSpacingY);
  [self _selectSideNodeAtPosition:targetPosition];
}

- (void)_selectPreviousSiblingNode {
  NSArray* nodes = _selectedNode.layer.nodes;
  NSInteger index = [nodes indexOfObject:_selectedNode];
  while (index > 0) {
    GINode* node = nodes[--index];
    if (!node.dummy) {
      [self _setSelectedNode:node display:YES scroll:YES notify:YES];
      break;
    }
  }
}

- (void)_selectNextSiblingNode {
  NSArray* nodes = _selectedNode.layer.nodes;
  NSInteger index = [nodes indexOfObject:_selectedNode];
  while (index < (NSInteger)nodes.count - 1) {
    GINode* node = nodes[++index];
    if (!node.dummy) {
      [self _setSelectedNode:node display:YES scroll:YES notify:YES];
      break;
    }
  }
}

- (void)_selectDefaultNode {
  GCHistoryCommit* headCommit = _graph.history.HEADCommit;
  [self _setSelectedNode:(headCommit ? [_graph nodeForCommit:headCommit] : nil) display:YES scroll:YES notify:YES];
}

- (void)_showContextualMenuForNode:(GINode*)node {
  [self _setSelectedNode:node display:YES scroll:NO notify:YES];
  NSMenu* menu = [_delegate graphView:self willShowContextualMenuForNode:node];
  if (menu) {
    NSPoint point = [self positionForNode:node];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(point.x + kContextualMenuOffsetX, point.y + kContextualMenuOffsetY) inView:self];
  }
}

#pragma mark - Events

- (void)mouseDown:(NSEvent*)event {
  GINode* node = [self findNodeAtPosition:[self convertPoint:event.locationInWindow fromView:nil]];
  if (event.clickCount > 1) {
    if (node) {
      if (node.layer.index == 0) {
        node = [_graph nodeForCommit:node.commit];  // Convert virtual node from top layer to real one
        XLOG_DEBUG_CHECK(node);
      }
      [_delegate graphView:self didDoubleClickOnNode:node];
    }
  } else if (event.modifierFlags & NSEventModifierFlagControl) {
    if (node && !node.dummy) {
      [self _showContextualMenuForNode:node];
    }
  } else {
    BOOL scroll = NO;
    if (node.dummy) {
      if (node.layer.index == 0) {
        node = [_graph nodeForCommit:node.commit];  // Convert virtual node from top layer to real one
        XLOG_DEBUG_CHECK(node);
        scroll = YES;
      } else {
        node = nil;
      }
    }

    GINode* selectedNode = _selectedNode;
    GINode* lastSelectedNode = _lastSelectedNode;
    [self _setSelectedNode:node display:YES scroll:NO notify:YES];
    if (event.modifierFlags & NSEventModifierFlagCommand) {
      if (lastSelectedNode == nil) {
        _lastSelectedNode = selectedNode;
      } else {
        _lastSelectedNode = lastSelectedNode;
      }
    }

    if (scroll) {
      [self scrollToSelection];
    }
  }
}

- (void)rightMouseDown:(NSEvent*)event {
  GINode* node = [self findNodeAtPosition:[self convertPoint:event.locationInWindow fromView:nil]];
  if (node && !node.dummy) {
    [self _showContextualMenuForNode:node];
  }
}

- (void)keyDown:(NSEvent*)event {
  switch (event.keyCode) {
    case kGIKeyCode_Tab:
      if (event.modifierFlags & NSEventModifierFlagShift) {
        [self.window selectPreviousKeyView:nil];
      } else {
        [self.window selectNextKeyView:nil];
      }
      return;

    case kGIKeyCode_Esc:
      [self _setSelectedNode:nil display:YES scroll:NO notify:YES];
      return;

    case kGIKeyCode_Left:
      if (event.modifierFlags & NSEventModifierFlagCommand) {
        [self _scrollToLeft];
      } else if (_selectedNode) {
        [self _selectPreviousSiblingNode];
      } else {
        [self _selectDefaultNode];
      }
      return;

    case kGIKeyCode_Right:
      if (event.modifierFlags & NSEventModifierFlagCommand) {
        [self _scrollToRight];
      } else if (_selectedNode) {
        [self _selectNextSiblingNode];
      } else {
        [self _selectDefaultNode];
      }
      return;

    case kGIKeyCode_Down:
      if (event.modifierFlags & NSEventModifierFlagOption) {
        [self _selectUncleNode];
      } else if (event.modifierFlags & NSEventModifierFlagCommand) {
        [self _scrollToBottom];
      } else if (_selectedNode) {
        [self _selectParentNode];
      } else {
        [self _selectDefaultNode];
      }
      return;

    case kGIKeyCode_Up:
      if (event.modifierFlags & NSEventModifierFlagOption) {
        [self _selectNephewNode];
      } else if (event.modifierFlags & NSEventModifierFlagCommand) {
        [self _scrollToTop];
      } else if (_selectedNode) {
        [self _selectChildNode];
      } else {
        [self _selectDefaultNode];
      }
      return;

    case kGIKeyCode_Home:
      [self _scrollToTop];
      return;

    case kGIKeyCode_End:
      [self _scrollToBottom];
      return;
  }
  [self.nextResponder tryToPerform:@selector(keyDown:) with:event];
}

#pragma mark - Drawing

static void _DrawNode(GINode* node, CGContextRef context, CGFloat x, CGFloat y) {
  BOOL onBranchMainLine = node.primaryLine.branchMainLine;
  NSUInteger childrenCount = node.commit.children.count;
  NSUInteger parentCount = node.commit.parents.count;
  if ((childrenCount > 1) || (parentCount > 1)) {
    CGColorRef color = onBranchMainLine ? node.primaryLine.color.CGColor : [[NSColor darkGrayColor] CGColor];
    CGFloat diameter = onBranchMainLine ? kMainLineNodeLargeDiameter : kSubNodeDiameter;
    diameter -= 1;  // TODO: Why is this needed?
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextFillEllipseInRect(context, CGRectMake(x - diameter / 2, y - diameter / 2, diameter, diameter));
    CGContextSetStrokeColorWithColor(context, color);
    CGContextStrokeEllipseInRect(context, CGRectMake(x - diameter / 2, y - diameter / 2, diameter, diameter));
  } else if (onBranchMainLine) {
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextFillEllipseInRect(context, CGRectMake(x - kMainLineNodeSmallDiameter / 2, y - kMainLineNodeSmallDiameter / 2, kMainLineNodeSmallDiameter, kMainLineNodeSmallDiameter));
  } else {
    CGContextSetFillColorWithColor(context, node.primaryLine.color.CGColor);
    CGContextFillEllipseInRect(context, CGRectMake(x - kSubNodeDiameter / 2, y - kSubNodeDiameter / 2, kSubNodeDiameter, kSubNodeDiameter));
  }
}

static void _DrawTipNode(GINode* node, CGContextRef context, CGFloat x, CGFloat y) {
  BOOL onBranchMainLine = node.primaryLine.branchMainLine;
  XLOG_DEBUG_CHECK(onBranchMainLine);
  CGColorRef color = onBranchMainLine ? node.primaryLine.color.CGColor : [[NSColor darkGrayColor] CGColor];
  CGFloat diameter = onBranchMainLine ? kMainLineNodeLargeDiameter : kSubNodeDiameter;
  if (node.dummy) {
    diameter -= 4;
    CGContextSetFillColorWithColor(context, color);
    CGContextFillEllipseInRect(context, CGRectMake(x - diameter / 2, y - diameter / 2, diameter, diameter));
    CGContextFillPath(context);
  } else {
    diameter -= 1;  // TODO: Why is this needed?
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextFillEllipseInRect(context, CGRectMake(x - diameter / 2, y - diameter / 2, diameter, diameter));
    CGContextSetStrokeColorWithColor(context, color);
    CGContextStrokeEllipseInRect(context, CGRectMake(x - diameter / 2, y - diameter / 2, diameter, diameter));
  }
}

static void _DrawRootNode(GINode* node, CGContextRef context, CGFloat x, CGFloat y) {
  BOOL onBranchMainLine = node.primaryLine.branchMainLine;
  CGColorRef color = onBranchMainLine ? node.primaryLine.color.CGColor : [[NSColor darkGrayColor] CGColor];
  CGFloat diameter = onBranchMainLine ? kMainLineNodeLargeDiameter : kSubNodeDiameter;
  diameter -= 1;  // TODO: Why is this needed?
  CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
  CGContextFillEllipseInRect(context, CGRectMake(x - diameter / 2, y - diameter / 2, diameter, diameter));
  CGContextSetStrokeColorWithColor(context, color);
  CGContextStrokeEllipseInRect(context, CGRectMake(x - diameter / 2, y - diameter / 2, diameter, diameter));
}

// Return square distance from P1 to (P0, P2) line
static inline CGFloat _SquareDistanceFromPointToLine(CGFloat x0, CGFloat y0, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
  return SQUARE(x1 * (y2 - y0) - y1 * (x2 - x0) + x2 * y0 - y2 * x0) / (SQUARE(y2 - y0) + SQUARE(x2 - x0));
}

- (void)drawLine:(GILine*)line inContext:(CGContextRef)context clampedToRect:(CGRect)dirtyRect {
  CGFloat offset = _graph.size.height;
  NSArray* nodes = line.nodes;
  NSUInteger count = nodes.count;
  CGFloat minY = CGRectGetMinY(dirtyRect);
  CGFloat maxY = CGRectGetMaxY(dirtyRect);
  BOOL recompute = YES;

  // Generate list of node coordinates aka points
  size_t pointCount;
  CGPoint* pointList;
  NSData* data = objc_getAssociatedObject(line, _associatedObjectDataKey);
  if (data) {
    XLOG_DEBUG_CHECK(data.length % sizeof(CGPoint) == 0);
    pointCount = data.length / sizeof(CGPoint);
    pointList = (CGPoint*)data.bytes;
    recompute = NO;
  } else {
    pointCount = 0;
    pointList = malloc(count * sizeof(CGPoint));
  }
  if (recompute) {
    if (count > 2) {
      GINode* node = nodes[0];
      pointList[pointCount].x = CONVERT_X(node.x);
      pointList[pointCount].y = CONVERT_Y(offset - node.layer.y);
      ++pointCount;
      for (NSUInteger i = 1; i < count; ++i) {
        node = nodes[i];
        CGFloat x = CONVERT_X(node.x);
        CGFloat y = CONVERT_Y(offset - node.layer.y);

        pointList[pointCount].x = x;
        pointList[pointCount].y = y;
        ++pointCount;
      }
      XLOG_DEBUG_CHECK(pointCount == count);
    } else if (count == 2) {
      GINode* node0 = nodes[0];
      pointList[pointCount].x = CONVERT_X(node0.x);
      pointList[pointCount].y = CONVERT_Y(offset - node0.layer.y);
      ++pointCount;
      GINode* node1 = nodes[1];
      pointList[pointCount].x = CONVERT_X(node1.x);
      pointList[pointCount].y = CONVERT_Y(offset - node1.layer.y);
      ++pointCount;
      XLOG_DEBUG_CHECK(pointCount == count);
    } else {
      XLOG_DEBUG_CHECK(count == 1);
      XLOG_DEBUG_CHECK(pointCount == 0);
    }
  }
  if (pointCount == 0) {
    free(pointList);
    return;
  }

  // Shift corner point positions
  if (recompute) {
    CGPoint* newPointList = malloc(pointCount * sizeof(CGPoint));
    size_t newPointCount = 0;
    newPointList[newPointCount].x = pointList[0].x;
    newPointList[newPointCount].y = pointList[0].y;
    ++newPointCount;
    CGFloat x0 = 0.0;
    CGFloat y0 = 0.0;
    CGFloat x1 = 0.0;
    CGFloat y1 = 0.0;
    for (size_t i = 1; i < pointCount - 1; ++i) {
#if __SHIFT_CORNERS__
      CGFloat previousX = pointList[i - 1].x;
#endif
      CGFloat x2 = pointList[i].x;
      CGFloat y2 = pointList[i].y;
#if __SHIFT_CORNERS__
      CGFloat nextX = pointList[i + 1].x;
#endif

#if __SHIFT_CORNERS__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfloat-equal"
      if ((x2 > previousX) && (nextX < x2)) {
        x2 += 2;
      } else if ((x2 > previousX) && (nextX == x2)) {
        y2 += 4;
      } else if ((x2 == previousX) && (nextX != x2)) {
        y2 -= 4;
      }
#pragma clang diagnostic pop
#endif

      if (newPointCount >= 2) {
        if (_SquareDistanceFromPointToLine(x0, y0, x2, y2, x1, y1) < kEpsilon * kEpsilon) {  // If P2 is very close to the line from P0 to P1, then they are aligned and we can remove P1
          --newPointCount;
          x1 = x0;
          y1 = y0;
        }
      }

      newPointList[newPointCount].x = x2;
      newPointList[newPointCount].y = y2;
      ++newPointCount;

      x0 = x1;
      y0 = y1;
      x1 = x2;
      y1 = y2;
    }
    newPointList[newPointCount].x = pointList[pointCount - 1].x;
    newPointList[newPointCount].y = pointList[pointCount - 1].y;
    ++newPointCount;
    XLOG_DEBUG_CHECK(newPointCount <= pointCount);
    free(pointList);
    pointList = newPointList;
    pointCount = newPointCount;
  }

  // Add intermediary points to line for corners
  if (recompute) {
    size_t newMaxPoints = 2 * (pointCount - 1) + pointCount;
    size_t newPointCount = 0;
    CGPoint* newPointList = malloc(newMaxPoints * sizeof(CGPoint));
    CGFloat x0 = pointList[0].x;
    CGFloat y0 = pointList[0].y;
    newPointList[newPointCount].x = x0;
    newPointList[newPointCount].y = y0;
    ++newPointCount;
    for (size_t i = 1; i < pointCount; ++i) {
      CGFloat x1 = pointList[i].x;
      CGFloat y1 = pointList[i].y;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfloat-equal"
      CGFloat D = kLineCornerSize;

      XLOG_DEBUG_CHECK(y1 != y0);
      CGFloat X0;
      CGFloat Y0;
      CGFloat X1;
      CGFloat Y1;
      if (x1 == x0) {
        X0 = x0;
        Y0 = y0 - D;

        X1 = x1;
        Y1 = y1 + D;
      } else {
        CGFloat A = (y0 - y1) / (x0 - x1);
        CGFloat B = y1 - A * x1;

        CGFloat K0 = sqrt(A * A * D * D - A * A * x0 * x0 - 2 * A * B * x0 + 2 * A * x0 * y0 - B * B + 2 * B * y0 + D * D - y0 * y0);
        X0 = (K0 - A * B + A * y0 + x0) / (A * A + 1);
        Y0 = A * X0 + B;
        if (Y0 >= y0) {
          X0 = (-K0 - A * B + A * y0 + x0) / (A * A + 1);
          Y0 = A * X0 + B;
          XLOG_DEBUG_CHECK(Y0 < y0);
        }

        CGFloat K1 = sqrt(A * A * D * D - A * A * x1 * x1 - 2 * A * B * x1 + 2 * A * x1 * y1 - B * B + 2 * B * y1 + D * D - y1 * y1);
        X1 = (K1 - A * B + A * y1 + x1) / (A * A + 1);
        Y1 = A * X1 + B;
        if (Y1 <= y1) {
          X1 = (-K1 - A * B + A * y1 + x1) / (A * A + 1);
          Y1 = A * X1 + B;
          XLOG_DEBUG_CHECK(Y1 > y1);
        }
      }
      XLOG_DEBUG_CHECK(Y1 < Y0);
#pragma clang diagnostic pop

      newPointList[newPointCount].x = X0;
      newPointList[newPointCount].y = Y0;
      ++newPointCount;
      newPointList[newPointCount].x = X1;
      newPointList[newPointCount].y = Y1;
      ++newPointCount;
      newPointList[newPointCount].x = x1;
      newPointList[newPointCount].y = y1;
      ++newPointCount;

      x0 = x1;
      y0 = y1;
    }
    XLOG_DEBUG_CHECK(newPointCount == newMaxPoints);
    free(pointList);
    pointList = newPointList;
    pointCount = newPointCount;
  }

  // Draw line
  CGContextBeginPath(context);
  BOOL visible = NO;
  size_t i = 0;
  while (1) {
    // Skip points until entering visible area
    if (!visible) {
      CGFloat y = pointList[i + 3].y;
      if (y > maxY) {
        i += 3;
        if (i == pointCount - 1) {
          break;  // TODO: Why is this happening?
        }
        continue;
      }
    }

    CGFloat x0 = pointList[i].x;
    CGFloat y0 = pointList[i].y;
    CGFloat x1 = pointList[i + 1].x;
    CGFloat y1 = pointList[i + 1].y;

    // Draw line start
    if (!visible) {
      CGContextMoveToPoint(context, x0, y0);
      CGContextAddLineToPoint(context, x1, y1);

      x0 = x1;
      y0 = y1;
      x1 = pointList[i + 2].x;
      y1 = pointList[i + 2].y;
      i += 1;
    }

    // Draw line segment
    CGContextMoveToPoint(context, x0, y0);
    CGContextAddLineToPoint(context, x1, y1);

    // Check if exiting visible area
    if (y0 < minY) {
      i = pointCount - 3;
    }

    // Draw line end
    if (i == pointCount - 3) {
      x0 = x1;
      y0 = y1;
      x1 = pointList[i + 2].x;
      y1 = pointList[i + 2].y;
      CGContextMoveToPoint(context, x0, y0);
      CGContextAddLineToPoint(context, x1, y1);

      visible = YES;
      break;  // We're done
    }

    // Draw line corner
    x0 = x1;
    y0 = y1;
    x1 = pointList[i + 2].x;
    y1 = pointList[i + 2].y;
    CGFloat x2 = pointList[i + 3].x;
    CGFloat y2 = pointList[i + 3].y;
    CGContextMoveToPoint(context, x0, y0);
    CGContextAddQuadCurveToPoint(context, x1, y1, x2, y2);

    i += 3;
    visible = YES;
  }

  BOOL shouldDraw = visible && [self needsToDrawRect:CGRectInset(CGContextGetPathBoundingBox(context), -kMainLineWidth, -kMainLineWidth)];
  if (shouldDraw) {
    XLOG_DEBUG_CHECK(!line.virtual || [[(GINode*)line.nodes[0] layer] index] == 0);
    CGContextSaveGState(context);
    CGContextSetLineWidth(context, line.branchMainLine && !line.virtual ? kMainLineWidth : kSubLineWidth);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    if (line.virtual) {
      const CGFloat pattern[] = {4, 2};
      CGContextSetLineDash(context, 0, pattern, 2);
    }
    CGContextSetStrokeColorWithColor(context, line.color.CGColor);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
  }

  if (recompute) {
    data = [[NSData alloc] initWithBytesNoCopy:pointList length:(pointCount * sizeof(CGPoint)) freeWhenDone:YES];
    objc_setAssociatedObject(line, _associatedObjectDataKey, data, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    data = nil;
  }
}

static void _DrawBranchTitle(CGContextRef context, CGFloat x, CGFloat y, CGPoint* previousBranchCorner, GIBranch* branch, NSColor* color, GIGraphOptions options) {
  // Cache common format for multiline string
  static NSMutableDictionary* multilineTitleAttributes = nil;
  if (multilineTitleAttributes == nil) {
    multilineTitleAttributes = [[NSMutableDictionary alloc] init];

    CTFontRef titleFont = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 13.0, CFSTR("en-US"));
    multilineTitleAttributes[NSFontAttributeName] = (__bridge id)titleFont;
    CFRelease(titleFont);

    NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
    style.lineHeightMultiple = 0.85;
    multilineTitleAttributes[NSParagraphStyleAttributeName] = style;
    style = nil;
  }
  multilineTitleAttributes[NSForegroundColorAttributeName] = [color shadowWithLevel:0.2];
  // Cache bold font and calculate darker color for building multiline string
  static CTFontRef boldFont = NULL;
  if (boldFont == NULL) {
    boldFont = CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, 13.0, CFSTR("en-US"));
  }
  NSColor* darkColor = NSColor.labelColor;

  // Start new attributed string for the branch title
  NSMutableAttributedString* multilineTitle = [[NSMutableAttributedString alloc] initWithString:@""];
  [multilineTitle beginEditing];

  for (GCHistoryLocalBranch* localBranch in branch.localBranches) {
    NSString* branchName = localBranch.name;
    NSRange branchNameRange = NSMakeRange(multilineTitle.length, branchName.length);
    _AppendAttributedString((__bridge CFMutableAttributedStringRef)multilineTitle, [NSString stringWithFormat:@"%@\n", branchName], multilineTitleAttributes);
    [multilineTitle addAttribute:NSFontAttributeName value:(__bridge id)boldFont range:branchNameRange];
    [multilineTitle addAttribute:NSForegroundColorAttributeName value:darkColor range:branchNameRange];

    GCBranch* upstream = localBranch.upstream;
    if (upstream) {
      _AppendAttributedString((__bridge CFMutableAttributedStringRef)multilineTitle, [NSString stringWithFormat:@"⬅ %@\n", upstream.name], multilineTitleAttributes);

      NSString* upstreamName = [upstream isKindOfClass:GCRemoteBranch.class] ? [(GCRemoteBranch*)upstream branchName] : upstream.name;
      NSRange upstreamNameRange = NSMakeRange(multilineTitle.length - upstreamName.length - 1, upstreamName.length);  // -1 to exclude '\n'
      [multilineTitle addAttribute:NSForegroundColorAttributeName value:darkColor range:upstreamNameRange];
    }

    _AppendAttributedString((__bridge CFMutableAttributedStringRef)multilineTitle, @"\n", nil);
  }

  for (GCHistoryRemoteBranch* remoteBranch in branch.remoteBranches) {
    NSString* branchName = remoteBranch.branchName;
    _AppendAttributedString((__bridge CFMutableAttributedStringRef)multilineTitle, [NSString stringWithFormat:@"%@\n", remoteBranch.name], multilineTitleAttributes);
    NSRange branchNameRange = NSMakeRange(multilineTitle.length - branchName.length - 1, branchName.length);  // -1 to exclude '\n'
    [multilineTitle addAttribute:NSFontAttributeName value:(__bridge id)boldFont range:branchNameRange];
    [multilineTitle addAttribute:NSForegroundColorAttributeName value:darkColor range:branchNameRange];
  }

  if (branch.remoteBranches.count) {
    _AppendAttributedString((__bridge CFMutableAttributedStringRef)multilineTitle, @"\n", nil);
  }

  for (GCHistoryTag* tag in branch.tags) {
    NSString* tagName = tag.name;
    _AppendAttributedString((__bridge CFMutableAttributedStringRef)multilineTitle, [NSString stringWithFormat:@"[%@]\n", tagName], multilineTitleAttributes);
    NSRange tagNameRange = NSMakeRange(multilineTitle.length - tagName.length - 2, tagName.length);  // -2 to exclude char ']' plus '\n'
    [multilineTitle addAttribute:NSFontAttributeName value:(__bridge id)boldFont range:tagNameRange];
    [multilineTitle addAttribute:NSForegroundColorAttributeName value:darkColor range:tagNameRange];
  }

  if (branch.tags.count) {
    _AppendAttributedString((__bridge CFMutableAttributedStringRef)multilineTitle, @"\n", nil);
  }

  [multilineTitle endEditing];
  if (multilineTitle.length == 0) {
    multilineTitle = nil;
    return;  // This should only happen if we have a detached HEAD with no other references pointing to the commit
  }

  // Prepare CoreText string from the rich attributed title
  CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)multilineTitle);
  CGSize size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, multilineTitle.length), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
  CGRect textRect = CGRectMake(kTitleOffsetX, kTitleOffsetY, ceil(size.width), ceil(size.height));
  CGPathRef path = CGPathCreateWithRect(textRect, NULL);
  CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, multilineTitle.length), path, NULL);
  CFAttributedStringRef ellipsis = CFAttributedStringCreate(kCFAllocatorDefault, CFSTR("\u2026"), (CFDictionaryRef)multilineTitleAttributes);
  CTLineRef ellipsisToken = CTLineCreateWithAttributedString(ellipsis);

  // Rotate context to draw labels with angle
  CGContextSaveGState(context);
  CGContextTranslateCTM(context, x, y);
  CGFloat radians = 45.0 / 180.0 * M_PI;
  CGContextRotateCTM(context, radians);

  // Make a transform copy to calculate rotated corner coordinates
  CGAffineTransform transform = CGAffineTransformRotate(CGAffineTransformTranslate(CGAffineTransformIdentity, x, y), radians);

  // Draw text and separators
  NSColor* separatorColor = [color colorWithAlphaComponent:0.6];
  CGFloat lastLineWidth = 0.0;
  CFArrayRef lines = CTFrameGetLines(frame);
  for (CFIndex i = 0, count = CFArrayGetCount(lines); i < count; ++i) {
    CTLineRef line = CFArrayGetValueAtIndex(lines, i);
    CGPoint origin;
    CTFrameGetLineOrigins(frame, CFRangeMake(i, 1), &origin);

    origin.x += textRect.origin.x + origin.y;
    origin.y += textRect.origin.y;

    CGFloat ascent;
    CGFloat descent;
    CGFloat lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);

    // Draw separator in case of new line which is guaranteed by the building algorithm
    CFRange stringRange = CTLineGetStringRange(line);
    if (stringRange.length == 1) {
      CGRect underlineRect = CGRectMake(floor(origin.x - 1.0), floor(origin.y - 1.0), ceil(lastLineWidth + ascent - descent), ceil(ascent - descent - 1.0));
      CGContextMoveToPoint(context, underlineRect.origin.x + 0.5, underlineRect.origin.y);
      CGContextAddLineToPoint(context, underlineRect.origin.x + underlineRect.size.height + 0.5, underlineRect.origin.y + underlineRect.size.height);
      CGContextAddLineToPoint(context, underlineRect.origin.x + underlineRect.size.width, underlineRect.origin.y + underlineRect.size.height);
      CGContextSetStrokeColorWithColor(context, separatorColor.CGColor);
      CGContextStrokePath(context);
      continue;
    }

#if __DEBUG_BOXES__
    CGRect labelRect = CGRectMake(origin.x, origin.y - descent, lineWidth, ascent + descent);
    CGContextSetRGBFillColor(context, 1.0, 0.0, 0.0, 0.333);
    CGContextFillRect(context, labelRect);
#endif

    // Max width will be reduced if it crosses titles of the next branch
    CGFloat maxBranchTitleWidth = kMaxBranchTitleWidth;
    if (previousBranchCorner) {
      // Calculate the bottom-right coordinates for current line in rotated context
      CGPoint currentTitleCorner = CGPointMake(origin.x + lineWidth, origin.y - descent);
      CGPoint rotatedTitleCorner = CGPointApplyAffineTransform(currentTitleCorner, transform);

      // Calculate angle between bottom-right corner of the current line and top-left corner of the first title in the next branch
      CGFloat angleInRadians = atan2(rotatedTitleCorner.y - previousBranchCorner->y, rotatedTitleCorner.x - previousBranchCorner->x);
      if ((angleInRadians < M_PI / 4.0) && (angleInRadians > -M_PI / 2.0)) {
        // Reduce allowed width to avoid overlapping
        maxBranchTitleWidth = (previousBranchCorner->x - x - kTitleOffsetX) * sqrt(2.0);

#if __DEBUG_TITLE_CORNERS__
        // Draw a red point where the tail would be
        CGRect dotRect = CGRectMake(currentBranchCorner.x - 1.0, currentBranchCorner.y - 1.0, 2.0, 2.0);
        CGContextSetRGBFillColor(context, 1.0, 0.0, 0.0, 1.0);
        CGContextFillRect(context, dotRect);
#endif
      }
    }

    // Draw line with ellipsis in the end if needed
    CGContextSetTextPosition(context, origin.x, origin.y);
    if (lineWidth <= maxBranchTitleWidth) {
      CTLineDraw(line, context);
    } else {
      CTLineRef drawLine = CTLineCreateTruncatedLine(line, maxBranchTitleWidth, kCTLineTruncationEnd, ellipsisToken);
      CTLineDraw(drawLine, context);
      CFRelease(drawLine);
    }

    // Remember last line width for the next separator below
    lastLineWidth = MIN(lineWidth, maxBranchTitleWidth);
  }

  // Reset context
  CGContextRestoreGState(context);

  if (previousBranchCorner) {
#if __DEBUG_TITLE_CORNERS__
    // Draw previous corner using semi-transparent red dot for debugging needs
    CGRect dotRect = CGRectMake(previousBranchCorner->x - 1.0, previousBranchCorner->y - 1.0, 2.0, 2.0);
    CGContextSetRGBFillColor(context, 1.0, 0.0, 0.0, 0.333);
    CGContextFillRect(context, dotRect);
#endif

    // Remember top-left title coordinates to limit drawing area for the left branch
    previousBranchCorner->x = x - kTitleOffsetX;
    previousBranchCorner->y = y + (size.height + kTitleOffsetY) * sqrt(2.0);
  }

  // Clean up
  multilineTitle = nil;
  CGPathRelease(path);
  CFRelease(ellipsisToken);
  CFRelease(ellipsis);
  CFRelease(frame);
  CFRelease(framesetter);
}

static void _DrawNodeLabels(CGContextRef context, CGFloat x, CGFloat y, GINode* node, NSDictionary* tagAttributes, NSDictionary* branchAttributes) {
  GCHistoryCommit* commit = node.commit;

  // Generate text
  NSMutableString* label = [[NSMutableString alloc] init];
  NSUInteger separator = NSNotFound;
  if (tagAttributes) {
    NSUInteger index = 0;
    for (GCHistoryTag* tag in commit.tags) {
      if (index) {
        [label appendString:@", "];
      }
      [label appendString:tag.name];
      if (tag.annotation) {
        [label appendString:@"*"];
      }
      ++index;
    }
  }
  if (branchAttributes) {
    NSUInteger index = 0;
    for (GCHistoryLocalBranch* branch in commit.localBranches) {
      if (separator == NSNotFound) {
        separator = label.length;
        if (separator) {
          [label appendString:@"\n"];
        }
      }
      if (index) {
        [label appendString:@", "];
      }
      [label appendString:branch.name];
      ++index;
    }
    for (GCHistoryRemoteBranch* branch in commit.remoteBranches) {
      if (separator == NSNotFound) {
        separator = label.length;
        if (separator) {
          [label appendString:@"\n"];
        }
      }
      if (index) {
        [label appendString:@", "];
      }
      [label appendString:branch.name];
      ++index;
    }
  }

  if (label.length) {
    // Prepare text

    CFMutableAttributedStringRef string = CFAttributedStringCreateMutable(kCFAllocatorDefault, label.length);
    CFAttributedStringBeginEditing(string);
    CFAttributedStringReplaceString(string, CFRangeMake(0, 0), (CFStringRef)label);
    if (separator != NSNotFound) {
      CFAttributedStringSetAttributes(string, CFRangeMake(0, separator), (CFDictionaryRef)tagAttributes, true);
      CFAttributedStringSetAttributes(string, CFRangeMake(separator, label.length - separator), (CFDictionaryRef)branchAttributes, true);
    } else {
      CFAttributedStringSetAttributes(string, CFRangeMake(0, label.length), (CFDictionaryRef)tagAttributes, true);
    }
    CFAttributedStringEndEditing(string);

    CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(string);
    CGSize size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, CFAttributedStringGetLength(string)), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
    XLOG_DEBUG_CHECK(size.height <= kNodeLabelMaxHeight);
    CGRect textRect = CGRectMake(kLabelOffsetX, kLabelOffsetY, ceil(size.width), ceil(size.height));
    CGPathRef path = CGPathCreateWithRect(textRect, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, CFAttributedStringGetLength(string)), path, NULL);
    CFAttributedStringRef tagCharacter = CFAttributedStringCreate(kCFAllocatorDefault, CFSTR("\u2026"), (CFDictionaryRef)tagAttributes);
    CTLineRef tagToken = CTLineCreateWithAttributedString(tagCharacter);
    CFAttributedStringRef branchCharacter = CFAttributedStringCreate(kCFAllocatorDefault, CFSTR("\u2026"), (CFDictionaryRef)branchAttributes);
    CTLineRef branchToken = CTLineCreateWithAttributedString(branchCharacter);

    // Prepare context

    CGContextSaveGState(context);
    CGContextTranslateCTM(context, x, y);

    // Draw label

    CGRect labelRect = CGRectInset(CGRectMake(textRect.origin.x, textRect.origin.y, MIN(textRect.size.width, kNodeLabelMaxWidth), textRect.size.height), -3.5, -2.5);
    CGContextSetFillColorWithColor(context, [NSColor.textBackgroundColor colorWithAlphaComponent:0.85].CGColor);
    GICGContextAddRoundedRect(context, labelRect, 4.0);
    CGContextFillPath(context);
    CGContextSetStrokeColorWithColor(context, NSColor.secondaryLabelColor.CGColor);
    GICGContextAddRoundedRect(context, labelRect, 4.0);
    CGContextStrokePath(context);

    CGContextMoveToPoint(context, 0, 0);
    CGContextAddLineToPoint(context, labelRect.origin.x + 1, labelRect.origin.y + 1);
    CGContextStrokePath(context);

    CGContextSetFillColorWithColor(context, NSColor.secondaryLabelColor.CGColor);
    CGContextFillEllipseInRect(context, CGRectMake(-2, -2, 4, 4));

    // Draw text

    CGContextSetFillColorWithColor(context, NSColor.secondaryLabelColor.CGColor);
    CFArrayRef lines = CTFrameGetLines(frame);
    for (CFIndex i = 0, count = CFArrayGetCount(lines); i < count; ++i) {
      CTLineRef line = CFArrayGetValueAtIndex(lines, i);
      CGPoint origin;
      CTFrameGetLineOrigins(frame, CFRangeMake(i, 1), &origin);
      CGContextSetTextPosition(context, textRect.origin.x + origin.x, textRect.origin.y + origin.y);
      if (size.width <= kNodeLabelMaxWidth) {
        CTLineDraw(line, context);
      } else {
        CFRange range = CTLineGetStringRange(line);
        CTLineRef drawLine = CTLineCreateTruncatedLine(line, kNodeLabelMaxWidth, kCTLineTruncationEnd, range.location >= (CFIndex)separator ? branchToken : tagToken);
        CTLineDraw(drawLine, context);
        CFRelease(drawLine);
      }
    }

    // Reset context

    CGContextRestoreGState(context);

    // Clean up

    CFRelease(branchToken);
    CFRelease(branchCharacter);
    CFRelease(tagToken);
    CFRelease(tagCharacter);
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(framesetter);
    CFRelease(string);
  }

  // Clean up
  label = nil;
}

static void _DrawHead(CGContextRef context, CGFloat x, CGFloat y, BOOL isDetached, CGColorRef color, NSDictionary* attributes) {
  CGRect rect = CGRectMake(-18, -9, 36, 18);

  // Prepare context

  CGContextSaveGState(context);
  CGContextTranslateCTM(context, x, y);

  // Draw label

  if (isDetached) {
    // This looks bad if transparent (e.g. secondary label colour). Looks a bit odd if light in dark mode too, so just use fixed colour for now.
    CGContextSetRGBFillColor(context, 0.4, 0.4, 0.4, 1.0);
  } else {
    CGContextSetFillColorWithColor(context, color);
  }
  GICGContextAddRoundedRect(context, rect, 4.0);
  CGContextFillPath(context);

  if (!isDetached) {
    // This looks bad if transparent (e.g. secondary label colour). Looks a bit odd if light in dark mode too, so just use fixed colour for now.
    CGContextSetRGBStrokeColor(context, 0.4, 0.4, 0.4, 1.0);
    CGContextSetLineWidth(context, 2);
    GICGContextAddRoundedRect(context, rect, 4.0);
    CGContextStrokePath(context);
  }

  // Draw text

  CFAttributedStringRef string = CFAttributedStringCreate(kCFAllocatorDefault, CFSTR("HEAD"), (CFDictionaryRef)attributes);
  CTLineRef line = CTLineCreateWithAttributedString(string);
  CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
  CGContextSetTextPosition(context, -15, -4);
  CTLineDraw(line, context);
  CFRelease(line);
  CFRelease(string);

  // Reset context

  CGContextRestoreGState(context);
}

static inline void _AppendAttributedString(CFMutableAttributedStringRef string, NSString* text, NSDictionary* attributes) {
  CFIndex length = CFAttributedStringGetLength(string);
  CFAttributedStringReplaceString(string, CFRangeMake(length, 0), (CFStringRef)text);
  if (attributes) {
    CFAttributedStringSetAttributes(string, CFRangeMake(length, text.length), (CFDictionaryRef)attributes, true);
  }
}

static void _DrawSelectedNode(CGContextRef context, CGFloat x, CGFloat y, GINode* node, NSDictionary* attributes1, NSDictionary* attributes2, NSDateFormatter* dateFormatter, BOOL isFirstResponder) {
  GCHistoryCommit* commit = node.commit;

  // Generate text

  CFMutableAttributedStringRef string = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0);
  CFAttributedStringBeginEditing(string);
#if DEBUG
  _AppendAttributedString(string, [NSString stringWithFormat:@"{%lu} ", node.layer.index], attributes2);
#endif
  _AppendAttributedString(string, [NSString stringWithFormat:@"%@: ", commit.shortSHA1], attributes2);
  _AppendAttributedString(string, commit.summary, attributes1);
  _AppendAttributedString(string, @"\nAuthor: ", attributes2);
  _AppendAttributedString(string, commit.author, attributes1);
  _AppendAttributedString(string, @"\nDate: ", attributes2);
  _AppendAttributedString(string, [NSString stringWithFormat:@"%@ (%@)", [dateFormatter stringFromDate:commit.date], GIFormatDateRelativelyFromNow(commit.date, NO)], attributes1);
  if (commit.hasReferences) {
    if (commit.localBranches.count) {
      _AppendAttributedString(string, @"\nLocal Branches: ", attributes2);
      NSUInteger index = 0;
      for (GCHistoryTag* branch in commit.localBranches) {
        if (index > 0) {
          _AppendAttributedString(string, @", ", attributes1);
        }
        _AppendAttributedString(string, branch.name, attributes1);
        ++index;
      }
    }
    if (commit.remoteBranches.count) {
      _AppendAttributedString(string, @"\nRemote Branches: ", attributes2);
      NSUInteger index = 0;
      for (GCHistoryTag* branch in commit.remoteBranches) {
        if (index > 0) {
          _AppendAttributedString(string, @", ", attributes1);
        }
        _AppendAttributedString(string, branch.name, attributes1);
        ++index;
      }
    }
    if (commit.tags.count) {
      _AppendAttributedString(string, @"\nTags: ", attributes2);
      NSUInteger index = 0;
      for (GCHistoryTag* tag in commit.tags) {
        if (index > 0) {
          _AppendAttributedString(string, @", ", attributes1);
        }
        _AppendAttributedString(string, tag.name, attributes1);
        ++index;
      }
    }
  }
  CFAttributedStringEndEditing(string);

  // Prepare text

  CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(string);
  CGSize size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, CFAttributedStringGetLength(string)), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
  XLOG_DEBUG_CHECK(size.height <= kSelectedLabelMaxHeight);
  CGRect textRect = CGRectMake(kSelectedOffsetX, -ceil(size.height) / 2, ceil(size.width), ceil(size.height));
  CGPathRef path = CGPathCreateWithRect(textRect, NULL);
  CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, CFAttributedStringGetLength(string)), path, NULL);
  CFAttributedStringRef character = CFAttributedStringCreate(kCFAllocatorDefault, CFSTR("\u2026"), (CFDictionaryRef)attributes1);
  CTLineRef token = CTLineCreateWithAttributedString(character);

  // Prepare label

  CGRect labelRect = CGRectMake(textRect.origin.x, textRect.origin.y, MIN(textRect.size.width, kSelectedLabelMaxWidth), textRect.size.height);
  labelRect.origin.x -= 1;
  labelRect.size.width += 5;
  labelRect.origin.y -= 4;
  labelRect.size.height += 8;

  CGMutablePathRef labelPath = CGPathCreateMutable();

  CGPathMoveToPoint(labelPath, NULL, labelRect.origin.x + kSelectedCornerRadius, labelRect.origin.y);
  CGPathAddLineToPoint(labelPath, NULL, labelRect.origin.x + labelRect.size.width - kSelectedCornerRadius, labelRect.origin.y);
  CGPathAddQuadCurveToPoint(labelPath, NULL, labelRect.origin.x + labelRect.size.width, labelRect.origin.y, labelRect.origin.x + labelRect.size.width, labelRect.origin.y + kSelectedCornerRadius);
  CGPathAddLineToPoint(labelPath, NULL, labelRect.origin.x + labelRect.size.width, labelRect.origin.y + labelRect.size.height - kSelectedCornerRadius);
  CGPathAddQuadCurveToPoint(labelPath, NULL, labelRect.origin.x + labelRect.size.width, labelRect.origin.y + labelRect.size.height, labelRect.origin.x + labelRect.size.width - kSelectedCornerRadius, labelRect.origin.y + labelRect.size.height);
  CGPathAddLineToPoint(labelPath, NULL, labelRect.origin.x + kSelectedCornerRadius, labelRect.origin.y + labelRect.size.height);

  CGPathAddCurveToPoint(labelPath, NULL, 14, labelRect.origin.y + labelRect.size.height, labelRect.origin.x + kSelectedCornerRadius, kSelectedTipHeight, 5, kSelectedTipHeight);
  CGPathAddLineToPoint(labelPath, NULL, 0, kSelectedTipHeight);
  CGPathAddArc(labelPath, NULL, 0, 0, kSelectedTipHeight, M_PI_2, -M_PI_2, false);
  CGPathAddLineToPoint(labelPath, NULL, 5, -kSelectedTipHeight);
  CGPathAddCurveToPoint(labelPath, NULL, labelRect.origin.x + kSelectedCornerRadius, -kSelectedTipHeight, 14, labelRect.origin.y, labelRect.origin.x + kSelectedCornerRadius, labelRect.origin.y);

  // Prepare context

  CGContextSaveGState(context);
  CGContextTranslateCTM(context, x, y);

  // Draw label

  if (isFirstResponder) {
    CGContextSetFillColorWithColor(context, [[NSColor alternateSelectedControlColor] CGColor]);  // NSTableView focused highlight color
  } else {
    CGContextSetFillColorWithColor(context, [[NSColor secondarySelectedControlColor] CGColor]);  // NSTableView unfocused highlight color
  }
  CGContextAddPath(context, labelPath);
  CGContextFillPath(context);

  CGContextSetStrokeColorWithColor(context, NSColor.textBackgroundColor.CGColor);
  CGContextSetLineWidth(context, kSelectedBorderWidth);
  CGContextAddPath(context, labelPath);
  CGContextStrokePath(context);

  // Draw node

  CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
  CGContextFillEllipseInRect(context, CGRectMake(-4, -4, 8, 8));

  // Draw text

  if (isFirstResponder) {
    CGContextSetFillColorWithColor(context, [[NSColor alternateSelectedControlTextColor] CGColor]);
  } else {
    CGContextSetFillColorWithColor(context, NSColor.secondaryLabelColor.CGColor);
  }
  CFArrayRef lines = CTFrameGetLines(frame);
  for (CFIndex i = 0, count = CFArrayGetCount(lines); i < count; ++i) {
    CTLineRef line = CFArrayGetValueAtIndex(lines, i);
    CGPoint origin;
    CTFrameGetLineOrigins(frame, CFRangeMake(i, 1), &origin);
    CGContextSetTextPosition(context, textRect.origin.x + origin.x, textRect.origin.y + origin.y);
    if (size.width <= kSelectedLabelMaxWidth) {
      CTLineDraw(line, context);
    } else {
      CTLineRef drawLine = CTLineCreateTruncatedLine(line, kSelectedLabelMaxWidth, kCTLineTruncationEnd, token);
      CTLineDraw(drawLine, context);
      CFRelease(drawLine);
    }
  }

  // Reset context

  CGContextRestoreGState(context);

  // Clean up

  CGPathRelease(labelPath);
  CFRelease(token);
  CFRelease(character);
  CFRelease(frame);
  CGPathRelease(path);
  CFRelease(framesetter);
  CFRelease(string);
}

- (NSUInteger)_indexOfLayerContainingPosition:(CGFloat)position {
  XLOG_DEBUG_CHECK(_graph.layers.count);
  NSArray* layers = _graph.layers;
  CGFloat offset = _graph.size.height;

  GILayer* firstLayer = layers.firstObject;
  if (position > CONVERT_Y(offset - firstLayer.y)) {
    return firstLayer.index;
  }

  GILayer* lastLayer = layers.lastObject;
  if (position < CONVERT_Y(offset - lastLayer.y)) {
    return lastLayer.index;
  }

  NSRange range = NSMakeRange(0, layers.count);
  while (1) {
    NSUInteger index = range.location + range.length / 2;
    GILayer* layer = layers[index];
    CGFloat y = CONVERT_Y(offset - layer.y);
    if (position > y) {
      range = NSMakeRange(range.location, index - range.location);
    } else {
      range = NSMakeRange(index, range.location + range.length - index);
    }
    if (range.length == 1) {
      return range.location;
    }
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  GIGraphOptions graphOptions = _graph.options;
  NSArray* layers = _graph.layers;
  NSUInteger layerCount = layers.count;
  NSUInteger startIndex = layerCount ? [self _indexOfLayerContainingPosition:(dirtyRect.origin.y + dirtyRect.size.height + kOverdrawMargin)] : NSNotFound;
  NSUInteger endIndex = layerCount ? [self _indexOfLayerContainingPosition:dirtyRect.origin.y - kOverdrawMargin] : 0;
  NSIndexSet* indexes = layerCount ? [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(startIndex, MIN(endIndex + 1, layerCount) - startIndex)] : [[NSIndexSet alloc] init];
  CGFloat offset = _graph.size.height;
  NSMutableSet* lines = [[NSMutableSet alloc] init];

  // Cache attributes
  static NSDictionary* tagAttributes = nil;
  if (tagAttributes == nil) {
    CTFontRef font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 11.0, CFSTR("en-US"));
    tagAttributes = @{(id)kCTForegroundColorFromContextAttributeName : (id)kCFBooleanTrue,
                      (id)kCTFontAttributeName : (__bridge id)font};
    CFRelease(font);
  }
  static NSDictionary* branchAttributes = nil;
  if (branchAttributes == nil) {
    CTFontRef font = CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, 11.0, CFSTR("en-US"));
    branchAttributes = @{(id)kCTForegroundColorFromContextAttributeName : (id)kCFBooleanTrue,
                         (id)kCTFontAttributeName : (__bridge id)font};
    CFRelease(font);
  }
  static NSDictionary* selectedAttributes1 = nil;
  if (selectedAttributes1 == nil) {
    CTFontRef font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 10.0, CFSTR("en-US"));
    selectedAttributes1 = @{(id)kCTForegroundColorFromContextAttributeName : (id)kCFBooleanTrue,
                            (id)kCTFontAttributeName : (__bridge id)font};
    CFRelease(font);
  }
  static NSDictionary* selectedAttributes2 = nil;
  if (selectedAttributes2 == nil) {
    CTFontRef font = CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, 10.0, CFSTR("en-US"));
    selectedAttributes2 = @{(id)kCTForegroundColorFromContextAttributeName : (id)kCFBooleanTrue,
                            (id)kCTFontAttributeName : (__bridge id)font};
    CFRelease(font);
  }

  // Set up graphics context
  CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
  CGContextSaveGState(context);
  CGContextSetTextDrawingMode(context, kCGTextFill);
  CGContextSetTextMatrix(context, CGAffineTransformIdentity);

#if __DEBUG_DRAWING__
  // Draw background
  CGContextSetFillColorWithColor(context, [[NSColor colorWithDeviceHue:(CGFloat)(random() % 1000) / 1000.0 saturation:0.25 brightness:0.75 alpha:1.0] CGColor]);
  CGContextFillRect(context, dirtyRect);

  // Draw grid
  CGContextSetLineWidth(context, 1);
  CGContextSetRGBStrokeColor(context, 1.0, 1.0, 1.0, 0.25);
  [layers enumerateObjectsAtIndexes:indexes
                            options:0
                         usingBlock:^(GILayer* layer, NSUInteger index, BOOL* stop) {
                           CGFloat y = CONVERT_Y(offset - layer.y);
                           CGContextMoveToPoint(context, dirtyRect.origin.x, y);
                           CGContextAddLineToPoint(context, dirtyRect.origin.x + dirtyRect.size.width, y);
                           CGContextStrokePath(context);
                         }];
  for (NSUInteger i = 0; i < 100; ++i) {
    CGFloat x = CONVERT_X(i);
    CGContextMoveToPoint(context, x, dirtyRect.origin.y);
    CGContextAddLineToPoint(context, x, dirtyRect.origin.y + dirtyRect.size.height);
    CGContextStrokePath(context);
  }
#endif

  // Draw all lines in the drawing area
  {
    // Can’t multiply against a dark background.
    if (!self.effectiveAppearance.matchesDarkAppearance) {
      CGContextSetBlendMode(context, kCGBlendModeMultiply);
    }

    [layers enumerateObjectsAtIndexes:indexes
                              options:0
                           usingBlock:^(GILayer* layer, NSUInteger index, BOOL* stop) {
                             for (GILine* line in layer.lines) {
                               if ([lines containsObject:line]) {
                                 continue;
                               }
                               [self drawLine:line inContext:context clampedToRect:dirtyRect];
                               [lines addObject:line];
                             }
                           }];

    CGContextSetBlendMode(context, kCGBlendModeNormal);
  }

  // Draw nodes
  CGContextSetLineWidth(context, 1);
  [layers enumerateObjectsAtIndexes:indexes
                            options:0
                         usingBlock:^(GILayer* layer, NSUInteger index, BOOL* stop) {
                           CGFloat y = CONVERT_Y(offset - layer.y);
                           for (GINode* node in layer.nodes) {
                             CGFloat x = CONVERT_X(node.x);

                             if (layer.index == 0) {
                               _DrawTipNode(node, context, x, y);
                               continue;
                             }

                             if (node.dummy) {
#if __DEBUG_DRAWING__
                               CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
                               CGContextFillRect(context, CGRectMake(x - 2, y - 2, 4, 4));
                               CGContextSetRGBFillColor(context, 0.0, 0.0, 0.0, 1.0);
                               CGContextFillRect(context, CGRectMake(x - 1, y - 1, 2, 2));
#endif
                               continue;
                             }

                             if (node.commit.root) {
                               _DrawRootNode(node, context, x, y);
                               continue;
                             }

                             _DrawNode(node, context, x, y);
                           }
                         }];

#if __DEBUG_MAIN_LINE__ || __DEBUG_DESCENDANTS__ || __DEBUG_ANCESTORS__
  // Draw highlighted debug nodes
  if (_selectedNode) {
    CGContextSetLineWidth(context, 3);
    CGContextSetRGBStrokeColor(context, 0.0, 0.0, 0.0, 1.0);
#if __DEBUG_MAIN_LINE__
    [_graph walkMainLineForAncestorsOfNode:_selectedNode
                                usingBlock:^(GINode* node, BOOL* stop) {
                                  CGFloat x = CONVERT_X(node.x);
                                  CGFloat y = CONVERT_Y(offset - node.layer.y);
                                  if (y < dirtyRect.origin.y + dirtyRect.size.height + kSpacingY / 2) {
                                    CGContextStrokeEllipseInRect(context, CGRectMake(x - 5, y - 5, 10, 10));
                                    if (y < dirtyRect.origin.y - kSpacingY / 2) {
                                      *stop = YES;
                                    }
                                  }
                                }];
#elif __DEBUG_DESCENDANTS__ || __DEBUG_ANCESTORS__
    __block NSUInteger count = 1;
    void (^commitBlock)(GCHistoryCommit*, BOOL*) = ^(GCHistoryCommit* commit, BOOL* stop) {
      GINode* node = [_graph nodeForCommit:commit];
      if (node) {
        CGFloat x = CONVERT_X(node.x);
        CGFloat y = CONVERT_Y(offset - node.layer.y);
        if ((y < dirtyRect.origin.y + dirtyRect.size.height + kSpacingY / 2) && (y > dirtyRect.origin.y - kSpacingY / 2)) {
          CGContextStrokeEllipseInRect(context, CGRectMake(x - 5, y - 5, 10, 10));
          CFAttributedStringRef string = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)[NSString stringWithFormat:@"%lu", count], NULL);
          CTLineRef line = CTLineCreateWithAttributedString(string);
          CGContextSetTextPosition(context, x + 8, y);
          CTLineDraw(line, context);
          CFRelease(line);
          CFRelease(string);
        }
        ++count;
      }
    };
#if __DEBUG_DESCENDANTS__
    [_graph.history walkDescendantsOfCommits:@[ _selectedNode.commit ]
                                  usingBlock:commitBlock];
#elif __DEBUG_ANCESTORS__
    [_graph.history walkAncestorsOfCommits:@[ _selectedNode.commit ]
                                usingBlock:commitBlock];
#else
#error
#endif
#else
#error
#endif
  }
#endif

  // Draw node labels
  if (_showsTagLabels || _showsBranchLabels) {
    CGContextSetLineWidth(context, 1);
    for (GINode* node in _graph.nodesWithReferences) {
      if (node == _selectedNode) {
        continue;
      }
      CGFloat x = CONVERT_X(node.x);
      CGFloat y = CONVERT_Y(offset - node.layer.y);
      if (NSIntersectsRect(NODE_LABEL_BOUNDS(x, y), dirtyRect)) {
#if __DEBUG_BOXES__
        CGContextSetRGBFillColor(context, 1.0, 0.0, 0.0, 0.666);
        CGContextFillRect(context, NODE_LABEL_BOUNDS(x, y));
#endif
        _DrawNodeLabels(context, x, y, node,
                        _showsTagLabels && (node.layer.index > 0) ? tagAttributes : nil,
                        _showsBranchLabels && (node.layer.index > 0) ? branchAttributes : nil);
      }
    }
  }

  // Draw HEAD
  GCHistoryCommit* headCommit = _graph.history.HEADCommit;
  if (headCommit) {
    GINode* headNode = nil;
    if (!_graph.history.HEADDetached && layers.count) {
      for (GINode* node in [(GILayer*)layers[0] nodes]) {
        if ([node.commit isEqualToCommit:headCommit]) {
          headNode = node;
        }
      }
    }
    if (headNode == nil) {
      headNode = [_graph nodeForCommit:headCommit];
    }
    if (headNode) {
      CGFloat x = CONVERT_X(headNode.x);
      CGFloat y = CONVERT_Y(offset - headNode.layer.y);
      if (NSIntersectsRect(HEAD_BOUNDS(x, y), dirtyRect)) {
#if __DEBUG_BOXES__
        CGContextSetRGBFillColor(context, 1.0, 0.0, 0.0, 0.666);
        CGContextFillRect(context, HEAD_BOUNDS(x, y));
#endif
        _DrawHead(context, x, y, !_graph.history.HEADBranch, headNode.primaryLine.color.CGColor, tagAttributes);
      }
    }
  }

  // Draw branch titles in reverse order
  if (startIndex == 0) {
    // Avoid overlapping by remembering coordinates of the previous title corner
    CGPoint previousBranchCorner = CGPointMake(CGFLOAT_MAX, 0.0);
    for (GIBranch* branch in _graph.branches.reverseObjectEnumerator) {
      GINode* node = branch.tipNode;
      CGFloat x = CONVERT_X(node.x);
      CGFloat y = CONVERT_Y(offset - node.layer.y);
      _DrawBranchTitle(context, x, y, &previousBranchCorner, branch, node.primaryLine.color, graphOptions);
    }
  }

  // Draw selected node if any
  if (_selectedNode) {
    CGFloat x = CONVERT_X(_selectedNode.x);
    CGFloat y = CONVERT_Y(offset - _selectedNode.layer.y);
    if (NSIntersectsRect(SELECTED_NODE_BOUNDS(x, y), dirtyRect)) {
#if __DEBUG_BOXES__
      CGContextSetRGBFillColor(context, 1.0, 0.0, 0.0, 0.666);
      CGContextFillRect(context, SELECTED_NODE_BOUNDS(x, y));
#endif
      _DrawSelectedNode(context, x, y, _selectedNode, selectedAttributes1, selectedAttributes2, _dateFormatter, self.window.keyWindow && (self.window.firstResponder == self));
    }
  }

  // Draw selected node if any
  if (_lastSelectedNode) {
    CGFloat x = CONVERT_X(_lastSelectedNode.x);
    CGFloat y = CONVERT_Y(offset - _lastSelectedNode.layer.y);
    if (NSIntersectsRect(SELECTED_NODE_BOUNDS(x, y), dirtyRect)) {
#if __DEBUG_BOXES__
      CGContextSetRGBFillColor(context, 1.0, 0.0, 0.0, 0.666);
      CGContextFillRect(context, SELECTED_NODE_BOUNDS(x, y));
#endif
      _DrawSelectedNode(context, x, y, _lastSelectedNode, selectedAttributes1, selectedAttributes2, _dateFormatter, self.window.keyWindow && (self.window.firstResponder == self));
    }
  }

  // Restore graphics context
  CGContextRestoreGState(context);

  // Clean up
  lines = nil;
}

@end

@implementation GIGraphView (NSScrollView)

- (GINode*)focusedNode {
  NSScrollView* scrollView = self.enclosingScrollView;
  NSRect rect = scrollView.documentVisibleRect;
  return [self _findNodeAtPosition:NSMakePoint(rect.origin.x + rect.size.width / 2, rect.origin.y + rect.size.height / 2) closest:YES];
}

- (void)_scrollToRect:(NSRect)rect {
  NSScrollView* scrollView = self.enclosingScrollView;
  if (!NSContainsRect(scrollView.documentVisibleRect, NSInsetRect(rect, 0, -kScrollingInset))) {
    [scrollView scrollToVisibleRect:rect];
    [scrollView flashScrollers];
  }
}

- (void)scrollToNode:(GINode*)node {
  NSPoint position = [self positionForNode:node];
  [self _scrollToRect:NSMakeRect(position.x - kSpacingX / 2, position.y - kSpacingY / 2, kSpacingX, kSpacingY)];
}

- (void)scrollToSelection {
  if (_selectedNode) {
    NSPoint position = [self positionForNode:_selectedNode];
    [self _scrollToRect:SELECTED_NODE_BOUNDS(position.x, position.y)];
  }
}

- (void)_scrollToTop {
  NSScrollView* scrollView = self.enclosingScrollView;
  NSRect bounds = scrollView.contentView.bounds;
  [scrollView scrollToPoint:NSMakePoint(bounds.origin.x, _minSize.height - bounds.size.height)];
  [scrollView flashScrollers];
}

- (void)_scrollToBottom {
  NSScrollView* scrollView = self.enclosingScrollView;
  NSRect bounds = scrollView.contentView.bounds;
  [scrollView scrollToPoint:NSMakePoint(bounds.origin.x, 0)];
  [scrollView flashScrollers];
}

- (void)_scrollToLeft {
  NSScrollView* scrollView = self.enclosingScrollView;
  NSRect bounds = scrollView.contentView.bounds;
  [scrollView scrollToPoint:NSMakePoint(0, bounds.origin.y)];
  [scrollView flashScrollers];
}

- (void)_scrollToRight {
  NSScrollView* scrollView = self.enclosingScrollView;
  NSRect bounds = scrollView.contentView.bounds;
  [scrollView scrollToPoint:NSMakePoint(_minSize.width - bounds.size.width, bounds.origin.y)];
  [scrollView flashScrollers];
}

- (void)scrollToTip {
  [self _scrollToTop];
}

@end
