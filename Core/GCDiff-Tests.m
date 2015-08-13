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

#import "GCTestCase.h"
#import "GCRepository+Index.h"

@implementation GCSingleCommitRepositoryTests (GCRepository_Diffs)

- (NSString*)_stringFromDiff:(GCDiff*)diff includeFile:(BOOL)includeFile {
  NSMutableString* string = [[NSMutableString alloc] init];
  for (GCDiffDelta* delta in diff.deltas) {
    if (includeFile) {
      [string appendFormat:@"%@ > %@\n", delta.oldFile.path, delta.newFile.path];
    }
    GCDiffPatch* patch = [self.repository makePatchForDiffDelta:delta isBinary:NULL error:NULL];
    [patch enumerateUsingBeginHunkHandler:NULL lineHandler:^(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber, const char* contentBytes, NSUInteger contentLength) {
      switch (change) {
        case kGCLineDiffChange_Unmodified: [string appendString:@"  "]; break;
        case kGCLineDiffChange_Added: [string appendString:@"+ "]; break;
        case kGCLineDiffChange_Deleted: [string appendString:@"- "]; break;
      }
      NSString* line = [[NSString alloc] initWithBytes:contentBytes length:contentLength encoding:NSUTF8StringEncoding];
      [string appendString:line];
    } endHunkHandler:NULL];
  }
  return string;
}

- (NSString*)_stringFromDiffingFileInWorkingDirectoryWithIndex:(NSString*)path {
  GCDiff* diff = [self.repository diffWorkingDirectoryWithRepositoryIndex:path options:kGCDiffOption_IncludeUntracked maxInterHunkLines:0 maxContextLines:0 error:NULL];
  return [self _stringFromDiff:diff includeFile:NO];
}

- (NSString*)_stringFromDiffingFileInIndexWithHEAD:(NSString*)path {
  GCDiff* diff = [self.repository diffRepositoryIndexWithHEAD:path options:0 maxInterHunkLines:0 maxContextLines:0 error:NULL];
  return [self _stringFromDiff:diff includeFile:NO];
}

- (NSString*)_stringFromDiffingWorkingDirectoryWithIndex {
  GCDiff* diff = [self.repository diffWorkingDirectoryWithRepositoryIndex:nil options:kGCDiffOption_IncludeUntracked maxInterHunkLines:0 maxContextLines:0 error:NULL];
  return [self _stringFromDiff:diff includeFile:YES];
}

- (NSString*)_stringFromDiffingIndexWithHEAD {
  GCDiff* diff = [self.repository diffRepositoryIndexWithHEAD:nil options:0 maxInterHunkLines:0 maxContextLines:0 error:NULL];
  return [self _stringFromDiff:diff includeFile:YES];
}

