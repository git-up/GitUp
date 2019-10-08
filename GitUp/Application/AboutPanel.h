//
//  AboutPanel.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AboutPanel : NSPanel
@property(nonatomic, weak) IBOutlet NSTextField* versionTextField;
@property(nonatomic, weak) IBOutlet NSTextField* copyrightTextField;
@end

NS_ASSUME_NONNULL_END
