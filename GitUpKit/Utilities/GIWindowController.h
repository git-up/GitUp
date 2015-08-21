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

#import "GIViewController.h"

typedef NS_ENUM(NSUInteger, GIOverlayStyle) {
  kGIOverlayStyle_Help = 0,
  kGIOverlayStyle_Informational,
  kGIOverlayStyle_Warning
};

@class GIWindowController;

@protocol GIWindowControllerDelegate <NSObject>
- (BOOL)windowController:(GIWindowController*)controller handleKeyDown:(NSEvent*)event;
- (void)windowControllerDidChangeHasModalView:(GIWindowController*)controller;
@end

@interface GIWindow : NSWindow
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wproperty-attribute-mismatch"
#pragma clang diagnostic ignored "-Wincompatible-property-type"
@property(nonatomic, readonly) GIWindowController* windowController;  // Redeclare superclass property
#pragma clang diagnostic pop
@end

@interface GIWindowController : NSWindowController
@property(nonatomic, assign) id<GIWindowControllerDelegate> delegate;
@property(strong) GIWindow* window;  // Redeclare superclass property

@property(nonatomic, readonly, getter=isOverlayVisible) BOOL overlayVisible;
- (void)showOverlayWithStyle:(GIOverlayStyle)style format:(NSString*)format, ... NS_FORMAT_FUNCTION(2, 3);
- (void)showOverlayWithStyle:(GIOverlayStyle)style message:(NSString*)message;
- (void)hideOverlay;

@property(nonatomic, readonly) BOOL hasModalView;
- (void)runModalView:(NSView*)view withInitialFirstResponder:(NSResponder*)responder completionHandler:(void (^)(BOOL success))handler;
- (void)stopModalView:(BOOL)success;
@end

@interface GIViewController (GIWindowController)
- (IBAction)finishModalView:(id)sender;  // Convenience method that calls -stopModalView: with YES
- (IBAction)cancelModalView:(id)sender;  // Convenience method that calls -stopModalView: with NO
@end
