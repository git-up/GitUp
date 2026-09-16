//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import <GitUpKit/GICommitViewController.h>

#import <GitUpKit/GIInterface.h>
#import "XLFacilityMacros.h"

@implementation GICommitViewController {
  NSString* _headCommitMessage;
  NSUInteger _prepareCommitMessageHookGeneration;
  BOOL _prepareCommitMessageHookRunning;
  NSError* _prepareCommitMessageHookError;
  NSString* _automaticallyPreparedCommitMessage;
}

#if DEBUG

+ (instancetype)allocWithZone:(struct _NSZone*)zone {
  XLOG_DEBUG_CHECK(self != [GICommitViewController class]);
  return [super allocWithZone:zone];
}

#endif

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithRepository:repository])) {
    _showsBranchInfo = YES;
  }
  return self;
}

- (void)_updateInterface {
  GCCommit* headCommit = nil;
  GCLocalBranch* branch = nil;
  [self.repository lookupHEADCurrentCommit:&headCommit branch:&branch error:NULL];  // Ignore errors

  NSString* name = [[self.repository readConfigOptionForVariable:@"user.name" error:NULL] value];
  NSString* email = [[self.repository readConfigOptionForVariable:@"user.email" error:NULL] value];
  NSString* user = email && name ? [NSString stringWithFormat:@"%@ <%@>", name, email] : (name ? name : (email ? email : NSLocalizedString(@"N/A", nil)));
  CGFloat fontSize = _infoTextField.font.pointSize;
  NSMutableAttributedString* string = [[NSMutableAttributedString alloc] init];
  [string beginEditing];
  if (_showsBranchInfo) {
    [string appendString:NSLocalizedString(@"Committing", nil) withAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:fontSize]}];
    switch (self.repository.state) {
      case kGCRepositoryState_Merge:
        [string appendString:NSLocalizedString(@" merge", nil) withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
        break;

      case kGCRepositoryState_Revert:
        [string appendString:NSLocalizedString(@" revert", nil) withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
        break;

      case kGCRepositoryState_CherryPick:
        [string appendString:NSLocalizedString(@" cherry-pick", nil) withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
        break;

      case kGCRepositoryState_Rebase:
      case kGCRepositoryState_RebaseInteractive:
      case kGCRepositoryState_RebaseMerge:
        [string appendString:NSLocalizedString(@" rebase", nil) withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
        break;

      default:
        break;
    }
    [string appendString:NSLocalizedString(@" as ", nil) withAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:fontSize]}];
    [string appendString:user withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
    if (branch) {
      [string appendString:NSLocalizedString(@" on branch ", nil) withAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:fontSize]}];
      [string appendString:branch.name withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
    } else {
      [string appendString:NSLocalizedString(@" on ", nil) withAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:fontSize]}];
      [string appendString:NSLocalizedString(@"detached HEAD", nil) withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
    }
  } else {
    [string appendString:NSLocalizedString(@"Committing as ", nil) withAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:fontSize]}];
    [string appendString:user withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:fontSize]}];
  }
  [string setAlignment:NSTextAlignmentCenter range:NSMakeRange(0, string.length)];
  [string endEditing];
  _infoTextField.attributedStringValue = string;

  _headCommitMessage = headCommit.message;
  if (!headCommit || self.repository.state) {  // Don't allow amending if there's no HEAD or repository is not in default state
    self.amendButton.enabled = NO;
    self.amendButton.state = NSControlStateValueOff;
  } else {
    self.amendButton.enabled = YES;
  }
}

- (NSArray*)_prepareCommitMessageHookArgumentsWithMessagePath:(NSString*)path amendCommitSHA1:(NSString*)sha1 {
  if (_amendButton.state) {
    return sha1 ? @[ path, @"commit", sha1 ] : @[ path, @"commit" ];
  }
  if (self.repository.state == kGCRepositoryState_Merge) {
    return @[ path, @"merge" ];
  }
  return @[ path ];
}

- (NSString*)_messageByInsertingPreparedMessage:(NSString*)preparedMessage beforeMessage:(NSString*)message {
  if (!preparedMessage.length || [preparedMessage isEqualToString:message]) {
    return message;
  }
  if (!message.length) {
    return preparedMessage;
  }
  if ([preparedMessage hasSuffix:@"\n"] || [message hasPrefix:@"\n"]) {
    return [preparedMessage stringByAppendingString:message];
  }
  return [preparedMessage stringByAppendingFormat:@"\n%@", message];
}

