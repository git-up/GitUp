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
// 1. Pasteboard: NSPasteboard
// 2. UserData: NSString
// 3. Error: *NSString
- (void)openInFinderEntry:(NSPasteboard *)pasteboard userData:(NSString *)userData error:(NSString * __autoreleasing *)error {
  
  if ([self canOpenItem:pasteboard]) {
    NSURL *url = [self items:pasteboard].firstObject;
    [self.appDelegate _openRepositoryWithURL:url withCloneMode:kCloneMode_None windowModeID:NSNotFound];
  }
  else {
    *error = NSLocalizedString(@"Can't open folder!", @"");
  }
}

@end
