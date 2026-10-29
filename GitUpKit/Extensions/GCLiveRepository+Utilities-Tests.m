//
//  GCLiveRepository+Utilities-Tests.m
//  Tests
//

#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#import "GCTestCase.h"
#import "GCLiveRepository+Utilities.h"  // Not a public header of GitUpKit
#import <GitUpKit/GCRepository+Index.h>

static NSString* const kLocalChangesAlertTitle = @"Local changes would be overwritten by checkout";
static NSString* const kDiscardButtonTitle = @"Discard Changes and Continue";
static NSString* const kCancelButtonTitle = @"Cancel";
static NSString* const kCreateLocalBranchButtonTitle = @"Create Local Branch";
static NSString* const kCheckoutCommitButtonTitle = @"Checkout Commit";
static NSString* const kLocalEdit = @"local edit\n";

// Alert the code asked to show as a sheet, with the handler AppKit calls when one of its buttons is clicked
@interface GCSheetAlert : NSObject
@property(nonatomic) NSAlert* alert;
@property(nonatomic, copy) void (^completionHandler)(NSModalResponse returnCode);
@end

@implementation GCSheetAlert
@end

// Records the errors it is asked to present, because presenting one runs a modal alert that would block the test
@interface GCErrorRecordingWindow : NSWindow
@property(nonatomic) NSArray<NSError*>* presentedErrors;
@end

@implementation GCErrorRecordingWindow

- (BOOL)presentError:(NSError*)error {
  self.presentedErrors = [(self.presentedErrors ?: @[]) arrayByAddingObject:error];
  return NO;
}

@end

/*
  c0 -> c1 (master)
   |\
   | \-> cT (topic)
    \
     \-> cF (origin/feature, no local branch)

  "conflict.txt" is different in every commit, so a local edit of it blocks any checkout from master
  "staged.txt" is the same in every commit, so a local edit of it never blocks a checkout
  "new.txt" only exists in cT
*/
@interface GCLiveRepositoryUtilitiesTests : GCTestCase
@property(nonatomic) NSString* rootPath;
@property(nonatomic) GCLiveRepository* liveRepository;
@property(nonatomic) GCErrorRecordingWindow* window;
@property(nonatomic) NSMutableArray<GCSheetAlert*>* pendingSheetAlerts;
@property(nonatomic) IMP originalBeginSheetImplementation;
@property(nonatomic) GCCommit* baseCommit;
@property(nonatomic) GCCommit* topicCommit;
@property(nonatomic) GCCommit* featureCommit;
@property(nonatomic) GCCommit* submoduleLocalBranchCommit;
@property(nonatomic) GCCommit* submoduleCommitWithoutBranches;
@property(nonatomic) GCCommit* submoduleRemoteBranchCommit;
@end

@implementation GCLiveRepositoryUtilitiesTests

- (void)setUp {
  [super setUp];

  // xctest has no application object, but GitUp always has one and NSAlert gives the Return key to its first button only then
  [NSApplication sharedApplication];

  [self startRecordingSheetAlerts];
  self.window = [[GCErrorRecordingWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];

  self.rootPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:self.rootPath withIntermediateDirectories:YES attributes:nil error:NULL]);
  self.liveRepository = [self createLiveRepositoryAtPath:[self.rootPath stringByAppendingPathComponent:@"repository"]];
  [self makeHistory];
}

- (void)tearDown {
  [self stopRecordingSheetAlerts];
  self.pendingSheetAlerts = nil;  // Their completion handlers keep the repository alive
  self.window = nil;
  self.liveRepository = nil;
  [[NSFileManager defaultManager] removeItemAtPath:self.rootPath error:NULL];

  [super tearDown];
}

#pragma mark - Tests

