//
//  CloneWindow.m
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import "CloneWindow.h"

@interface CloneWindow ()
@property(nonatomic, weak) IBOutlet NSTextField* urlTextField;
@property(nonatomic, weak) IBOutlet NSButton* cloneRecursiveButton;
@end

@implementation CloneWindow

- (void)setUrl:(NSString *)url {
  self.urlTextField.stringValue = url;
  self.cloneRecursiveButton.state = NSOnState;
}

- (NSString *)url {
  return self.urlTextField.stringValue;
}

- (BOOL)urlExists {
  return self.url.length;
}

- (BOOL)recursive {
  return self.cloneRecursiveButton.state;
}

@end
