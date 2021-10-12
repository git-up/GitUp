#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GIPrivate.h"
#import "GILaunchServicesLocator.h"
#import <QuartzCore/CATransaction.h>
#import <ImageIO/ImageIO.h>

#define kImageInset 10
#define kBorderWidth 8
#define kDividerWidth 2
#define kMaxImageDimension 4000

@interface GIImageDiffView ()
@property(nonatomic, strong) NSPanGestureRecognizer* panGestureRecognizer;
@property(nonatomic, strong) NSClickGestureRecognizer* clickGestureRecognizer;
@property(nonatomic, strong) GCLiveRepository* repository;
@property(nonatomic, strong) NSImageView* oldImageView;
@property(nonatomic, strong) NSImageView* currentImageView;
@property(nonatomic, strong) CALayer* oldImageMaskLayer;
@property(nonatomic, strong) CALayer* currentImageMaskLayer;
@property(nonatomic, strong) CALayer* oldImageBorderLayer;
@property(nonatomic, strong) CALayer* currentImageBorderLayer;
@property(nonatomic, strong) NSView* dividerView;
@property(nonatomic, strong) CALayer* transparencyCheckerboardLayer;
@property(nonatomic, strong) NSColor* checkerboardColor;
@property(nonatomic, strong) NSProgressIndicator* progressIndicator;
@property(nonatomic) CGFloat percentage;
@property(nonatomic) NSSize oldImageSize;
@property(nonatomic) NSSize currentImageSize;
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
  self.wantsLayer = true;

  _oldImageBorderLayer = [[CALayer alloc] init];
  _currentImageBorderLayer = [[CALayer alloc] init];
  [self.layer addSublayer:_oldImageBorderLayer];
  [self.layer addSublayer:_currentImageBorderLayer];

  _transparencyCheckerboardLayer = [[CALayer alloc] init];
  NSBundle* bundle = NSBundle.gitUpKitBundle;
  NSImage* patternImage = [bundle imageForResource:@"background_pattern"];
  _checkerboardColor = [NSColor colorWithPatternImage:patternImage];
  _transparencyCheckerboardLayer.backgroundColor = _checkerboardColor.CGColor;
  [self.layer addSublayer:_transparencyCheckerboardLayer];

  _currentImageView = [[NSImageView alloc] init];
  _oldImageView = [[NSImageView alloc] init];
  [self addSubview:_currentImageView];
  [self addSubview:_oldImageView];

  _oldImageMaskLayer = [[CALayer alloc] init];
  _oldImageMaskLayer.backgroundColor = NSColor.blackColor.CGColor;
  _oldImageView.wantsLayer = true;
  _oldImageView.layer.mask = _oldImageMaskLayer;

  _currentImageMaskLayer = [[CALayer alloc] init];
  _currentImageMaskLayer.backgroundColor = NSColor.blackColor.CGColor;
  _currentImageView.wantsLayer = true;
  _currentImageView.layer.mask = _currentImageMaskLayer;

  _dividerView = [[NSView alloc] init];
  [self addSubview:_dividerView];

  _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 30, 30)];
  _progressIndicator.style = NSProgressIndicatorStyleSpinning;
  [self addSubview:_progressIndicator];
  [_progressIndicator startAnimation:self];
  _progressIndicator.hidden = true;

  _panGestureRecognizer = [[NSPanGestureRecognizer alloc] initWithTarget:self action:@selector(didMoveSplit:)];
  _clickGestureRecognizer = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(didMoveSplit:)];
  [self addGestureRecognizer:_panGestureRecognizer];
  [self addGestureRecognizer:_clickGestureRecognizer];
}

- (void)setDelta:(GCDiffDelta*)delta {
  if (delta != _delta) {
    _delta = delta;
    [self updateCurrentImage];
    [self updateOldImage];
    self.percentage = 0.5;
  }
}

- (void)setPercentage:(CGFloat)percentage {
  _percentage = percentage;
  [self setNeedsDisplay:true];
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
  _currentImageSize = [self imageSizeWithoutLoadingFromPath:newPath];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSImage* limitedSizeImage = [self generateLimitedSizeImageFromPath:newPath];
    dispatch_async(dispatch_get_main_queue(), ^{
      _currentImageView.image = limitedSizeImage;
      [self setNeedsDisplay:true];
    });
  });
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
    _oldImageSize = [self imageSizeWithoutLoadingFromPath:oldPath];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSImage* limitedSizeImage = [self generateLimitedSizeImageFromPath:oldPath];
      dispatch_async(dispatch_get_main_queue(), ^{
        _oldImageView.image = limitedSizeImage;
        [self setNeedsDisplay:true];
      });
    });
  } else {
    _oldImageView.image = nil;
  }
}

- (NSSize)imageSizeWithoutLoadingFromPath:(NSString*)path {
  NSURL* imageFileURL = [NSURL fileURLWithPath:path];
  CGImageSourceRef imageSource = CGImageSourceCreateWithURL((CFURLRef)imageFileURL, NULL);
  if (imageSource == NULL) {
    return NSZeroSize;
  }
  CFDictionaryRef imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
  CFRelease(imageSource);

  CGFloat width = 0.0f;
  CGFloat height = 0.0f;
  if (imageProperties != NULL) {
    CFNumberRef widthNum = CFDictionaryGetValue(imageProperties, kCGImagePropertyPixelWidth);
    if (widthNum != NULL) {
      CFNumberGetValue(widthNum, kCFNumberCGFloatType, &width);
    }
    CFNumberRef heightNum = CFDictionaryGetValue(imageProperties, kCGImagePropertyPixelHeight);
    if (heightNum != NULL) {
      CFNumberGetValue(heightNum, kCFNumberCGFloatType, &height);
    }
    CFNumberRef orientationNum = CFDictionaryGetValue(imageProperties, kCGImagePropertyOrientation);
    if (orientationNum != NULL) {
      int orientation;
      CFNumberGetValue(orientationNum, kCFNumberIntType, &orientation);
      if (orientation > 4) {
        CGFloat temp = width;
        width = height;
        height = temp;
      }
    }
    CFRelease(imageProperties);
  }
  return NSMakeSize(width, height);
}

