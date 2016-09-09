#import <Foundation/Foundation.h>

#import "BITHockeyBaseManager.h"


// Notification message which tells that loading messages finished
#define BITHockeyFeedbackMessagesLoadingStarted @"BITHockeyFeedbackMessagesLoadingStarted"

// Notification message which tells that loading messages finished
#define BITHockeyFeedbackMessagesLoadingFinished @"BITHockeyFeedbackMessagesLoadingFinished"


/**
 *  Defines behavior of the user data field
 */
typedef NS_ENUM(NSInteger, BITFeedbackUserDataElement) {
  /**
   *  don't ask for this user data element at all
   */
  BITFeedbackUserDataElementDontShow = 0,
  /**
   *  the user may provide it, but does not have to
   */
  BITFeedbackUserDataElementOptional = 1,
  /**
   *  the user has to provide this to continue
   */
  BITFeedbackUserDataElementRequired = 2
};


@class BITFeedbackMessage;
@class BITFeedbackWindowController;


/**
 The feedback module.
 
 This is the HockeySDK module for letting your users to communicate directly with you via
 the app and an integrated user interface. It provides to have a single threaded
 discussion with a user running your app.

 The user interface provides a window than can be presented  using
 `[BITFeedbackManager showFeedbackWindow]`.
 This window integrates all features to load new messages, write new messages, view message
 and ask the user for additional (optional) data like name and email.
 
 If the user provides the email address, all responses from the server will also be send
 to the user via email and the user is also able to respond directly via email too.
 
 It is also integrates actions to invoke the user interface to compose a new messages,
 reload the list content from the server and changing the users name or email if these
 are allowed to be set.
 
 If new messages are written while the device is offline, the SDK automatically retries to
 send them once the app starts again or gets active again, or if the notification
 `BITHockeyNetworkDidBecomeReachableNotification` is fired.
 
 New message are automatically loaded on startup, when the app becomes active again 
 or when the notification `BITHockeyNetworkDidBecomeReachableNotification` is fired and
 the last server communication task was more than 5 minutes ago. This
 only happens if the user ever did initiate a conversation by writing the first
 feedback message.
 */

@interface BITFeedbackManager : BITHockeyBaseManager

///-----------------------------------------------------------------------------
/// @name General settings
///-----------------------------------------------------------------------------


/**
 Define if a name has to be provided by the user when providing feedback

 - `BITFeedbackUserDataElementDontShow`: Don't ask for this user data element at all
 - `BITFeedbackUserDataElementOptional`: The user may provide it, but does not have to
 - `BITFeedbackUserDataElementRequired`: The user has to provide this to continue

 The default value is `BITFeedbackUserDataElementOptional`.

 @warning If you provide a non nil value for the `BITFeedbackManager` class via
 `[BITHockeyManagerDelegate userNameForHockeyManager:componentManager:]` then this
 property will automatically be set to `BITFeedbackUserDataElementDontShow`

 @see requireUserEmail
 @see `[BITHockeyManagerDelegate userNameForHockeyManager:componentManager:]`
 */
@property (nonatomic, readwrite) BITFeedbackUserDataElement requireUserName;


/**
 Define if an email address has to be provided by the user when providing feedback
 
 If the user provides the email address, all responses from the server will also be send
 to the user via email and the user is also able to respond directly via email too.

 - `BITFeedbackUserDataElementDontShow`: Don't ask for this user data element at all
 - `BITFeedbackUserDataElementOptional`: The user may provide it, but does not have to
 - `BITFeedbackUserDataElementRequired`: The user has to provide this to continue
 
 The default value is `BITFeedbackUserDataElementOptional`.

 @warning If you provide a non nil value for the `BITFeedbackManager` class via
 `[BITHockeyManagerDelegate userEmailForHockeyManager:componentManager:]` then this
 property will automatically be set to `BITFeedbackUserDataElementDontShow`
 
 @see requireUserName
 @see `[BITHockeyManagerDelegate userEmailForHockeyManager:componentManager:]`
 */
@property (nonatomic, readwrite) BITFeedbackUserDataElement requireUserEmail;


/**
 Indicates if an Notification Center alert should be shown when new messages arrived
 
 The alert is only shown, if the newest message is not originated from the current user.
 This requires the users email address to be present! The optional userid property
 cannot be used, because users could also answer via email and then this information
 is not available.
 
 Default is `YES`
 @see requireUserEmail
 @see `[BITHockeyManagerDelegate userEmailForHockeyManager:componentManager:]`
 */
@property (nonatomic, readwrite) BOOL showAlertOnIncomingMessages;


///-----------------------------------------------------------------------------
/// @name User Interface
///-----------------------------------------------------------------------------


/**
 Present the modal feedback list user interface.
 */
- (void)showFeedbackWindow;


@end
