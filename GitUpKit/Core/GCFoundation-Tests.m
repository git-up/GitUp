//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
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

#import <XCTest/XCTest.h>
#import "GCFoundation.h"

@interface GCFoundation_Tests : XCTestCase

@end

@implementation GCFoundation_Tests {
  NSFileManager* _fileManager;
  NSString* _sandboxPath;
  NSString* _realFilePath;
  NSString* _absentFilePath;
  NSString* _symlinkPath;
  NSString* _symlinkToSymlinkPath;
}

- (void)createSymlinkAtPath:(NSString*)symlinkPath toPath:(NSString*)sourcePath {
  NSError* error;
  XCTAssertTrue([_fileManager createSymbolicLinkAtPath:symlinkPath
                                   withDestinationPath:sourcePath
                                                 error:&error],
                @"Couldn't create symlink due to an error %@", error);
}

- (void)createFileAtPath:(NSString*)path {
  XCTAssertTrue([_fileManager createFileAtPath:path
                                      contents:nil
                                    attributes:nil],
                @"Couldn't create file at path '%@' due to to an error", path);
}

- (void)createDirectoryAtPath:(NSString*)path {
  NSError* error;
  XCTAssertTrue([_fileManager createDirectoryAtPath:path
                        withIntermediateDirectories:NO
                                         attributes:NULL
                                              error:&error],
                @"Couldn't create directory at path '%@' due to an error %@", path, error);
}

- (void)setUp {
  [super setUp];

  _fileManager = [NSFileManager new];

  NSUUID* uuid = [NSUUID UUID];
  _sandboxPath = [NSTemporaryDirectory() stringByAppendingPathComponent:uuid.UUIDString];
  [self createDirectoryAtPath:_sandboxPath];

  _realFilePath = [_sandboxPath stringByAppendingPathComponent:@"file"];
  [self createFileAtPath:_realFilePath];

  _absentFilePath = [_sandboxPath stringByAppendingPathComponent:@"absent"];
  _symlinkPath = [_sandboxPath stringByAppendingPathComponent:@"symlink"];
  _symlinkToSymlinkPath = [_sandboxPath stringByAppendingPathComponent:@"symlink_to_symlink"];
}

- (void)tearDown {
  [_fileManager removeItemAtPath:_sandboxPath error:NULL];

  [super tearDown];
}

#pragma mark - File

- (void)testFileExistsAtPath_FollowLastSymlink_ExistingFile_returnsYES {
  XCTAssertTrue([_fileManager fileExistsAtPath:_realFilePath followLastSymlink:YES]);
}

- (void)testFileExistsAtPath_DoNotFollowLastSymlink_ExistingFile_returnsYES {
  XCTAssertTrue([_fileManager fileExistsAtPath:_realFilePath followLastSymlink:NO]);
}

- (void)testFileExistsAtPath_AbsentFile_returnsNO {
  XCTAssertFalse([_fileManager fileExistsAtPath:_absentFilePath followLastSymlink:NO]);
  XCTAssertFalse([_fileManager fileExistsAtPath:_absentFilePath followLastSymlink:YES]);
}

#pragma mark - Symlink to file

- (void)testFileExistsAtPath_FollowLastSymlink_ExistingSymlink_ExistingSymlinkDestination_returnsYES {
  [self createSymlinkAtPath:_symlinkPath toPath:_realFilePath];

  XCTAssertTrue([_fileManager fileExistsAtPath:_symlinkPath followLastSymlink:YES]);
}

- (void)testFileExistsAtPath_FollowLastSymlink_ExistingSymlink_MadeUpSymlinkDestination_returnsNO {
  [self createSymlinkAtPath:_symlinkPath toPath:_absentFilePath];

  XCTAssertFalse([_fileManager fileExistsAtPath:_symlinkPath followLastSymlink:YES]);
}

- (void)testFileExistsAtPath_DoNotFollowLastSymlink_ExistingSymlink_MadeUpSymlinkDestination_returnsYES {
  [self createSymlinkAtPath:_symlinkPath toPath:_absentFilePath];

  XCTAssertTrue([_fileManager fileExistsAtPath:_symlinkPath followLastSymlink:NO]);
}

- (void)testFileExistsAtPath_AbsentSymlink_returnsNO {
  XCTAssertFalse([_fileManager fileExistsAtPath:_symlinkPath followLastSymlink:NO]);
  XCTAssertFalse([_fileManager fileExistsAtPath:_symlinkPath followLastSymlink:YES]);
}

#pragma mark - Symlink to symlink to file

- (void)testFileExistsAtPath_FollowLastSymlink_ExistingSymlinkToSymlink_ExistingFinalSymlinkDestination_returnsYES {
  NSString* lastSymlinkPath = _symlinkPath;
  NSString* firstSymlinkPath = _symlinkToSymlinkPath;

  [self createSymlinkAtPath:lastSymlinkPath toPath:_realFilePath];
  [self createSymlinkAtPath:firstSymlinkPath toPath:lastSymlinkPath];

  XCTAssertTrue([_fileManager fileExistsAtPath:firstSymlinkPath followLastSymlink:YES]);
}

- (void)testFileExistsAtPath_FollowLastSymlink_ExistingSymlinkToSymlink_AbsentFinalSymlinkDestination_returnsNO {
  NSString* lastSymlinkPath = _symlinkPath;
  NSString* firstSymlinkPath = _symlinkToSymlinkPath;

  [self createSymlinkAtPath:lastSymlinkPath toPath:_absentFilePath];
  [self createSymlinkAtPath:firstSymlinkPath toPath:lastSymlinkPath];

  XCTAssertFalse([_fileManager fileExistsAtPath:firstSymlinkPath followLastSymlink:YES]);
}

- (void)testFileExistsAtPath_DoesNotFollowLastSymlink_ExistingSymlinkToSymlink_returnsYES {
  NSString* lastSymlinkPath = _symlinkPath;
  NSString* firstSymlinkPath = _symlinkToSymlinkPath;

  [self createSymlinkAtPath:lastSymlinkPath toPath:_absentFilePath];
  [self createSymlinkAtPath:firstSymlinkPath toPath:lastSymlinkPath];

  XCTAssertTrue([_fileManager fileExistsAtPath:firstSymlinkPath followLastSymlink:NO]);
}

#pragma mark - Intermediate symlink

- (void)testFileExistsAtPath_PathWithIntermediateSymlink_AlwaysFollowsIntermediateSymlink {
  NSString* directoryPath = [_sandboxPath stringByAppendingPathComponent:@"folder"];
  NSString* fileInDirectoryPath = [directoryPath stringByAppendingPathComponent:@"file"];

  [self createDirectoryAtPath:directoryPath];
  [self createFileAtPath:fileInDirectoryPath];
  [self createSymlinkAtPath:_symlinkPath toPath:directoryPath];

  NSString* filePathWithSymlink = [_symlinkPath stringByAppendingPathComponent:@"file"];

  XCTAssertTrue([_fileManager fileExistsAtPath:filePathWithSymlink followLastSymlink:NO]);
  XCTAssertTrue([_fileManager fileExistsAtPath:filePathWithSymlink followLastSymlink:YES]);
}

@end
