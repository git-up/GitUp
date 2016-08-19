//
//  GitFlowAboutPanel.m
//  GitUp
//
//  Created by Alex Severyanov on 8/19/16.
//
//

#import "GitFlowAboutPanel.h"

@interface GitFlowAboutPanel()
@property (nonatomic, strong) IBOutlet NSButton *gitFlowButton;
@property (nonatomic, strong) IBOutlet NSButton *changesButton;
@end

@implementation GitFlowAboutPanel

- (void)setButtonTitleFor:(NSButton*)button toString:(NSString*)title withColor:(NSColor*)color {
  
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  [style setAlignment:NSCenterTextAlignment];
  NSDictionary *attrsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:color, NSForegroundColorAttributeName, style, NSParagraphStyleAttributeName, nil];
  NSAttributedString *attrString = [[NSAttributedString alloc]initWithString:title attributes:attrsDictionary];
  [button setAttributedTitle:attrString];
}

-(void)awakeFromNib {
  NSArray *titles = @[ NSLocalizedString(@"Git Flow", nil), NSLocalizedString(@"Changes", nil) ];
  NSArray *buttons = @[ self.gitFlowButton, self.changesButton  ];
  for (NSUInteger i = 0; i < buttons.count; ++i) {
    NSButton *button = buttons[i];
    NSString *title = titles[i];
    NSColor *color = [NSColor blueColor];
    [self setButtonTitleFor:button toString:title withColor:color];
  }
}

- (IBAction)changesAction:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"https://github.com/AlexIzh/git-flow-improvement-branch#improve"]];
}

- (IBAction)gitFlowAction:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"http://nvie.com/posts/a-successful-git-branching-model/"]];
}

@end
