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

#import "GIDiffViewController.h"
#import "GIDiffContentsViewController.h"
#import "GIDiffFilesViewController.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

@interface GIDiffViewController () <GIDiffContentsViewControllerDelegate, GIDiffFilesViewControllerDelegate>
@property(nonatomic, weak) IBOutlet NSView* contentsView;
@property(nonatomic, weak) IBOutlet NSView* filesView;
@property(nonatomic, weak) IBOutlet NSTextField* fromTextField;
@property(nonatomic, weak) IBOutlet NSTextField* toTextField;
@end

@implementation GIDiffViewController {
  GIDiffContentsViewController* _diffContentsViewController;
  GIDiffFilesViewController* _diffFilesViewController;
  NSDateFormatter* _dateFormatter;
  BOOL _disableFeedbackLoop;
}

- (instancetype)initWithRepository:(GCLiveRepository*)repository {
  if ((self = [super initWithRepository:repository])) {
    _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.dateStyle = NSDateFormatterShortStyle;
    _dateFormatter.timeStyle = NSDateFormatterShortStyle;
  }
  return self;
}

- (void)loadView {
  [super loadView];
  
  _diffContentsViewController = [[GIDiffContentsViewController alloc] initWithRepository:self.repository];
  _diffContentsViewController.delegate = self;
  _diffContentsViewController.emptyLabel = NSLocalizedString(@"No differences", nil);
  [_contentsView replaceWithView:_diffContentsViewController.view];
  
  _diffFilesViewController = [[GIDiffFilesViewController alloc] initWithRepository:self.repository];
  _diffFilesViewController.delegate = self;
  [_filesView replaceWithView:_diffFilesViewController.view];
}

- (void)setCommit:(GCCommit*)commit withParentCommit:(GCCommit*)parentCommit {
  if ((commit != _commit) || (parentCommit != _parentCommit)) {
    _commit = commit;
    _parentCommit = parentCommit;
    if (_commit) {
      NSError* error;
      GCDiff* diff = [self.repository diffCommit:_commit
                                      withCommit:_parentCommit
                                     filePattern:nil
                                         options:(self.repository.diffBaseOptions | kGCDiffOption_FindRenames)
                               maxInterHunkLines:self.repository.diffMaxInterHunkLines
                                 maxContextLines:self.repository.diffMaxContextLines
                                           error:&error];
      if (!diff) {
        [self presentError:error];
      }
      [_diffContentsViewController setDeltas:diff.deltas usingConflicts:nil];
      [_diffFilesViewController setDeltas:diff.deltas usingConflicts:nil];
      
      _fromTextField.stringValue = [NSString stringWithFormat:@"\"%@\" <%@> (%@)", _commit.summary, _commit.shortSHA1, [_dateFormatter stringFromDate:_commit.date]];
      _toTextField.stringValue = [NSString stringWithFormat:@"\"%@\" <%@> (%@)", _parentCommit.summary, _parentCommit.shortSHA1, [_dateFormatter stringFromDate:_parentCommit.date]];
    } else {
      [_diffContentsViewController setDeltas:nil usingConflicts:nil];
      [_diffFilesViewController setDeltas:nil usingConflicts:nil];
      
      _fromTextField.stringValue = NSLocalizedString(@"n/a", nil);
      _toTextField.stringValue = NSLocalizedString(@"n/a", nil);
    }
  }
}

#pragma mark - GIDiffContentsViewControllerDelegate

- (void)diffContentsViewControllerDidScroll:(GIDiffContentsViewController*)scroll {
  if (!_disableFeedbackLoop) {
    _diffFilesViewController.selectedDelta = [_diffContentsViewController topVisibleDelta:NULL];
  }
}

#pragma mark - GIDiffFilesViewControllerDelegate

- (void)diffFilesViewController:(GIDiffFilesViewController*)controller willSelectDelta:(GCDiffDelta*)delta {
  _disableFeedbackLoop = YES;
  [_diffContentsViewController setTopVisibleDelta:delta offset:0];
  _disableFeedbackLoop = NO;
}

@end
