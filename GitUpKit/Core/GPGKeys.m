//  Copyright (C) 2015-2022 Pierre-Olivier Latour <info@pol-online.net>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#import "GPGKeys.h"
#import "GPGContext.h"
#import "GPGContext+Private.h"
#import "XLFacilityMacros.h"

@interface GPGKey()
@property (nonatomic, assign) gpgme_key_t key;
@property (nonatomic, strong) GPGContext* gpgContext;
@property (nonatomic, strong, nullable) NSString* name;
@property (nonatomic, strong, nullable) NSString* email;
@property (nonatomic, strong, nullable) NSString* keyId;
@end

@interface GPGKeys : NSObject
-(instancetype)initWithContext:(GPGContext*)context;

-(NSArray<GPGKey*>*)allSecretKeys;
@end


NSString* helperGpgDataToString(gpgme_data_t data) {
  gpgme_data_seek(data, 0, SEEK_SET);
  char buffer[1024] = {0};
  ssize_t readCount = gpgme_data_read(data, buffer, 1024);
  
  NSData* readData = [[NSData alloc] initWithBytes:buffer length:readCount];
  NSString* readString = [[NSString alloc] initWithData:readData encoding:NSUTF8StringEncoding];
  
  return readString;
}

@implementation GPGKey
static dispatch_once_t initializeThreadInfo;

+(NSArray<GPGKey *> *)allSecretKeys {
  dispatch_once(&initializeThreadInfo, ^{
    gpgme_check_version(NULL);
  });
  
  GPGContext* contextWrapper = [[GPGContext alloc] init];
  gpg_error_t keylistStartError = gpgme_op_keylist_start(contextWrapper.gpgContext, NULL, 1);
  
  if (keylistStartError) {
    XLOG_ERROR(@"Failed to start keylist: %s", gpg_strerror(keylistStartError));
    return nil;
  }
  
  NSMutableArray<GPGKey*> *keys = [NSMutableArray array];
  gpg_error_t err = 0;
  while (!err) {
    gpgme_key_t key;
    err = gpgme_op_keylist_next (contextWrapper.gpgContext, &key);
    if (err) {
      break;
    }
    
    GPGKey* gpgKey = [[GPGKey alloc] initWithGPGKey:key context:contextWrapper];
    [keys addObject:gpgKey];
  }
  
  if (gpg_err_code (err) != GPG_ERR_EOF) {
    XLOG_ERROR(@"Cannot list keys: %s", gpg_strerror(err));
    return nil;
  }
  
  return [keys copy];
}

+(instancetype)secretKeyForId:(NSString *)keyId {
  NSArray<GPGKey *>* allKeys = [self allSecretKeys];
  NSUInteger indexOfKey = [allKeys indexOfObjectPassingTest:^BOOL(GPGKey * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    return [obj.keyId isEqualToString:keyId];
  }];
  
  if (indexOfKey == NSNotFound) {
    return nil;
  }
  return allKeys[indexOfKey];
}

- (instancetype)initWithGPGKey:(gpgme_key_t)key context:(GPGContext*)context {
  self = [super init];
  if (self) {
    // retain key on initializer, release on object dealloc.
    gpgme_key_ref(key);
    self.key = key;
    self.gpgContext = context;
    
    if (_key->uids) {
      if (_key->uids->name) {
        _name = [[NSString alloc] initWithCString:_key->uids->name
                                         encoding:NSUTF8StringEncoding];
      }
      if (_key->uids->email) {
        _email = [[NSString alloc] initWithCString:_key->uids->email
                                          encoding:NSUTF8StringEncoding];
      }
    }
    
    if (_key->subkeys) {
      if (_key->subkeys->keyid) {
        _keyId = [[NSString alloc] initWithCString:_key->subkeys->keyid
                                          encoding:NSUTF8StringEncoding];
      }
    }
  }
  return self;
}

-(NSString *)description {
  return [NSString stringWithFormat:@"<%@: %p 'keyId: %@' 'email: %@' 'name: %@'>", self.class, self, self.keyId, self.email, self.name];
}

-(void)dealloc {
  gpgme_key_unref(_key);
}

-(NSString*)signSignature:(NSString*)document {
  gpgme_signers_clear(_gpgContext.gpgContext);
  gpgme_signers_add(_gpgContext.gpgContext, _key);
  
  gpgme_data_t in, out;
  gpgme_data_new(&out);
  
  gpgme_error_t err = gpgme_data_new_from_mem(&in, [document UTF8String], document.length, 1);
  if (err) {
    XLOG_ERROR(@"Failed to initialize input data: %s", gpg_strerror(err));
    return nil;
  }
  
  gpgme_set_textmode(_gpgContext.gpgContext, 0);
  gpgme_set_armor(_gpgContext.gpgContext, 1);
  
  err = gpgme_op_sign(_gpgContext.gpgContext, in, out, GPGME_SIG_MODE_DETACH);
  if (err) {
    XLOG_ERROR(@"Signing failed due: %s", gpg_strerror(err));
    return nil;
  }
  
  NSString* signatureString = helperGpgDataToString(out);
  
  gpgme_data_release(in);
  gpgme_data_release(out);
  
  return signatureString;
}

@end
