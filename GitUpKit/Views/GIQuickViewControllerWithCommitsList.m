//
//  GIQuickViewControllerWithCommitsList.m
//  GitUpKit (OSX)
//
//  Created by Dmitry Lobanov on 31.08.2020.
//

#import "GIQuickViewControllerWithCommitsList.h"

#import "GIQuickViewController.h"
//#import "GIDiffContentsViewController.h"
//#import "GIDiffFilesViewController.h"
#import "GIViewController+Utilities.h"
#import "NSView+Embedding.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

#import "GICommitListViewController.h"
@interface GIQuickViewControllerWithCommitsList () <GICommitListViewControllerDelegate>
@property (strong, nonatomic, readwrite) GICommitListViewController *commitListViewController;
@property (strong, nonatomic, readwrite) GIQuickViewController *quickViewController;

@property (strong, nonatomic, readwrite) NSLayoutConstraint *hiddenConstraint;
@property (strong, nonatomic, readwrite) NSLayoutConstraint *revealedConstraint;
@end

@implementation GIQuickViewControllerWithCommitsList

#pragma mark - Check
- (BOOL)isHistoryShown {
  return self.commitListViewController.results.count > 0;
}

#pragma mark - Actions
- (void)toggleLeftView {
  BOOL shouldReveal = self.isHistoryShown;
  self.hiddenConstraint.active = !shouldReveal;
  self.revealedConstraint.active = shouldReveal;
  [self.view setNeedsLayout:YES];
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
    context.duration = 0.25;
    context.allowsImplicitAnimation = YES;
    [self.view layout];
  } completionHandler:^{
  }];
}

#pragma mark - Layout
- (void)addConstraints {
  if (@available(macOS 10.11, *)) {
    NSView *leftView = self.commitListViewController.view;
    if (leftView.superview != nil) {
      NSView *superview = leftView.superview;
      NSArray *constraints = @[
                               [leftView.leftAnchor constraintEqualToAnchor:superview.leftAnchor],
                               [leftView.topAnchor constraintEqualToAnchor:superview.topAnchor],
                               [leftView.bottomAnchor constraintEqualToAnchor:superview.bottomAnchor],
                               [leftView.widthAnchor constraintEqualToAnchor:superview.widthAnchor multiplier:0.3]
                               ];
      [NSLayoutConstraint activateConstraints:constraints];
    }

    NSView *rightView = self.quickViewController.view;
    if (rightView.superview != nil) {
      NSView *superview = rightView.superview;
      self.hiddenConstraint = [rightView.leftAnchor constraintEqualToAnchor:superview.leftAnchor];
      self.revealedConstraint = [rightView.leftAnchor constraintEqualToAnchor:leftView.rightAnchor];
      NSArray *constraints = @[
                               [rightView.topAnchor constraintEqualToAnchor:superview.topAnchor],
                               [rightView.bottomAnchor constraintEqualToAnchor:superview.bottomAnchor],
                               [rightView.rightAnchor constraintEqualToAnchor:superview.rightAnchor],
                               ];
      [NSLayoutConstraint activateConstraints:constraints];
    }
    
    [self toggleLeftView];
  } else {
    NSView *leftView = self.commitListViewController.view;
    if (leftView.superview != nil) {
      NSView *superview = leftView.superview;
      NSArray *constraints = @[
        [NSLayoutConstraint constraintWithItem:leftView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:leftView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeWidth multiplier:0.3 constant:0.0]
      ];
      NSArray *verticalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{@"view": leftView}];
      [NSLayoutConstraint activateConstraints:[constraints arrayByAddingObjectsFromArray:verticalConstraints]];
    }
    NSView *rightView = self.quickViewController.view;
    if (rightView.superview != nil) {
      NSView *superview = rightView.superview;
      self.hiddenConstraint = [NSLayoutConstraint constraintWithItem:rightView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0.0];
      self.revealedConstraint = [NSLayoutConstraint constraintWithItem:rightView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:leftView attribute:NSLayoutAttributeRight multiplier:1.0 constant:0.0];
      NSArray *constraints = @[
        [NSLayoutConstraint constraintWithItem:rightView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeRight multiplier:1.0 constant:0.0],
      ];
      NSArray *verticalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{@"view": rightView}];
      [NSLayoutConstraint activateConstraints:[constraints arrayByAddingObjectsFromArray:verticalConstraints]];
    }
    
    [self toggleLeftView];
  }
}

