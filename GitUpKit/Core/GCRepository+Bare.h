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

typedef NS_ENUM(NSUInteger, GCMergeAnalysisResult) {
  kGCMergeAnalysisResult_Unknown = 0,
  kGCMergeAnalysisResult_UpToDate,
  kGCMergeAnalysisResult_FastForward,
  kGCMergeAnalysisResult_Normal
};

typedef NS_ENUM(NSUInteger, GCCommitRelation) {
  kGCCommitRelation_Unknown = 0,
  kGCCommitRelation_Identical,
  kGCCommitRelation_Ancestor,
  kGCCommitRelation_Descendant,
  kGCCommitRelation_Cousin,
  kGCCommitRelation_Unrelated
};

@class GCCommit, GCIndex;

typedef GCCommit* (^GCConflictHandler)(GCIndex* index, GCCommit* ourCommit, GCCommit* theirCommit, NSArray* parentCommits, NSString* message, NSError** outError);

@interface GCRepository (Bare)
- (GCCommit*)squashCommitOntoParent:(GCCommit*)squashCommit withUpdatedMessage:(NSString*)message error:(NSError**)error;

- (GCCommit*)cherryPickCommit:(GCCommit*)pickCommit
                againstCommit:(GCCommit*)againstCommit
           withAncestorCommit:(GCCommit*)ancestorCommit  // Typically a parent of "pickCommit" (the first one to use the main line)
                      message:(NSString*)message
              conflictHandler:(GCConflictHandler)handler  // May be NULL
                        error:(NSError**)error;

- (GCCommit*)revertCommit:(GCCommit*)revertCommit
            againstCommit:(GCCommit*)againstCommit
       withAncestorCommit:(GCCommit*)ancestorCommit  // Typically a parent of "revertCommit" (the first one to use the main line)
                  message:(NSString*)message
          conflictHandler:(GCConflictHandler)handler  // May be NULL
                    error:(NSError**)error;

- (GCCommitRelation)findRelationOfCommit:(GCCommit*)ofCommit relativeToCommit:(GCCommit*)toCommit error:(NSError**)error;

- (GCCommit*)findMergeBaseForCommits:(NSArray*)commits error:(NSError**)error;
- (GCMergeAnalysisResult)analyzeMergingCommit:(GCCommit*)mergeCommit intoCommit:(GCCommit*)intoCommit ancestorCommit:(GCCommit**)ancestorCommit error:(NSError**)error;
- (GCCommit*)mergeCommit:(GCCommit*)mergeCommit
              intoCommit:(GCCommit*)intoCommit
      withAncestorCommit:(GCCommit*)ancestorCommit  // Typically a parent of both "mergeCommit" and "intoCommit"
                 message:(NSString*)message
         conflictHandler:(GCConflictHandler)handler  // May be NULL
                   error:(NSError**)error;

- (GCCommit*)createCommitFromIndex:(GCIndex*)index
                       withParents:(NSArray*)parents
                           message:(NSString*)message
                             error:(NSError**)error;

- (GCCommit*)copyCommit:(GCCommit*)copyCommit
     withUpdatedMessage:(NSString*)message
         updatedParents:(NSArray*)parents
   updatedTreeFromIndex:(GCIndex*)index
        updateCommitter:(BOOL)updateCommitter
                  error:(NSError**)error;

- (GCCommit*)replayCommit:(GCCommit*)replayCommit
               ontoCommit:(GCCommit*)ontoCommit
       withAncestorCommit:(GCCommit*)ancestorCommit  // Typically a parent of "replayCommit" (the first one to use the main line)
           updatedMessage:(NSString*)message
           updatedParents:(NSArray*)parents
          updateCommitter:(BOOL)updateCommitter
            skipIdentical:(BOOL)skipIdentical
          conflictHandler:(GCConflictHandler)handler
                    error:(NSError**)error;

- (GCCommit*)replayMainLineParentsFromCommit:(GCCommit*)fromCommit
                                  uptoCommit:(GCCommit*)uptoCommit  // Must be an ancestor of "fromCommit"
                                  ontoCommit:(GCCommit*)ontoCommit
                              preserveMerges:(BOOL)preserveMerges
                             updateCommitter:(BOOL)updateCommitter
                               skipIdentical:(BOOL)skipIdentical
                             conflictHandler:(GCConflictHandler)handler
                                       error:(NSError**)error;
@end
