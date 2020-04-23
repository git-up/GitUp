//
//  CloneWindowController.m
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "CloneWindowController.h"
#import <GitUpKit/GitUpKit.h>

@interface CloneWindowControllerResult ()
- (instancetype)initWithRepositoryURL:(NSURL*)url directoryPath:(NSString*)path recursive:(BOOL)recursive;
@end

@implementation CloneWindowControllerResult
- (instancetype)initWithRepositoryURL:(NSURL*)url directoryPath:(NSString*)path recursive:(BOOL)recursive {
  if ((self = [super init])) {
    self.repositoryURL = url;
    self.directoryPath = path;
    self.recursive = recursive;
  }
  return self;
}

- (BOOL)invalidRepository {
  return self.repositoryURL == nil;
}

- (BOOL)emptyDirectoryPath {
  return self.directoryPath == nil;
}
@end

@interface CloneWindowController ()
@property(nonatomic, weak) IBOutlet NSTextField* urlTextField;
@property(nonatomic, weak) IBOutlet NSButton* cloneRecursiveButton;
@property(nonatomic, readonly) BOOL urlExists;
@property(nonatomic, readonly) BOOL recursive;
@end

@implementation CloneWindowController
#pragma mark - Initialization
- (instancetype)init {
  return [super initWithWindowNibName:@"CloneWindowController"];
}

#pragma mark - Window Lifecycle
- (void)beforeRunInModal {
  self.urlTextField.stringValue = self.url;
  self.cloneRecursiveButton.state = NSOnState;
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

#pragma mark - Modal
- (void)runModalForURL:(NSString*)url completion:(nonnull void (^)(CloneWindowControllerResult* _Nonnull))completion {
  if (!completion) {
    return;
  }

  self.url = url;
  if (self.windowLoaded) {
    [self beforeRunInModal];
  }
  if ([NSApp runModalForWindow:self.window] && self.urlExists) {
    NSURL* url = GCURLFromGitURL(self.urlTextField.stringValue);
    if (url) {
      NSString* name = [url.path.lastPathComponent stringByDeletingPathExtension];
      NSSavePanel* savePanel = [NSSavePanel savePanel];
      savePanel.title = NSLocalizedString(@"Clone Repository", nil);
      savePanel.prompt = NSLocalizedString(@"Clone", nil);
      savePanel.nameFieldLabel = NSLocalizedString(@"Name:", nil);
      savePanel.nameFieldStringValue = name ? name : @"";
      savePanel.showsTagField = NO;
      if ([savePanel runModal] == NSFileHandlingPanelOKButton) {
        NSString* path = savePanel.URL.path;
        completion([[CloneWindowControllerResult alloc] initWithRepositoryURL:url directoryPath:path recursive:self.recursive]);
      } else {
        // empty directory path or cancel button pressed.
        completion([[CloneWindowControllerResult alloc] initWithRepositoryURL:url directoryPath:nil recursive:self.recursive]);
      }
    } else {
      // invalid repository
      completion([[CloneWindowControllerResult alloc] initWithRepositoryURL:url directoryPath:nil recursive:self.recursive]);
    }
  }
}

#pragma mark - Getters
- (BOOL)urlExists {
  return self.urlTextField.stringValue.length;
}

- (BOOL)recursive {
  return self.cloneRecursiveButton.state;
}

@end
