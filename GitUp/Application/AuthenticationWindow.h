//
//  AuthenticationWindow.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AuthenticationWindow : NSWindow
@property(nonatomic, weak) IBOutlet NSTextField* urlTextField;
@property(nonatomic, weak) IBOutlet NSTextField* nameTextField;
@property(nonatomic, weak) IBOutlet NSSecureTextField* passwordTextField;
@end

NS_ASSUME_NONNULL_END
