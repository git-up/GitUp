//
//  GIQuickViewControllerWithCommitsList.h
//  GitUpKit (OSX)
//
//  Created by Dmitry Lobanov on 31.08.2020.
//

#import "GIViewController.h"
#import "GIQuickViewController.h"

@class GCHistoryCommit;
@class GCCommit;

@interface GIQuickViewControllerWithCommitsList : GIViewController
@property(nonatomic, strong) GCHistoryCommit* commit;
@property(weak, nonatomic) id<GIQuickViewControllerDelegate> delegate;
@property(nonatomic, strong) NSArray <GCHistoryCommit *> *list;
@end

