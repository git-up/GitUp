//
//  ServicesProvider.m
//  Application
//
//  Created by Dmitry Lobanov on 17/09/2019.
//

#import "ServicesProvider.h"
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "Document.h"

@interface AppDelegate (ServicesProvider)
- (void)_openRepositoryWithURL:(NSURL*)url withCloneMode:(CloneMode)cloneMode windowModeID:(WindowModeID)windowModeID;
@end

@interface ServicesProvider ()
@property (weak, nonatomic, readonly) AppDelegate *appDelegate;
@end

@implementation ServicesProvider

#pragma mark - Accessors
- (AppDelegate *)appDelegate {
  return [AppDelegate sharedDelegate];
}

#pragma mark - Check pasteboard
- (BOOL)canOpenItem:(NSPasteboard *)pasteboard {
  return [self items:pasteboard].count > 0;
}

- (NSArray <NSURL *>*)items:(NSPasteboard *)pasteboard {
  return [pasteboard readObjectsForClasses:@[NSURL.class] options:nil];
}

#pragma mark - Services Provider
// the minimum method which consists of 3 parameters.
// 1. methodName: NSPasteboard
// 2. userData: NSString
// 3. error: *NSError
// methodName ( first part ) will be used in .plist to advertise service.

// NOTE:
// To debug services functionailty.
// 1. Be sure that methodName ( openRepository ) is used as instance method in plist.
// 2. Set correct send types in plist. ( NSURLPboardType for urls. )
// 3. Open Derived data and put .app into ~/Application directory.
// 4. Rename app if necessary.
// 5. Use pbs utility to refresh services.
// 5.1. /System/Library/CoreServices/pbs -update
// 5.2. /System/Library/CoreServices/pbs -flush
// 5.3. /System/Library/CoreServices/pbs -dump_cache
// 6. Be sure that your .app is appearing in dump_cache output.
// 7. Check finder contextual menu.
- (void)openRepository:(NSPasteboard *)pasteboard userData:(NSString *)userData error:(NSError * __autoreleasing *)error {
  if ([self canOpenItem:pasteboard]) {
    NSURL *url = [self items:pasteboard].firstObject;
    [self.appDelegate _openRepositoryWithURL:url withCloneMode:kCloneMode_None windowModeID:NSNotFound];
  }
  else {
    // fill error if needed.
  }
}

@end
