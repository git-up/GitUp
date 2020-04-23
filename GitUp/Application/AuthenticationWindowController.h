//
//  AuthenticationWindowController.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class GCRepository;

@interface AuthenticationWindowController : NSWindowController

// Repository
- (void)repository:(GCRepository*)repository willStartTransferWithURL:(NSURL*)url;
- (BOOL)repository:(GCRepository*)repository requiresPlainTextAuthenticationForURL:(NSURL*)url user:(NSString*)user username:(NSString* _Nullable* _Nonnull)username password:(NSString* _Nullable* _Nonnull)password;
- (void)repository:(GCRepository*)repository didFinishTransferWithURL:(NSURL*)url success:(BOOL)success;
@end

NS_ASSUME_NONNULL_END
