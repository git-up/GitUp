#import <AppKit/AppKit.h>

@interface GIImageDiffView : NSView
- (id)initWithRepository:(GCLiveRepository*)repository;
- (CGFloat)desiredHeightForWidth:(CGFloat)width;
@end