- (void)testCheckoutBlockedByLocalChangesOffersToDiscardThem {
  [self writeString:kLocalEdit toFile:@"conflict.txt"];

  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.topicCommit] window:self.window];

  XCTAssertEqual(self.pendingSheetAlerts.count, 1);
  NSAlert* alert = self.pendingSheetAlerts.firstObject.alert;
  XCTAssertEqualObjects(alert.messageText, kLocalChangesAlertTitle);
  NSMutableArray<NSString*>* buttonTitles = [[NSMutableArray alloc] init];
  for (NSButton* button in alert.buttons) {
    [buttonTitles addObject:button.title];
  }
  XCTAssertEqual(buttonTitles.count, 2);
  XCTAssertEqualObjects([NSSet setWithArray:buttonTitles], ([NSSet setWithObjects:kDiscardButtonTitle, kCancelButtonTitle, nil]));
  NSButton* discardButton = [self buttonWithTitle:kDiscardButtonTitle inAlert:alert];
  XCTAssertTrue(discardButton.hasDestructiveAction);  // Drawn in red
  XCTAssertNotEqualObjects(discardButton.keyEquivalent, @"\r");  // Return does not discard the changes
  NSString* alertText = [NSString stringWithFormat:@"%@\n%@", alert.messageText, alert.informativeText];
  XCTAssertTrue([alertText localizedCaseInsensitiveContainsString:@"undo"]);  // Warns that discarding cannot be undone
}

- (void)testDiscardChangesAndContinueChecksOutBranchWithoutStagedOrUnstagedChanges {
  [self writeString:kLocalEdit toFile:@"conflict.txt"];
  [self writeString:@"staged edit\n" toFile:@"staged.txt"];
  XCTAssertTrue([self.liveRepository addFileToIndex:@"staged.txt" error:NULL]);

  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.topicCommit] window:self.window];
  [self clickButtonWithTitle:kDiscardButtonTitle];

  XCTAssertEqualObjects([self headBranch].name, @"topic");
  XCTAssertEqualObjects([self contentsOfFile:@"conflict.txt"], @"topic\n");
  XCTAssertEqualObjects([self contentsOfFile:@"staged.txt"], @"same\n");
  NSError* error;
  XCTAssertTrue([self.liveRepository checkClean:kGCCleanCheckOption_IgnoreUntrackedFiles error:&error], @"%@", error);  // Nothing is left staged either
}

- (void)testDiscardChangesAndContinueOverwritesUntrackedFileInTheWayAndKeepsOtherUntrackedFiles {
  [self writeString:@"untracked file\n" toFile:@"new.txt"];
  [self writeString:@"untracked notes\n" toFile:@"notes.txt"];  // In no commit, so it is never in the way of a checkout

  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.topicCommit] window:self.window];
  [self clickButtonWithTitle:kDiscardButtonTitle];

  XCTAssertEqualObjects([self headBranch].name, @"topic");
  XCTAssertEqualObjects([self contentsOfFile:@"new.txt"], @"topic new\n");
  XCTAssertEqualObjects([self contentsOfFile:@"notes.txt"], @"untracked notes\n");
}

- (void)testDiscardChangesAndContinueChecksOutCommitWithDetachedHEAD {
  // Commit without branches
  [self writeString:kLocalEdit toFile:@"conflict.txt"];
  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.baseCommit] window:self.window];
  [self clickButtonWithTitle:kDiscardButtonTitle];

  GCLocalBranch* branch;
  XCTAssertEqualObjects([self.liveRepository lookupHEAD:&branch error:NULL], self.baseCommit);
  XCTAssertNil(branch);
  XCTAssertEqualObjects([self contentsOfFile:@"conflict.txt"], @"base\n");

  // Tip of a remote branch, with "Checkout Commit" chosen instead of creating a local branch
  [self writeString:kLocalEdit toFile:@"conflict.txt"];
  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.featureCommit] window:self.window];
  [self clickButtonWithTitle:kCheckoutCommitButtonTitle];
  [self clickButtonWithTitle:kDiscardButtonTitle];

  XCTAssertEqualObjects([self.liveRepository lookupHEAD:&branch error:NULL], self.featureCommit);
  XCTAssertNil(branch);
  XCTAssertEqualObjects([self contentsOfFile:@"conflict.txt"], @"feature\n");
}

