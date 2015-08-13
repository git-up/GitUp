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

#import "GIInterface.h"

#import "XLFacilityMacros.h"

#if __GI_HAS_APPKIT__

extern CFDictionaryRef GIDiffViewAttributes;

extern CTLineRef GIDiffViewAddedLine;
extern CTLineRef GIDiffViewDeletedLine;

extern CGFloat GIDiffViewLineHeight;
extern CGFloat GIDiffViewLineDescent;

extern NSColor* GIDiffViewDeletedBackgroundColor;
extern NSColor* GIDiffViewDeletedHighlightColor;
extern NSColor* GIDiffViewAddedBackgroundColor;
extern NSColor* GIDiffViewAddedHighlightColor;
extern NSColor* GIDiffViewSeparatorBackgroundColor;
extern NSColor* GIDiffViewSeparatorLineColor;
extern NSColor* GIDiffViewSeparatorTextColor;
extern NSColor* GIDiffViewVerticalLineColor;
extern NSColor* GIDiffViewLineNumberColor;
extern NSColor* GIDiffViewPlainTextColor;

extern const char* GIDiffViewMissingNewlinePlaceholder;

#endif

extern void GIComputeHighlightRanges(const char* deletedBytes, NSUInteger deletedCount, CFIndex deletedLength, CFRange* deletedRange, const char* addedBytes, NSUInteger addedCount, CFIndex addedLength, CFRange* addedRange);  // Assumes UTF-8 buffers

@interface GINode ()
@property(nonatomic, readonly) GCHistoryCommit* alternateCommit;  // Dummy nodes only and may be nil
@property(nonatomic) CGFloat x;
- (instancetype)initWithLayer:(GILayer*)layer primaryLine:(GILine*)line commit:(GCHistoryCommit*)commit dummy:(BOOL)dummy alternateCommit:(GCHistoryCommit*)alternateCommit;
- (void)addParent:(GINode*)parent;
@end

@interface GILine ()
#if __GI_HAS_APPKIT__
@property(nonatomic, strong) NSColor* color;
#endif
@property(nonatomic) CGFloat x;
@property(nonatomic, readonly) GILine* childLine;  // Computed
- (instancetype)initWithBranch:(GIBranch*)branch;
- (void)addNode:(GINode*)node;
@end

@interface GIBranch ()
@property(nonatomic, assign) GILine* mainLine;
@end

@interface GILayer ()
@property(nonatomic) CGFloat y;
@property(nonatomic) CGFloat maxX;
- (instancetype)initWithIndex:(NSUInteger)index;
- (void)addNode:(GINode*)node;
- (void)addLine:(GILine*)line;
@end

#if __GI_HAS_APPKIT__

@interface NSScrollView (GIPrivate)
- (void)scrollToPoint:(NSPoint)point;  // Like -[NSView scrollPoint:] but doesn't animate scrolling and works around OS X 10.10 bug where target is not always reached
- (void)scrollToVisibleRect:(NSRect)rect;  // Like -[NSView scrollRectToVisible:] but doesn't animate scrolling and works around OS X 10.10 bug where target is not always reached
@end

#endif
