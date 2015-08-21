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
#define kTextInsetLeft 5
#define kTextInsetRight 5
#define kTextBottomPadding 0

typedef NS_ENUM(NSUInteger, DiffLineType) {
  kDiffLineType_Separator = 0,
  kDiffLineType_Context,
  kDiffLineType_Change
};

typedef NS_ENUM(NSUInteger, SelectionMode) {
  kSelectionMode_None = 0,
  kSelectionMode_Replace,
  kSelectionMode_Extend,
  kSelectionMode_Inverse
};

@interface GISplitDiffLine : NSObject
@property(nonatomic, readonly) DiffLineType type;

@property(nonatomic) NSUInteger leftNumber;
@property(nonatomic, strong) NSString* leftString;
@property(nonatomic) CTLineRef leftLine;
@property(nonatomic) BOOL leftWrapped;
@property(nonatomic) CFRange leftHighlighted;

@property(nonatomic) const char* leftContentBytes;  // Not valid outside of patch generation
@property(nonatomic) NSUInteger leftContentLength;  // Not valid outside of patch generation

@property(nonatomic) NSUInteger rightNumber;
@property(nonatomic, strong) NSString* rightString;
@property(nonatomic) CTLineRef rightLine;
@property(nonatomic) BOOL rightWrapped;
@property(nonatomic) CFRange rightHighlighted;

@property(nonatomic) const char* rightContentBytes;  // Not valid outside of patch generation
@property(nonatomic) NSUInteger rightContentLength;  // Not valid outside of patch generation
@end

@implementation GISplitDiffLine

- (id)initWithType:(DiffLineType)type {
  if ((self = [super init])) {
    _type = type;
  }
  return self;
}

- (void)dealloc {
  if (_leftLine) {
    CFRelease(_leftLine);
  }
  if (_rightLine) {
    CFRelease(_rightLine);
  }
}

- (NSString*)description {
  switch (_type) {
    case kDiffLineType_Separator: return _leftString;
    case kDiffLineType_Context: return [NSString stringWithFormat:@"[%lu] '%@' | [%lu] '%@'", _leftNumber, _leftString, _rightNumber, _rightString];
    case kDiffLineType_Change: return [NSString stringWithFormat:@"[%lu] '%@' | [%lu] '%@'", _leftNumber, _leftString, _rightNumber, _rightString];
  }
  return nil;
}

@end

@implementation GISplitDiffView {
  NSMutableArray* _lines;
  NSSize _size;
  
  BOOL _rightSelection;
  NSMutableIndexSet* _selectedLines;
  NSRange _selectedText;
  NSUInteger _selectedTextStart;
  NSUInteger _selectedTextEnd;
  SelectionMode _selectionMode;
  NSIndexSet* _startLines;
  NSUInteger _startIndex;
  NSUInteger _startOffset;
}

- (void)didFinishInitializing {
  [super didFinishInitializing];
  
  _lines = [[NSMutableArray alloc] initWithCapacity:1024];
  _selectedLines = [[NSMutableIndexSet alloc] init];
}

- (BOOL)isEmpty {
  return (_lines.count == 0);
}

- (void)didUpdatePatch {
  [super didUpdatePatch];
  
  [_lines removeAllObjects];
}

