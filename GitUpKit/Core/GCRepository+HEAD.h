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

#import "GCRepository.h"

typedef NS_OPTIONS(NSUInteger, GCCheckoutOptions) {
  kGCCheckoutOption_Force = (1 << 0),
  kGCCheckoutOption_UpdateSubmodulesRecursively = (1 << 1)
};

@interface GCRepository (HEAD)
@property(nonatomic, readonly, getter=isHEADUnborn) BOOL HEADUnborn;

- (GCReference*)lookupHEADReference:(NSError**)error;  // Returns the "raw" reference for HEAD
- (GCCommit*)lookupHEAD:(GCLocalBranch**)currentBranch error:(NSError**)error;  // "currentBranch" is optional and will be set to nil if the HEAD is detached
- (BOOL)lookupHEADCurrentCommit:(GCCommit**)commit branch:(GCLocalBranch**)branch error:(NSError**)error;  // "commit" is optional and will be set to nil if HEAD is unborn and "branch" is optional and will be set to nil if HEAD is unborn or detached

- (BOOL)setHEADToReference:(GCReference*)reference error:(NSError**)error;  // git update-ref --no-deref HEAD {branch}
- (BOOL)setDetachedHEADToCommit:(GCCommit*)commit error:(NSError**)error;  // git update-ref HEAD {commit}

- (BOOL)moveHEADToCommit:(GCCommit*)commit reflogMessage:(NSString*)message error:(NSError**)error;  // git reset --soft {commit} (but with custom reflog message)

- (BOOL)checkoutCommit:(GCCommit*)commit options:(GCCheckoutOptions)options error:(NSError**)error;  // git checkout {commit}
- (BOOL)checkoutLocalBranch:(GCLocalBranch*)branch options:(GCCheckoutOptions)options error:(NSError**)error;  // git checkout {branch}
- (BOOL)checkoutTreeForCommit:(GCCommit*)commit  // Pass nil for HEAD
                 withBaseline:(GCCommit*)baseline  // Pass nil for HEAD
                      options:(GCCheckoutOptions)options
                        error:(NSError**)error;
- (BOOL)checkoutIndex:(GCIndex*)index withOptions:(GCCheckoutOptions)options error:(NSError**)error;  // This will checkout conflicts

- (BOOL)checkoutFileToWorkingDirectory:(NSString*)path fromCommit:(GCCommit*)commit skipIndex:(BOOL)skipIndex error:(NSError**)error;  // git checkout {commit} {file}

- (GCCommit*)createCommitFromHEADWithMessage:(NSString*)message error:(NSError**)error;  // git commit --allow-empty -m {message}
- (GCCommit*)createCommitFromHEADAndOtherParent:(GCCommit*)parent withMessage:(NSString*)message error:(NSError**)error;  // git commit --allow-empty -m {message}
- (GCCommit*)createCommitByAmendingHEADWithMessage:(NSString*)message error:(NSError**)error;  // git commit --amend -m {message}
@end
