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
- (void)setVersionString:(NSString *)versionString {
  self.versionTextField.stringValue = versionString;
}

- (void)setCopyrightString:(NSString *)copyrightString {
  self.copyrightTextField.stringValue = copyrightString;
}
@end