- (CGFloat)updateLayoutForWidth:(CGFloat)width {
  if (self.patch && (NSInteger)width != (NSInteger)_size.width) {
    [_lines removeAllObjects];
    
    CGFloat lineWidth = floor((width - 2 * kTextLineNumberMargin - 2 * kTextInsetLeft - 2 * kTextInsetRight) / 2);
    __block NSUInteger lineIndex = NSNotFound;
    __block NSUInteger startIndex = NSNotFound;
    __block NSUInteger addedCount = 0;
    __block NSUInteger deletedCount = 0;
    void (^highlightBlock)() = ^() {
      if ((addedCount == deletedCount) && (startIndex != NSNotFound)) {
        NSUInteger deletedIndex = startIndex;
        NSUInteger addedIndex = startIndex;
        while (addedCount) {
          GISplitDiffLine* deletedLine = [_lines objectAtIndex:deletedIndex++];
          while (deletedLine.leftWrapped) {
            deletedLine = [_lines objectAtIndex:deletedIndex++];
          }
          GISplitDiffLine* addedLine = [_lines objectAtIndex:addedIndex++];
          while (addedLine.rightWrapped) {
            addedLine = [_lines objectAtIndex:addedIndex++];
          }
          CFRange deletedRange;
          CFRange addedRange;
          GIComputeHighlightRanges(deletedLine.leftContentBytes, deletedLine.leftContentLength, deletedLine.leftString.length, &deletedRange,
                                   addedLine.rightContentBytes, addedLine.rightContentLength, addedLine.rightString.length, &addedRange);
          while (deletedRange.length > 0) {
            CFRange range = CTLineGetStringRange(deletedLine.leftLine);
            if ((deletedRange.location >= range.location) && (deletedRange.location < range.location + range.length)) {
              if (deletedRange.location + deletedRange.length <= range.location + range.length) {
                deletedLine.leftHighlighted = CFRangeMake(deletedRange.location - range.location, deletedRange.length);
                break;
              }
              deletedLine.leftHighlighted = CFRangeMake(deletedRange.location - range.location, range.location + range.length - deletedRange.location);
              deletedRange = CFRangeMake(range.location + range.length, deletedRange.location + deletedRange.length - range.location - range.length);
            }
            deletedLine = [_lines objectAtIndex:deletedIndex++];
            XLOG_DEBUG_CHECK(deletedLine.leftWrapped);
          }
          while (addedRange.length > 0) {
            CFRange range = CTLineGetStringRange(addedLine.rightLine);
            if ((addedRange.location >= range.location) && (addedRange.location < range.location + range.length)) {
              if (addedRange.location + addedRange.length <= range.location + range.length) {
                addedLine.rightHighlighted = CFRangeMake(addedRange.location - range.location, addedRange.length);
                break;
              }
              addedLine.rightHighlighted = CFRangeMake(addedRange.location - range.location, range.location + range.length - addedRange.location);
              addedRange = CFRangeMake(range.location + range.length, addedRange.location + addedRange.length - range.location - range.length);
            }
            addedLine = [_lines objectAtIndex:addedIndex++];
            XLOG_DEBUG_CHECK(addedLine.rightWrapped);
          }
          --addedCount;
        }
      }
    };
    [self.patch enumerateUsingBeginHunkHandler:^(NSUInteger oldLineNumber, NSUInteger oldLineCount, NSUInteger newLineNumber, NSUInteger newLineCount) {
      
      NSString* string = [[NSString alloc] initWithFormat:@"@@ -%lu,%lu +%lu,%lu @@", oldLineNumber, oldLineCount, newLineNumber, newLineCount];
      CFAttributedStringRef attributedString = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)string, GIDiffViewAttributes);
      CTLineRef line = CTLineCreateWithAttributedString(attributedString);
      CFRelease(attributedString);
      
      GISplitDiffLine* diffLine = [[GISplitDiffLine alloc] initWithType:kDiffLineType_Separator];
      diffLine.leftString = string;
      diffLine.leftLine = line;  // Transfer ownership to GISplitDiffLine
      [_lines addObject:diffLine];
      
      addedCount = 0;
      deletedCount = 0;
      startIndex = NSNotFound;
      
    } lineHandler:^(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber, const char* contentBytes, NSUInteger contentLength) {
      
      NSString* string;
      if (contentBytes[contentLength - 1] != '\n') {
        size_t length = strlen(GIDiffViewMissingNewlinePlaceholder);
        char* buffer = malloc(contentLength + length);
        bcopy(contentBytes, buffer, contentLength);
        bcopy(GIDiffViewMissingNewlinePlaceholder, &buffer[contentLength], length);
        string = [[NSString alloc] initWithBytesNoCopy:buffer length:(contentLength + length) encoding:NSUTF8StringEncoding freeWhenDone:YES];
      } else {
        string = [[NSString alloc] initWithBytesNoCopy:(void*)contentBytes length:contentLength encoding:NSUTF8StringEncoding freeWhenDone:NO];
      }
      if (string == nil) {
        string = @"<LINE IS NOT VALID UTF-8>\n";
        XLOG_DEBUG_UNREACHABLE();
      }
      
      switch (change) {
        
        case kGCLineDiffChange_Unmodified:
          highlightBlock();
          addedCount = 0;
          deletedCount = 0;
          startIndex = NSNotFound;
          break;
        
        case kGCLineDiffChange_Deleted:
          ++deletedCount;
          break;
        
        case kGCLineDiffChange_Added:
          ++addedCount;
          break;
        
      }
      
      CFAttributedStringRef attributedString = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)string, GIDiffViewAttributes);
      CTTypesetterRef typeSetter = CTTypesetterCreateWithAttributedString(attributedString);
      CFIndex length = CFAttributedStringGetLength(attributedString);
      CFIndex offset = 0;
      BOOL isWrappedLine = NO;
      do {
        CFIndex index = CTTypesetterSuggestLineBreak(typeSetter, offset, lineWidth);
        CTLineRef line = CTTypesetterCreateLine(typeSetter, CFRangeMake(offset, index));
        switch (change) {  // Assume the order of repeating changes is always [unmodified -> deleted -> added -> unmodified]
          
          case kGCLineDiffChange_Unmodified: {
            GISplitDiffLine* diffLine = [[GISplitDiffLine alloc] initWithType:kDiffLineType_Context];
            [_lines addObject:diffLine];
            diffLine.leftNumber = oldLineNumber;
            diffLine.leftString = string;
            diffLine.leftLine = line;  // Transfer ownership to GISplitDiffLine
            diffLine.leftWrapped = isWrappedLine;
            diffLine.rightNumber = newLineNumber;
            diffLine.rightString = string;
            diffLine.rightLine = CFRetain(line);  // Transfer ownership to GISplitDiffLine
            diffLine.rightWrapped = isWrappedLine;
            lineIndex = NSNotFound;
            break;
          }
          
          case kGCLineDiffChange_Deleted: {
            if (lineIndex == NSNotFound) {
              XLOG_DEBUG_CHECK(!isWrappedLine);
              lineIndex = _lines.count;
            }
            GISplitDiffLine* diffLine = [[GISplitDiffLine alloc] initWithType:kDiffLineType_Change];
            [_lines addObject:diffLine];
            diffLine.leftNumber = oldLineNumber;
            diffLine.leftString = string;
            diffLine.leftLine = line;  // Transfer ownership to GISplitDiffLine
            diffLine.leftWrapped = isWrappedLine;
            if (!isWrappedLine) {
              diffLine.leftContentBytes = contentBytes;
              diffLine.leftContentLength = contentLength;
            }
            break;
          }
          
          case kGCLineDiffChange_Added: {
            GISplitDiffLine* diffLine;
            if (lineIndex != NSNotFound) {
              if (startIndex == NSNotFound) {
                startIndex = lineIndex;
              }
              diffLine = _lines[lineIndex];
              lineIndex += 1;
              if (lineIndex == _lines.count) {
                lineIndex = NSNotFound;
              }
            } else {
              diffLine = [[GISplitDiffLine alloc] initWithType:kDiffLineType_Change];
              [_lines addObject:diffLine];
            }
            diffLine.rightNumber = newLineNumber;
            diffLine.rightString = string;
            diffLine.rightLine = line;  // Transfer ownership to GISplitDiffLine
            diffLine.rightWrapped = isWrappedLine;
            if (!isWrappedLine) {
              diffLine.rightContentBytes = contentBytes;
              diffLine.rightContentLength = contentLength;
            }
            break;
          }
          
        }
        offset += index;
        isWrappedLine = YES;
      } while (offset < length);
      CFRelease(typeSetter);
      CFRelease(attributedString);
      
    } endHunkHandler:^{
      
      highlightBlock();
      
    }];
    _size = NSMakeSize(width, _lines.count * GIDiffViewLineHeight + kTextBottomPadding);
  }
  return _size.height;
}

