//
//  AuthenticationWindowController.m
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "AuthenticationWindowController.h"
#import <GitUpKit/GitUpKit.h>
#import <GitUpKit/XLFacilityMacros.h>

@interface AuthenticationWindowControllerModel : NSObject
@property (nonatomic, assign) BOOL useKeychain;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *password;

@property (nonatomic, assign, readonly) BOOL isValid;
@end

@implementation AuthenticationWindowControllerModel
- (BOOL)isValid {
  return self.url && self.name && self.password;
}
- (void)unsetUseKeychain {
  self.useKeychain = NO;
}
- (void)willStartTransfer {
  self.useKeychain = YES;
  self.url = nil;
  self.name = nil;
  self.password = nil;
}
- (void)didFinishTransferWithURL:(NSURL *)url success:(BOOL)success onResult:(void(^)(AuthenticationWindowControllerModel *model))onResult {
  if (onResult) {
    BOOL shouldPassModel = success && self.isValid;
    onResult( shouldPassModel ? self : nil );
  }
  self.url = nil;
  self.name = nil;
  self.password = nil;
}
@end

@interface AuthenticationWindowController ()

// Model
@property (nonatomic, strong) AuthenticationWindowControllerModel *model;

// Outlets
@property(nonatomic, weak) IBOutlet NSTextField* urlTextField;
@property(nonatomic, weak) IBOutlet NSTextField* nameTextField;
@property(nonatomic, weak) IBOutlet NSSecureTextField* passwordTextField;

// First Responder
- (NSResponder *)firstResponderWhenUsernameExists:(BOOL)usernameExists;
- (void)makeFirstResponderWhenUsernameExists:(BOOL)usernameExists;

// Credentials
@property (nonatomic, assign, readonly) BOOL credentialsExists;
@end

@implementation AuthenticationWindowController
#pragma mark - FirstResponder
- (NSResponder *)firstResponderWhenUsernameExists:(BOOL)usernameExists {
  return usernameExists ? self.passwordTextField : self.nameTextField;
}

- (void)makeFirstResponderWhenUsernameExists:(BOOL)usernameExists {
  [self.window makeFirstResponder:[self firstResponderWhenUsernameExists:usernameExists]];
}

#pragma mark - Credentials
- (BOOL)credentialsExists {
  return self.nameTextField.stringValue.length && self.passwordTextField.stringValue.length;
}

#pragma mark - Repository
- (void)repository:(GCRepository*)repository willStartTransferWithURL:(NSURL*)url {
  [self.model willStartTransfer];
}

- (BOOL)repository:(GCRepository*)repository requiresPlainTextAuthenticationForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password {
  if (self.model.useKeychain) {
    [self.model unsetUseKeychain];
    if (self.loadPlainTextAuthenticationFormKeychain) {
      if (self.loadPlainTextAuthenticationFormKeychain(url, user, username, password)) {
        return YES;
      }
    }
  } else {
    XLOG_VERBOSE(@"Skipping Keychain lookup for repeated authentication failures");
  }

  self.urlTextField.stringValue = url.absoluteString;
  self.nameTextField.stringValue = *username ? *username : @"";
  self.passwordTextField.stringValue = @"";
  [self makeFirstResponderWhenUsernameExists:*username != nil];
  if ([NSApp runModalForWindow:self.window] && self.credentialsExists) {
    self.model.url = url;
    self.model.name = self.nameTextField.stringValue;
    self.model.password = self.passwordTextField.stringValue;
    *username = self.model.name;
    *password = self.model.password;
    return YES;
  }
  return NO;
}

- (void)repository:(GCRepository*)repository didFinishTransferWithURL:(NSURL*)url success:(BOOL)success {
  [self.model didFinishTransferWithURL:url success:success onResult:^(AuthenticationWindowControllerModel *model) {
    if (model && self.savePlainTextAuthenticationToKeychain) {
      self.savePlainTextAuthenticationToKeychain(model.url, model.name, model.password);
    }
  }];
}

@end