- (NSImage*)generateLimitedSizeImageFromPath:(NSString*)path {
  CGImageSourceRef imageSource = CGImageSourceCreateWithURL((CFURLRef)[NSURL fileURLWithPath:path], NULL);
  if (!imageSource) {
    return nil;
  }

  CFDictionaryRef options = (CFDictionaryRef)CFBridgingRetain(@{
    (id)kCGImageSourceCreateThumbnailWithTransform : @YES,
    (id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
    (id)kCGImageSourceThumbnailMaxPixelSize : @(kMaxImageDimension)
  });
  CGImageRef image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options);
  NSImage* convertedImage = [[NSImage alloc] initWithCGImage:image size:NSZeroSize];

  CGImageRelease(image);
  CFRelease(options);
  CFRelease(imageSource);

  return convertedImage;
}

- (CGFloat)desiredHeightForWidth:(CGFloat)width {
  return [self desiredImageFrame:width].size.height + 2 * kImageInset;
}

- (void)drawRect:(NSRect)dirtyRect {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [self updateColors];
  [self updateFrames];
  _progressIndicator.hidden = _currentImageView.image != nil || _oldImageView.image != nil;
  [CATransaction commit];
}

- (void)updateColors {
  _oldImageBorderLayer.backgroundColor = NSColor.gitUpDiffDeletedTextHighlightColor.CGColor;
  _currentImageBorderLayer.backgroundColor = NSColor.gitUpDiffAddedTextHighlightColor.CGColor;
  _dividerView.layer.backgroundColor = NSColor.gitUpDiffModifiedBackgroundColor.CGColor;
  _transparencyCheckerboardLayer.backgroundColor = _checkerboardColor.CGColor;
}

- (void)updateFrames {
  CGRect fittedImageFrame = [self fittedImageFrame];
  _progressIndicator.frame = CGRectMake(
      (fittedImageFrame.size.width - _progressIndicator.frame.size.width) / 2,
      (fittedImageFrame.size.height - _progressIndicator.frame.size.height) / 2,
      _progressIndicator.frame.size.width,
      _progressIndicator.frame.size.height);
  _transparencyCheckerboardLayer.frame = fittedImageFrame;
  _currentImageView.frame = fittedImageFrame;
  if (_oldImageView.image != nil && _currentImageView.image != nil) {
    _oldImageView.frame = fittedImageFrame;
    [_oldImageView setHidden:false];
    CGFloat dividerOffset = fittedImageFrame.size.width * _percentage;
    _oldImageMaskLayer.frame = CGRectMake(0,
                                          0,
                                          dividerOffset,
                                          fittedImageFrame.size.height);
    _currentImageMaskLayer.frame = CGRectMake(dividerOffset,
                                              0,
                                              fittedImageFrame.size.width * (1 - _percentage),
                                              fittedImageFrame.size.height);
    _oldImageBorderLayer.frame = CGRectMake(fittedImageFrame.origin.x - kBorderWidth,
                                            fittedImageFrame.origin.y - kBorderWidth,
                                            dividerOffset + kBorderWidth,
                                            fittedImageFrame.size.height + 2 * kBorderWidth);
    _currentImageBorderLayer.frame = CGRectMake(fittedImageFrame.origin.x + dividerOffset,
                                                fittedImageFrame.origin.y - kBorderWidth,
                                                fittedImageFrame.size.width * (1 - _percentage) + kBorderWidth,
                                                fittedImageFrame.size.height + 2 * kBorderWidth);
    _dividerView.frame = CGRectMake(fittedImageFrame.origin.x + dividerOffset - kDividerWidth / 2,
                                    fittedImageFrame.origin.y - kBorderWidth,
                                    kDividerWidth,
                                    fittedImageFrame.size.height + 2 * kBorderWidth);
  } else if (_oldImageView.image != nil) {
    [_oldImageView setHidden:false];
    _oldImageView.frame = fittedImageFrame;
    _oldImageMaskLayer.frame = CGRectMake(0,
                                          0,
                                          fittedImageFrame.size.width,
                                          fittedImageFrame.size.height);
    _oldImageBorderLayer.frame = CGRectMake(fittedImageFrame.origin.x - kBorderWidth,
                                            fittedImageFrame.origin.y - kBorderWidth,
                                            fittedImageFrame.size.width + 2 * kBorderWidth,
                                            fittedImageFrame.size.height + 2 * kBorderWidth);
  } else {
    _currentImageMaskLayer.frame = CGRectMake(0,
                                              0,
                                              fittedImageFrame.size.width,
                                              fittedImageFrame.size.height);
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
  CGFloat maxHeight = MAX(_currentImageSize.height, _oldImageSize.height);
  CGFloat maxWidth = MAX(_currentImageSize.width, _oldImageSize.width);
  return NSMakeSize(maxWidth, maxHeight);
}

- (void)didMoveSplit:(NSGestureRecognizer*)gestureRecognizer {
  CGRect imageFrame = [self fittedImageFrame];
  CGFloat unboundPercentage = ([gestureRecognizer locationInView:self].x - imageFrame.origin.x) / imageFrame.size.width;
  self.percentage = MIN(1, MAX(0, unboundPercentage));
}
@end
