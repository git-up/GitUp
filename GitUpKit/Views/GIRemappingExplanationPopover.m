//
//  GIRemappingExplanationPopover.m
//  GitUpKit
//
//  Created by Lucas Derraugh on 3/3/24.
//

#import "GIRemappingExplanationPopover.h"

static NSString* const GIRemappingExplanationShownUserDefaultKey = @"GIRemappingExplanationShownUserDefaultKey";

@interface GIRemappingExplanationViewController : NSViewController
@end

@interface GIRemappingExplanationViewController ()
@property(nonatomic, copy) void (^dismissCallback)();
@end

@implementation GIRemappingExplanationViewController

- (instancetype)initWithDismissCallback:(void (^)())dismissCallback {
  if ((self = [super initWithNibName:NSStringFromClass(self.class) bundle:[NSBundle bundleForClass:self.class]])) {
    self.dismissCallback = dismissCallback;
  }
  return self;
}

- (IBAction)okay:(id)sender {
  self.dismissCallback();
}

@end

@interface GIRemappingExplanationPopover ()
@end

@implementation GIRemappingExplanationPopover

+ (void)showIfNecessaryRelativeToRect:(NSRect)positioningRect ofView:(NSView*)positioningView preferredEdge:(NSRectEdge)preferredEdge {
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  if (![defaults boolForKey:GIRemappingExplanationShownUserDefaultKey]) {
    NSPopover* popover = [[NSPopover alloc] init];
    __weak NSPopover* weakPopover = popover;
    popover.contentViewController = [[GIRemappingExplanationViewController alloc] initWithDismissCallback:^{
      [defaults setBool:YES forKey:GIRemappingExplanationShownUserDefaultKey];
      [weakPopover close];
    }];
    [popover showRelativeToRect:positioningRect ofView:positioningView preferredEdge:NSRectEdgeMinY];
  }
}

@end
