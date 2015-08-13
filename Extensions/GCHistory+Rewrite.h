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

#import "GCCore.h"

@interface GCHistory (Rewrite)
- (BOOL)isCommitOnAnyLocalBranch:(GCHistoryCommit*)commit;

- (GCReferenceTransform*)revertCommit:(GCHistoryCommit*)commit
                        againstBranch:(GCHistoryLocalBranch*)branch
                          withMessage:(NSString*)message
                      conflictHandler:(GCConflictHandler)handler
                            newCommit:(GCCommit**)newCommit
                                error:(NSError**)error;
- (GCReferenceTransform*)cherryPickCommit:(GCHistoryCommit*)commit
                            againstBranch:(GCHistoryLocalBranch*)branch
                              withMessage:(NSString*)message
                          conflictHandler:(GCConflictHandler)handler
                                newCommit:(GCCommit**)newCommit
                                    error:(NSError**)error;

- (GCReferenceTransform*)fastForwardBranch:(GCHistoryLocalBranch*)branch
                                  toCommit:(GCHistoryCommit*)commit
                                     error:(NSError**)error;
- (GCReferenceTransform*)mergeCommit:(GCHistoryCommit*)commit
                          intoBranch:(GCHistoryLocalBranch*)branch
                  withAncestorCommit:(GCHistoryCommit*)ancestorCommit
                             message:(NSString*)message
                     conflictHandler:(GCConflictHandler)handler
                           newCommit:(GCCommit**)newCommit
                               error:(NSError**)error;
- (GCReferenceTransform*)rebaseBranch:(GCHistoryLocalBranch*)branch
                           fromCommit:(GCHistoryCommit*)fromCommit
                           ontoCommit:(GCHistoryCommit*)commit
                      conflictHandler:(GCConflictHandler)handler
                         newTipCommit:(GCCommit**)newTipCommit
                                error:(NSError**)error;

- (GCReferenceTransform*)rewriteCommit:(GCHistoryCommit*)commit
                     withUpdatedCommit:(GCCommit*)updatedCommit
                             copyTrees:(BOOL)copyTrees
                       conflictHandler:(GCConflictHandler)handler
                                 error:(NSError**)error;
- (GCReferenceTransform*)deleteCommit:(GCHistoryCommit*)commit
                  withConflictHandler:(GCConflictHandler)handler
                                error:(NSError**)error;
- (GCReferenceTransform*)fixupCommit:(GCHistoryCommit*)commit
                           newCommit:(GCCommit**)newCommit
                               error:(NSError**)error;
- (GCReferenceTransform*)squashCommit:(GCHistoryCommit*)commit
                          withMessage:(NSString*)message
                            newCommit:(GCCommit**)newCommit
                                error:(NSError**)error;
- (GCReferenceTransform*)swapCommitWithItsParent:(GCHistoryCommit*)commit
                                 conflictHandler:(GCConflictHandler)handler
                                  newChildCommit:(GCCommit**)newChildCommit
                                 newParentCommit:(GCCommit**)newParentCommit
                                           error:(NSError**)error;
@end
