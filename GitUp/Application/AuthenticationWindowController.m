//
//  AuthenticationWindowController.m
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "AuthenticationWindowController.h"
#import <GitUpKit/GitUpKit.h>
#import <GitUpKit/XLFacilityMacros.h>
#import "KeychainAccessor.h"

@interface AuthenticationWindowControllerModel : NSObject
@property(nonatomic, assign) BOOL useCredentialHelper;
@property(nonatomic, assign) BOOL useKeychain;
@property(nonatomic, assign) BOOL credentialsFromHelper;  // Current credentials were provided by a Git credential helper
@property(nonatomic, copy) NSURL* url;
@property(nonatomic, copy) NSString* name;
@property(nonatomic, copy) NSString* password;

@property(nonatomic, assign, readonly) BOOL isValid;
@end

@implementation AuthenticationWindowControllerModel
- (BOOL)isValid {
  return self.url && self.name && self.password;
}
- (void)unsetUseCredentialHelper {
  self.useCredentialHelper = NO;
}
- (void)unsetUseKeychain {
  self.useKeychain = NO;
}
- (void)willStartTransfer {
  self.useCredentialHelper = YES;
  self.useKeychain = YES;
  self.credentialsFromHelper = NO;
  self.url = nil;
  self.name = nil;
  self.password = nil;
}
- (void)didFinishTransferWithURL:(NSURL*)url success:(BOOL)success onResult:(void (^)(AuthenticationWindowControllerModel* model))onResult {
  if (onResult) {
    BOOL shouldPassModel = success && self.isValid;
    onResult(shouldPassModel ? self : nil);
  }
  self.credentialsFromHelper = NO;
  self.url = nil;
  self.name = nil;
  self.password = nil;
}
@end

@interface AuthenticationWindowController ()

// Model
@property(nonatomic, strong) AuthenticationWindowControllerModel* model;

// Outlets
@property(nonatomic, weak) IBOutlet NSTextField* urlTextField;
@property(nonatomic, weak) IBOutlet NSTextField* nameTextField;
@property(nonatomic, weak) IBOutlet NSSecureTextField* passwordTextField;

// Credentials
@property(nonatomic, assign, readonly) BOOL credentialsExists;

@end

@implementation AuthenticationWindowController
#pragma mark - Initialization
- (instancetype)init {
  if ((self = [super initWithWindowNibName:@"AuthenticationWindowController"])) {
    self.model = [[AuthenticationWindowControllerModel alloc] init];
  }
  return self;
}

#pragma mark - Window Lifecycle
- (void)beforeRunInModal {
  self.urlTextField.stringValue = self.model.url.absoluteString;
  self.nameTextField.stringValue = self.model.name;
  self.passwordTextField.stringValue = self.model.password;
  [self makeFirstResponderWhenUsernameExists:self.model.name.length > 0];
}
- (void)windowDidLoad {
  [super windowDidLoad];
  [self beforeRunInModal];
}

#pragma mark - Actions
- (IBAction)dismissModal:(id)sender {
  [NSApp stopModalWithCode:[(NSButton*)sender tag]];
  [self close];
}

#pragma mark - FirstResponder
- (NSResponder*)firstResponderWhenUsernameExists:(BOOL)usernameExists {
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
  // Being asked again after a helper provided credentials means the remote rejected them: let the helpers know and fall through to the other sources
  if (self.model.credentialsFromHelper && self.model.isValid) {
    NSError* error;
    if (![repository rejectCredentialsForURL:self.model.url username:self.model.name password:self.model.password error:&error]) {
      XLOG_WARNING(@"Failed rejecting credentials with Git credential helpers: %@", error.localizedDescription);
    }
    self.model.credentialsFromHelper = NO;
    self.model.url = nil;
    self.model.name = nil;
    self.model.password = nil;
  }

  // Try the credential helpers configured in Git first (e.g. "gh auth git-credential", "osxkeychain" or Git Credential Manager)
  if (self.model.useCredentialHelper) {
    [self.model unsetUseCredentialHelper];
    NSString* helperUsername = nil;
    NSString* helperPassword = nil;
    NSError* error;
    if ([repository fillCredentialsForURL:url user:user username:&helperUsername password:&helperPassword error:&error]) {
      self.model.url = url;
      self.model.name = helperUsername;
      self.model.password = helperPassword;
      self.model.credentialsFromHelper = YES;
      *username = helperUsername;
      *password = helperPassword;
      return YES;
    }
    XLOG_VERBOSE(@"Git credential helpers did not provide credentials for \"%@\": %@", url, error.localizedDescription);
  }

  if (self.model.useKeychain) {
    [self.model unsetUseKeychain];
    if ([KeychainAccessor loadPlainTextAuthenticationFormKeychainForURL:url user:user username:username password:password allowInteraction:YES]) {
      return YES;
    }
  } else {
    XLOG_VERBOSE(@"Skipping Keychain lookup for repeated authentication failures");
  }

  // TODO: Add data to model and when window is appearing, we should set data from model.
  // We need two callbacks ( willPresentModal and didPresentModal ).
  self.model.url = url;

  self.model.name = *username ? *username : @"";
  self.model.password = @"";

  if (self.windowLoaded) {
    [self beforeRunInModal];
  } else {
    // look at -windowDidLoad when window first time loaded.
  }

  if ([NSApp runModalForWindow:self.window] && self.credentialsExists) {
    self.model.name = self.nameTextField.stringValue;
    self.model.password = self.passwordTextField.stringValue;
    *username = self.model.name;
    *password = self.model.password;
    return YES;
  }

  return NO;
}

- (void)repository:(GCRepository*)repository didFinishTransferWithURL:(NSURL*)url success:(BOOL)success {
  [self.model didFinishTransferWithURL:url
                               success:success
                              onResult:^(AuthenticationWindowControllerModel* model) {
                                if (!model) {
                                  return;
                                }
                                if (model.credentialsFromHelper) {
                                  // Let the helpers cache the credentials, like Git itself does, instead of duplicating them in the Keychain
                                  NSError* error;
                                  if (![repository approveCredentialsForURL:model.url username:model.name password:model.password error:&error]) {
                                    XLOG_WARNING(@"Failed approving credentials with Git credential helpers: %@", error.localizedDescription);
                                  }
                                } else {
                                  [KeychainAccessor savePlainTextAuthenticationToKeychainForURL:url username:model.name password:model.password];
                                }
                              }];
}

@end
