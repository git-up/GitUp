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

#import <QuartzCore/QuartzCore.h>
#import <sys/sysctl.h>

#import "GIModalView.h"

#import "XLFacilityMacros.h"

#define __ENABLE_BLUR__ 0

#if __ENABLE_BLUR__
#ifndef kCFCoreFoundationVersionNumber10_10
#define kCFCoreFoundationVersionNumber10_10 1152
#endif
#endif

#if __ENABLE_BLUR__
#define kBlurRadius 20.0
#define kAnimationDuration 0.2
#define kBlurName @"blur"
#define kBlurKeyPath @"backgroundFilters." kBlurName ".inputRadius"
#endif

@implementation GIModalView {
  BOOL _useBackgroundFilters;
}

// See https://developer.apple.com/library/mac/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html
- (void)_initialize {
  self.wantsLayer = YES;
  
#if __ENABLE_BLUR__
  if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber10_10) {  // Background filters don't seem to work on 10.8 and 10.9
    size_t size;
    if (sysctlbyname("hw.model", NULL, &size, NULL, 0) == 0) {
      char* machine = malloc(size);
      if (sysctlbyname("hw.model", machine, &size, NULL, 0) == 0) {
        if (strncmp(machine, "MacBookAir", 10)) {  // MBA 2013 hangs for 1-2 seconds the first time the blur effect is used in the app
          _useBackgroundFilters = YES;
        }
      }
      free(machine);
    }
  }
  
  if (_useBackgroundFilters) {
    CIFilter* blurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
    blurFilter.name = kBlurName;
    [blurFilter setDefaults];
    [blurFilter setValue:@(0.0) forKey:@"inputRadius"];
    self.backgroundFilters = @[blurFilter];
  }
#endif
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

- (void)presentContentView:(NSView*)view withCompletionHandler:(dispatch_block_t)handler {
  XLOG_DEBUG_CHECK(self.subviews.count == 0);
  
  NSRect bounds = self.bounds;
  NSRect frame = view.frame;
  view.frame = NSMakeRect(round((bounds.size.width - frame.size.width) / 2), round((bounds.size.height - frame.size.height) / 2), frame.size.width, frame.size.height);
  view.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
  view.wantsLayer = YES;
  view.layer.borderWidth = 1.0;
  view.layer.borderColor = [[NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.0 alpha:0.2] CGColor];
  view.layer.cornerRadius = 5.0;
  
#if __ENABLE_BLUR__
  if (_useBackgroundFilters) {
    [self.layer setValue:@(kBlurRadius) forKeyPath:kBlurKeyPath];
    CABasicAnimation* animation = [CABasicAnimation animation];
    animation.keyPath = kBlurKeyPath;
    animation.fromValue = @(0.0);
    animation.toValue = nil;
    animation.duration = kAnimationDuration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    [self.layer addAnimation:animation forKey:nil];
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    [[NSAnimationContext currentContext] setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
      
      if (handler) {
        handler();
      }
      
    }];
    [self.animator addSubview:view];
    [NSAnimationContext endGrouping];
  } else
#endif
  {
    view.layer.backgroundColor = [[NSColor colorWithDeviceRed:0.95 green:0.95 blue:0.95 alpha:1.0] CGColor];
    self.layer.backgroundColor = [[NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.0 alpha:0.4] CGColor];
    [self addSubview:view];
    if (handler) {
      dispatch_async(dispatch_get_main_queue(), handler);
    }
  }
}

- (void)dismissContentViewWithCompletionHandler:(dispatch_block_t)handler {
  XLOG_DEBUG_CHECK(self.subviews.count == 1);
  
  NSView* view = self.subviews.firstObject;
#if __ENABLE_BLUR__
  if (_useBackgroundFilters) {
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    [[NSAnimationContext currentContext] setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
      
      view.wantsLayer = NO;
      if (handler) {
        handler();
      }
      
    }];
    [view.animator removeFromSuperviewWithoutNeedingDisplay];
    [NSAnimationContext endGrouping];
    
    [self.layer setValue:@(0.0) forKeyPath:kBlurKeyPath];
    CABasicAnimation* animation = [CABasicAnimation animation];
    animation.keyPath = kBlurKeyPath;
    animation.fromValue = @(kBlurRadius);
    animation.toValue = nil;
    animation.duration = kAnimationDuration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [self.layer addAnimation:animation forKey:nil];
  } else
#endif
  {
    [view removeFromSuperviewWithoutNeedingDisplay];
    view.wantsLayer = NO;
    self.layer.backgroundColor = nil;
    if (handler) {
      dispatch_async(dispatch_get_main_queue(), handler);
    }
  }
}

// Prevent events bubbling to ancestor views - TODO: Is there a better way?
- (void)mouseDown:(NSEvent*)event {}
- (void)rightMouseDown:(NSEvent*)event {}
- (void)otherMouseDown:(NSEvent*)event {}
- (void)mouseUp:(NSEvent*)event {}
- (void)rightMouseUp:(NSEvent*)event {}
- (void)otherMouseUp:(NSEvent*)event {}
- (void)mouseMoved:(NSEvent*)event {}
- (void)mouseDragged:(NSEvent*)event {}
- (void)scrollWheel:(NSEvent*)event {}
- (void)rightMouseDragged:(NSEvent*)event {}
- (void)otherMouseDragged:(NSEvent*)event {}
- (void)mouseEntered:(NSEvent*)event {}
- (void)mouseExited:(NSEvent*)event {}

@end
