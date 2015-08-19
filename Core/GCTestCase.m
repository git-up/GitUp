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

#import <objc/runtime.h>

#import "GCTestCase.h"
#import "GCRepository+Index.h"

#define kGitCLTPath @"/usr/bin/git"

static const void* _associatedObjectKey = &_associatedObjectKey;

@implementation GCTestCase

- (void)setUp {
  [super setUp];
  
  // Figure out if running as Xcode Server bot or under Travis CI
  _botMode = [NSUserName() isEqualToString:@"_xcsbuildd"] || getenv("TRAVIS");
}

- (GCRepository*)createLocalRepositoryAtPath:(NSString*)path bare:(BOOL)bare {
  GCRepository* repo = [[GCRepository alloc] initWithNewLocalRepository:path bare:bare error:NULL];
  XCTAssertNotNil(repo);
  
  NSString* configDirectory = [[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] stringByAppendingPathComponent:@"git"];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:configDirectory withIntermediateDirectories:YES attributes:nil error:NULL]);
  NSString* configPath = [configDirectory stringByAppendingPathComponent:@"config"];
  NSString* configString = @"[user]\n\
	name = Bot\n\
	email = bot@example.com\n\
";
  XCTAssertTrue([configString writeToFile:configPath atomically:YES encoding:NSASCIIStringEncoding error:NULL]);
  
  git_config* config;
  XCTAssertEqual(git_config_new(&config), GIT_OK);
  if (!repo.bare) {
    XCTAssertEqual(git_config_add_file_ondisk(config, [[repo.repositoryPath stringByAppendingPathComponent:@"config"] fileSystemRepresentation], GIT_CONFIG_LEVEL_LOCAL, true), GIT_OK);
  }
  XCTAssertEqual(git_config_add_file_ondisk(config, configPath.fileSystemRepresentation, GIT_CONFIG_LEVEL_APP, true), GIT_OK);
  git_repository_set_config(repo.private, config);
  git_config_free(config);
  
  objc_setAssociatedObject(repo, _associatedObjectKey, [configDirectory stringByDeletingLastPathComponent], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  
  return repo;
}

- (void)destroyLocalRepository:(GCRepository*)repository {
  XCTAssert([[NSFileManager defaultManager] removeItemAtPath:(repository.bare ? repository.repositoryPath : repository.workingDirectoryPath) error:NULL]);
}

- (NSString*)_runCLTWithPath:(NSString*)path arguments:(NSArray*)arguments currentDirectory:(NSString*)currentDirectory environment:(NSDictionary*)environment {
  GCTask* task = [[GCTask alloc] initWithExecutablePath:path];
  task.currentDirectoryPath = currentDirectory;
  task.additionalEnvironment = environment;
  NSData* data;
  return [task runWithArguments:arguments stdin:nil stdout:&data stderr:NULL exitStatus:NULL error:NULL] ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

- (NSString*)_runGitCLTWithRepository:(GCRepository*)repository command:(NSString*)command arguments:(va_list)arguments {
  NSMutableArray* array = [[NSMutableArray alloc] init];
  for (NSString* arg = command; arg != nil; arg = va_arg(arguments, NSString*)) {
    [array addObject:arg];
  }
  return [self _runCLTWithPath:kGitCLTPath
                     arguments:array
              currentDirectory:(repository ? (repository.bare ? repository.repositoryPath : repository.workingDirectoryPath) : [[NSFileManager defaultManager] currentDirectoryPath])
                   environment:(repository ? @{@"XDG_CONFIG_HOME": objc_getAssociatedObject(repository, _associatedObjectKey)} : @{})];
}

- (NSString*)runGitCLTWithRepository:(GCRepository*)repository command:(NSString*)command, ... {
  va_list arguments;
  va_start(arguments, command);
  NSString* result = [self _runGitCLTWithRepository:repository command:command arguments:arguments];
  va_end(arguments);
  return result;
}

@end

@implementation GCTestCase (Extensions)

- (void)assertGitCLTOutputEqualsString:(NSString*)string withRepository:(GCRepository*)repository command:(NSString*)command, ... {
  va_list arguments;
  va_start(arguments, command);
  NSString* result = [self _runGitCLTWithRepository:repository command:command arguments:arguments];
  va_end(arguments);
  XCTAssertTrue([result isEqualToString:string]);
}

- (void)assertGitCLTOutputContainsString:(NSString*)string withRepository:(GCRepository*)repository command:(NSString*)command, ... {
  va_list arguments;
  va_start(arguments, command);
  NSString* result = [self _runGitCLTWithRepository:repository command:command arguments:arguments];
  va_end(arguments);
  XCTAssertTrue([result rangeOfString:string].location != NSNotFound);  // -containsString: doesn't exist pre-10.10
}

- (void)assertGitCLTOutputEndsWithString:(NSString*)string withRepository:(GCRepository*)repository command:(NSString*)command, ... {
  va_list arguments;
  va_start(arguments, command);
  NSString* result = [self _runGitCLTWithRepository:repository command:command arguments:arguments];
  va_end(arguments);
  XCTAssertTrue([result hasSuffix:string]);
}

@end

@implementation GCTests
@end

@implementation GCEmptyRepositoryTestCase

- (void)setUp {
  [super setUp];
  
  // Create working directory
  if (self.botMode) {
    _temporaryPath = [NSString stringWithFormat:@"/tmp/gitup-%i", getpid()];
  } else {
    _temporaryPath = @"/tmp/gitup";
  }
  if ([[NSFileManager defaultManager] fileExistsAtPath:_temporaryPath]) {
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:_temporaryPath error:NULL]);
  }
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:_temporaryPath withIntermediateDirectories:NO attributes:nil error:NULL]);
  
  // Initialize new repository
  _repository = [self createLocalRepositoryAtPath:_temporaryPath bare:NO];
  XCTAssertNotNil(_repository);
}