- (void)drawRect:(NSRect)dirtyRect {
  NSRect bounds = self.bounds;
  CGFloat offset = floor(bounds.size.width / 2);
  CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
  CGContextSaveGState(context);
  
  [self updateLayoutForWidth:bounds.size.width];
  
  [self.backgroundColor setFill];
  CGContextFillRect(context, dirtyRect);
  
  if (_lines.count) {
    NSColor* selectedColor = self.window.keyWindow && (self.window.firstResponder == self) ? [NSColor selectedControlColor] : [NSColor secondarySelectedControlColor];
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    NSUInteger count = _lines.count;
    NSUInteger start = MIN(MAX(count - (dirtyRect.origin.y + dirtyRect.size.height - kTextBottomPadding) / GIDiffViewLineHeight, 0), count);
    NSUInteger end = MIN(MAX(count - (dirtyRect.origin.y - kTextBottomPadding) / GIDiffViewLineHeight + 1, 0), count);
    for (NSUInteger i = start; i < end; ++i) {
      __unsafe_unretained GISplitDiffLine* diffLine = _lines[i];
      CTLineRef leftLine = diffLine.leftLine;
      CTLineRef rightLine = diffLine.rightLine;
      CGFloat linePosition = (count - 1 - i) * GIDiffViewLineHeight + kTextBottomPadding;
      CGFloat textPosition = linePosition + GIDiffViewLineDescent;
      if (diffLine.type == kDiffLineType_Separator) {
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
        CGContextSetTextPosition(context, kTextLineNumberMargin + 4, textPosition);
        CTLineDraw(leftLine, context);
      } else {
        if (leftLine) {
          if (!_rightSelection && [_selectedLines containsIndex:diffLine.leftNumber]) {
            [selectedColor setFill];
            CGContextFillRect(context, CGRectMake(0, linePosition, offset, GIDiffViewLineHeight));
          } else if (diffLine.type != kDiffLineType_Context) {
            [GIDiffViewDeletedBackgroundColor setFill];
            CGContextFillRect(context, CGRectMake(0, linePosition, offset, GIDiffViewLineHeight));
            
            CFRange highlighted = diffLine.leftHighlighted;
            if (highlighted.length) {
              [GIDiffViewDeletedHighlightColor setFill];
              CFRange range = CTLineGetStringRange(leftLine);
              CGFloat startX = kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(leftLine, range.location + highlighted.location, NULL));
              CGFloat endX = kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(leftLine, range.location + highlighted.location + highlighted.length, NULL));
              CGContextFillRect(context, CGRectMake(startX, linePosition, endX - startX, GIDiffViewLineHeight));
            }
          }
        }
        if (rightLine) {
          if (_rightSelection && [_selectedLines containsIndex:diffLine.rightNumber]) {
            [selectedColor setFill];
            CGContextFillRect(context, CGRectMake(offset, linePosition, bounds.size.width, GIDiffViewLineHeight));
          } else if (diffLine.type != kDiffLineType_Context) {
            [GIDiffViewAddedBackgroundColor setFill];
            CGContextFillRect(context, CGRectMake(offset, linePosition, bounds.size.width, GIDiffViewLineHeight));
            
            CFRange highlighted = diffLine.rightHighlighted;
            if (highlighted.length) {
              [GIDiffViewAddedHighlightColor setFill];
              CFRange range = CTLineGetStringRange(rightLine);
              CGFloat startX = offset + kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(rightLine, range.location + highlighted.location, NULL));
              CGFloat endX = offset + kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(rightLine, range.location + highlighted.location + highlighted.length, NULL));
              CGContextFillRect(context, CGRectMake(startX, linePosition, endX - startX, GIDiffViewLineHeight));
            }
          }
        }
        
        if (leftLine) {
          if (!diffLine.leftWrapped) {
            [GIDiffViewLineNumberColor setFill];
            CFAttributedStringRef string = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)(diffLine.leftNumber >= 100000 ? @"9999…" : [NSString stringWithFormat:@"%5lu", diffLine.leftNumber]), GIDiffViewAttributes);
            CTLineRef prefix = CTLineCreateWithAttributedString(string);
            CGContextSetTextPosition(context, 5, textPosition);
            CTLineDraw(prefix, context);
            CFRelease(prefix);
            CFRelease(string);
          }
          
          if (!_rightSelection && _selectedText.length && (i >= _selectedText.location) && (i < _selectedText.location + _selectedText.length)) {
            [selectedColor setFill];
            CGFloat startX = kTextLineNumberMargin + kTextInsetLeft;
            CGFloat endX = offset;
            if (i == _selectedText.location) {
              startX = kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(leftLine, _selectedTextStart, NULL));
            }
            if (i == _selectedText.location + _selectedText.length - 1) {
              endX = kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(leftLine, _selectedTextEnd, NULL));
            }
            CGContextFillRect(context, CGRectMake(startX, linePosition, endX - startX, GIDiffViewLineHeight));
          }
          
          [GIDiffViewPlainTextColor set];
          CGContextSetTextPosition(context, kTextLineNumberMargin + kTextInsetLeft, textPosition);
          CTLineDraw(leftLine, context);
        }
        if (rightLine) {
          if (!diffLine.rightWrapped) {
            [GIDiffViewLineNumberColor setFill];
            CFAttributedStringRef string = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)(diffLine.rightNumber >= 100000 ? @"9999…" : [NSString stringWithFormat:@"%5lu", diffLine.rightNumber]), GIDiffViewAttributes);
            CTLineRef prefix = CTLineCreateWithAttributedString(string);
            CGContextSetTextPosition(context, offset + 5, textPosition);
            CTLineDraw(prefix, context);
            CFRelease(prefix);
            CFRelease(string);
          }
          
          if (_rightSelection && _selectedText.length && (i >= _selectedText.location) && (i < _selectedText.location + _selectedText.length)) {
            [selectedColor setFill];
            CGFloat startX = offset + kTextLineNumberMargin + kTextInsetLeft;
            CGFloat endX = bounds.size.width;
            if (i == _selectedText.location) {
              startX = offset + kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(rightLine, _selectedTextStart, NULL));
            }
            if (i == _selectedText.location + _selectedText.length - 1) {
              endX = offset + kTextLineNumberMargin + kTextInsetLeft + round(CTLineGetOffsetForStringIndex(rightLine, _selectedTextEnd, NULL));
            }
            CGContextFillRect(context, CGRectMake(startX, linePosition, endX - startX, GIDiffViewLineHeight));
          }
          
          [GIDiffViewPlainTextColor set];
          CGContextSetTextPosition(context, offset + kTextLineNumberMargin + kTextInsetLeft, textPosition);
          CTLineDraw(rightLine, context);
        }
      }
    }
  }
  
  [GIDiffViewVerticalLineColor setStroke];
  CGContextMoveToPoint(context, kTextLineNumberMargin - 0.5, 0);
  CGContextAddLineToPoint(context, kTextLineNumberMargin - 0.5, bounds.size.height);
  CGContextStrokePath(context);
  CGContextMoveToPoint(context, offset - 0.5, 0);
  CGContextAddLineToPoint(context, offset - 0.5, bounds.size.height);
  CGContextStrokePath(context);
  CGContextMoveToPoint(context, offset + kTextLineNumberMargin - 0.5, 0);
  CGContextAddLineToPoint(context, offset + kTextLineNumberMargin - 0.5, bounds.size.height);
  CGContextStrokePath(context);
  
  CGContextRestoreGState(context);
}

