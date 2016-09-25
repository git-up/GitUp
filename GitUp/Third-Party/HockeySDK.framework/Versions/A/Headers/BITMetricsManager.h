#import <Foundation/Foundation.h>
#import "BITHockeyBaseManager.h"

/**
 The metrics module.
 
 This is the HockeySDK module that handles users, sessions and events tracking.
 
 Unless disabled, this module automatically tracks users and session of your app to give you
 better insights about how your app is being used.
 Users are tracked in a completely anonymous way without collecting any personally identifiable
 information.
 */
@interface BITMetricsManager : BITHockeyBaseManager

@end