- (void)tearDown {
  // Destroy repository
  [self destroyLocalRepository:_repository];
  _repository = nil;
  _temporaryPath = nil;
  
  [super tearDown];
}

@end

@implementation GCEmptyRepositoryTestCase (Extensions)

- (void)updateFileAtPath:(NSString*)path withString:(NSString*)string {
  XCTAssertTrue([string writeToFile:[_repository.workingDirectoryPath stringByAppendingPathComponent:path] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}

- (void)deleteFileAtPath:(NSString*)path {
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[_repository.workingDirectoryPath stringByAppendingPathComponent:path] error:NULL]);
}

- (GCCommit*)makeCommitWithUpdatedFileAtPath:(NSString*)path string:(NSString*)string message:(NSString*)message {
  [self updateFileAtPath:path withString:string];
  XCTAssertTrue([self.repository addFileToIndex:path error:NULL]);
  GCCommit* commit = [self.repository createCommitFromHEADWithMessage:message error:NULL];
  XCTAssertNotNil(commit);
  return commit;
}

- (GCCommit*)makeCommitWithDeletedFileAtPath:(NSString*)path message:(NSString*)message {
  [self deleteFileAtPath:path];
  XCTAssertTrue([self.repository removeFileFromIndex:path error:NULL]);
  GCCommit* commit = [self.repository createCommitFromHEADWithMessage:message error:NULL];
  XCTAssertNotNil(commit);
  return commit;
}

- (void)assertContentsOfFileAtPath:(NSString*)path equalsString:(NSString*)string {
  NSString* contents = [NSString stringWithContentsOfFile:[self.repository.workingDirectoryPath stringByAppendingPathComponent:path] encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertEqualObjects(contents, string);
}

@end

@implementation GCEmptyRepositoryTests
@end

@implementation GCSingleCommitRepositoryTestCase

- (void)setUp {
  [super setUp];
  
  // Make commits
  _initialCommit = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Hello World!\n" message:@"Initial commit"];
  
  // Look up HEAD
  GCLocalBranch* branch;  // Use local variable to work around ARC limitation
  GCCommit* commit = [self.repository lookupHEAD:&branch error:NULL];
  XCTAssertEqualObjects(commit, _initialCommit);
  XCTAssertEqualObjects(branch.name, @"master");
  _masterBranch = branch;
}

- (void)tearDown {
  _masterBranch = nil;
  _initialCommit = nil;
  
  [super tearDown];
}

@end

@implementation GCSingleCommitRepositoryTests
@end

@implementation GCMultipleCommitsRepositoryTestCase

- (void)setUp {
  [super setUp];
  
  // Make commits
  _commit1 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Bonjour Monde!\n" message:@"1"];
  _commit2 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Gutentag Welt!\n" message:@"2"];
  _commit3 = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Hola Mundo!\n" message:@"3"];
  
  // Create topic branch
  _topicBranch = [self.repository createLocalBranchFromCommit:self.initialCommit withName:@"topic" force:NO error:NULL];
  XCTAssertNotNil(_topicBranch);
  
  // Make commit on topic branch
  XCTAssertTrue([self.repository checkoutLocalBranch:_topicBranch options:0 error:NULL]);
  _commitA = [self makeCommitWithUpdatedFileAtPath:@"hello_world.txt" string:@"Goodbye World!\n" message:@"A"];
  XCTAssertTrue([self.repository checkoutLocalBranch:self.masterBranch options:0 error:NULL]);
}

- (void)tearDown {
  _topicBranch = nil;
  _commit1 = nil;
  _commit2 = nil;
  _commit3 = nil;
  _commitA = nil;
  
  [super tearDown];
}

@end

@implementation GCMultipleCommitsRepositoryTests
@end

@implementation GCSQLiteRepositoryTestCase

- (void)setUp {
  [super setUp];
  
  NSString* path;
  if (self.botMode) {
    path = [NSString stringWithFormat:@"/tmp/sqlite-repository-%i", getpid()];
  } else {
    path = @"/tmp/sqlite-repository";
  }
  _configPath = [path stringByAppendingPathExtension:@"config"];
  _databasePath = [path stringByAppendingPathExtension:@"db"];
  [[NSFileManager defaultManager] removeItemAtPath:_databasePath error:NULL];
  NSString* configString = @"[user]\n\
	name = Bot\n\
	email = bot@example.com\n\
";
  XCTAssertTrue([configString writeToFile:_configPath atomically:YES encoding:NSASCIIStringEncoding error:NULL]);
  _repository = [[GCSQLiteRepository alloc] initWithDatabase:_databasePath config:_configPath localRepositoryContents:nil error:NULL];
  XCTAssertNotNil(_repository);
  XCTAssertTrue(_repository.bare);
  XCTAssertTrue(_repository.empty);
}

- (void)tearDown {
  _repository = nil;
  if ([[NSFileManager defaultManager] fileExistsAtPath:_configPath isDirectory:NULL]) {
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:_configPath error:NULL]);
  }
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:_databasePath error:NULL]);
  
  [super tearDown];
}

@end

@implementation GCSQLiteRepositoryTests
@end