#pragma mark - View Lifecycle
- (void)loadView {
  self.view = [[GIView alloc] initWithFrame:NSScreen.mainScreen.frame];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  self.commitListViewController = [[GICommitListViewController alloc] initWithRepository:self.repository];
  self.commitListViewController.delegate = self;
  
  self.quickViewController = [[GIQuickViewController alloc] initWithRepository:self.repository];
  __weak typeof(self) weakSelf = self;
  self.quickViewController.willShowContextualMenu = ^(NSMenu *menu, GCDiffDelta *delta, GCIndexConflict *conflict) {
    [weakSelf willShowContextualMenu:menu delta:delta conflict:conflict];
  };

  [self.view addSubview:self.commitListViewController.view];
  [self.view addSubview:self.quickViewController.view];
  
  self.commitListViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
  self.quickViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
  [self addConstraints];
}

- (void)setCommit:(GCHistoryCommit *)commit {
  if (self.quickViewController.commit.autoIncrementID != commit.autoIncrementID || self.quickViewController.commit == nil) {
    self.quickViewController.commit = commit;
  }
  if (self.commitListViewController.selectedCommit.autoIncrementID != commit.autoIncrementID || self.commitListViewController.selectedCommit == nil) {
     self.commitListViewController.selectedCommit = commit;
  }
}

#pragma mark - Getters / Setters
- (GCHistoryCommit *)commit {
  return self.quickViewController.commit;
}

- (void)setDelegate:(id<GIQuickViewControllerDelegate>)delegate {
  self.quickViewController.delegate = delegate;
}

- (id<GIQuickViewControllerDelegate>)delegate {
  return self.quickViewController.delegate;
}

- (void)setList:(NSArray<GCHistoryCommit *> *)list {
  self.commitListViewController.results = list;
  [self toggleLeftView];
}

- (NSArray<GCHistoryCommit *> *)list {
  NSMutableArray* result = [NSMutableArray new];
  for (GCHistoryCommit* element in self.commitListViewController.results) {
    if ([element isKindOfClass:GCHistoryCommit.class]) {
      [result addObject:element];
    }
  }
  return [result copy];
}

#pragma mark - CommitListControllerDelegate
- (void)commitListViewControllerDidChangeSelection:(GICommitListViewController *)controller {
  // we should reload data in quickview.
  self.quickViewController.commit = controller.selectedCommit;
  [self.quickViewController.delegate quickViewDidSelectCommit:self.quickViewController.commit commitsList:nil];
  // TODO: add quick view model.
  // also we should update QuickViewModel to be in touch with toolbar...
}

#pragma mark - GIViewController
- (void)viewDidFinishLiveResize {
  [self.commitListViewController viewDidFinishLiveResize];
  [self.quickViewController viewDidFinishLiveResize];
}

#pragma mark - Contextual Menu Handling
- (void)willShowContextualMenu:(NSMenu *)menu delta:(GCDiffDelta *)delta conflict:(GCIndexConflict *)conflict {
  if (GC_FILE_MODE_IS_FILE(delta.newFile.mode)) {
    if (self.isHistoryShown) {
      __weak typeof(self) weakSelf = self;
      [menu addItemWithTitle:NSLocalizedString(@"Hide file history...", nil) block:^{
        [weakSelf.delegate quickViewWantsToShowSelectedCommitsList:nil selectedCommit:weakSelf.commit];
      }];
    }
    else {
      __weak typeof(self) weakSelf = self;
      [menu addItemWithTitle:NSLocalizedString(@"Show file history...", nil) block:^{
        // git log
        // show selected files history.
        [weakSelf getSelectedCommitsForFilesMatchingPaths:@[delta.canonicalPath] result:^(NSArray *commits) {
          NSMutableArray *result = [NSMutableArray new];
          for (GCCommit *commit in commits) {
            GCHistoryCommit *historyCommit = [weakSelf.repository.history historyCommitForCommit:commit];
            [result addObject:historyCommit];
          }
          [weakSelf.delegate quickViewWantsToShowSelectedCommitsList:[result copy] selectedCommit:result.firstObject];
        }];
      }];
    }
  }
}

@end
