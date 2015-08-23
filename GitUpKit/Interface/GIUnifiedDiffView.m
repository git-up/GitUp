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

#import "GIPrivate.h"

#define kTextLineNumberMargin (5 * 8)
#define kTextInsetLeft 15
#define kTextInsetRight 5
#define kTextBottomPadding 0

typedef NS_ENUM(NSUInteger, SelectionMode) {
  kSelectionMode_None = 0,
  kSelectionMode_Replace,
  kSelectionMode_Extend,
  kSelectionMode_Inverse
};

typedef struct {
  NSUInteger index;
  CFRange range;  // Absolute
  GCLineDiffChange change;
  NSUInteger oldLineNumber;
  NSUInteger newLineNumber;
  CFRange highlighted;  // Relative to line
  
  const char* contentBytes;  // Not valid outside of patch generation
  NSUInteger contentLength;  // Not valid outside of patch generation
} LineInfo;

@implementation GIUnifiedDiffView {
  CFMutableAttributedStringRef _string;
  NSUInteger _lineInfoMax;
  NSUInteger _lineInfoCount;
  LineInfo* _lineInfoList;
  CTFramesetterRef _framesetter;
  CTFrameRef _frame;
  NSSize _size;
  
  NSMutableIndexSet* _selectedLines;
  CFRange _selectedText;
  SelectionMode _selectionMode;
  NSIndexSet* _startLines;
  NSUInteger _deletedIndex;
}

- (void)didFinishInitializing {
  [super didFinishInitializing];
  
  _selectedLines = [[NSMutableIndexSet alloc] init];
}

- (void)dealloc {
  if (_frame) {
    CFRelease(_frame);
  }
  if (_framesetter) {
    CFRelease(_framesetter);
  }
  if (_string) {
    CFRelease(_string);
  }
  if (_lineInfoList) {
    free(_lineInfoList);
  }
}

- (BOOL)isEmpty {
  return (_string && !CFAttributedStringGetLength(_string));
}

- (void)_addLineWithString:(CFStringRef)string
                    change:(GCLineDiffChange)change
             oldLineNumber:(NSUInteger)oldLineNumber
             newLineNumber:(NSUInteger)newLineNumber
              contentBytes:(const char*)contentBytes
             contentLength:(NSUInteger)contentLength
{
  CFIndex length = CFAttributedStringGetLength(_string);
  CFAttributedStringReplaceString(_string, CFRangeMake(length, 0), string);
  
  if (_lineInfoCount == _lineInfoMax) {
    _lineInfoMax *= 2;
    _lineInfoList = realloc(_lineInfoList, _lineInfoMax * sizeof(LineInfo));
  }
  LineInfo* info = &_lineInfoList[_lineInfoCount];
  info->index = _lineInfoCount;
  info->range = CFRangeMake(length, CFStringGetLength(string));
  info->change = change;
  info->oldLineNumber = oldLineNumber;
  info->newLineNumber = newLineNumber;
  info->highlighted.length = 0;
  info->contentBytes = contentBytes;
  info->contentLength = contentLength;
  _lineInfoCount += 1;
}

