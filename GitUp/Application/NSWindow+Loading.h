//
//  NSWindow+Loading.h
//  Application
//
//  Created by Dmitry Lobanov on 22.10.2019.
//

#import <AppKit/AppKit.h>


#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSWindow (Loading)
+ (id)loadWindowFromBundleXibWithName:(NSString *)name expectedClass:(Class)expectedClass;
@end

NS_ASSUME_NONNULL_END