- (void)testDiscardChangesAndContinueCreatesLocalBranchTrackingRemoteBranch {
  [self writeString:kLocalEdit toFile:@"conflict.txt"];

  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.featureCommit] window:self.window];
  [self clickButtonWithTitle:kCreateLocalBranchButtonTitle];
  [self clickButtonWithTitle:kDiscardButtonTitle];

  GCLocalBranch* branch = [self headBranch];
  XCTAssertEqualObjects(branch.name, @"feature");
  XCTAssertEqualObjects([self.liveRepository lookupUpstreamForLocalBranch:branch error:NULL].name, @"origin/feature");
  XCTAssertEqualObjects([self contentsOfFile:@"conflict.txt"], @"feature\n");
}

- (void)testCancelKeepsLocalChangesAndCurrentBranch {
  [self writeString:kLocalEdit toFile:@"conflict.txt"];

  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.topicCommit] window:self.window];
  [self clickButtonWithTitle:kCancelButtonTitle];

  XCTAssertEqualObjects([self headBranch].name, @"master");
  XCTAssertEqualObjects([self contentsOfFile:@"conflict.txt"], kLocalEdit);
  XCTAssertEqual(self.pendingSheetAlerts.count, 0);
  XCTAssertEqual(self.window.presentedErrors.count, 0);
}

- (void)testCheckoutErrorNotCausedByLocalChangesDoesNotOfferToDiscardThem {
  [self writeString:kLocalEdit toFile:@"conflict.txt"];
  [self addWorktreeForBranchWithName:@"topic"];  // A branch checked out in another worktree cannot be checked out here, whatever the local changes

  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.topicCommit] window:self.window];

  XCTAssertEqual(self.pendingSheetAlerts.count, 0);
  XCTAssertEqual(self.window.presentedErrors.count, 1);
}

- (void)testCheckoutBlockedOnlyBySubmoduleChangesShowsErrorWithoutOfferingToDiscardThem {
  [self makeHistoryWithSubmodule];
  [self writeString:kLocalEdit toFile:@"sub/file.txt"];  // The checkout does not look inside the submodule, so it moves HEAD and only the submodule update after it fails

  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.submoduleLocalBranchCommit] window:self.window];
  [self assertCheckoutConflictErrorShownWithoutDiscardOffer:@"Local branch"];

  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.submoduleCommitWithoutBranches] window:self.window];
  [self assertCheckoutConflictErrorShownWithoutDiscardOffer:@"Commit without branches"];

  [self.liveRepository smartCheckoutCommit:[self historyCommitForCommit:self.submoduleRemoteBranchCommit] window:self.window];
  [self clickButtonWithTitle:kCreateLocalBranchButtonTitle];
  [self assertCheckoutConflictErrorShownWithoutDiscardOffer:@"Create Local Branch"];
}

// The checkout error is shown as before, with only an OK button, instead of the alert offering to discard the local changes
- (void)assertCheckoutConflictErrorShownWithoutDiscardOffer:(NSString*)scenario {
  XCTAssertEqual(self.pendingSheetAlerts.count, 0, @"%@", scenario);
  XCTAssertEqual(self.window.presentedErrors.count, 1, @"%@", scenario);
  NSError* error = self.window.presentedErrors.firstObject;
  XCTAssertEqualObjects(error.domain, GCErrorDomain, @"%@", scenario);
  XCTAssertEqual(error.code, kGCErrorCode_CheckoutConflicts, @"%@", scenario);  // The local changes blocked the checkout, it did not fail for another reason

  // Next checkout starts with nothing shown
  [self.pendingSheetAlerts removeAllObjects];
  self.window.presentedErrors = nil;
}

#pragma mark - Repository

- (GCLiveRepository*)createLiveRepositoryAtPath:(NSString*)path {
  GCLiveRepository* repository = [[GCLiveRepository alloc] initWithNewLocalRepository:path bare:NO defaultBranchName:@"master" error:NULL];
  XCTAssertNotNil(repository);
  [self useTestConfigForRepository:repository];
  return repository;
}

