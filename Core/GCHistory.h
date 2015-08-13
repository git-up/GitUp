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
#import "GCCommit.h"
#import "GCTag.h"
#import "GCBranch.h"

typedef NS_ENUM(NSUInteger, GCHistorySorting) {
  kGCHistorySorting_None = 0,
  kGCHistorySorting_ReverseChronological
};

@class GCSearchIndex, GCSnapshot;

@interface GCHistoryCommit : GCCommit
@property(nonatomic, readonly) NSUInteger autoIncrementID;  // Uniquely increasing ID for each GCHistoryCommit instantiated for a GCHistory (can be used for LUTs)
@property(nonatomic, readonly) NSArray* parents;  // Sorting is defined by hierarchy
@property(nonatomic, readonly) NSArray* children;  // Sorting is arbitrary and not guaranteed to be stable
@property(nonatomic, readonly) NSArray* localBranches;
@property(nonatomic, readonly) NSArray* remoteBranches;
@property(nonatomic, readonly) NSArray* tags;
@property(nonatomic, readonly, getter=isRoot) BOOL root;
@property(nonatomic, readonly, getter=isLeaf) BOOL leaf;
@property(nonatomic, readonly) BOOL hasReferences;
@end

@interface GCHistoryTag : GCTag
@property(nonatomic, readonly) GCHistoryCommit* commit;  // Cached at time of last history update and DOES NOT automatically update (use -lookupCommitForTag:annotation:error: instead)
@property(nonatomic, readonly) GCTagAnnotation* annotation;  // Cached at time of last history update and DOES NOT automatically update (use -lookupCommitForTag:annotation:error: instead)
@end

@interface GCHistoryLocalBranch : GCLocalBranch
@property(nonatomic, readonly) GCHistoryCommit* tipCommit;  // Cached at time of last history update and DOES NOT automatically update (use -lookupTipCommitForBranch:error: instead)
@property(nonatomic, readonly) GCBranch* upstream;  // Cached at time of last history update and DOES NOT automatically update (use -lookupUpstreamForLocalBranch:error: instead) - Will be a GCHistoryLocalBranch or GCHistoryRemoteBranch
@end

@interface GCHistoryRemoteBranch : GCRemoteBranch
@property(nonatomic, readonly) GCHistoryCommit* tipCommit;  // Cached at time of last history update and DOES NOT automatically update (use -lookupTipCommitForBranch:error: instead)
@end

@interface GCHistory : NSObject
@property(nonatomic, readonly) GCRepository* repository;  // NOT RETAINED
@property(nonatomic, readonly) GCHistorySorting sorting;
@property(nonatomic, readonly, getter=isEmpty) BOOL empty;  // Convenience method
@property(nonatomic, readonly) NSArray* allCommits;
@property(nonatomic, readonly) NSArray* rootCommits;
@property(nonatomic, readonly) NSArray* leafCommits;
@property(nonatomic, readonly) GCHistoryCommit* HEADCommit;  // nil if HEAD is unborn
@property(nonatomic, readonly) GCHistoryLocalBranch* HEADBranch;  // nil if HEAD is detached
@property(nonatomic, readonly, getter=isHEADDetached) BOOL HEADDetached;  // Convenience method
@property(nonatomic, readonly) NSArray* tags;  // Always sorted alphabetically
@property(nonatomic, readonly) NSArray* localBranches;  // Always sorted alphabetically
@property(nonatomic, readonly) NSArray* remoteBranches;  // Always sorted alphabetically
@property(nonatomic, readonly) NSUInteger nextAutoIncrementID;  // See @autoIncrementID on GCHistoryCommit
- (GCHistoryCommit*)historyCommitWithSHA1:(NSString*)sha1;
- (GCHistoryCommit*)historyCommitForCommit:(GCCommit*)commit;
- (GCHistoryLocalBranch*)historyLocalBranchForLocalBranch:(GCLocalBranch*)branch;
- (GCHistoryLocalBranch*)historyLocalBranchWithName:(NSString*)name;
- (GCHistoryRemoteBranch*)historyRemoteBranchForRemoteBranch:(GCRemoteBranch*)branch;
- (GCHistoryRemoteBranch*)historyRemoteBranchWithName:(NSString*)name;

- (NSUInteger)countAncestorCommitsFromCommit:(GCHistoryCommit*)fromCommit toCommit:(GCHistoryCommit*)toCommit;  // Returns NSNotFound if "toCommit" is not an ancestor of "fromCommit"
@end

@interface GCHistoryWalker : NSObject
- (BOOL)iterateWithCommitBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block;  // Returns NO if over or if stopped
@end

@interface GCHistory (GCHistoryWalker)
- (void)walkAncestorsOfCommits:(NSArray*)commits usingBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block;  // Commits are walked so that parents are guaranteed not to be called before all their children have been called (however the order between siblings is undefined)
- (void)walkDescendantsOfCommits:(NSArray*)commits usingBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block;  // Commits are walked so that children are guaranteed not to be called before all their parents have been called (however the order between siblings is undefined)

- (void)walkAllCommitsFromLeavesUsingBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block;  // Convenience wrapper for walking all ancestors from the history leaves
- (void)walkAllCommitsFromRootsUsingBlock:(void (^)(GCHistoryCommit* commit, BOOL* stop))block;  // Convenience wrapper for walking all descendants from the history roots

- (GCHistoryWalker*)walkerForAncestorsOfCommits:(NSArray*)commits;  // Low-level API - DO NOT update the history while iterating the walker
- (GCHistoryWalker*)walkerForDescendantsOfCommits:(NSArray*)commits;  // Low-level API - DO NOT update the history while iterating the walker
@end

@interface GCRepository (GCHistory)
- (GCHistory*)loadHistoryUsingSorting:(GCHistorySorting)sorting error:(NSError**)error;  // git log {--all}
- (BOOL)reloadHistory:(GCHistory*)history referencesDidChange:(BOOL*)referencesDidChange addedCommits:(NSArray**)addedCommits removedCommits:(NSArray**)removedCommits error:(NSError**)error;

- (GCHistory*)loadHistoryFromSnapshot:(GCSnapshot*)snapshot usingSorting:(GCHistorySorting)sorting error:(NSError**)error;

- (NSArray*)lookupCommitsForFile:(NSString*)path followRenames:(BOOL)follow error:(NSError**)error;  // git log {--follow} -p {file}
@end
