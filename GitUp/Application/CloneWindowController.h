//
//  CloneWindowController.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CloneWindowControllerResult : NSObject
@property (nonatomic, copy) NSURL *repositoryURL;
@property (nonatomic, copy) NSString *directoryPath;
@property (nonatomic, assign) BOOL recursive;

@property (nonatomic, assign, readonly) BOOL invalidRepository;
@property (nonatomic, assign, readonly) BOOL emptyDirectoryPath;
@end

@interface CloneWindowController : NSWindowController
@property (nonatomic, copy) NSString *url;
- (void)runModalForURL:(NSString *)url completion:(void(^)(CloneWindowControllerResult *result))completion;
@end

NS_ASSUME_NONNULL_END