// Only the repository config and a test identity apply, so the global git config of the machine cannot change checkouts or commits
- (void)useTestConfigForRepository:(GCRepository*)repository {
  NSString* configPath = [self.rootPath stringByAppendingPathComponent:[repository.workingDirectoryPath.lastPathComponent stringByAppendingPathExtension:@"config"]];
  XCTAssertTrue([@"[user]\n\tname = Bot\n\temail = bot@example.com\n" writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  git_config* config;
  XCTAssertEqual(git_config_new(&config), GIT_OK);
  XCTAssertEqual(git_config_add_file_ondisk(config, [[repository.repositoryPath stringByAppendingPathComponent:@"config"] fileSystemRepresentation], GIT_CONFIG_LEVEL_LOCAL, repository.private, true), GIT_OK);
  XCTAssertEqual(git_config_add_file_ondisk(config, configPath.fileSystemRepresentation, GIT_CONFIG_LEVEL_APP, repository.private, true), GIT_OK);
  git_repository_set_config(repository.private, config);
  git_config_free(config);
}

- (void)makeHistory {
  self.baseCommit = [self commitFiles:@{@"conflict.txt" : @"base\n", @"staged.txt" : @"same\n"} message:@"Base"];
  GCLocalBranch* masterBranch = [self headBranch];
  GCLocalBranch* topicBranch = [self.liveRepository createLocalBranchFromCommit:self.baseCommit withName:@"topic" force:NO error:NULL];
  GCLocalBranch* featureBranch = [self.liveRepository createLocalBranchFromCommit:self.baseCommit withName:@"feature" force:NO error:NULL];
  XCTAssertNotNil(topicBranch);
  XCTAssertNotNil(featureBranch);
  [self commitFiles:@{@"conflict.txt" : @"master\n"} message:@"Master"];

  XCTAssertTrue([self.liveRepository checkoutLocalBranch:topicBranch options:(GCCheckoutOptions)0 error:NULL]);
  self.topicCommit = [self commitFiles:@{@"conflict.txt" : @"topic\n", @"new.txt" : @"topic new\n"} message:@"Topic"];

  XCTAssertTrue([self.liveRepository checkoutLocalBranch:featureBranch options:(GCCheckoutOptions)0 error:NULL]);
  self.featureCommit = [self commitFiles:@{@"conflict.txt" : @"feature\n"} message:@"Feature"];

  XCTAssertTrue([self.liveRepository checkoutLocalBranch:masterBranch options:(GCCheckoutOptions)0 error:NULL]);

  // Keep "feature" only as a remote branch
  NSURL* remoteURL = [NSURL fileURLWithPath:[self.rootPath stringByAppendingPathComponent:@"origin.git"]];
  XCTAssertNotNil([self.liveRepository addRemoteWithName:@"origin" url:remoteURL error:NULL]);
  XCTAssertNotNil([self.liveRepository createDirectReferenceWithFullName:@"refs/remotes/origin/feature" target:self.featureCommit force:NO error:NULL]);
  XCTAssertTrue([self.liveRepository deleteLocalBranch:featureBranch error:NULL]);

  [self.liveRepository notifyRepositoryChanged];  // The live repository reloads its history only when notified
}

/*
  c1 -> cA (master, "sub" at s2)
         \
          \-> cB ("sub" at s1) -> cC (subtopic)
               \
                \-> cD (origin/subfeature, no local branch)

  "file.txt" of the submodule is different in s1 and s2, so a local edit of it blocks updating the submodule to s1 after a checkout from master
*/
- (void)makeHistoryWithSubmodule {
  // Cloned from a local repository, so no network is needed
  NSString* originPath = [self.rootPath stringByAppendingPathComponent:@"submodule-origin"];
  GCRepository* origin = [[GCRepository alloc] initWithNewLocalRepository:originPath bare:NO defaultBranchName:@"master" error:NULL];
  XCTAssertNotNil(origin);
  [self useTestConfigForRepository:origin];
  GCCommit* originCommit1 = [self commitFiles:@{@"file.txt" : @"s1\n"} message:@"s1" inRepository:origin];
  [self commitFiles:@{@"file.txt" : @"s2\n"} message:@"s2" inRepository:origin];

  GCSubmodule* submodule = [self.liveRepository addSubmoduleWithURL:[NSURL fileURLWithPath:originPath] atPath:@"sub" recursive:NO error:NULL];
  XCTAssertNotNil(submodule);
  GCCommit* masterCommit = [self.liveRepository createCommitFromHEADWithMessage:@"Add submodule" error:NULL];
  XCTAssertNotNil(masterCommit);
  GCLocalBranch* masterBranch = [self headBranch];

  GCLocalBranch* topicBranch = [self.liveRepository createLocalBranchFromCommit:masterCommit withName:@"subtopic" force:NO error:NULL];
  XCTAssertNotNil(topicBranch);
  XCTAssertTrue([self.liveRepository checkoutLocalBranch:topicBranch options:(GCCheckoutOptions)0 error:NULL]);
  GCRepository* submoduleRepository = [[GCRepository alloc] initWithSubmodule:submodule error:NULL];
  XCTAssertNotNil(submoduleRepository);
  GCCommit* submoduleCommit1 = [submoduleRepository findCommitWithSHA1:originCommit1.SHA1 error:NULL];
  XCTAssertNotNil(submoduleCommit1);
  XCTAssertTrue([submoduleRepository checkoutCommit:submoduleCommit1 options:(GCCheckoutOptions)0 error:NULL]);
  XCTAssertTrue([self.liveRepository addSubmoduleToRepositoryIndex:submodule error:NULL]);
  self.submoduleCommitWithoutBranches = [self.liveRepository createCommitFromHEADWithMessage:@"Submodule at s1" error:NULL];
  XCTAssertNotNil(self.submoduleCommitWithoutBranches);
  self.submoduleLocalBranchCommit = [self commitFiles:@{@"subtopic.txt" : @"subtopic\n"} message:@"Subtopic"];

  GCLocalBranch* featureBranch = [self.liveRepository createLocalBranchFromCommit:self.submoduleCommitWithoutBranches withName:@"subfeature" force:NO error:NULL];
  XCTAssertNotNil(featureBranch);
  XCTAssertTrue([self.liveRepository checkoutLocalBranch:featureBranch options:(GCCheckoutOptions)0 error:NULL]);
  self.submoduleRemoteBranchCommit = [self commitFiles:@{@"subfeature.txt" : @"subfeature\n"} message:@"Subfeature"];
  XCTAssertNotNil([self.liveRepository createDirectReferenceWithFullName:@"refs/remotes/origin/subfeature" target:self.submoduleRemoteBranchCommit force:NO error:NULL]);

  XCTAssertTrue([self.liveRepository checkoutLocalBranch:masterBranch options:kGCCheckoutOption_UpdateSubmodulesRecursively error:NULL]);  // Also puts the submodule back to s2
  XCTAssertTrue([self.liveRepository deleteLocalBranch:featureBranch error:NULL]);

  [self.liveRepository notifyRepositoryChanged];
}

- (GCCommit*)commitFiles:(NSDictionary<NSString*, NSString*>*)files message:(NSString*)message {
  return [self commitFiles:files message:message inRepository:self.liveRepository];
}

- (GCCommit*)commitFiles:(NSDictionary<NSString*, NSString*>*)files message:(NSString*)message inRepository:(GCRepository*)repository {
  for (NSString* path in files) {
    XCTAssertTrue([files[path] writeToFile:[repository.workingDirectoryPath stringByAppendingPathComponent:path] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    XCTAssertTrue([repository addFileToIndex:path error:NULL]);
  }
  GCCommit* commit = [repository createCommitFromHEADWithMessage:message error:NULL];
  XCTAssertNotNil(commit);
  return commit;
}

- (void)addWorktreeForBranchWithName:(NSString*)name {
  GCLocalBranch* branch = [self.liveRepository findLocalBranchWithName:name error:NULL];
  XCTAssertNotNil(branch);
  git_worktree_add_options options = GIT_WORKTREE_ADD_OPTIONS_INIT;
  options.ref = branch.private;
  git_worktree* worktree = NULL;
  NSString* path = [self.rootPath stringByAppendingPathComponent:@"worktree"];
  XCTAssertEqual(git_worktree_add(&worktree, self.liveRepository.private, "worktree", path.fileSystemRepresentation, &options), GIT_OK);
  git_worktree_free(worktree);
}

- (GCHistoryCommit*)historyCommitForCommit:(GCCommit*)commit {
  GCHistoryCommit* historyCommit = [self.liveRepository.history historyCommitForCommit:commit];
  XCTAssertNotNil(historyCommit);
  return historyCommit;
}

- (GCLocalBranch*)headBranch {
  GCLocalBranch* branch;
  XCTAssertNotNil([self.liveRepository lookupHEAD:&branch error:NULL]);
  return branch;
}

- (void)writeString:(NSString*)string toFile:(NSString*)path {
  XCTAssertTrue([string writeToFile:[self.liveRepository.workingDirectoryPath stringByAppendingPathComponent:path] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}

- (NSString*)contentsOfFile:(NSString*)path {
  return [NSString stringWithContentsOfFile:[self.liveRepository.workingDirectoryPath stringByAppendingPathComponent:path] encoding:NSUTF8StringEncoding error:NULL];
}

#pragma mark - Alerts

// The code shows its alerts as sheets with -beginSheetModalForWindow:completionHandler:, so the test keeps them instead of showing them
- (void)startRecordingSheetAlerts {
  NSMutableArray<GCSheetAlert*>* pendingSheetAlerts = [[NSMutableArray alloc] init];
  self.pendingSheetAlerts = pendingSheetAlerts;
  Method method = class_getInstanceMethod([NSAlert class], @selector(beginSheetModalForWindow:completionHandler:));
  IMP recordingImplementation = imp_implementationWithBlock(^(NSAlert* alert, NSWindow* sheetWindow, void (^completionHandler)(NSModalResponse returnCode)) {
    (void)sheetWindow;
    GCSheetAlert* sheetAlert = [[GCSheetAlert alloc] init];
    sheetAlert.alert = alert;
    sheetAlert.completionHandler = completionHandler;
    [pendingSheetAlerts addObject:sheetAlert];
  });
  self.originalBeginSheetImplementation = method_setImplementation(method, recordingImplementation);
}

- (void)stopRecordingSheetAlerts {
  Method method = class_getInstanceMethod([NSAlert class], @selector(beginSheetModalForWindow:completionHandler:));
  IMP recordingImplementation = method_setImplementation(method, self.originalBeginSheetImplementation);
  imp_removeBlock(recordingImplementation);
}

// Clicks a button of the oldest alert still shown: NSAlert ends its sheet with the tag of the clicked button as the return code
- (void)clickButtonWithTitle:(NSString*)title {
  GCSheetAlert* sheetAlert = self.pendingSheetAlerts.firstObject;
  if (sheetAlert == nil) {
    XCTFail(@"No alert is shown to click \"%@\"", title);
    return;
  }
  [self.pendingSheetAlerts removeObjectAtIndex:0];
  NSButton* button = [self buttonWithTitle:title inAlert:sheetAlert.alert];
  if (button == nil) {
    XCTFail(@"No \"%@\" button in the alert \"%@\"", title, sheetAlert.alert.messageText);
    return;
  }
  sheetAlert.completionHandler(button.tag);
}

- (NSButton*)buttonWithTitle:(NSString*)title inAlert:(NSAlert*)alert {
  for (NSButton* button in alert.buttons) {
    if ([button.title isEqualToString:title]) {
      return button;
    }
  }
  return nil;
}

@end
