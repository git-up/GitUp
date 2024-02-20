//
//  QuickViewModel.h
//  Application
//
//  Created by Dmitry Lobanov on 15/09/2019.
//

#import <Foundation/Foundation.h>
@import GitUpKit;

NS_ASSUME_NONNULL_BEGIN

@interface QuickViewModel : NSObject
- (instancetype)initWithRepository:(GCLiveRepository *)repository;

// Checking
@property (assign, nonatomic, readonly) BOOL hasPrevious;
@property (assign, nonatomic, readonly) BOOL hasNext;
@property (assign, nonatomic, readonly) BOOL hasPaging;

// Moving
- (void)moveBackward;
- (void)moveForward;

// States
- (void)enterWithHistoryCommit:(GCHistoryCommit *)commit commitList:(NSArray *)commitList onResult:(void(^)(GCHistoryCommit *,  NSArray * _Nullable))result;
- (void)exit;
@property (strong, nonatomic, readonly) GCHistoryCommit *currentCommit;
@property (strong, nonatomic, readwrite) GCHistoryCommit *selectedCommit;
@end

NS_ASSUME_NONNULL_END