- (void)didUpdatePatch {
  [super didUpdatePatch];
  
  if (_frame) {
    CFRelease(_frame);
    _frame = NULL;
  }
  if (_framesetter) {
    CFRelease(_framesetter);
    _framesetter = NULL;
  }
  if (_string) {
    CFRelease(_string);
    _string = NULL;
  }
  if (_lineInfoList) {
    free(_lineInfoList);
    _lineInfoList = NULL;
  }
  
  if (self.patch) {
    _string = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0);
    _lineInfoCount = 0;
    _lineInfoMax = 512;
    _lineInfoList = malloc(_lineInfoMax * sizeof(LineInfo));
    
    __block NSUInteger deletedIndex = NSNotFound;
    __block NSUInteger addedIndex = NSNotFound;
    void (^highlightBlock)(NSUInteger) = ^(NSUInteger index) {
      if ((deletedIndex != NSNotFound) && (addedIndex != NSNotFound) && (index - addedIndex == addedIndex - deletedIndex)) {
        for (NSUInteger i = 0; i < addedIndex - deletedIndex; ++i) {
          LineInfo* deletedInfo = &_lineInfoList[deletedIndex + i];
          LineInfo* addedInfo = &_lineInfoList[addedIndex + i];
          GIComputeHighlightRanges(deletedInfo->contentBytes, deletedInfo->contentLength, deletedInfo->range.length, &deletedInfo->highlighted,
                                   addedInfo->contentBytes, addedInfo->contentLength, addedInfo->range.length, &addedInfo->highlighted);
        }
      }
    };
    [self.patch enumerateUsingBeginHunkHandler:^(NSUInteger oldLineNumber, NSUInteger oldLineCount, NSUInteger newLineNumber, NSUInteger newLineCount) {
      
      CFStringRef string = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("@@ -%lu,%lu +%lu,%lu @@\n"), oldLineNumber, oldLineCount, newLineNumber, newLineCount);
      [self _addLineWithString:string change:NSNotFound oldLineNumber:oldLineNumber newLineNumber:newLineNumber contentBytes:NULL contentLength:0];
      CFRelease(string);
      
      deletedIndex = NSNotFound;
      addedIndex = NSNotFound;
      
    } lineHandler:^(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber, const char* contentBytes, NSUInteger contentLength) {
      
      CFStringRef string;
      if (contentBytes[contentLength - 1] != '\n') {
        size_t length = strlen(GIDiffViewMissingNewlinePlaceholder);
        char* buffer = malloc(contentLength + length);
        bcopy(contentBytes, buffer, contentLength);
        bcopy(GIDiffViewMissingNewlinePlaceholder, &buffer[contentLength], length);
        string = CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, (const UInt8*)buffer, (contentLength + length), kCFStringEncodingUTF8, false, kCFAllocatorMalloc);
      } else {
        string = CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, (const UInt8*)contentBytes, contentLength, kCFStringEncodingUTF8, false, kCFAllocatorNull);
      }
      if (string == NULL) {
        string = CFSTR("<LINE IS NOT VALID UTF-8>\n");
        XLOG_DEBUG_UNREACHABLE();
      }
      [self _addLineWithString:string change:change oldLineNumber:oldLineNumber newLineNumber:newLineNumber contentBytes:contentBytes contentLength:contentLength];
      CFRelease(string);
      
      if (change == kGCLineDiffChange_Deleted) {
        if (deletedIndex == NSNotFound) {
          deletedIndex = _lineInfoCount - 1;
        }
      } else if (change == kGCLineDiffChange_Added) {
        if (addedIndex == NSNotFound) {
          addedIndex = _lineInfoCount - 1;
        }
      } else {
        highlightBlock(_lineInfoCount - 1);
        deletedIndex = NSNotFound;
        addedIndex = NSNotFound;
      }
      
    } endHunkHandler:^{
      
      highlightBlock(_lineInfoCount);
      
    }];
    
  }
}

- (CGFloat)updateLayoutForWidth:(CGFloat)width {
  if (_string && (NSInteger)width != (NSInteger)_size.width) {
    if (_frame) {
      CFRelease(_frame);
    }
    if (_framesetter) {
      CFRelease(_framesetter);
    }
    CFAttributedStringSetAttributes(_string, CFRangeMake(0, CFAttributedStringGetLength(_string)), GIDiffViewAttributes, false);
    _framesetter = CTFramesetterCreateWithAttributedString(_string);
    CGFloat textWidth = width - 2 * kTextLineNumberMargin - kTextInsetLeft - kTextInsetRight;
    CGPathRef path = CGPathCreateWithRect(CGRectMake(0, 0, textWidth, CGFLOAT_MAX), NULL);
    _frame = CTFramesetterCreateFrame(_framesetter, CFRangeMake(0, CFAttributedStringGetLength(_string)), path, NULL);
    CGPathRelease(path);
    _size = NSMakeSize(width, CFArrayGetCount(CTFrameGetLines(_frame)) * GIDiffViewLineHeight + kTextBottomPadding);
  }
  return _size.height;
}

- (const LineInfo*)_infoForLineRange:(CFRange)lineRange {
  const LineInfo* info = NULL;
  CFRange range = CFRangeMake(0, _lineInfoCount);
  while (range.length) {
    CFIndex index = range.location + range.length / 2;
    info = &_lineInfoList[index];
    if (lineRange.location >= info->range.location + info->range.length) {
      range = CFRangeMake(index, range.location + range.length - index);
    } else if (lineRange.location + lineRange.length <= info->range.location) {
      range = CFRangeMake(range.location, index - range.location);
    } else {
      break;
    }
  }
  return info;
}

