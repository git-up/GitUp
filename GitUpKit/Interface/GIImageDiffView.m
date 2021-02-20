#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GIPrivate.h"

@interface GIImageDiffView ()
@property(nonatomic, strong) GCLiveRepository* repository;
@property(nonatomic, strong) NSImageView* currentImageView;
@end

@implementation GIImageDiffView
- (id)initWithRepository:(GCLiveRepository*)repository {
  self = [super initWithFrame:CGRectZero];
  self.repository = repository;
  [self setupView];
  return self;
}

- (void)setupView {
  _currentImageView = [[NSImageView alloc] init];
  [self addSubview:_currentImageView];
}

- (CGFloat)desiredHeightForWidth:(CGFloat)width {
  return width * 2;
}

- (void)drawRect:(NSRect)dirtyRect {
  [self updateFrames];
}

- (void)updateFrames {
  _currentImageView.frame = self.frame;
}
@end
