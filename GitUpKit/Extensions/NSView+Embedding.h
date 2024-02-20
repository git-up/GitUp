//
//  NSView+Embedding.h
//  GitUpKit (OSX)
//
//  Created by Dmitry Lobanov on 06.04.2020.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSView (Embedding)
- (void)embedView:(NSView *)view;
@end

NS_ASSUME_NONNULL_END
