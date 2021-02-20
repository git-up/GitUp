#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GIPrivate.h"

@interface GIImageDiffView ()
@end

@implementation GIImageDiffView
- (CGFloat)desiredHeightForWidth:(CGFloat)width {
  return width * 2;
}
@end
