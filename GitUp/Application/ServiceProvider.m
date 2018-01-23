//  Copyright (C) 2015-2017 Pierre-Olivier Latour <info@pol-online.net>
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

#import <Foundation/Foundation.h>
#import "ServiceProvider.h"

@implementation ServiceProvider : NSObject

- (void)service:(NSPasteboard*)pboard
       userData:(NSString*)userData
          error:(NSString**)error {
  NSURL* url = [NSURL URLFromPasteboard:pboard];
  [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url
                                                                         display:YES
                                                               completionHandler:^(NSDocument* document, BOOL documentWasAlreadyOpen, NSError* openError) {
                                                                 if (!document) {
                                                                   if (openError.code == -3) {
                                                                     NSAlert* alert = [[NSAlert alloc] init];
                                                                     alert.messageText = @"Could not find a repository in this folder. Create one?";
                                                                     [alert addButtonWithTitle:@"OK"];
                                                                     [alert addButtonWithTitle:@"Cancel"];
                                                                     if ([alert runModal] == NSAlertFirstButtonReturn) {
                                                                       NSError* error;
                                                                       GCRepository* repository = [[GCRepository alloc] initWithNewLocalRepository:url.path bare:NO error:&error];
                                                                       if (repository) {
                                                                         [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:repository.workingDirectoryPath]
                                                                                                                                                display:YES
                                                                                                                                      completionHandler:^(NSDocument* document, BOOL documentWasAlreadyOpen, NSError* openError) {
                                                                                                                                        if (!document) {
                                                                                                                                          [[NSDocumentController sharedDocumentController] presentError:openError];
                                                                                                                                        }
                                                                                                                                      }];
                                                                       } else {
                                                                         [[NSDocumentController sharedDocumentController] presentError:error];
                                                                       }
                                                                     }
                                                                   } else {
                                                                     [[NSDocumentController sharedDocumentController] presentError:openError];
                                                                   }
                                                                 }

                                                               }];
}
@end
