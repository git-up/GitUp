#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GIPrivate.h"

@interface GIImageDiffView ()
@property(nonatomic, strong) GCLiveRepository* repository;
@end

@implementation GIImageDiffView
- (id)initWithRepository:(GCLiveRepository*)repository {
  self = [super initWithFrame:CGRectZero];
  self.repository = repository;
  return self;
}

- (CGFloat)desiredHeightForWidth:(CGFloat)width {
  return width * 2;
}
@end
