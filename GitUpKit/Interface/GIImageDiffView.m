#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GIPrivate.h"
#import "GILaunchServicesLocator.h"

#define kImageInset 10

@interface GIImageDiffView ()
@property(nonatomic, strong) GCLiveRepository* repository;
@property(nonatomic, strong) NSImageView* oldImageView;
@property(nonatomic, strong) NSImageView* currentImageView;
@property(nonatomic) CGFloat percentage;
@end

@implementation GIImageDiffView
- (id)initWithRepository:(GCLiveRepository*)repository {
  self = [super initWithFrame:CGRectZero];
  self.repository = repository;
  _percentage = 0.5;
  [self setupView];
  return self;
}

- (void)setupView {
  _currentImageView = [[NSImageView alloc] init];
  _oldImageView = [[NSImageView alloc] init];
  [self addSubview:_currentImageView];
  [self addSubview:_oldImageView];
}

- (void)setDelta:(GCDiffDelta*)delta {
  if (delta != _delta) {
    _delta = delta;
    [self updateCurrentImage];
    [self updateOldImage];
    self.percentage = 0.5;
  }
}

- (void)updateCurrentImage {
  NSError* error;
  NSString* newPath;
  if (_delta.newFile.SHA1 != nil) {
    newPath = [GILaunchServicesLocator.diffTemporaryDirectoryPath stringByAppendingPathComponent:_delta.newFile.SHA1];
    NSString* newExtension = _delta.newFile.path.pathExtension;
    if (newExtension.length) {
      newPath = [newPath stringByAppendingPathExtension:newExtension];
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:newPath]) {
      [self.repository exportBlobWithSHA1:_delta.newFile.SHA1 toPath:newPath error:&error];
    }
  } else {
    newPath = [self.repository absolutePathForFile:_delta.canonicalPath];
  }
  _currentImageView.image = [[NSImage alloc] initWithContentsOfFile:newPath];
}

- (void)updateOldImage {
  NSError* error;
  if (_delta.oldFile.SHA1 != nil) {
    NSString* oldPath = [GILaunchServicesLocator.diffTemporaryDirectoryPath stringByAppendingPathComponent:_delta.oldFile.SHA1];
    NSString* oldExtension = _delta.oldFile.path.pathExtension;
    if (oldExtension.length) {
      oldPath = [oldPath stringByAppendingPathExtension:oldExtension];
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:oldPath]) {
      [self.repository exportBlobWithSHA1:_delta.oldFile.SHA1 toPath:oldPath error:&error];
    }
    _oldImageView.image = [[NSImage alloc] initWithContentsOfFile:oldPath];
  } else {
    _oldImageView.image = nil;
  }
}

- (CGFloat)desiredHeightForWidth:(CGFloat)width {
  return [self desiredImageFrame:width].size.height + 2 * kImageInset;
}

- (void)drawRect:(NSRect)dirtyRect {
  [self updateFrames];
}

- (void)updateFrames {
  CGRect fittedImageFrame = [self fittedImageFrame];
  _currentImageView.frame = fittedImageFrame;
  if (_oldImageView.image != nil) {
    _oldImageView.frame = fittedImageFrame;
    [_oldImageView setHidden:false];
  } else {
    [_oldImageView setHidden:true];
  }
}

- (CGRect)desiredImageFrame:(CGFloat)width {
  CGFloat maxContentWidth = width - 2 * kImageInset;
  CGFloat originalImageWidth = [self originalDiffImageSize].width;
  CGFloat originalImageHeight = [self originalDiffImageSize].height;

  CGFloat scaledImageWidth = MIN(originalImageWidth, maxContentWidth);
  CGFloat scaledImageHeight = originalImageHeight * scaledImageWidth / originalImageWidth;

  CGFloat x = (width - scaledImageWidth) / 2;
  return CGRectMake(x, self.bounds.size.height - scaledImageHeight - kImageInset, scaledImageWidth, scaledImageHeight);
}

- (CGRect)fittedImageFrame {
  CGFloat maxContentWidth = self.frame.size.width - 2 * kImageInset;
  CGFloat maxContentHeight = self.frame.size.height - 2 * kImageInset;
  CGFloat originalImageWidth = [self originalDiffImageSize].width;
  CGFloat originalImageHeight = [self originalDiffImageSize].height;

  CGFloat scaledImageWidth = MIN(originalImageWidth, maxContentWidth);
  CGFloat scaledImageHeight = MIN(originalImageHeight, maxContentHeight);
  CGFloat widthScalingFactor = scaledImageWidth / originalImageWidth;
  CGFloat heightScalingFactor = scaledImageHeight / originalImageHeight;
  CGFloat minimumScalingFactor = MIN(widthScalingFactor, heightScalingFactor);

  CGFloat actualImageWidth = originalImageWidth * minimumScalingFactor;
  CGFloat actualImageHeight = originalImageHeight * minimumScalingFactor;

  return CGRectMake((self.frame.size.width - actualImageWidth) / 2,
                    self.bounds.size.height - actualImageHeight - kImageInset,
                    actualImageWidth,
                    actualImageHeight);
}

- (NSSize)originalDiffImageSize {
  CGFloat maxHeight = MAX(_currentImageView.image.size.height, _oldImageView.image.size.height);
  CGFloat maxWidth = MAX(_currentImageView.image.size.width, _oldImageView.image.size.width);
  return NSMakeSize(maxWidth, maxHeight);
}
@end
