//
//  NSView+Embedding.m
//  GitUpKit (OSX)
//
//  Created by Dmitry Lobanov on 06.04.2020.
//

#import "NSView+Embedding.h"

@implementation NSView (Embedding)
- (void)embedView:(NSView *)view {
  [self.class embedView:view inView:self];
}

+ (void)embedView:(NSView *)view inView:(NSView *)superview {
  [superview addSubview:view];
  view.translatesAutoresizingMaskIntoConstraints = NO;
  
  if (superview != nil && view != nil) {
    if (@available(macOS 10.11, *)) {
      NSArray *constraints = @[
        [view.leftAnchor constraintEqualToAnchor:superview.leftAnchor],
        [view.topAnchor constraintEqualToAnchor:superview.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:superview.bottomAnchor],
        [view.rightAnchor constraintEqualToAnchor:superview.rightAnchor]
      ];
      [NSLayoutConstraint activateConstraints:constraints];
    } else {
      // Fallback on earlier versions
      NSArray *verticalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{@"view": view}];
      NSArray *horizontalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{@"view": view}];
      NSArray *constraints = [[NSArray arrayWithArray:verticalConstraints] arrayByAddingObjectsFromArray:horizontalConstraints];
      [NSLayoutConstraint activateConstraints:constraints];
    }
  }
}
@end