- (void)drawRect:(NSRect)dirtyRect {
  NSRect bounds = self.bounds;
  CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
  CGContextSaveGState(context);
  
  [self updateLayoutForWidth:bounds.size.width];
  
  [self.backgroundColor setFill];
  CGContextFillRect(context, dirtyRect);
  
  if (_frame) {
    NSColor* selectedColor = self.window.keyWindow && (self.window.firstResponder == self) ? [NSColor selectedControlColor] : [NSColor secondarySelectedControlColor];
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CFArrayRef lines = CTFrameGetLines(_frame);
    CFIndex count = CFArrayGetCount(lines);
    CFIndex start = MIN(MAX(count - (dirtyRect.origin.y + dirtyRect.size.height - kTextBottomPadding) / GIDiffViewLineHeight, 0), count);
    CFIndex end = MIN(MAX(count - (dirtyRect.origin.y - kTextBottomPadding) / GIDiffViewLineHeight + 1, 0), count);
    const LineInfo* info = NULL;
    for (CFIndex i = start; i < end; ++i) {
      CTLineRef line = CFArrayGetValueAtIndex(lines, i);
      CFRange lineRange = CTLineGetStringRange(line);
      CGFloat linePosition = (count - 1 - i) * GIDiffViewLineHeight + kTextBottomPadding;
      CGFloat textPosition = linePosition + GIDiffViewLineDescent;
      
      if (info) {
        while (lineRange.location >= info->range.location + info->range.length) {
          XLOG_DEBUG_CHECK(info != &_lineInfoList[_lineInfoCount - 1]);
          ++info;
        }
      } else {
        info = [self _infoForLineRange:lineRange];
      }
#ifdef __clang_analyzer__
      if (!info) break;
#endif
      
      if ((NSUInteger)info->change != NSNotFound) {
        if ([_selectedLines containsIndex:info->index]) {
          [selectedColor setFill];
          CGContextFillRect(context, CGRectMake(0, linePosition, bounds.size.width, GIDiffViewLineHeight));
        } else if (info->change != kGCLineDiffChange_Unmodified) {
          if (info->change == kGCLineDiffChange_Deleted) {
            [GIDiffViewDeletedBackgroundColor setFill];
          } else {
            [GIDiffViewAddedBackgroundColor setFill];
          }
          CGContextFillRect(context, CGRectMake(0, linePosition, bounds.size.width, GIDiffViewLineHeight));
          
          if (info->highlighted.length) {
            if (info->change == kGCLineDiffChange_Deleted) {
              [GIDiffViewDeletedHighlightColor setFill];
            } else {
              [GIDiffViewAddedHighlightColor setFill];
            }
            CGFloat startX = CTLineGetOffsetForStringIndex(line, info->range.location + info->highlighted.location, NULL);
            CGFloat endX = CTLineGetOffsetForStringIndex(line, info->range.location + info->highlighted.location + info->highlighted.length, NULL);
            if (endX > startX) {
              startX = 2 * kTextLineNumberMargin + kTextInsetLeft + round(startX);
              endX = 2 * kTextLineNumberMargin + kTextInsetLeft + round(endX);
              CGContextFillRect(context, CGRectMake(startX, linePosition, endX - startX, GIDiffViewLineHeight));
            }
          }
        }
        
        [GIDiffViewLineNumberColor setFill];
        if ((lineRange.location == info->range.location) && (info->oldLineNumber != NSNotFound)) {
          CFAttributedStringRef string = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)(info->oldLineNumber >= 100000 ? @"9999…" : [NSString stringWithFormat:@"%5lu", info->oldLineNumber]), GIDiffViewAttributes);
          CTLineRef prefix = CTLineCreateWithAttributedString(string);
          CGContextSetTextPosition(context, 5, textPosition);
          CTLineDraw(prefix, context);
          CFRelease(prefix);
          CFRelease(string);
          
          if (info->change == kGCLineDiffChange_Deleted) {
            CGContextSetTextPosition(context, 2 * kTextLineNumberMargin + 4, textPosition);
            CTLineDraw(GIDiffViewDeletedLine, context);
          }
        }
        if ((lineRange.location == info->range.location) && (info->newLineNumber != NSNotFound)) {
          CFAttributedStringRef string = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)(info->newLineNumber >= 100000 ? @"9999…" : [NSString stringWithFormat:@"%5lu", info->newLineNumber]), GIDiffViewAttributes);
          CTLineRef prefix = CTLineCreateWithAttributedString(string);
          CGContextSetTextPosition(context, kTextLineNumberMargin + 5, textPosition);
          CTLineDraw(prefix, context);
          CFRelease(prefix);
          CFRelease(string);
          
          if (info->change == kGCLineDiffChange_Added) {
            CGContextSetTextPosition(context, 2 * kTextLineNumberMargin + 4, textPosition);
            CTLineDraw(GIDiffViewAddedLine, context);
          }
        }
        
        if (_selectedText.length && (_selectedText.location < lineRange.location + lineRange.length) && (_selectedText.location + _selectedText.length > lineRange.location)) {
          [selectedColor setFill];
          CGFloat startX = 2 * kTextLineNumberMargin + kTextInsetLeft;
          CGFloat endX = bounds.size.width;
          if (_selectedText.location > lineRange.location) {
            startX = 2 * kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(line, _selectedText.location, NULL));
          }
          if (_selectedText.location + _selectedText.length < lineRange.location + lineRange.length) {
            endX = 2 * kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(line, _selectedText.location + _selectedText.length, NULL));
          }
          CGContextFillRect(context, CGRectMake(startX, linePosition, endX - startX, GIDiffViewLineHeight));
        }
        
        [GIDiffViewPlainTextColor set];
        CGContextSetTextPosition(context, 2 * kTextLineNumberMargin + kTextInsetLeft, textPosition);
        CTLineDraw(line, context);
      } else {
        [GIDiffViewSeparatorBackgroundColor setFill];
        CGContextFillRect(context, CGRectMake(0, linePosition + 1, bounds.size.width, GIDiffViewLineHeight - 1));
        
        [GIDiffViewSeparatorLineColor setStroke];
        CGContextMoveToPoint(context, 0, linePosition + 0.5);
        CGContextAddLineToPoint(context, bounds.size.width, linePosition + 0.5);
        CGContextStrokePath(context);
        CGContextMoveToPoint(context, 0, linePosition + GIDiffViewLineHeight - 0.5);
        CGContextAddLineToPoint(context, bounds.size.width, linePosition + GIDiffViewLineHeight - 0.5);
        CGContextStrokePath(context);
        
        [GIDiffViewSeparatorTextColor setFill];
        CGContextSetTextPosition(context, 2 * kTextLineNumberMargin + 4, textPosition);
        CTLineDraw(line, context);
      }
    }
  }
  
  [GIDiffViewVerticalLineColor setStroke];
  CGContextMoveToPoint(context, kTextLineNumberMargin - 0.5, 0);
  CGContextAddLineToPoint(context, kTextLineNumberMargin - 0.5, bounds.size.height);
  CGContextStrokePath(context);
  CGContextMoveToPoint(context, 2 * kTextLineNumberMargin - 0.5, 0);
  CGContextAddLineToPoint(context, 2 * kTextLineNumberMargin - 0.5, bounds.size.height);
  CGContextStrokePath(context);
  
  CGContextRestoreGState(context);
}

