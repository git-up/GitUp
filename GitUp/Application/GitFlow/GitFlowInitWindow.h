//
//  GitFlowInitWindow.h
//  GitUp
//
//  Created by Alex Severyanov on 8/20/16.
//
//

#import <Cocoa/Cocoa.h>

@interface GitFlowInitWindow : NSWindow

@property (nonatomic, strong) IBOutlet NSButton *doneButton;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;

@property (nonatomic, strong) IBOutlet NSTextField *masterBranchField;
@property (nonatomic, strong) IBOutlet NSTextField *developBranchField;

@property (nonatomic, strong) IBOutlet NSTextField *featurePrefixField;
@property (nonatomic, strong) IBOutlet NSTextField *improvementPrefixField;
@property (nonatomic, strong) IBOutlet NSTextField *releasePrefixField;
@property (nonatomic, strong) IBOutlet NSTextField *hotfixPrefixField;
@property (nonatomic, strong) IBOutlet NSTextField *tagVersionPrefixField;

@end