- (void)testDiffs {
  // Make sure we have no diffs
  XCTAssertEqualObjects([self _stringFromDiffingFileInWorkingDirectoryWithIndex:@"hello_world.txt"], @"");
  XCTAssertEqualObjects([self _stringFromDiffingFileInIndexWithHEAD:@"hello_world.txt"], @"");
  XCTAssertEqualObjects([self _stringFromDiffingWorkingDirectoryWithIndex], @"");
  XCTAssertEqualObjects([self _stringFromDiffingIndexWithHEAD], @"");
  
  // Modify file in working directory
  [self updateFileAtPath:@"hello_world.txt" withString:@"Bonjour le monde!\n"];
  XCTAssertEqualObjects([self _stringFromDiffingFileInWorkingDirectoryWithIndex:@"hello_world.txt"], @"- Hello World!\n+ Bonjour le monde!\n");
  XCTAssertEqualObjects([self _stringFromDiffingFileInIndexWithHEAD:@"hello_world.txt"], @"");
  XCTAssertEqualObjects([self _stringFromDiffingWorkingDirectoryWithIndex], @"hello_world.txt > hello_world.txt\n- Hello World!\n+ Bonjour le monde!\n");
  XCTAssertEqualObjects([self _stringFromDiffingIndexWithHEAD], @"");
  
  // Add modified file to index
  XCTAssertTrue([self.repository addFileToIndex:@"hello_world.txt" error:NULL]);
  XCTAssertEqualObjects([self _stringFromDiffingFileInWorkingDirectoryWithIndex:@"hello_world.txt"], @"");
  XCTAssertEqualObjects([self _stringFromDiffingFileInIndexWithHEAD:@"hello_world.txt"], @"- Hello World!\n+ Bonjour le monde!\n");
  XCTAssertEqualObjects([self _stringFromDiffingWorkingDirectoryWithIndex], @"");
  XCTAssertEqualObjects([self _stringFromDiffingIndexWithHEAD], @"hello_world.txt > hello_world.txt\n- Hello World!\n+ Bonjour le monde!\n");
  
  // Add new file to working directory
  [self updateFileAtPath:@"test.txt" withString:@"This is a test\n"];
  XCTAssertEqualObjects([self _stringFromDiffingFileInWorkingDirectoryWithIndex:@"test.txt"], @"+ This is a test\n");
  XCTAssertEqualObjects([self _stringFromDiffingFileInIndexWithHEAD:@"test.txt"], @"");
  XCTAssertEqualObjects([self _stringFromDiffingWorkingDirectoryWithIndex], @"test.txt > (null)\n+ This is a test\n");
  XCTAssertEqualObjects([self _stringFromDiffingIndexWithHEAD], @"hello_world.txt > hello_world.txt\n- Hello World!\n+ Bonjour le monde!\n");
  
  // Add new file to index
  XCTAssertTrue([self.repository addFileToIndex:@"test.txt" error:NULL]);
  XCTAssertEqualObjects([self _stringFromDiffingFileInWorkingDirectoryWithIndex:@"test.txt"], @"");
  XCTAssertEqualObjects([self _stringFromDiffingFileInIndexWithHEAD:@"test.txt"], @"+ This is a test\n");
  XCTAssertEqualObjects([self _stringFromDiffingWorkingDirectoryWithIndex], @"");
  XCTAssertEqualObjects([self _stringFromDiffingIndexWithHEAD], @"hello_world.txt > hello_world.txt\n- Hello World!\n+ Bonjour le monde!\n(null) > test.txt\n+ This is a test\n");
  
  // Strip trailing newline from file in working directory
  [self updateFileAtPath:@"hello_world.txt" withString:@"Bonjour le monde!"];
  XCTAssertEqualObjects([self _stringFromDiffingFileInWorkingDirectoryWithIndex:@"hello_world.txt"], @"- Bonjour le monde!\n+ Bonjour le monde!");
  
  // Commit changes
  XCTAssertTrue([self.repository addFileToIndex:@"hello_world.txt" error:NULL]);
  GCCommit* newCommit = [self.repository createCommitFromHEADWithMessage:@"Update" error:NULL];
  XCTAssertNotNil(newCommit);
  
  // Diff commits
  GCDiff* diff = [self.repository diffCommit:newCommit
                                  withCommit:self.initialCommit
                                 filePattern:nil
                                     options:(kGCDiffOption_FindRenames | kGCDiffOption_FindCopies)
                           maxInterHunkLines:0
                             maxContextLines:0
                                       error:NULL];
  XCTAssertNotNil(diff);
  XCTAssertEqual(diff.deltas.count, 2);
  __block int count = 0;
  for (GCDiffDelta* delta in diff.deltas) {
    GCDiffPatch* patch = [self.repository makePatchForDiffDelta:delta isBinary:NULL error:NULL];
    XCTAssertNotNil(patch);
    [patch enumerateUsingBeginHunkHandler:^(NSUInteger oldLineNumber, NSUInteger oldLineCount, NSUInteger newLineNumber, NSUInteger newLineCount) {
      ++count;  // 2 x 1 hunks
    } lineHandler:^(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber, const char* contentBytes, NSUInteger contentLength) {
      ++count;  // 2 + 1 lines
    } endHunkHandler:^{
      ;
    }];
  }
  XCTAssertEqual(count, 5);
  
  // Diff commits again
  GCDiff* diff2 = [self.repository diffCommit:newCommit
                                   withCommit:self.initialCommit
                                  filePattern:nil
                                      options:(kGCDiffOption_FindRenames | kGCDiffOption_FindCopies)
                            maxInterHunkLines:0
                              maxContextLines:0
                                        error:NULL];
  XCTAssertNotNil(diff2);
  XCTAssertTrue([diff2 isEqualToDiff:diff]);
}