- (void)resetCursorRects {
  NSRect bounds = self.bounds;
  CGFloat offset = floor(bounds.size.width / 2);
  [self addCursorRect:NSMakeRect(kTextLineNumberMargin + kTextInsetLeft, 0, offset - kTextLineNumberMargin - kTextInsetLeft, bounds.size.height)
               cursor:[NSCursor IBeamCursor]];
  [self addCursorRect:NSMakeRect(offset + kTextLineNumberMargin + kTextInsetLeft, 0, bounds.size.width - offset - kTextLineNumberMargin - kTextInsetLeft, bounds.size.height)
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
  if (_selectedLines.count) {
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
      if (_selectedText.length == 1) {
        GISplitDiffLine* diffLine = _lines[_selectedText.location];
        NSString* string = _rightSelection ? diffLine.rightString : diffLine.leftString;
        *text = [string substringWithRange:NSMakeRange(_selectedTextStart, _selectedTextEnd - _selectedTextStart)];
      } else {
        *text = [[NSMutableString alloc] init];
        for (NSUInteger i = _selectedText.location; i < _selectedText.location + _selectedText.length; ++i) {
          GISplitDiffLine* diffLine = _lines[i];
          NSString* string = _rightSelection ? diffLine.rightString : diffLine.leftString;
          if (string) {
            CFRange range = CTLineGetStringRange(_rightSelection ? diffLine.rightLine : diffLine.leftLine);
            if (i == _selectedText.location) {
              [(NSMutableString*)*text appendString:[string substringWithRange:NSMakeRange(_selectedTextStart, range.location + range.length - _selectedTextStart)]];
            } else if (i == _selectedText.location + _selectedText.length - 1) {
              [(NSMutableString*)*text appendString:[string substringWithRange:NSMakeRange(range.location, _selectedTextEnd - range.location)]];
            } else {
              [(NSMutableString*)*text appendString:[string substringWithRange:NSMakeRange(range.location, range.length)]];
            }
          }
        }
      }
    }
    if (_selectedLines.count) {
      XLOG_DEBUG_CHECK(!_selectedText.length);
      *text = [[NSMutableString alloc] init];
      NSUInteger lastLineNumber = NSNotFound;
      for (GISplitDiffLine* diffLine in _lines) {
        if (_rightSelection) {
          if ([_selectedLines containsIndex:diffLine.rightNumber] && (lastLineNumber != diffLine.rightNumber)) {
            [(NSMutableString*)*text appendString:diffLine.rightString];
            lastLineNumber = diffLine.rightNumber;
          }
        } else {
          if ([_selectedLines containsIndex:diffLine.leftNumber] && (lastLineNumber != diffLine.leftNumber)) {
            [(NSMutableString*)*text appendString:diffLine.leftString];
            lastLineNumber = diffLine.leftNumber;
          }
        }
      }
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
      if (_rightSelection) {
        [(NSMutableIndexSet*)*newLines addIndex:index];
      } else {
        [(NSMutableIndexSet*)*oldLines addIndex:index];
      }
    }];
  }
}