- (void)_applyPreparedCommitMessage:(NSString*)preparedMessage replacingInitialMessage:(NSString*)initialMessage {
  NSString* currentMessage = _messageTextView.string;
  NSString* message;
  BOOL replacesInitialMessage = [currentMessage isEqualToString:initialMessage];
  if (replacesInitialMessage) {
    message = preparedMessage;
  } else if (initialMessage.length && [currentMessage hasPrefix:initialMessage]) {
    NSString* userMessage = [currentMessage substringFromIndex:initialMessage.length];
    message = [self _messageByInsertingPreparedMessage:preparedMessage beforeMessage:userMessage];
  } else {
    message = [self _messageByInsertingPreparedMessage:preparedMessage beforeMessage:currentMessage];
  }
  _messageTextView.string = message;
  _automaticallyPreparedCommitMessage = replacesInitialMessage ? message : nil;
}

- (void)_cancelPrepareCommitMessageHook {
  ++_prepareCommitMessageHookGeneration;
  _prepareCommitMessageHookRunning = NO;
  _prepareCommitMessageHookError = nil;
  _automaticallyPreparedCommitMessage = nil;
}

- (void)_runPrepareCommitMessageHookWithInitialMessage:(NSString*)initialMessage {
  if (![self.repository pathForHookWithName:@"prepare-commit-msg"]) {
    return;
  }

  NSUInteger generation = ++_prepareCommitMessageHookGeneration;
  _prepareCommitMessageHookRunning = YES;
  _prepareCommitMessageHookError = nil;
  _automaticallyPreparedCommitMessage = nil;

  NSString* repositoryPath = self.repository.repositoryPath;
  NSString* messagePath = [repositoryPath stringByAppendingPathComponent:@"COMMIT_EDITMSG"];
  NSString* sha1 = nil;
  if (_amendButton.state) {
    GCCommit* headCommit = nil;
    [self.repository lookupHEADCurrentCommit:&headCommit branch:NULL error:NULL];
    sha1 = headCommit.SHA1;
  }
  NSArray* arguments = [self _prepareCommitMessageHookArgumentsWithMessagePath:messagePath amendCommitSHA1:sha1];

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError* error = nil;
    NSString* preparedMessage = nil;
    GCRepository* repository = [[GCRepository alloc] initWithExistingLocalRepository:repositoryPath error:&error];
    if (repository && [initialMessage writeToFile:messagePath atomically:YES encoding:NSUTF8StringEncoding error:&error] && [repository runHookWithName:@"prepare-commit-msg" arguments:arguments standardInput:nil error:&error]) {
      preparedMessage = [[NSString alloc] initWithContentsOfFile:messagePath encoding:NSUTF8StringEncoding error:&error];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      if (generation != _prepareCommitMessageHookGeneration) {
        return;
      }
      _prepareCommitMessageHookRunning = NO;
      _prepareCommitMessageHookError = error;
      if (preparedMessage) {
        [self _applyPreparedCommitMessage:preparedMessage replacingInitialMessage:initialMessage];
      } else if (error) {
        [self presentError:error];
      }
    });
  });
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.infoTextField.maximumNumberOfLines = 2;
}

// TODO: Live update these fields
- (void)viewWillAppear {
  [super viewWillAppear];

  if (_messageTextView.string.length == 0) {
    NSString* message = @"";

    if (self.repository.state == kGCRepositoryState_Merge) {
      NSError* error;
      NSString* mergeMessage = [NSString stringWithContentsOfFile:[self.repository.repositoryPath stringByAppendingPathComponent:@"MERGE_MSG"] encoding:NSUTF8StringEncoding error:&error];
      if (mergeMessage) {
        message = mergeMessage;
      } else {
        XLOG_ERROR(@"Failed reading MERGE_MSG from \"%@\":%@ ", self.repository.repositoryPath, error);
      }
    }

    _messageTextView.string = message;
    _automaticallyPreparedCommitMessage = nil;
    [_messageTextView.undoManager removeAllActions];
    [_messageTextView selectAll:nil];

    [self _runPrepareCommitMessageHookWithInitialMessage:message];
  }

  [self _updateInterface];
}

