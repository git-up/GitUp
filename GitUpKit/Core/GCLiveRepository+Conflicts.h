//
//  GCLiveRepository+Conflicts.h
//  GitUpKit (macOS)
//
//  Created by Felix Lapalme on 2024-04-13.
//

#import <GitUpKit/GitUpKit.h>

@protocol GCMergeConflictResolver <NSObject>
- (BOOL)resolveMergeConflictsWithOurCommit:(GCCommit*)ourCommit theirCommit:(GCCommit*)theirCommit;
@end

@interface GCLiveRepository (Conflicts)

- (GCCommit*)resolveConflictsWithResolver:(id<GCMergeConflictResolver>)resolver
                                    index:(GCIndex*)index
                                ourCommit:(GCCommit*)ourCommit
                              theirCommit:(GCCommit*)theirCommit
                            parentCommits:(NSArray*)parentCommits
                                  message:(NSString*)message
                                    error:(NSError**)error;

@end
