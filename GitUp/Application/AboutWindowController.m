//
//  AboutWindowController.m
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "AboutWindowController.h"

@interface AboutWindowController ()
@property(nonatomic, weak) IBOutlet NSTextField* versionTextField;
@property(nonatomic, weak) IBOutlet NSTextField* copyrightTextField;
@end

@implementation AboutWindowController

- (instancetype)init {
  return [super initWithWindowNibName:@"AboutWindowController"];
}

- (void)windowDidLoad {
  [super windowDidLoad];
  [self populateWithDataWhenUpdateIsPending:self.updatePending];
}

- (void)populateWithDataWhenUpdateIsPending:(BOOL)updatePending {
  NSString* version = nil;
#if DEBUG
  version = @"DEBUG";
#else
  if (updatePending) {
    version = NSLocalizedString(@"Update Pending", nil);
  } else {
    version = [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@)", nil), [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
  }
#endif
  self.versionTextField.stringValue = version;
  self.copyrightTextField.stringValue = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"];
}

@end
