#import <Foundation/Foundation.h>

/**
 *  Provides details about the crash that occured in the previous app session
 */
@interface BITCrashDetails : NSObject

/**
 *  UUID for the crash report
 */
@property (nonatomic, readonly, strong) NSString *incidentIdentifier;

/**
 *  UUID for the app installation on the device
 */
@property (nonatomic, readonly, strong) NSString *reporterKey;

/**
 *  Signal that caused the crash
 */
@property (nonatomic, readonly, strong) NSString *signal;

/**
 *  Exception name that triggered the crash, nil if the crash was not caused by an exception
 */
@property (nonatomic, readonly, strong) NSString *exceptionName;

/**
 *  Exception reason, nil if the crash was not caused by an exception
 */
@property (nonatomic, readonly, strong) NSString *exceptionReason;

/**
 *  Date and time the app started, nil if unknown
 */
@property (nonatomic, readonly, strong) NSDate *appStartTime;

/**
 *  Date and time the crash occured, nil if unknown
 */
@property (nonatomic, readonly, strong) NSDate *crashTime;

/**
 *  Operation System version string the app was running on when it crashed.
 */
@property (nonatomic, readonly, strong) NSString *osVersion;

/**
 *  Operation System build string the app was running on when it crashed
 *
 *  This may be unavailable.
 */
@property (nonatomic, readonly, strong) NSString *osBuild;

/**
 *  CFBundleShortVersionString value of the app that crashed
 *
 *  Can be `nil` if the crash was captured with an older version of the SDK
 *  or if the app doesn't set the value.
 */
@property (nonatomic, readonly, strong) NSString *appVersion;

/**
 *  CFBundleVersion value of the app that crashed
 */
@property (nonatomic, readonly, strong) NSString *appBuild;

@end
