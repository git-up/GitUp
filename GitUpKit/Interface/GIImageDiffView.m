#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GIPrivate.h"
#import "GILaunchServicesLocator.h"

@interface GIImageDiffView ()
@property(nonatomic, strong) GCLiveRepository* repository;
@property(nonatomic, strong) NSImageView* oldImageView;
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
  _oldImageView = [[NSImageView alloc] init];
  [self addSubview:_currentImageView];
  [self addSubview:_oldImageView];
}

- (void)setDelta:(GCDiffDelta*)delta {
  if (delta != _delta) {
    _delta = delta;
    [self updateCurrentImage];
    [self updateOldImage];
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
  return width * 2;
}

- (void)drawRect:(NSRect)dirtyRect {
  [self updateFrames];
}

- (void)updateFrames {
  _oldImageView.frame = CGRectMake(self.frame.origin.x,
                                       self.frame.origin.y,
                                       self.frame.size.width,
                                       self.frame.size.height / 2);
  _currentImageView.frame = CGRectMake(self.frame.origin.x,
                                   self.frame.origin.y + self.frame.size.height / 2,
                                   self.frame.size.width,
                                   self.frame.size.height / 2);
}
@end
