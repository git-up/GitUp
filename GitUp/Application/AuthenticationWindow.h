//
//  AuthenticationWindow.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AuthenticationWindow : NSWindow
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *password;
- (NSResponder *)firstResponderWhenUsernameExists:(BOOL)usernameExists;
- (void)makeFirstResponderWhenUsernameExists:(BOOL)usernameExists;
@property (nonatomic, assign, readonly) BOOL credentialsExists;
@end

NS_ASSUME_NONNULL_END
