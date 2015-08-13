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

#import "GCPrivate.h"

@implementation GCRepository (Reset)

- (BOOL)_resetToCommit:(git_commit*)commit mode:(GCResetMode)mode error:(NSError**)error {
  git_checkout_options options = GIT_CHECKOUT_OPTIONS_INIT;
  git_reset_t resetMode;
  switch (mode) {
    case kGCResetMode_Soft: resetMode = GIT_RESET_SOFT; break;
    case kGCResetMode_Mixed: resetMode = GIT_RESET_MIXED; break;
    case kGCResetMode_Hard: resetMode = GIT_RESET_HARD; break;
  }
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_reset, self.private, (git_object*)commit, resetMode, &options);  // This calls git_repository_state_cleanup() if MIXED or HARD
  return YES;
}

- (BOOL)resetToHEAD:(GCResetMode)mode error:(NSError**)error {
  git_commit* commit = [self loadHEADCommit:NULL error:error];
  return commit ? [self _resetToCommit:commit mode:mode error:error] : NO;
}

- (BOOL)resetToTag:(GCTag*)tag mode:(GCResetMode)mode error:(NSError**)error {
  GCCommit* commit = [self lookupCommitForTag:tag annotation:NULL error:error];
  return commit ? [self _resetToCommit:commit.private mode:mode error:error] : NO;
}

- (BOOL)resetToCommit:(GCCommit*)commit mode:(GCResetMode)mode error:(NSError**)error {
  return [self _resetToCommit:commit.private mode:mode error:error];
}

@end
