//  Copyright (C) 2015-2018 Pierre-Olivier Latour <info@pol-online.net>
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

#import <objc/runtime.h>

#import "GIAppKit.h"
#import "GIConstants.h"

#import "XLFacilityMacros.h"

#define kSummaryMaxWidth 50
#define kBodyMaxWidth 72

@interface GILayoutManager : NSLayoutManager
@end

NSString* const GICommitMessageViewUserDefaultKey_ShowInvisibleCharacters = @"GICommitMessageViewUserDefaultKey_ShowInvisibleCharacters";
NSString* const GICommitMessageViewUserDefaultKey_ShowMargins = @"GICommitMessageViewUserDefaultKey_ShowMargins";

NSString* const GICommitMessageViewUserDefaultsKey_ContinuousSpellChecking = @"GICommitMessageViewUserDefaultKey_EnableSpellChecking"; // Inconsistent for backwards compatibility.
NSString* const GICommitMessageViewUserDefaultsKey_GrammarChecking = @"GICommitMessageView_GrammarChecking";
NSString* const GICommitMessageViewUserDefaultsKey_AutomaticSpellingCorrection = @"GICommitMessageView_AutomaticSpellingCorrection";

NSString* const GICommitMessageViewUserDefaultsKey_SmartInsertDelete = @"GICommitMessageView_SmartInsertDelete";
NSString* const GICommitMessageViewUserDefaultsKey_QuoteSubstitution = @"GICommitMessageView_QuoteSubstitution";
NSString* const GICommitMessageViewUserDefaultsKey_DashSubstitution = @"GICommitMessageView_DashSubstitution";
NSString* const GICommitMessageViewUserDefaultsKey_LinkDetection = @"GICommitMessageView_LinkDetection";
NSString* const GICommitMessageViewUserDefaultsKey_DataDetection = @"GICommitMessageView_DataDetection";
NSString* const GICommitMessageViewUserDefaultsKey_TextReplacement = @"GICommitMessageView_TextReplacement";

NSString* const GIUserDefaultKey_FontSize = @"GIUserDefaultKey_FontSize";

CGFloat const GIDefaultFontSize = 10;

CGFloat GIFontSize(void) {
  CGFloat size = [[NSUserDefaults standardUserDefaults] floatForKey:GIUserDefaultKey_FontSize];
  return size > 0 ? size : GIDefaultFontSize;
}

static const void* _associatedObjectCommitKey = &_associatedObjectCommitKey;
static NSColor* _separatorColor = nil;

@implementation NSMutableAttributedString (GIAppKit)

- (void)appendString:(NSString*)string withAttributes:(NSDictionary*)attributes {
  if (string.length) {
    NSInteger length = self.length;
    [self replaceCharactersInRange:NSMakeRange(length, 0) withString:string];
    if (attributes) {
      [self setAttributes:attributes range:NSMakeRange(length, self.length - length)];
    }
  }
}

@end

@implementation NSAlert (GIAppKit)

+ (void)_alertDidEnd:(NSAlert*)alert returnCode:(NSInteger)returnCode contextInfo:(void*)contextInfo {
  void (^handler)(NSInteger) = contextInfo ? CFBridgingRelease(contextInfo) : NULL;
  [alert.window orderOut:nil];  // Dismiss the alert window before the handler might chain another one
  if (handler) {
    handler(returnCode);
  }
}

- (void)beginSheetModalForWindow:(NSWindow*)window withCompletionHandler:(void (^)(NSInteger returnCode))handler {
  [self beginSheetModalForWindow:window modalDelegate:[NSAlert class] didEndSelector:@selector(_alertDidEnd:returnCode:contextInfo:) contextInfo:(handler ? (void*)CFBridgingRetain(handler) : NULL)];
}

- (void)setType:(GIAlertType)type {
  switch (type) {
    case kGIAlertType_Note:
      self.icon = [[NSBundle bundleForClass:[GILayoutManager class]] imageForResource:@"icon_alert_note"];
      break;  // TODO: Image is not cached
    case kGIAlertType_Caution:
      self.icon = [[NSBundle bundleForClass:[GILayoutManager class]] imageForResource:@"icon_alert_caution"];
      break;  // TODO: Image is not cached
    case kGIAlertType_Stop:
    case kGIAlertType_Danger:
      self.icon = [[NSBundle bundleForClass:[GILayoutManager class]] imageForResource:@"icon_alert_stop"];
      break;  // TODO: Image is not cached
  }
}

