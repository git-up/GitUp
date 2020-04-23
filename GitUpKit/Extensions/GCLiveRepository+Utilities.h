//
//  GCLiveRepository+Utilities.h
//  GitUpKit (OSX)
//
//  Created by Lucas Derraugh on 8/2/19.
//

#import <GitUpKit/GitUpKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GCLiveRepository (Utilities)

/// Attempt to checkout branch matching commit or fallback to commit. Window is used to present modal dialog.
- (void)smartCheckoutCommit:(GCHistoryCommit*)commit window:(NSWindow*)window;

/// Returns target for smart checkout
- (id)smartCheckoutTarget:(GCHistoryCommit*)commit;

/// Checkout remote branch and ask user to create local branch if none exists. Window is used to present modal dialog.
- (void)checkoutRemoteBranch:(GCHistoryRemoteBranch*)remoteBranch window:(NSWindow*)window;

@end

NS_ASSUME_NONNULL_END
