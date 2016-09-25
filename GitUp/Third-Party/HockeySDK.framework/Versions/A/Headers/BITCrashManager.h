#import <Foundation/Foundation.h>

#import "BITHockeyBaseManager.h"

// flags if the crashreporter is activated at all
// set this as bool in user defaults e.g. in the settings, if you want to let the user be able to deactivate it
#define kHockeySDKCrashReportActivated @"HockeySDKCrashReportActivated"

// flags if the crashreporter should automatically send crashes without asking the user again
// set this as bool in user defaults e.g. in the settings, if you want to let the user be able to set this on or off
// or set it on runtime using the `autoSubmitCrashReport property`
#define kHockeySDKAutomaticallySendCrashReports @"HockeySDKAutomaticallySendCrashReports"

@protocol BITCrashManagerDelegate;

@class BITCrashDetails;
@class BITCrashMetaData;
@class BITCrashReportUI;


/**
 * Custom block that handles the alert that prompts the user whether he wants to send crash reports
 *
 * @param crashReportText The textual representation of the crash report
 * @param applicationLog The application log that will be attached to the crash report
 */
typedef void(^BITCustomCrashReportUIHandler)(NSString *crashReportText, NSString *applicationLog);


/**
 * Prototype of a callback function used to execute additional user code. Called upon completion of crash
 * handling, after the crash report has been written to disk.
 *
 * @param context The API client's supplied context value.
 *
 * @see `BITCrashManagerCallbacks`
 * @see `[BITCrashManager setCrashCallbacks:]`
 */
typedef void (*BITCrashManagerPostCrashSignalCallback)(void *context);

/**
 * This structure contains callbacks supported by `BITCrashManager` to allow the host application to perform
 * additional tasks prior to program termination after a crash has occured.
 *
 * @see `BITCrashManagerPostCrashSignalCallback`
 * @see `[BITCrashManager setCrashCallbacks:]`
 */
typedef struct BITCrashManagerCallbacks {
  /** An arbitrary user-supplied context value. This value may be NULL. */
  void *context;
  
  /**
   * The callback used to report caught signal information.
   */
  BITCrashManagerPostCrashSignalCallback handleSignal;
} BITCrashManagerCallbacks;

/**
 * Crash Manager alert user input
 */
typedef NS_ENUM(NSUInteger, BITCrashManagerUserInput) {
  /**
   *  User chose not to send the crash report
   */
  BITCrashManagerUserInputDontSend = 0,
  /**
   *  User wants the crash report to be sent
   */
  BITCrashManagerUserInputSend = 1,
  /**
   *  User chose to always send crash reports
   */
  BITCrashManagerUserInputAlwaysSend = 2
  
};


/**
 * The crash reporting module.
 *
 * This is the HockeySDK module for handling crash reports, including when distributed via the App Store.
 * As a foundation it is using the open source, reliable and async-safe crash reporting framework
 * [PLCrashReporter](https://www.plcrashreporter.org).
 *
 * This module works as a wrapper around the underlying crash reporting framework and provides functionality to
 * detect new crashes, queues them if networking is not available, present a user interface to approve sending
 * the reports to the HockeyApp servers and more.
 *
 * It also provides options to add additional meta information to each crash report, like `userName`, `userEmail`,
 * additional textual log information via `BITCrashanagerDelegate` protocol and a way to detect startup
 * crashes so you can adjust your startup process to get these crash reports too and delay your app initialization.
 *
 * Crashes are send the next time the app starts. If `autoSubmitCrashReport` is enabled, crashes will be send
 * without any user interaction, otherwise an alert will appear allowing the users to decide whether they want
 * to send the report or not. This module is not sending the reports right when the crash happens
 * deliberately, because if is not safe to implement such a mechanism while being async-safe (any Objective-C code
 * is _NOT_ async-safe!) and not causing more danger like a deadlock of the device, than helping. We found that users
 * do start the app again because most don't know what happened, and you will get by far most of the reports.
 *
 * Sending the reports on startup is done asynchronously (non-blocking) if the crash happened outside of the
 * time defined in `maxTimeIntervalOfCrashForReturnMainApplicationDelay`.
 *
 * More background information on this topic can be found in the following blog post by Landon Fuller, the
 * developer of [PLCrashReporter](https://www.plcrashreporter.org), about writing reliable and
 * safe crash reporting: [Reliable Crash Reporting](http://goo.gl/WvTBR)
 *
 * @warning If you start the app with the Xcode debugger attached, detecting crashes will _NOT_ be enabled!
 */
