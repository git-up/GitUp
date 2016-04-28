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

typedef NS_ENUM(NSUInteger, GIAlertType) {
  kGIAlertType_Note = 0,
  kGIAlertType_Caution,
  kGIAlertType_Stop,
  kGIAlertType_Danger
};

extern NSString* const GICommitMessageViewUserDefaultKey_ShowInvisibleCharacters;
extern NSString* const GICommitMessageViewUserDefaultKey_ShowMargins;
extern NSString* const GICommitMessageViewUserDefaultKey_EnableSpellChecking;

@interface NSMutableAttributedString (GIAppKit)
- (void)appendString:(NSString*)string withAttributes:(NSDictionary*)attributes;
@end

@interface NSAlert (GIAppKit)
- (void)beginSheetModalForWindow:(NSWindow*)window withCompletionHandler:(void (^)(NSInteger returnCode))handler;  // AppKit version is 10.9+ only
- (void)setType:(GIAlertType)type;  // Set the alert icon
@end

@interface NSView (GIAppKit)
- (void)replaceWithView:(NSView*)view;  // Preserves frame and autoresizing mask
- (NSImage*)takeSnapshot;
@end

@interface NSMenu (GIAppKit)
- (NSMenuItem*)addItemWithTitle:(NSString*)title block:(dispatch_block_t)block;
- (NSMenuItem*)addItemWithTitle:(NSString*)title keyEquivalent:(unichar)code modifierMask:(NSUInteger)mask block:(dispatch_block_t)block;  // Pass a NULL block to add a disabled item
@end

@interface GIFlippedView : NSView
@end

@interface GITextView : NSTextView
@end

@interface GICommitMessageView : GITextView
@end

@interface GITableCellView : NSTableCellView
@property(nonatomic) NSInteger row;
- (void)saveTextFieldColors;
@end

@interface GITableView : NSTableView
@end

@interface GIDualSplitView : NSSplitView <NSSplitViewDelegate>  // This view assumes only 2 subviews and is its own delegate!
@property(nonatomic) IBInspectable CGFloat minSize1;
@property(nonatomic) IBInspectable CGFloat minSize2;
@end
