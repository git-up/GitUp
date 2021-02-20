#import <AppKit/AppKit.h>

@interface GIImageDiffView : NSView
@property(nonatomic, strong) GCDiffDelta* delta;

- (id)initWithRepository:(GCLiveRepository *)repository;
- (CGFloat)desiredHeightForWidth:(CGFloat)width;
@end