@end

@implementation NSView (GIAppKit)

- (void)replaceWithView:(NSView*)view {
  XLOG_DEBUG_CHECK(self.superview);
  view.frame = self.frame;
  view.autoresizingMask = self.autoresizingMask;
  [self.superview replaceSubview:self with:view];
}

- (NSImage*)takeSnapshot {
  NSBitmapImageRep* rep = [self bitmapImageRepForCachingDisplayInRect:self.bounds];
  [self cacheDisplayInRect:self.bounds toBitmapImageRep:rep];
  NSImage* image = [[NSImage alloc] initWithSize:rep.size];
  [image addRepresentation:rep];
  return image;
}

@end

@implementation NSMenu (GIAppKit)

- (NSMenuItem*)addItemWithTitle:(NSString*)title block:(dispatch_block_t)block {
  return [self addItemWithTitle:title keyEquivalent:0 modifierMask:0 block:block];
}

- (void)_blockAction:(NSMenuItem*)sender {
  dispatch_block_t block = sender.representedObject;
  block();
}

- (NSMenuItem*)addItemWithTitle:(NSString*)title keyEquivalent:(unichar)code modifierMask:(NSUInteger)mask block:(dispatch_block_t)block {
  NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:(code ? [NSString stringWithCharacters:&code length:1] : @"")];
  if (block) {
    item.target = self;
    item.action = @selector(_blockAction:);
    item.representedObject = [block copy];
  }
  item.keyEquivalentModifierMask = mask;
  [self addItem:item];
  return item;
}

@end

@implementation GIFlippedView

- (BOOL)isFlipped {
  return YES;
}

@end

@implementation GITextView

- (void)doCommandBySelector:(SEL)selector {
  if (selector == @selector(insertTab:)) {
    [self.window selectNextKeyView:nil];
    return;
  }
  if (selector == @selector(insertBacktab:)) {
    [self.window selectPreviousKeyView:nil];
    return;
  }
  [super doCommandBySelector:selector];
}

@end

@implementation GICommitMessageView

- (void)dealloc {
  NSArray* allObservedKeys = @[
    GICommitMessageViewUserDefaultKey_ShowInvisibleCharacters,
    GICommitMessageViewUserDefaultKey_ShowMargins,
    GICommitMessageViewUserDefaultsKey_ContinuousSpellChecking,
    GICommitMessageViewUserDefaultsKey_GrammarChecking,
    GICommitMessageViewUserDefaultsKey_AutomaticSpellingCorrection,
    GICommitMessageViewUserDefaultsKey_SmartInsertDelete,
    GICommitMessageViewUserDefaultsKey_QuoteSubstitution,
    GICommitMessageViewUserDefaultsKey_DashSubstitution,
    GICommitMessageViewUserDefaultsKey_LinkDetection,
    GICommitMessageViewUserDefaultsKey_DataDetection,
    GICommitMessageViewUserDefaultsKey_TextReplacement,
    GIUserDefaultKey_FontSize,
  ];
  for (NSString* key in allObservedKeys) {
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:key context:(__bridge void*)[GICommitMessageView class]];
  }
}

- (void)awakeFromNib {
  [super awakeFromNib];

  [self updateFont];
  [self.textContainer replaceLayoutManager:[[GILayoutManager alloc] init]];
  
  // Enable automatic text replacement
  self.automaticTextReplacementEnabled = YES;
  
  // User defaults observing
  [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:GICommitMessageViewUserDefaultKey_ShowInvisibleCharacters options:0 context:(__bridge void*)[GICommitMessageView class]];
  [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:GICommitMessageViewUserDefaultKey_ShowMargins options:0 context:(__bridge void*)[GICommitMessageView class]];
  [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:GIUserDefaultKey_FontSize options:0 context:(__bridge void*)[GICommitMessageView class]];

  NSArray* keysWantingInitialValue = @[
    GICommitMessageViewUserDefaultsKey_ContinuousSpellChecking,
    GICommitMessageViewUserDefaultsKey_GrammarChecking,
    GICommitMessageViewUserDefaultsKey_AutomaticSpellingCorrection,
    GICommitMessageViewUserDefaultsKey_SmartInsertDelete,
    GICommitMessageViewUserDefaultsKey_QuoteSubstitution,
    GICommitMessageViewUserDefaultsKey_DashSubstitution,
    GICommitMessageViewUserDefaultsKey_LinkDetection,
    GICommitMessageViewUserDefaultsKey_DataDetection,
    GICommitMessageViewUserDefaultsKey_TextReplacement,
  ];
  for (NSString* key in keysWantingInitialValue) {
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:key options:NSKeyValueObservingOptionInitial context:(__bridge void*)[GICommitMessageView class]];
  }
}

