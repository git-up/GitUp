//
//  AboutPanel.h
//  Application
//
//  Created by Dmitry Lobanov on 08.10.2019.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AboutPanel : NSPanel
@property (nonatomic, copy) NSString *versionString;
@property (nonatomic, copy) NSString *copyrightString;
@end

NS_ASSUME_NONNULL_END
