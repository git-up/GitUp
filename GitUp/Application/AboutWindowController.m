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
  [self configureUI];
}

- (void)configureUI {
  NSString* version = nil;
#if DEBUG
  version = @"DEBUG";
#else
  version = [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@)", nil), [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
#endif
  self.versionTextField.stringValue = version;
  self.copyrightTextField.stringValue = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"];
}

@end