- (void)mouseDown:(NSEvent*)event {
  NSRect bounds = self.bounds;
  CGFloat offset = floor(bounds.size.width / 2);
  NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
  
  // Reset state
  _selectionMode = kSelectionMode_None;
  _startLines = nil;
  _startIndex = NSNotFound;
  if (!_lines.count) {
    return;
  }
  
  // Check if mouse is in the content area
  NSInteger y = _lines.count - (location.y - kTextBottomPadding) / GIDiffViewLineHeight;
  if ((y >= 0) && (y < (NSInteger)_lines.count)) {
    GISplitDiffLine* diffLine = _lines[y];
    
    // Clear selection if changing side
    BOOL rightSelection = (location.x >= offset);
    if (rightSelection != _rightSelection) {
      [_selectedLines removeAllIndexes];
      _selectedText.length = 0;
    }
    _rightSelection = rightSelection;
    
    // Set selection mode according to modifier flags
    if (event.modifierFlags & NSCommandKeyMask) {
      _selectionMode = kSelectionMode_Inverse;
    } else if ((event.modifierFlags & NSShiftKeyMask) && _selectedLines.count) {
      _selectionMode = kSelectionMode_Extend;
    } else {
      _selectionMode = kSelectionMode_Replace;
    }
    
    // Check if mouse is in the margin area
    if (((location.x >= 0) && (location.x < kTextLineNumberMargin)) || ((location.x >= offset) && (location.x < offset + kTextLineNumberMargin))) {
      
      // Reset selection
      _selectedText.length = 0;
      if (_selectionMode == kSelectionMode_Replace) {
        [_selectedLines removeAllIndexes];
      }
      
      // Update selected lines
      NSUInteger index = (_rightSelection ? diffLine.rightNumber : diffLine.leftNumber);
      if (diffLine.type != kDiffLineType_Separator) {  // Ignore separators
        _startIndex = index;
      } else {
        _selectionMode = kSelectionMode_None;
      }
      switch (_selectionMode) {
        
        case kSelectionMode_None:
          break;
        
        case kSelectionMode_Replace: {
          XLOG_DEBUG_CHECK(_selectedLines.count == 0);
          [_selectedLines addIndex:index];
          _startLines = [_selectedLines copy];
          break;
        }
        
        case kSelectionMode_Extend: {
          XLOG_DEBUG_CHECK(_selectedLines.count > 0);
          _startLines = [_selectedLines copy];
          if (index > _startLines.lastIndex) {
            [_selectedLines addIndexesInRange:NSMakeRange(_startLines.lastIndex, index - _startLines.lastIndex + 1)];
          } else if (index < _startLines.firstIndex) {
            [_selectedLines addIndexesInRange:NSMakeRange(index, _startLines.firstIndex - index + 1)];
          }
          break;
        }
        
        case kSelectionMode_Inverse: {
          _startLines = [_selectedLines copy];
          if ([_selectedLines containsIndex:index]) {
            [_selectedLines removeIndex:index];
          } else {
            [_selectedLines addIndex:index];
          }
          break;
        }
        
      }
      [self setNeedsDisplay:YES];  // TODO: Only redraw what's needed
      
    }
    // Otherwise check if mouse is is in the diff area
    else if (((location.x >= kTextLineNumberMargin + kTextInsetLeft) && (location.x < offset)) || (location.x >= offset + kTextLineNumberMargin + kTextInsetLeft)) {
      
      // Reset selection
      _selectedText.length = 0;
      [_selectedLines removeAllIndexes];
      
      // Update selected text
      CTLineRef line = _rightSelection ? diffLine.rightLine : diffLine.leftLine;
      CFIndex index = CTLineGetStringIndexForPosition(line, CGPointMake(location.x - ((_rightSelection ? offset : 0) + kTextLineNumberMargin + kTextInsetLeft), GIDiffViewLineHeight / 2));
      if (index != kCFNotFound) {
        _startIndex = y;
        _startOffset = index;
        if (event.clickCount > 1) {
          NSString* string = _rightSelection ? diffLine.rightString : diffLine.leftString;
          CFRange range = CTLineGetStringRange(line);
          [string enumerateSubstringsInRange:NSMakeRange(range.location, range.length) options:NSStringEnumerationByWords usingBlock:^(NSString* substring, NSRange substringRange, NSRange enclosingRange, BOOL* stop) {
            if ((index >= (CFIndex)substringRange.location) && (index <= (CFIndex)(substringRange.location + substringRange.length))) {
              _selectedText = NSMakeRange(y, 1);
              _selectedTextStart = substringRange.location;
              _selectedTextEnd = substringRange.location + substringRange.length;
              _startIndex = _selectedText.location;
              _startOffset = _selectedTextStart;
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
  NSRect bounds = self.bounds;
  CGFloat offset = floor(bounds.size.width / 2);
  NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
  
  // Check if mouse is in the content area
  NSInteger y = _lines.count - (location.y - kTextBottomPadding) / GIDiffViewLineHeight;
  if ((y >= 0) && (y < (NSInteger)_lines.count)) {
    GISplitDiffLine* diffLine = _lines[y];
    
    // Check if we are in line-selection mode
    if (_startLines) {
      if (diffLine.type != kDiffLineType_Separator) {  // Ignore separators
        
        // Update selected lines
        if (_rightSelection ? diffLine.rightLine : diffLine.leftLine) {
          NSUInteger index = (_rightSelection ? diffLine.rightNumber : diffLine.leftNumber);
          switch (_selectionMode) {
            
            case kSelectionMode_None:
              break;
            
            case kSelectionMode_Replace:
            case kSelectionMode_Extend: {
              XLOG_DEBUG_CHECK(_startLines.count > 0);
              [_selectedLines removeAllIndexes];
              [_selectedLines addIndexes:_startLines];
              if (index > _startLines.lastIndex) {
                [_selectedLines addIndexesInRange:NSMakeRange(_startLines.lastIndex, index - _startLines.lastIndex + 1)];
              } else if (index < _startLines.firstIndex) {
                [_selectedLines addIndexesInRange:NSMakeRange(index, _startLines.firstIndex - index + 1)];
              }
              break;
            }
            
            case kSelectionMode_Inverse: {
              [_selectedLines removeAllIndexes];
              [_selectedLines addIndexes:_startLines];
              for (NSUInteger i = MIN(_startIndex, index); i <= MAX(_startIndex, index); ++i) {
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
    }
    // Otherwise we are in text-selection mode
    else {
      CTLineRef line = _rightSelection ? diffLine.rightLine : diffLine.leftLine;
      CFIndex index = CTLineGetStringIndexForPosition(line, CGPointMake(location.x - ((_rightSelection ? offset : 0) + kTextLineNumberMargin + kTextInsetLeft), GIDiffViewLineHeight / 2));
      if (index != kCFNotFound) {
        
        // Update selected text
        if ((NSUInteger)y > _startIndex) {
          _selectedText = NSMakeRange(_startIndex, y - _startIndex + 1);
          _selectedTextStart = _startOffset;
          _selectedTextEnd = index;
        } else if ((NSUInteger)y < _startIndex) {
          _selectedText = NSMakeRange(y, _startIndex - y + 1);
          _selectedTextStart = index;
          _selectedTextEnd = _startOffset;
        } else {
          _selectedText = NSMakeRange(_startIndex, 1);
          if ((NSUInteger)index > _startOffset) {
            _selectedTextStart = _startOffset;
            _selectedTextEnd = index;
          } else if ((NSUInteger)index < _startOffset) {
            _selectedTextStart = index;
            _selectedTextEnd = _startOffset;
          }
        }
        [self setNeedsDisplay:YES];  // TODO: Only redraw what's needed
        
      }
    }
    
  }
  
  // Scroll if needed
  [self autoscroll:event];
}

- (void)mouseUp:(NSEvent*)event {
  if (_lines.count) {
    [self.delegate diffViewDidChangeSelection:self];  // TODO: Avoid calling delegate if seleciton hasn't actually changed
  }
}

@end