@interface BITCrashManager : BITHockeyBaseManager


///-----------------------------------------------------------------------------
/// @name Configuration
///-----------------------------------------------------------------------------

/**
 *  Defines if the build in crash report UI should ask for name and email
 *
 *  Default: _YES_
 */
@property (nonatomic, assign) BOOL askUserDetails;


/**
 *  Trap fatal signals via a Mach exception server. This is now used by default!
 *
 *  Default: _YES_
 *
 * @deprecated Mach Exception Handler is now enabled by default!
 */
@property (nonatomic, assign, getter=isMachExceptionHandlerEnabled) BOOL enableMachExceptionHandler __attribute__((deprecated("Mach Exceptions are now enabled by default. If you want to disable them, please use the new property disableMachExceptionHandler")));


/**
 *  Disable trap fatal signals via a Mach exception server.
 *
 *  By default the SDK is catching fatal signals via a Mach exception server.
 *  This option allows you to use in-process BSD Signals for catching crashes instead.
 *
 *  Default: _NO_
 *
 * @warning The Mach exception handler executes in-process, and will interfere with debuggers when
 *  they attempt to suspend all active threads (which will include the Mach exception handler).
 *  Mach-based handling should _NOT_ be used when a debugger is attached. The SDK will not
 *  enable catching exceptions if the app is started with the debugger running. If you attach
 *  the debugger during runtime, this may cause issues if it is not disabled!
 */
@property (nonatomic, assign, getter=isMachExceptionHandlerDisabled) BOOL disableMachExceptionHandler;


/**
 *  Submit crash reports without asking the user
 *
 *  _YES_: The crash report will be submitted without asking the user
 *  _NO_: The user will be asked if the crash report can be submitted (default)
 *
 *  Default: _NO_
 */
@property (nonatomic, assign, getter=isAutoSubmitCrashReport) BOOL autoSubmitCrashReport;

/**
 * Set the callbacks that will be executed prior to program termination after a crash has occurred
 *
 * PLCrashReporter provides support for executing an application specified function in the context
 * of the crash reporter's signal handler, after the crash report has been written to disk.
 *
 * Writing code intended for execution inside of a signal handler is exceptionally difficult, and is _NOT_ recommended!
 *
 * _Program Flow and Signal Handlers_
 *
 * When the signal handler is called the normal flow of the program is interrupted, and your program is an unknown state. Locks may be held, the heap may be corrupt (or in the process of being updated), and your signal handler may invoke a function that was being executed at the time of the signal. This may result in deadlocks, data corruption, and program termination.
 *
 * _Async-Safe Functions_
 *
 * A subset of functions are defined to be async-safe by the OS, and are safely callable from within a signal handler. If you do implement a custom post-crash handler, it must be async-safe. A table of POSIX-defined async-safe functions and additional information is available from the [CERT programming guide - SIG30-C](https://www.securecoding.cert.org/confluence/display/seccode/SIG30-C.+Call+only+asynchronous-safe+functions+within+signal+handlers).
 *
 * Most notably, the Objective-C runtime itself is not async-safe, and Objective-C may not be used within a signal handler.
 *
 * Documentation taken from PLCrashReporter: https://www.plcrashreporter.org/documentation/api/v1.2-rc2/async_safety.html
 *
 * @see BITCrashManagerPostCrashSignalCallback
 * @see BITCrashManagerCallbacks
 *
 * @param callbacks A pointer to an initialized PLCrashReporterCallback structure, see https://www.plcrashreporter.org/documentation/api/v1.2-rc2/struct_p_l_crash_reporter_callbacks.html
 */