- (void)resetCursorRects {
  NSRect bounds = self.bounds;
  [self addCursorRect:NSMakeRect(2 * kTextLineNumberMargin + kTextInsetLeft, 0, bounds.size.width - 2 * kTextLineNumberMargin - kTextInsetLeft, bounds.size.height)
               cursor:[NSCursor IBeamCursor]];
}

- (BOOL)hasSelection {
  return _selectedLines.count || _selectedText.length;
}

- (BOOL)hasSelectedText {
  return _selectedText.length ? YES : NO;
}

- (BOOL)hasSelectedLines {
  return _selectedLines.count ? YES : NO;
}

- (void)clearSelection {
  if (_selectedLines.count || _selectedText.length) {
    [_selectedLines removeAllIndexes];
    _selectedText.length = 0;
    [self setNeedsDisplay:YES];  // TODO: Only redraw what's needed
    
    [self.delegate diffViewDidChangeSelection:self];
  }
}

- (void)getSelectedText:(NSString**)text oldLines:(NSIndexSet**)oldLines newLines:(NSIndexSet**)newLines {
  if (text) {
    if (_selectedText.length > 0) {
      XLOG_DEBUG_CHECK(!_selectedLines.count);
      *text = [(NSString*)CFAttributedStringGetString(_string) substringWithRange:NSMakeRange(_selectedText.location, _selectedText.length)];
    }
    if (_selectedLines.count) {
      XLOG_DEBUG_CHECK(!_selectedText.length);
      *text = [[NSMutableString alloc] init];
      [_selectedLines enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
        const LineInfo* info = &_lineInfoList[index];
        if ((NSUInteger)info->change != NSNotFound) {
          [(NSMutableString*)*text appendString:[(NSString*)CFAttributedStringGetString(_string) substringWithRange:NSMakeRange(info->range.location, info->range.length)]];
        }
      }];
    }
  }
  if (oldLines) {
    *oldLines = [NSMutableIndexSet indexSet];
  }
  if (newLines) {
    *newLines = [NSMutableIndexSet indexSet];
  }
  if (oldLines || newLines) {
    [_selectedLines enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
      const LineInfo* info = &_lineInfoList[index];
      if ((NSUInteger)info->change != NSNotFound) {
        if (oldLines && (info->oldLineNumber != NSNotFound)) {
          [(NSMutableIndexSet*)*oldLines addIndex:info->oldLineNumber];
        }
        if (newLines && (info->newLineNumber != NSNotFound)) {
          [(NSMutableIndexSet*)*newLines addIndex:info->newLineNumber];
        }
      }
    }];
  }
}