- (void)testUnifiedDiff {
  // Add some files & commit changes
  [self updateFileAtPath:@".gitignore" withString:@"ignored.txt\n"];
  XCTAssertTrue([self.repository addFileToIndex:@".gitignore" error:NULL]);
  [self updateFileAtPath:@"modified.txt" withString:@""];
  XCTAssertTrue([self.repository addFileToIndex:@"modified.txt" error:NULL]);
  [self updateFileAtPath:@"deleted.txt" withString:@""];
  XCTAssertTrue([self.repository addFileToIndex:@"deleted.txt" error:NULL]);
  [self updateFileAtPath:@"renamed1.txt" withString:@"Nothing to see here!"];
  XCTAssertTrue([self.repository addFileToIndex:@"renamed1.txt" error:NULL]);
  [self updateFileAtPath:@"type-changed.txt" withString:@""];
  XCTAssertTrue([self.repository addFileToIndex:@"type-changed.txt" error:NULL]);
  XCTAssertNotNil([self.repository createCommitFromHEADWithMessage:@"Update" error:NULL]);
  
  // Touch files
  [self updateFileAtPath:@"ignored.txt" withString:@""];
  [self updateFileAtPath:@"modified.txt" withString:@"Hi there!"];
  [self updateFileAtPath:@"added.txt" withString:@"This is a test"];
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"deleted.txt"] error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] moveItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"renamed1.txt"] toPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"renamed2.txt"] error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"type-changed.txt"] error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"type-changed.txt"] withDestinationPath:@"hello_world.txt" error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"hello_world.txt"] toPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"copied.txt"] error:NULL]);
  
  // Stage some files
  XCTAssertTrue([self.repository addFileToIndex:@"modified.txt" error:NULL]);
  XCTAssertTrue([self.repository removeFileFromIndex:@"deleted.txt" error:NULL]);
  XCTAssertTrue([self.repository removeFileFromIndex:@"renamed1.txt" error:NULL]);
  XCTAssertTrue([self.repository addFileToIndex:@"renamed2.txt" error:NULL]);
  XCTAssertTrue([self.repository addFileToIndex:@"added.txt" error:NULL]);
  
  GCDiff* diff = [self.repository diffWorkingDirectoryWithHEAD:nil
                                                       options:(kGCDiffOption_FindTypeChanges | kGCDiffOption_FindRenames | kGCDiffOption_FindCopies | kGCDiffOption_IncludeUnmodified | kGCDiffOption_IncludeUntracked | kGCDiffOption_IncludeIgnored)
                                             maxInterHunkLines:0
                                               maxContextLines:3
                                                         error:NULL];
  XCTAssertNotNil(diff);
  XCTAssertEqual([diff changeForFile:@".gitignore"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([diff changeForFile:@"added.txt"], kGCFileDiffChange_Added);
  XCTAssertEqual([diff changeForFile:@"copied.txt"], kGCFileDiffChange_Copied);
  XCTAssertEqual([diff changeForFile:@"deleted.txt"], kGCFileDiffChange_Deleted);
  XCTAssertEqual([diff changeForFile:@"hello_world.txt"], kGCFileDiffChange_Unmodified);
  XCTAssertEqual([diff changeForFile:@"ignored.txt"], kGCFileDiffChange_Ignored);
  XCTAssertEqual([diff changeForFile:@"modified.txt"], kGCFileDiffChange_Modified);
  XCTAssertEqual([diff changeForFile:@"renamed1.txt"], NSNotFound);  // ?
  XCTAssertEqual([diff changeForFile:@"renamed2.txt"], kGCFileDiffChange_Renamed);
  XCTAssertEqual([diff changeForFile:@"type-changed.txt"], kGCFileDiffChange_TypeChanged);
}

- (void)testDiffFileExport {
  GCDiff* diff = [self.repository diffWorkingDirectoryWithHEAD:nil options:kGCDiffOption_IncludeUnmodified maxInterHunkLines:0 maxContextLines:0 error:NULL];
  XCTAssertNotNil(diff);
  XCTAssertEqual(diff.deltas.count, 1);
  GCDiffDelta* delta = diff.deltas[0];
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  XCTAssertTrue([self.repository exportBlobWithSHA1:delta.oldFile.SHA1 toPath:path error:NULL]);
}

- (void)testDiffIndexes {
  GCIndex* repositoryIndex = [self.repository readRepositoryIndex:NULL];
  XCTAssertNotNil(repositoryIndex);
  GCIndex* memoryIndex = [self.repository createInMemoryIndex:NULL];
  XCTAssertNotNil(memoryIndex);
  GCDiff* diff = [self.repository diffIndex:memoryIndex withIndex:repositoryIndex filePattern:nil options:0 maxInterHunkLines:0 maxContextLines:0 error:NULL];
  XCTAssertNotNil(diff);
  XCTAssertEqual(diff.deltas.count, 1);
  GCDiffDelta* delta = diff.deltas[0];
  XCTAssertEqual(delta.change, kGCFileDiffChange_Deleted);
  XCTAssertEqualObjects(delta.canonicalPath, @"hello_world.txt");
}

@end
