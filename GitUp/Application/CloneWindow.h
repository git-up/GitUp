//
//  CloneWindow.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface CloneWindow : NSWindow
@property(nonatomic, weak) IBOutlet NSTextField* urlTextField;
@property(nonatomic, weak) IBOutlet NSButton* cloneRecursiveButton;
@end

NS_ASSUME_NONNULL_END