- (void)mouseDown:(NSEvent*)event {
  NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
  
  // Reset state
  _selectionMode = kSelectionMode_None;
  _startLines = nil;
  _deletedIndex = NSNotFound;
  if (_string == NULL) {
    return;
  }
  
  // Check if mouse is in the content area
  CFArrayRef lines = CTFrameGetLines(_frame);
  CFIndex index  = CFArrayGetCount(lines) - (location.y - kTextBottomPadding) / GIDiffViewLineHeight;
  if ((index >= 0) && (index < CFArrayGetCount(lines))) {
    CTLineRef line = CFArrayGetValueAtIndex(lines, index);
    
    // Set selection mode according to modifier flags
    if (event.modifierFlags & NSCommandKeyMask) {
      _selectionMode = kSelectionMode_Inverse;
    } else if ((event.modifierFlags & NSShiftKeyMask) && _selectedLines.count) {
      _selectionMode = kSelectionMode_Extend;
    } else {
      _selectionMode = kSelectionMode_Replace;
    }
    
    // Check if mouse is in the margin area
    if (location.x < 2 * kTextLineNumberMargin) {
      
      // Reset selection
      _selectedText.length = 0;
      if (_selectionMode == kSelectionMode_Replace) {
        [_selectedLines removeAllIndexes];
      }
      
      // Update selected lines
      const LineInfo* info = [self _infoForLineRange:CTLineGetStringRange(line)];
      if ((NSUInteger)info->change != NSNotFound) {  // Ignore separators
        _deletedIndex = info->index;
      } else {
        _selectionMode = kSelectionMode_None;
      }
      switch (_selectionMode) {
        
        case kSelectionMode_None:
          break;
        
        case kSelectionMode_Replace: {
          XLOG_DEBUG_CHECK(_selectedLines.count == 0);
          [_selectedLines addIndex:info->index];
          _startLines = [_selectedLines copy];
          break;
        }
        
        case kSelectionMode_Extend: {
          XLOG_DEBUG_CHECK(_selectedLines.count > 0);
          _startLines = [_selectedLines copy];
          if (info->index > _startLines.lastIndex) {
            [_selectedLines addIndexesInRange:NSMakeRange(_startLines.lastIndex, info->index - _startLines.lastIndex + 1)];
          } else if (info->index < _startLines.firstIndex) {
            [_selectedLines addIndexesInRange:NSMakeRange(info->index, _startLines.firstIndex - info->index + 1)];
          }
          break;
        }
        
        case kSelectionMode_Inverse: {
          _startLines = [_selectedLines copy];
          if ([_selectedLines containsIndex:info->index]) {
            [_selectedLines removeIndex:info->index];
          } else {
            [_selectedLines addIndex:info->index];
          }
          break;
        }
        
      }
      [self setNeedsDisplay:YES];  // TODO: Only redraw what's needed
      
    }
    // Otherwise check if mouse is is in the diff area
    else if (location.x >= 2 * kTextLineNumberMargin + kTextInsetLeft) {
      
      // Reset selection
      _selectedText.length = 0;
      [_selectedLines removeAllIndexes];
      
      // Update selected text
      index = CTLineGetStringIndexForPosition(line, CGPointMake(location.x - (2 * kTextLineNumberMargin + kTextInsetLeft), GIDiffViewLineHeight / 2));
      if (index != kCFNotFound) {
        _deletedIndex = index;
        if (event.clickCount > 1) {
          CFRange range = CTLineGetStringRange(line);
          NSString* string = (NSString*)CFAttributedStringGetString(_string);
          [string enumerateSubstringsInRange:NSMakeRange(range.location, range.length) options:NSStringEnumerationByWords usingBlock:^(NSString* substring, NSRange substringRange, NSRange enclosingRange, BOOL* stop) {
            if ((index >= (CFIndex)substringRange.location) && (index <= (CFIndex)(substringRange.location + substringRange.length))) {
              _selectedText = CFRangeMake(substringRange.location, substringRange.length);
              _deletedIndex = _selectedText.location;
              *stop = YES;
            }
          }];
        }
      } else {
        _selectionMode = kSelectionMode_None;
      }
      [self setNeedsDisplay:YES];  // TODO: Only redraw what's needed
      
    } else {
      _selectionMode = kSelectionMode_None;
    }
    
  }
  // Otherwise clear entire selection
  else {
    [self clearSelection];
  }
}

