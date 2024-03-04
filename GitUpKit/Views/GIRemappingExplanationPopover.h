//
//  GIRemappingExplanationViewController.h
//  GitUpKit
//
//  Created by Lucas Derraugh on 3/3/24.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GIRemappingExplanationPopover : NSObject

+ (void)showIfNecessaryRelativeToRect:(NSRect)positioningRect ofView:(NSView*)positioningView preferredEdge:(NSRectEdge)preferredEdge;

@end

NS_ASSUME_NONNULL_END
