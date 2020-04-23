//
//  CloneWindowController.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CloneWindowControllerResult : NSObject
@property(nonatomic, copy) NSURL* repositoryURL;
@property(nonatomic, copy) NSString* directoryPath;
@property(nonatomic) BOOL recursive;

@property(nonatomic, readonly) BOOL invalidRepository;
@property(nonatomic, readonly) BOOL emptyDirectoryPath;
@end

@interface CloneWindowController : NSWindowController
@property(nonatomic, copy) NSString* url;
- (void)runModalForURL:(NSString*)url completion:(void (^)(CloneWindowControllerResult* result))completion;
@end

NS_ASSUME_NONNULL_END
