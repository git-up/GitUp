//
//  KeychainAccessor.m
//  Application
//
//  Created by Dmitry Lobanov on 05.11.2019.
//

#import "KeychainAccessor.h"
#import <Security/Security.h>
#import <GitUpKit/XLFacilityMacros.h>

@implementation KeychainAccessor

// WARNING: We are using the same attributes for the keychain items than Git CLT appears to be using as of version 1.9.3
+ (BOOL)loadPlainTextAuthenticationFormKeychainForURL:(NSURL*)url user:(NSString*)user username:(NSString**)username password:(NSString**)password allowInteraction:(BOOL)allowInteraction {
  const char* serverName = url.host.UTF8String;
  if (serverName && serverName[0]) {  // TODO: How can this be NULL?
    const char* accountName = (*username).UTF8String;
    SecKeychainItemRef itemRef;
    UInt32 passwordLength;
    void* passwordData;
    SecKeychainSetUserInteractionAllowed(allowInteraction);  // Ignore errors
    OSStatus status = SecKeychainFindInternetPassword(NULL,
                                                      (UInt32)strlen(serverName), serverName,
                                                      0, NULL,  // Any security domain
                                                      accountName ? (UInt32)strlen(accountName) : 0, accountName,
                                                      0, NULL,  // Any path
                                                      0,  // Any port
                                                      kSecProtocolTypeAny,
                                                      kSecAuthenticationTypeAny,
                                                      &passwordLength, &passwordData, &itemRef);
    if (status == noErr) {
      BOOL success = NO;
      *password = [[NSString alloc] initWithBytes:passwordData length:passwordLength encoding:NSUTF8StringEncoding];
      if (accountName == NULL) {
        UInt32 tag = kSecAccountItemAttr;
        UInt32 format = CSSM_DB_ATTRIBUTE_FORMAT_STRING;
        SecKeychainAttributeInfo info = {1, &tag, &format};
        SecKeychainAttributeList* attributes;
        status = SecKeychainItemCopyAttributesAndData(itemRef, &info, NULL, &attributes, NULL, NULL);
        if (status == noErr) {
          XLOG_DEBUG_CHECK(attributes->count == 1);
          XLOG_DEBUG_CHECK(attributes->attr[0].tag == kSecAccountItemAttr);
          *username = [[NSString alloc] initWithBytes:attributes->attr[0].data length:attributes->attr[0].length encoding:NSUTF8StringEncoding];
          success = YES;
          SecKeychainItemFreeAttributesAndData(attributes, NULL);
        } else {
          XLOG_ERROR(@"SecKeychainItemCopyAttributesAndData() returned error %i", status);
        }
      } else {
        success = YES;
      }
      SecKeychainItemFreeContent(NULL, passwordData);
      CFRelease(itemRef);
      if (success) {
        return YES;
      }
    } else if (status != errSecItemNotFound) {
      XLOG_ERROR(@"SecKeychainFindInternetPassword() returned error %i", status);
    }
  } else {
    XLOG_WARNING(@"Unable to extract hostname from remote URL: %@", url);
  }
  return NO;
}

+ (void)savePlainTextAuthenticationToKeychainForURL:(NSURL*)url username:(NSString*)username password:(NSString*)password {
  SecProtocolType type;
  if ([url.scheme isEqualToString:@"http"]) {
    type = kSecProtocolTypeHTTP;
  } else if ([url.scheme isEqualToString:@"https"]) {
    type = kSecProtocolTypeHTTPS;
  } else {
    XLOG_DEBUG_UNREACHABLE();
    return;
  }
  const char* serverName = url.host.UTF8String;
  const char* accountName = username.UTF8String;
  const char* accountPassword = password.UTF8String;
  SecKeychainSetUserInteractionAllowed(true);  // Ignore errors
  OSStatus status = SecKeychainAddInternetPassword(NULL,
                                                   (UInt32)strlen(serverName), serverName,
                                                   0, NULL,  // Any security domain
                                                   accountName ? (UInt32)strlen(accountName) : 0, accountName,
                                                   0, NULL,  // Any path
                                                   0,  // Any port
                                                   type,
                                                   kSecAuthenticationTypeAny,
                                                   (UInt32)strlen(accountPassword), accountPassword, NULL);
  if (status != noErr) {
    XLOG_ERROR(@"SecKeychainAddInternetPassword() returned error %i", status);
  } else {
    XLOG_VERBOSE(@"Successfully saved authentication in Keychain");
  }
}

@end
