#import <Foundation/Foundation.h>


/**
 *  This class provides properties that can be attached to a crash report via a custom alert view flow
 */
@interface BITCrashMetaData : NSObject

/**
 *  User provided description that should be attached to the crash report as plain text
 */
@property (nonatomic, copy) NSString *userDescription;

/**
 *  User name that should be attached to the crash report
 */
@property (nonatomic, copy) NSString *userName;

/**
 *  User email that should be attached to the crash report
 */
@property (nonatomic, copy) NSString *userEmail;

/**
 *  User ID that should be attached to the crash report
 */
@property (nonatomic, copy) NSString *userID;

@end
