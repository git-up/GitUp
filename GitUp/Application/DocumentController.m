//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
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

#import "DocumentController.h"
#import "AppDelegate.h"
#import "Common.h"

#import <GitUpKit/GitUpKit.h>
#import <GitUpKit/XLFacilityMacros.h>

@implementation DocumentController

// Patch method to allow selecting folders
- (void)beginOpenPanel:(NSOpenPanel*)openPanel forTypes:(NSArray*)inTypes completionHandler:(void (^)(NSInteger result))completionHandler {
  XLOG_DEBUG_CHECK([inTypes isEqualToArray:@[ @"public.directory" ]]);
  openPanel.canChooseFiles = NO;
  openPanel.canChooseDirectories = YES;
  openPanel.treatsFilePackagesAsDirectories = YES;
  [super beginOpenPanel:openPanel forTypes:inTypes completionHandler:completionHandler];
}

- (NSError*)willPresentError:(NSError*)error {
  NSError* underlyingError = [error.userInfo objectForKey:NSUnderlyingErrorKey];
  if ([underlyingError.domain isEqualToString:GCErrorDomain]) {
    error = underlyingError;  // Required to display real error from -[NSDocument readFromURL:ofType:error:]
  }

  if ([error.domain isEqualToString:GCErrorDomain] && (error.code == kGCErrorCode_CheckoutConflicts) && [error.localizedDescription hasSuffix:@" checkout"]) {  // TODO: Avoid hardcoding libgit2 error
    error = GCNewError(kGCErrorCode_CheckoutConflicts, @"Local changes would be overwritten by checkout");
  }

  return [super willPresentError:error];
}

- (void)addDocument:(NSDocument*)document {
  [super addDocument:document];

  [[AppDelegate sharedDelegate] handleDocumentCountChanged];
}

- (void)removeDocument:(NSDocument*)document {
  [super removeDocument:document];

  [[AppDelegate sharedDelegate] handleDocumentCountChanged];
}

- (void)newWindowForTab:(id)sender {
  [self openDocument:sender];
}

@end