- (void)updateFont {
  // To match the original design, the commit message font should be 10% larger than the diff view font.
  self.font = [NSFont userFixedPitchFontOfSize:roundf(1.1 * GIFontSize())];
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  if ([[NSUserDefaults standardUserDefaults] boolForKey:GICommitMessageViewUserDefaultKey_ShowMargins]) {
    NSRect bounds = self.bounds;
    CGFloat offset = self.textContainerOrigin.x + self.textContainerInset.width + self.textContainer.lineFragmentPadding;
    CGFloat charWidth = self.font.maximumAdvancement.width;  // TODO: Is this the most reliable way to get the character width of a fixed-width font?
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

    CGContextSaveGState(context);

    CGFloat x1 = floor(offset + kSummaryMaxWidth * charWidth) + 0.5;
    const CGFloat pattern1[] = {2, 4};
    CGContextSetLineDash(context, 0, pattern1, 2);
    CGContextSetRGBStrokeColor(context, 0.33, 0.33, 0.33, 0.2);
    CGContextMoveToPoint(context, x1, 0);
    CGContextAddLineToPoint(context, x1, bounds.size.height);
    CGContextStrokePath(context);

    CGFloat x2 = floor(offset + kBodyMaxWidth * charWidth) + 0.5;
    const CGFloat pattern2[] = {4, 2};
    CGContextSetLineDash(context, 0, pattern2, 2);
    CGContextSetRGBStrokeColor(context, 0.33, 0.33, 0.33, 0.2);
    CGContextMoveToPoint(context, x2, 0);
    CGContextAddLineToPoint(context, x2, bounds.size.height);
    CGContextStrokePath(context);

    CGContextRestoreGState(context);
  }
}