- (void)viewDidDisappear {
  [super viewDidDisappear];

  [self _cancelPrepareCommitMessageHook];
  _headCommitMessage = nil;
}

- (void)repositoryDidChange {
  if (self.viewVisible) {
    [self _updateInterface];
  }
}

- (void)didCreateCommit:(GCCommit*)commit {
  _messageTextView.string = @"";
  [_messageTextView.undoManager removeAllActions];

  _otherMessageTextView.string = @"";
  [_otherMessageTextView.undoManager removeAllActions];

  _amendButton.state = NSControlStateValueOff;
  _automaticallyPreparedCommitMessage = nil;

  [_delegate commitViewController:self didCreateCommit:commit];
}

- (IBAction)toggleAmend:(id)sender {
  BOOL shouldReplaceMessage = (_messageTextView.string.length == 0) || [_messageTextView.string isEqualToString:_automaticallyPreparedCommitMessage];
  if (_amendButton.state && shouldReplaceMessage) {
    _messageTextView.string = _headCommitMessage;
    [_messageTextView.undoManager removeAllActions];
    [_messageTextView selectAll:nil];
    [self _runPrepareCommitMessageHookWithInitialMessage:_headCommitMessage];
  } else {
    [self _cancelPrepareCommitMessageHook];
  }
}

@end

@implementation GICommitViewController (Extensions)

- (void)createCommitFromHEADWithMessage:(NSString*)message {
  NSError* error;

  if (_prepareCommitMessageHookRunning) {
    [self presentAlertWithType:kGIAlertType_Caution title:NSLocalizedString(@"The prepare-commit-msg hook is still running", nil) message:NSLocalizedString(@"Please wait for it to finish before committing.", nil)];
    return;
  }
  if (_prepareCommitMessageHookError) {
    [self presentError:_prepareCommitMessageHookError];
    return;
  }

  if (![self.repository runHookWithName:@"pre-commit" arguments:nil standardInput:nil error:&error]) {
    [self presentError:error];
    return;
  }

  NSString* commitMsgHookPath = [self.repository pathForHookWithName:@"commit-msg"];
  if (commitMsgHookPath) {
    NSString* path = [self.repository.repositoryPath stringByAppendingPathComponent:@"COMMIT_EDITMSG"];
    if (![message writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
      [self presentError:error];
      return;
    }
    if (![self.repository runHookWithName:@"commit-msg" arguments:@[ path ] standardInput:nil error:&error]) {
      [self presentError:error];
      return;
    }
    message = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!message) {
      [self presentError:error];
      return;
    }
  }

  GCCommit* newCommit;
  [self.repository setUndoActionName:NSLocalizedString(@"Commit", nil)];
  if (_amendButton.state) {
    XLOG_DEBUG_CHECK(self.repository.state != kGCRepositoryState_Merge);
    newCommit = [self.repository performHEADCommitAmendingWithMessage:message error:&error];
  } else {
    GCCommit* otherParent = nil;
    if (self.repository.state == kGCRepositoryState_Merge) {
      NSString* sha1 = [NSString stringWithContentsOfFile:[self.repository.repositoryPath stringByAppendingPathComponent:@"MERGE_HEAD"] encoding:NSASCIIStringEncoding error:&error];
      if (sha1 && (sha1.length != 41)) {
        error = GCNewError(kGCErrorCode_Generic, @"Invalid MERGE_HEAD file");
        sha1 = nil;
      }
      otherParent = sha1 ? [self.repository findCommitWithSHA1:[sha1 substringToIndex:40] error:&error] : nil;
      if (otherParent == nil) {
        [self presentError:error];
        return;
      }
    }

    newCommit = [self.repository performCommitCreationFromHEADAndOtherParent:otherParent withMessage:message error:&error];
  }

  if (newCommit) {
    if (![self.repository runHookWithName:@"post-commit" arguments:nil standardInput:nil error:&error]) {
      [self presentError:error];
    }
    [self didCreateCommit:newCommit];
  } else {
    [self presentError:error];
  }
}

@end