- (void)mouseDragged:(NSEvent*)event {
  if (_selectionMode == kSelectionMode_None) {
    return;
  }
  NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
  
  // Check if mouse is in the content area
  CFArrayRef lines = CTFrameGetLines(_frame);
  CFIndex index  = CFArrayGetCount(lines) - (location.y - kTextBottomPadding) / GIDiffViewLineHeight;
  if ((index >= 0) && (index < CFArrayGetCount(lines))) {
    CTLineRef line = CFArrayGetValueAtIndex(lines, index);
    
    // Check if we are in line-selection mode
    if (_startLines) {
      const LineInfo* info = [self _infoForLineRange:CTLineGetStringRange(line)];
      if ((NSUInteger)info->change != NSNotFound) {  // Ignore separators
        
        // Update selected lines
        switch (_selectionMode) {
          
          case kSelectionMode_None:
            break;
          
          case kSelectionMode_Replace:
          case kSelectionMode_Extend: {
            XLOG_DEBUG_CHECK(_startLines.count > 0);
            [_selectedLines removeAllIndexes];
            [_selectedLines addIndexes:_startLines];
            if (info->index > _startLines.lastIndex) {
              [_selectedLines addIndexesInRange:NSMakeRange(_startLines.lastIndex, info->index - _startLines.lastIndex + 1)];
            } else if (info->index < _startLines.firstIndex) {
              [_selectedLines addIndexesInRange:NSMakeRange(info->index, _startLines.firstIndex - info->index + 1)];
            }
            break;
          }
          
          case kSelectionMode_Inverse: {
            [_selectedLines removeAllIndexes];
            [_selectedLines addIndexes:_startLines];
            for (NSUInteger i = MIN(_deletedIndex, info->index); i <= MAX(_deletedIndex, info->index); ++i) {
              if (![_selectedLines containsIndex:i]) {
                [_selectedLines addIndex:i];
              } else {
                [_selectedLines removeIndex:i];
              }
            }
            break;
          }
          
        }
        [self setNeedsDisplay:YES];  // TODO: Only redraw what's needed
        
      }
    }
    // Otherwise we are in text-selection mode
    else {
      index = CTLineGetStringIndexForPosition(line, CGPointMake(location.x - (2 * kTextLineNumberMargin + kTextInsetLeft), GIDiffViewLineHeight / 2));
      if (index != kCFNotFound) {
        
        // Update selected text
        if (index > (CFIndex)_deletedIndex) {
          _selectedText = CFRangeMake((CFIndex)_deletedIndex, index - (CFIndex)_deletedIndex);
        } else if (index < (CFIndex)_deletedIndex) {
          _selectedText = CFRangeMake(index, (CFIndex)_deletedIndex - index);
        }
        [self setNeedsDisplay:YES];  // TODO: Only redraw what's needed
        
      }
    }
    
  }
  
  // Scroll if needed
  [self autoscroll:event];
}

- (void)mouseUp:(NSEvent*)event {
  if (_string) {
    [self.delegate diffViewDidChangeSelection:self];  // TODO: Avoid calling delegate if seleciton hasn't actually changed
  }
}

@end
