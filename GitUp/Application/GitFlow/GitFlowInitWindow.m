//
//  GitFlowInitWindow.m
//  GitUp
//
//  Created by Alex Severyanov on 8/20/16.
//
//

#import "GitFlowInitWindow.h"

@implementation GitFlowInitWindow
- (void)controlTextDidChange:(NSNotification *)obj {
  NSTextField *field = obj.object;
  if (field.stringValue.length > 0) {
    self.doneButton.enabled = [self allFieldsFilled];
  } else {
    self.doneButton.enabled = NO;
  }
}

- (BOOL)allFieldsFilled {
  NSArray<NSTextField *> *fields = @[
                                     self.masterBranchField,
                                     self.developBranchField,
                                     self.featurePrefixField,
                                     self.releasePrefixField,
                                     self.hotfixPrefixField
                                     ];
  for (NSTextField *field in fields) {
    if (field.stringValue.length == 0) { return NO; }
  }
  return YES;
}

@end
