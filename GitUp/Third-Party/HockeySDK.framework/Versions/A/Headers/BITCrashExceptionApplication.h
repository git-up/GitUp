#import <Cocoa/Cocoa.h>

/**
 * `NSApplication` subclass to catch additional exceptions
 *
 * On OS X runtime not all uncaught exceptions do end in an custom `NSUncaughtExceptionHandler`.
 * In addition "sometimes" exceptions don't even cause the app to crash, depending on where and
 * when they happen.
 *
 * Here are the known scenarios:
 *
 *   1. Custom `NSUncaughtExceptionHandler` don't start working until after `NSApplication` has finished
 *      calling all of its delegate methods!
 *
 *      Example:
 *        - (void)applicationDidFinishLaunching:(NSNotification *)note {
 *          ...
 *          [NSException raise:@"ExceptionAtStartup" format:@"This will not be recognized!"];
 *          ...
 *        }
 *
 *
 *   2. The default `NSUncaughtExceptionHandler` in `NSApplication` only logs exceptions to the console and
 *      ends their processing. Resulting in exceptions that occur in the `NSApplication` "scope" not
 *      occurring in a registered custom `NSUncaughtExceptionHandler`.
 *
 *      Example:
 *        - (void)applicationDidFinishLaunching:(NSNotification *)note {
 *          ...
 *           [self performSelector:@selector(delayedException) withObject:nil afterDelay:5];
 *          ...
 *        }
 *
 *        - (void)delayedException {
 *          NSArray *array = [NSArray array];
 *          [array objectAtIndex:23];
 *        }
 *
 *   3. Any exceptions occurring in IBAction or other GUI does not even reach the NSApplication default
 *      UncaughtExceptionHandler.
 *
 *      Example:
 *        - (IBAction)doExceptionCrash:(id)sender {
 *          NSArray *array = [NSArray array];
 *          [array objectAtIndex:23];
 *        }
 *
 *
 * Solution A:
 *
 *   Implement `NSExceptionHandler` and set the `ExceptionHandlingMask` to `NSLogAndHandleEveryExceptionMask`
 *
 *   Benefits:
 *
 *     1. Solves all of the above scenarios
 *
 *     2. Clean solution using a standard Cocoa System specifically meant for this purpose.
 *
 *     3. Safe. Doesn't use private API.
 *
 *   Problems:
 *
 *     1. To catch all exceptions the `NSExceptionHandlers` mask has to include `NSLogOtherExceptionMask` and
 *        `NSHandleOtherExceptionMask`. But this will result in @catch blocks to be called after the exception
 *        handler processed the exception and likely lets the app crash and create a crash report.
 *        This makes the @catch block basically not working at all.
 *
 *     2. If anywhere in the app a custom `NSUncaughtExceptionHandler` will be registered, e.g. in a closed source
 *        library the develop has to use, the complete mechanism will stop working
 *
 *     3. Not clear if this solves all scenarios there can be.
 *
 *     4. Requires to adjust PLCrashReporter not to register its `NSUncaughtExceptionHandler` which is not a good idea,
 *        since it would require the `NSExceptionHandler` would catch *all* exceptions and that would cause
 *        PLCrashReporter to stop all running threads every time an exception occurs even if will be handled right
 *        away, e.g. by a system framework.
 *
 *
 * Solution B:
 *
 *   Overwrite and extend specific methods of `NSApplication`. Can be implemented via subclassing NSApplication or
 *   by using a category.
 *
 *   Benefits:
 *
 *     1. Solves scenarios 2 (by overwriting `reportException:`) and 3 (by overwriting `sendEvent:`)
 *
 *     2. Subclassing approach isn't enforcing the mechanism onto apps and let developers opt-in.
 *        (Category approach would enforce it and rather be a problem of this soltuion.)
 *
 *     3. Safe. Doesn't use private API.
 *
 *  Problems:
 *
 *     1. Does not automatically solve scenario 1. Developer would have to put all that code into @try @catch blocks
 *
 *     2. Not a clean implementation, rather feels like a workaround.
 *
 *     3. Not clear if this solves all scenarios there can be.
 *
 *
 * Chosen Solution: B via subclassing
 *
 *   Reasons:
 *
 *     1. The Problems 1. and 2. of Solution A are too drastic and aren't acceptable for every developer using this SDK
 *        Especially Problem 1 is a big No Go for lots of developers.
 *
 *     2. Solution B can be used optionally, can be adopted easily into developers own `NSApplication` subclasses and
 *        by implementing it in a subclass instead of a category isn't enforced even though it requires additional
 *        steps for setup.
 *
 *     3. The not covered Scenario 1. can be achieved by the developer by enclosing most of the code within
 *        NSApplication startup delegates in @try @catch blocks or moving as much code as possible out of these
 *        methods and deferring their execution, e.g. using background threads. Not ideal though.
 *
 *
 * References:
 *   https://developer.apple.com/library/mac/documentation/cocoa/Conceptual/Exceptions/Tasks/ControllingAppResponse.html#//apple_ref/doc/uid/20000473-BBCHGJIJ
 *   http://stackoverflow.com/a/4199717/474794
 *   http://stackoverflow.com/a/3419073/474794
 *   http://macdevcenter.com/pub/a/mac/2007/07/31/understanding-exceptions-and-handlers-in-cocoa.html
 *
 */
@interface BITCrashExceptionApplication : NSApplication

@end
