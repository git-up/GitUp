//
//  AuthenticationWindow.m
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "AuthenticationWindow.h"

@interface AuthenticationWindow ()
@property(nonatomic, weak) IBOutlet NSTextField* urlTextField;
@property(nonatomic, weak) IBOutlet NSTextField* nameTextField;
@property(nonatomic, weak) IBOutlet NSSecureTextField* passwordTextField;
@end

@implementation AuthenticationWindow
#pragma mark - TextFields
- (void)setUrl:(NSString *)url {
  self.urlTextField.stringValue = url;
}
- (void)setName:(NSString *)name {
  self.nameTextField.stringValue = name;
}
- (void)setPassword:(NSString *)password {
  self.passwordTextField.stringValue = password;
}

- (NSString *)url {
  return [self.urlTextField.stringValue copy];
}
- (NSString *)name {
  return [self.nameTextField.stringValue copy];
}
- (NSString *)password {
  return [self.passwordTextField.stringValue copy];
}

#pragma mark - FirstResponder
- (NSResponder *)firstResponderWhenUsernameExists:(BOOL)usernameExists {
  return usernameExists ? self.passwordTextField : self.nameTextField;
}

- (void)makeFirstResponderWhenUsernameExists:(BOOL)usernameExists {
  [self makeFirstResponder:[self firstResponderWhenUsernameExists:usernameExists]];
}

- (BOOL)credentialsExists {
  return self.name.length && self.password.length;
}
@end
