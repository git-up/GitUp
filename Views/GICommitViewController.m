//  Copyright (C) 2015 Pierre-Olivier Latour <info@pol-online.net>
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

#import "GICommitViewController.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

@implementation GICommitViewController {
  NSString* _headCommitMessage;
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
  NSString* user = email && name ? [NSString stringWithFormat:@"%@ <%@>", name, email] : (name ? name : (email ? email :  NSLocalizedString(@"N/A", nil)));
  CGFloat fontSize = _infoTextField.font.pointSize;
  NSMutableAttributedString* string = [[NSMutableAttributedString alloc] init];
  [string beginEditing];
  if (_showsBranchInfo) {
    [string appendString:NSLocalizedString(@"Committing", nil) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:fontSize]}];
    switch (self.repository.state) {
      
      case kGCRepositoryState_Merge:
        [string appendString:NSLocalizedString(@" merge", nil) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
        break;
      
      case kGCRepositoryState_Revert:
        [string appendString:NSLocalizedString(@" revert", nil) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
        break;
      
      case kGCRepositoryState_CherryPick:
        [string appendString:NSLocalizedString(@" cherry-pick", nil) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
        break;
      
      case kGCRepositoryState_Rebase:
      case kGCRepositoryState_RebaseInteractive:
      case kGCRepositoryState_RebaseMerge:
        [string appendString:NSLocalizedString(@" rebase", nil) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
        break;
      
      default:
        break;
      
    }
    [string appendString:NSLocalizedString(@" as ", nil) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:fontSize]}];
    [string appendString:user withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
    if (branch) {
      [string appendString:NSLocalizedString(@" on branch ", nil) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:fontSize]}];
      [string appendString:branch.name withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
    } else {
      [string appendString:NSLocalizedString(@" on ", nil) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:fontSize]}];
      [string appendString:NSLocalizedString(@"detached HEAD", nil) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
    }
  } else {
    [string appendString:NSLocalizedString(@"Committing as ", nil) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:fontSize]}];
    [string appendString:user withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]}];
  }
  [string setAlignment:NSCenterTextAlignment range:NSMakeRange(0, string.length)];
  [string endEditing];
  _infoTextField.attributedStringValue = string;
  
  _headCommitMessage = headCommit.message;
  if (!headCommit || self.repository.state) {  // Don't allow amending if there's no HEAD or repository is not in default state
    self.amendButton.enabled = NO;
    self.amendButton.state = NSOffState;
  } else {
    self.amendButton.enabled = YES;
  }
}

// TODO: Live update these fields
- (void)viewWillShow {
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
    [_messageTextView.undoManager removeAllActions];
    [_messageTextView selectAll:nil];
  }
  
  [self _updateInterface];
}

- (void)viewDidHide {
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
  
  _amendButton.state = NSOffState;
  
  [_delegate commitViewController:self didCreateCommit:commit];
}

- (IBAction)toggleAmend:(id)sender {
  if (_amendButton.state && (_messageTextView.string.length == 0)) {
    _messageTextView.string = _headCommitMessage;
    [_messageTextView.undoManager removeAllActions];
    [_messageTextView selectAll:nil];
  }
}

@end

@implementation GICommitViewController (Extensions)

- (void)createCommitFromHEADWithMessage:(NSString*)message {
  NSError* error;
  
  if (![self.repository runHookWithName:@"pre-commit" arguments:nil standardInput:nil error:&error]) {
    [self presentError:error];
    return;
  }
  
  NSString* hook = [self.repository pathForHookWithName:@"commit-msg"];
  if (hook) {
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    if (![message writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
      [self presentError:error];
      return;
    }
    if (![self.repository runHookWithName:@"commit-msg" arguments:@[path] standardInput:nil error:&error]) {
      [self presentError:error];
      return;
    }
    message = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!message) {
      [self presentError:error];
      return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
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
