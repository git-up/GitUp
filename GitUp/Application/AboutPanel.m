//
//  AboutPanel.m
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "AboutPanel.h"
@interface AboutPanel ()
@property(nonatomic, weak) IBOutlet NSTextField* versionTextField;
@property(nonatomic, weak) IBOutlet NSTextField* copyrightTextField;
@end

@implementation AboutPanel
- (void)populateWithDataWhenUpdateIsPending:(BOOL)updatePending {
    NSString *version = nil;
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

@implementation AboutPanelWindowController

- (instancetype)init {
  return [super initWithWindowNibName:@"AboutPanel"];
}

- (void)populateWithDataWhenUpdateIsPending:(BOOL)updatePending {
  [self loadWindow];
  [(AboutPanel *)self.window populateWithDataWhenUpdateIsPending:updatePending];
}

@end
