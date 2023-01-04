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

#import "GPGContext.h"
#import "GPGContext+Private.h"
#import "XLFacilityMacros.h"

@implementation GPGContext
-(instancetype)init {
  self = [super init];
  if (self) {
    static dispatch_once_t initializeThreadInfo;
    dispatch_once(&initializeThreadInfo, ^{
      gpgme_check_version(NULL);
    });

    gpgme_error_t initError = gpgme_new(&_gpgContext);
    if (initError) {
      XLOG_ERROR(@"Failed to initialize GPGME context");
      return nil;
    }
  }
  return self;
}

-(void)dealloc {
  gpgme_release(_gpgContext);
}
@end
