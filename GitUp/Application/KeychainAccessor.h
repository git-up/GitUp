//
//  KeychainAccessor.h
//  Application
//
//  Created by Dmitry Lobanov on 05.11.2019.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KeychainAccessor : NSObject
+ (BOOL)loadPlainTextAuthenticationFormKeychainForURL:(NSURL*)url user:(NSString*)user username:(NSString* _Nullable* _Nonnull)username password:(NSString* _Nullable* _Nonnull)password allowInteraction:(BOOL)allowInteraction;
+ (void)savePlainTextAuthenticationToKeychainForURL:(NSURL*)url username:(NSString*)username password:(NSString*)password;
@end

NS_ASSUME_NONNULL_END