#define HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(PROPERTY, DEFAULTS_KEY)                                                 \
if ([keyPath isEqualToString:GICommitMessageViewUserDefaultsKey_##DEFAULTS_KEY]) {                                      \
  BOOL newValue = [[NSUserDefaults standardUserDefaults] boolForKey:GICommitMessageViewUserDefaultsKey_##DEFAULTS_KEY]; \
  if (newValue != [self is##PROPERTY]) {                                                                                \
    [self set##PROPERTY:newValue];                                                                                      \
    [self setNeedsDisplay:YES];                                                                                         \
  }                                                                                                                     \
  return;                                                                                                               \
}

// WARNING: This is called *several* times when the default has been changed
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
  if (context != (__bridge void*)[GICommitMessageView class]) {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    return;
  }

  if ([keyPath isEqualToString:GICommitMessageViewUserDefaultKey_ShowInvisibleCharacters]) {
    NSRange range = NSMakeRange(0, self.textStorage.length);
    [self.layoutManager invalidateGlyphsForCharacterRange:range changeInLength:0 actualCharacterRange:NULL];
    [self.layoutManager invalidateLayoutForCharacterRange:range isSoft:NO actualCharacterRange:NULL];
    [self setNeedsDisplay:YES];
    return;
  }

  if ([keyPath isEqualToString:GICommitMessageViewUserDefaultKey_ShowMargins]) {
    [self setNeedsDisplay:YES];
    return;
  }

  if ([keyPath isEqualToString:GIUserDefaultKey_FontSize]) {
    [self updateFont];
    return;
  }

  if ([keyPath isEqualToString:GICommitMessageViewUserDefaultsKey_ContinuousSpellChecking]) {
    BOOL newValue = [[NSUserDefaults standardUserDefaults] boolForKey:GICommitMessageViewUserDefaultsKey_ContinuousSpellChecking];
    if (newValue != [self isContinuousSpellCheckingEnabled]) {
      [self setContinuousSpellCheckingEnabled:newValue];
      [self setNeedsDisplay:YES];  // TODO: Why is this needed to refresh?
    }
    return;
  }

  HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(ContinuousSpellCheckingEnabled, ContinuousSpellChecking)
  HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(GrammarCheckingEnabled, GrammarChecking)
  HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(AutomaticSpellingCorrectionEnabled, AutomaticSpellingCorrection)
  HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(SmartInsertDeleteEnabled, SmartInsertDelete)
  HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(AutomaticQuoteSubstitutionEnabled, QuoteSubstitution)
  HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(AutomaticDashSubstitutionEnabled, DashSubstitution)
  HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(AutomaticLinkDetectionEnabled, LinkDetection)
  HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(AutomaticDataDetectionEnabled, DataDetection)
  HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY(AutomaticTextReplacementEnabled, TextReplacement)

  XLOG_DEBUG_UNREACHABLE();
}

/// This property does not have ‘is’ on the getter. Add it here so HANDLE_DEFAULTS_KEY_AND_UPDATE_PROPERTY works.
- (BOOL)isSmartInsertDeleteEnabled {
  return [self smartInsertDeleteEnabled];
}

#define OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(PROPERTY, DEFAULTS_KEY)                                                       \
- (void)set##PROPERTY:(BOOL)newValue {                                                                                    \
  [super set##PROPERTY:newValue];                                                                                         \
  if (newValue != [[NSUserDefaults standardUserDefaults] boolForKey:GICommitMessageViewUserDefaultsKey_##DEFAULTS_KEY]) { \
    [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:GICommitMessageViewUserDefaultsKey_##DEFAULTS_KEY];    \
  }                                                                                                                       \
}

OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(ContinuousSpellCheckingEnabled, ContinuousSpellChecking)
OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(GrammarCheckingEnabled, GrammarChecking)
OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(AutomaticSpellingCorrectionEnabled, AutomaticSpellingCorrection)
OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(SmartInsertDeleteEnabled, SmartInsertDelete)
OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(AutomaticQuoteSubstitutionEnabled, QuoteSubstitution)
OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(AutomaticDashSubstitutionEnabled, DashSubstitution)
OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(AutomaticLinkDetectionEnabled, LinkDetection)
OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(AutomaticDataDetectionEnabled, DataDetection)
OVERRIDE_SETTER_AND_UPDATE_DEFAULTS(AutomaticTextReplacementEnabled, TextReplacement)

@end

@implementation GITableCellView

+ (void)initialize {
  _separatorColor = [NSColor colorWithDeviceRed:0.9 green:0.9 blue:0.9 alpha:1.0];
}

- (void)saveTextFieldColors {
  for (NSView* view in self.subviews) {
    if ([view isKindOfClass:[NSTextField class]]) {
      objc_setAssociatedObject(view, _associatedObjectCommitKey, [(NSTextField*)view textColor], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  }
}

- (void)awakeFromNib {
  [super awakeFromNib];

  [self saveTextFieldColors];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
  [super setBackgroundStyle:backgroundStyle];

  for (NSView* view in self.subviews) {
    if ([view isKindOfClass:[NSTextField class]]) {
      if (backgroundStyle == NSBackgroundStyleDark) {
        [(NSTextField*)view setTextColor:[NSColor whiteColor]];
      } else {
        [(NSTextField*)view setTextColor:objc_getAssociatedObject(view, _associatedObjectCommitKey)];
      }
    }
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  NSRect bounds = self.bounds;
  CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

  [_separatorColor setStroke];
  CGContextMoveToPoint(context, 0, 0.5);
  CGContextAddLineToPoint(context, bounds.size.width, 0.5);
  CGContextStrokePath(context);
  if (_row == 0) {
    CGContextMoveToPoint(context, 0, bounds.size.height - 0.5);
    CGContextAddLineToPoint(context, bounds.size.width, bounds.size.height - 0.5);
    CGContextStrokePath(context);
  }
}

@end

@implementation GITableView

- (BOOL)validateProposedFirstResponder:(NSResponder*)responder forEvent:(NSEvent*)event {
  return YES;
}

// NSTableView built-in fallback for tab key when not editable cell is around is to change the first responder to the next key view directly without using -selectNextKeyView:
- (void)keyDown:(NSEvent*)event {
  if (event.keyCode == kGIKeyCode_Tab) {
    if (event.modifierFlags & NSShiftKeyMask) {
      [self.window selectPreviousKeyView:nil];
    } else {
      [self.window selectNextKeyView:nil];
    }
  } else {
    [super keyDown:event];
  }
}

@end

@implementation GILayoutManager

- (void)drawGlyphsForGlyphRange:(NSRange)range atPoint:(NSPoint)point {
  if ([[NSUserDefaults standardUserDefaults] boolForKey:GICommitMessageViewUserDefaultKey_ShowInvisibleCharacters]) {
    NSTextStorage* storage = self.textStorage;
    NSString* string = storage.string;
    for (NSUInteger glyphIndex = range.location; glyphIndex < range.location + range.length; ++glyphIndex) {
      NSUInteger characterIndex = [self characterIndexForGlyphAtIndex:glyphIndex];
      switch ([string characterAtIndex:characterIndex]) {
        case ' ': {
          NSFont* font = [storage attribute:NSFontAttributeName atIndex:characterIndex effectiveRange:NULL];
          XLOG_DEBUG_CHECK([font.fontName isEqualToString:@"Menlo-Regular"]);
          [self replaceGlyphAtIndex:glyphIndex withGlyph:[font glyphWithName:@"periodcentered"]];
          break;
        }

        case '\n': {
          NSFont* font = [storage attribute:NSFontAttributeName atIndex:characterIndex effectiveRange:NULL];
          XLOG_DEBUG_CHECK([font.fontName isEqualToString:@"Menlo-Regular"]);
          [self replaceGlyphAtIndex:glyphIndex withGlyph:[font glyphWithName:@"carriagereturn"]];
          break;
        }
      }
    }
  }
  [super drawGlyphsForGlyphRange:range atPoint:point];
}

@end

@implementation GIDualSplitView

- (instancetype)initWithFrame:(NSRect)frameRect {
  if ((self = [super initWithFrame:frameRect])) {
    self.delegate = self;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
  if ((self = [super initWithCoder:coder])) {
    self.delegate = self;
  }
  return self;
}

- (CGFloat)splitView:(NSSplitView*)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
  return _minSize1;
}

- (CGFloat)splitView:(NSSplitView*)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
  return (splitView.vertical ? splitView.bounds.size.width : splitView.bounds.size.height) - _minSize2;
}

// See http://stackoverflow.com/a/30494691/463432
- (void)splitView:(NSSplitView*)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
  [splitView adjustSubviews];
  // Take the min size constraints into account.
  // Using -setPosition:ofDividerAtIndex: from inside this method confuses Core Animation on 10.8.
  if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber10_9) {
    NSView* view = splitView.subviews.firstObject;
    [splitView setPosition:(splitView.vertical ? view.frame.size.width : view.frame.size.height)ofDividerAtIndex:0];
  } else {
    NSView* view1 = splitView.subviews[0];
    NSView* view2 = splitView.subviews[1];
    NSSize splitViewSize = splitView.bounds.size;
    if (splitView.vertical) {
      CGFloat splitPosition = MAX(view1.bounds.size.width, _minSize1);
      view1.frame = NSMakeRect(0, 0, splitPosition, splitViewSize.height);
      view2.frame = NSMakeRect(splitPosition + splitView.dividerThickness, 0, splitViewSize.width - splitPosition - splitView.dividerThickness, splitViewSize.height);
    } else {
      CGFloat splitPosition = MAX(view1.bounds.size.height, _minSize1);
      view1.frame = NSMakeRect(0, 0, splitViewSize.width, splitPosition);
      view2.frame = NSMakeRect(0, splitPosition + splitView.dividerThickness, splitViewSize.width, splitViewSize.height - splitPosition - splitView.dividerThickness);
    }
  }
}

@end