- (void)setCrashCallbacks: (BITCrashManagerCallbacks *) callbacks;


///-----------------------------------------------------------------------------
/// @name Crash Meta Information
///-----------------------------------------------------------------------------

/**
 * Indicates if the app crash in the previous session
 *
 * Use this on startup, to check if the app starts the first time after it crashed
 * previously. You can use this also to disable specific events, like asking
 * the user to rate your app.
 *
 * @warning This property only has a correct value, once `[BITHockeyManager startManager]` was
 * invoked!
 */
@property (nonatomic, readonly) BOOL didCrashInLastSession;

/**
 Provides an interface to pass user input from a custom alert to a crash report
 
 @param userInput Defines the users action wether to send, always send, or not to send the crash report.
 @param userProvidedMetaData The content of this optional BITCrashMetaData instance will be attached to the crash report and allows to ask the user for e.g. additional comments or info.
 
 @return Returns YES if the input is a valid option and successfully triggered further processing of the crash report
 
 @see BITCrashManagerUserInput
 @see BITCrashMetaData
 */
- (BOOL)handleUserInput:(BITCrashManagerUserInput)userInput withUserProvidedMetaData:(BITCrashMetaData *)userProvidedMetaData;

/**
 Lets you set a custom block which handles showing a custom UI and asking the user
 whether he wants to send the crash report.
 
 This replaces the default alert the SDK would show!
 
 You can use this to present any kind of user interface which asks the user for additional information,
 e.g. what they did in the app before the app crashed.
 
 In addition to this you should always ask your users if they agree to send crash reports, send them
 always or not and return the result when calling `handleUserInput:withUserProvidedCrashDescription`.
 
 @param crashReportUIHandler A block that is responsible for loading, presenting and and dismissing your custom user interface which prompts the user if he wants to send crash reports. The block is also responsible for triggering further processing of the crash reports.
 
 @warning Block needs to call the `[BITCrashManager handleUserInput:withUserProvidedMetaData:]` method!
 
 @warning This needs to be set before calling `[BITHockeyManager startManager]`!
 */
- (void)setCrashReportUIHandler:(BITCustomCrashReportUIHandler)crashReportUIHandler;

/**
 * Provides details about the crash that occured in the last app session
 */
@property (nonatomic, readonly) BITCrashDetails *lastSessionCrashDetails;

/**
 * Provides the time between startup and crash in seconds
 *
 * Use this in together with `didCrashInLastSession` to detect if the app crashed very
 * early after startup. This can be used to delay app initialization until the crash
 * report has been sent to the server or if you want to do any other actions like
 * cleaning up some cache data etc.
 *
 * The `BITCrashManagerDelegate` protocol provides some delegates to inform if sending
 * a crash report was finished successfully, ended in error or was cancelled by the user.
 *
 * *Default*: _-1_
 * @see didCrashInLastSession
 * @see BITCrashManagerDelegate
 */
@property (nonatomic, readonly) NSTimeInterval timeintervalCrashInLastSessionOccured;


///-----------------------------------------------------------------------------
/// @name Helper
///-----------------------------------------------------------------------------

/**
 *  Detect if a debugger is attached to the app process
 *
 *  This is only invoked once on app startup and can not detect if the debugger is being
 *  attached during runtime!
 *
 *  @return BOOL if the debugger is attached on app startup
 */
- (BOOL)isDebuggerAttached;


/**
 * Lets the app crash for easy testing of the SDK
 *
 * The best way to use this is to trigger the crash with a button action.
 *
 * Make sure not to let the app crash in `applicationDidFinishLaunching` or any other
 * startup method! Since otherwise the app would crash before the SDK could process it.
 *
 * Note that our SDK provides support for handling crashes that happen early on startup.
 * Check the documentation for more information on how to use this.
 */
- (void)generateTestCrash;


@end
