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

@implementation GCSingleCommitRepositoryTests (GCRepository_Index)

- (void)testIndex {
  // Modify file in working directory and add to index
  [self updateFileAtPath:@"hello_world.txt" withString:@"Bonjour le monde!\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"hello_world.txt" error:NULL]);
  [self assertGitCLTOutputEqualsString:@"M  hello_world.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Read back file from index
  GCIndex* index = [self.repository readRepositoryIndex:NULL];
  XCTAssertNotNil(index);
  XCTAssertNil([self.repository readContentsForFile:@"hello-world.txt" inIndex:index error:NULL]);
  NSData* data = [self.repository readContentsForFile:@"hello_world.txt" inIndex:index error:NULL];
  XCTAssertEqualObjects(data, [@"Bonjour le monde!\n" dataUsingEncoding:NSUTF8StringEncoding]);
  
  // Remove file from index
  XCTAssertTrue([self.repository removeFileFromIndex:@"hello_world.txt" error:NULL]);
  [self assertGitCLTOutputEqualsString:@"D  hello_world.txt\n?? hello_world.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Add new file to working directory
  [self updateFileAtPath:@"test.txt" withString:@"This is a test\n"];
  
  // Add all working directory files to index
  XCTAssertTrue([self.repository addAllFilesToIndex:NULL]);
  [self assertGitCLTOutputEqualsString:@"M  hello_world.txt\nA  test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Delete / update working directory files
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"hello_world.txt"] error:NULL]);
  [self updateFileAtPath:@"test.txt" withString:@"This is another test\n"];
  XCTAssertTrue([self.repository removeFileFromIndex:@"hello_world.txt" error:NULL]);
  XCTAssertTrue([self.repository addFileToIndex:@"test.txt" error:NULL]);
  [self assertGitCLTOutputEqualsString:@"D  hello_world.txt\nA  test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Remove all files from index
  XCTAssertTrue([self.repository removeFileFromIndex:@"test.txt" error:NULL]);
  [self assertGitCLTOutputEqualsString:@"D  hello_world.txt\n?? test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Unstage deleted file
  XCTAssertTrue([self.repository resetFileInIndexToHEAD:@"hello_world.txt" error:NULL]);
  [self assertGitCLTOutputEqualsString:@" D hello_world.txt\n?? test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Restore deleted file from index to working directory
  XCTAssertTrue([self.repository checkoutFileFromIndex:@"hello_world.txt" error:NULL]);
  [self assertGitCLTOutputEqualsString:@"?? test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Re-add file to index
  XCTAssertTrue([self.repository addFileToIndex:@"test.txt" error:NULL]);
  [self assertGitCLTOutputEqualsString:@"A  test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Reset index
  XCTAssertTrue([self.repository resetIndexToHEAD:NULL]);
  [self assertGitCLTOutputEqualsString:@"?? test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
}

- (void)testIndex_Lines {
  // Create test multiline file and commit it
  NSMutableArray* content0 = [[NSMutableArray alloc] init];
  for (int i = 0; i < 1000; ++i) {
    [content0 addObject:[NSString stringWithFormat:@"Line %i", i + 1]];
  }
  [self makeCommitWithUpdatedFileAtPath:@"lines.txt" string:[content0 componentsJoinedByString:@"\n"] message:@"Update"];
  
  // Edit various lines in the file
  NSMutableArray* content1 = [content0 mutableCopy];
  [content1 replaceObjectAtIndex:799 withObject:@"Test"];  // Replace line 800
  [content1 removeObjectAtIndex:199];  // Delete line 200
  [content1 insertObject:@"Hello World!" atIndex:499];  // Add line 500
  [self updateFileAtPath:@"lines.txt" withString:[content1 componentsJoinedByString:@"\n"]];
  
  // Stage some lines
  XCTAssertTrue([self.repository addLinesFromFileToIndex:@"lines.txt" error:NULL usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
    if ((oldLineNumber == 200) || (newLineNumber == 500)) {
      return YES;
    }
    return NO;
  }]);
  NSString* output1 = @"\
--- a/lines.txt\n\
+++ b/lines.txt\n\
@@ -200 +199,0 @@ Line 199\n\
-Line 200\n\
@@ -500,0 +500 @@ Line 500\n\
+Hello World!\n\
";
  [self assertGitCLTOutputEndsWithString:output1 withRepository:self.repository command:@"diff", @"--cached", @"--unified=0", nil];
  NSString* output2 = @"\
--- a/lines.txt\n\
+++ b/lines.txt\n\
@@ -800 +800 @@ Line 799\n\
-Line 800\n\
+Test\n\
";
  [self assertGitCLTOutputEndsWithString:output2 withRepository:self.repository command:@"diff", @"--unified=0", nil];
  
  // Unstage some lines
  XCTAssertTrue([self.repository resetLinesFromFileInIndexToHEAD:@"lines.txt" error:NULL usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
    if (newLineNumber == 500) {
      return YES;
    }
    return NO;
  }]);
  NSString* output3 = @"\
--- a/lines.txt\n\
+++ b/lines.txt\n\
@@ -200 +199,0 @@ Line 199\n\
-Line 200\n\
";
  [self assertGitCLTOutputEndsWithString:output3 withRepository:self.repository command:@"diff", @"--cached", @"--unified=0", nil];
  NSString* output4 = @"\
--- a/lines.txt\n\
+++ b/lines.txt\n\
@@ -499,0 +500 @@ Line 500\n\
+Hello World!\n\
@@ -799 +800 @@ Line 799\n\
-Line 800\n\
+Test\n\
";
  [self assertGitCLTOutputEndsWithString:output4 withRepository:self.repository command:@"diff", @"--unified=0", nil];
  
  // Discard some lines
  XCTAssertTrue([self.repository checkoutLinesFromFileFromIndex:@"lines.txt" error:NULL usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
    if ((oldLineNumber == 799) || (newLineNumber == 800)) {
      return YES;
    }
    return NO;
  }]);
  NSString* output5 = @"\
--- a/lines.txt\n\
+++ b/lines.txt\n\
@@ -200 +199,0 @@ Line 199\n\
-Line 200\n\
";
  [self assertGitCLTOutputEndsWithString:output5 withRepository:self.repository command:@"diff", @"--cached", @"--unified=0", nil];
  NSString* output6 = @"\
--- a/lines.txt\n\
+++ b/lines.txt\n\
@@ -499,0 +500 @@ Line 500\n\
+Hello World!\n\
";
  [self assertGitCLTOutputEndsWithString:output6 withRepository:self.repository command:@"diff", @"--unified=0", nil];
}

@end

@implementation GCEmptyRepositoryTests (GCRepository_Index)

- (void)testIndex_Copies {
  GCFileMode mode;
  NSMutableArray* lines = [[NSMutableArray alloc] init];
  for (int i = 0; i < 10; ++i) {
    [lines addObject:[NSString stringWithFormat:@"Line %i", i + 1]];
  }
  NSData* data = [[lines componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
  
  GCIndex* index1 = [self.repository createInMemoryIndex:NULL];
  XCTAssertNotNil(index1);
  XCTAssertTrue(index1.empty);
  
  GCIndex* index2 = [self.repository createInMemoryIndex:NULL];
  XCTAssertNotNil(index2);
  XCTAssertTrue(index2.empty);
  
  XCTAssertTrue([self.repository addFile:@"lines.txt" withContents:data toIndex:index1 error:NULL]);
  XCTAssertFalse(index1.empty);
  XCTAssertNotNil([index1 SHA1ForFile:@"lines.txt" mode:&mode]);
  XCTAssertEqual(mode, kGCFileMode_Blob);
  
  XCTAssertTrue([self.repository copyFile:@"lines.txt" fromOtherIndex:index1 toIndex:index2 error:NULL]);
  XCTAssertFalse(index2.empty);
  XCTAssertNotNil([index2 SHA1ForFile:@"lines.txt" mode:&mode]);
  XCTAssertEqual(mode, kGCFileMode_Blob);
  
  XCTAssertTrue([self.repository clearIndex:index2 error:NULL]);
  XCTAssertTrue(index2.empty);
  XCTAssertNil([index2 SHA1ForFile:@"lines.txt" mode:NULL]);
  
  XCTAssertTrue([self.repository copyLinesInFile:@"lines.txt" fromOtherIndex:index1 toIndex:index2 error:NULL usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
    
    return (newLineNumber % 2);
    
  }]);
  XCTAssertFalse(index2.empty);
  NSData* data2 = [self.repository exportBlobWithOID:[index2 OIDForFile:@"lines.txt"] error:NULL];
  XCTAssertNotNil(data2);
  NSString* string2 = [[NSString alloc] initWithData:data2 encoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(string2, @"Line 1\nLine 3\nLine 5\nLine 7\nLine 9\n");
  
  XCTAssertTrue([self.repository clearIndex:index2 error:NULL]);
  [lines replaceObjectAtIndex:4 withObject:@"Line ?"];
  XCTAssertTrue([self.repository addFile:@"lines.txt" withContents:[[lines componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] toIndex:index2 error:NULL]);
  XCTAssertTrue([self.repository copyLinesInFile:@"lines.txt" fromOtherIndex:index1 toIndex:index2 error:NULL usingFilter:^BOOL(GCLineDiffChange change, NSUInteger oldLineNumber, NSUInteger newLineNumber) {
    
    return YES;
    
  }]);
  NSData* data3 = [self.repository exportBlobWithOID:[index2 OIDForFile:@"lines.txt"] error:NULL];
  XCTAssertNotNil(data3);
  NSString* string3 = [[NSString alloc] initWithData:data3 encoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(string3, @"Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10");
}

@end
