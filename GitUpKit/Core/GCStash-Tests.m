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

// TODO: Test stash file list and content diff
@implementation GCSingleCommitRepositoryTests (GCStash)

- (void)testStashes {
  // Add new file to working directory and commit it
  GCCommit* commit = [self makeCommitWithUpdatedFileAtPath:@"foo.txt" string:@"Guten Tag\n" message:@"Added file"];
  
  // Attempt to stash no changes
  GCStash* stash0 = [self.repository saveStashWithMessage:@"Just testing" keepIndex:NO includeUntracked:NO error:NULL];
  XCTAssertNil(stash0);
  
  // Modify file in working directory
  [self updateFileAtPath:@"hello_world.txt" withString:@"Bonjour le monde!\n"];
  
  // Save stash
  GCStash* stash1 = [self.repository saveStashWithMessage:@"Just testing" keepIndex:NO includeUntracked:NO error:NULL];
  XCTAssertTrue([stash1.message rangeOfString:@"Just testing"].location != NSNotFound);
  XCTAssertEqualObjects(stash1.baseCommit, commit);
  XCTAssertNotNil(stash1.indexCommit);
  XCTAssertNil(stash1.untrackedCommit);
  XCTAssertEqualObjects([self.repository listStashes:NULL], @[stash1]);
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  
  // Attempt to pop stash on top of re-modified file
  [self updateFileAtPath:@"hello_world.txt" withString:@"Hola Mundo!\n"];
  XCTAssertFalse([self.repository popStash:stash1 restoreIndex:NO error:NULL]);
  XCTAssertTrue([self.repository checkoutFileFromIndex:@"hello_world.txt" error:NULL]);
  
  // Pop stash
  XCTAssertTrue([self.repository popStash:stash1 restoreIndex:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@" M hello_world.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Add new file to working directory
  [self updateFileAtPath:@"test.txt" withString:@"This is a test\n"];
  
  // Save stash
  GCStash* stash2 = [self.repository saveStashWithMessage:@"Testing again" keepIndex:NO includeUntracked:YES error:NULL];
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  
  // Attempt to pop stash on top of re-modified new file
  [self updateFileAtPath:@"test.txt" withString:@"Nothing to see here\n"];
  XCTAssertFalse([self.repository popStash:stash2 restoreIndex:NO error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"test.txt"] error:NULL]);
  
  // Pop stash
  XCTAssertTrue([self.repository popStash:stash2 restoreIndex:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@" M hello_world.txt\n?? test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Add modified file to index
  XCTAssertTrue([self.repository addFileToIndex:@"hello_world.txt" error:NULL]);
  
  // Add new file to index
  [self updateFileAtPath:@"bar.txt" withString:@"Bar\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"bar.txt" error:NULL]);
  
  // Modify other file
  [self updateFileAtPath:@"foo.txt" withString:@"Welt\n"];
  
  // Save stash
  GCStash* stash3 = [self.repository saveStashWithMessage:@"Testing again" keepIndex:NO includeUntracked:YES error:NULL];
  XCTAssertFalse([self.repository checkRepositoryDirty:YES]);
  
  // Apply stash - TODO: https://github.com/libgit2/libgit2/issues/3230
  XCTAssertTrue([self.repository applyStash:stash3 restoreIndex:NO error:NULL]);
  [self assertGitCLTOutputEqualsString:@"A  bar.txt\n M foo.txt\n M hello_world.txt\n?? test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit mode:kGCResetMode_Hard error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self.repository.workingDirectoryPath stringByAppendingPathComponent:@"test.txt"] error:NULL]);
  
  // Add modified file to index
  [self updateFileAtPath:@"hello_world.txt" withString:@"Hola Mundo!\n"];
  XCTAssertTrue([self.repository addFileToIndex:@"hello_world.txt" error:NULL]);
  
  // Attempt to apply stash again and restore index on top of modified index
  XCTAssertFalse([self.repository applyStash:stash3 restoreIndex:YES error:NULL]);
  
  // Attempt to apply stash again on top of modified index but don't restore index
  XCTAssertFalse([self.repository applyStash:stash3 restoreIndex:NO error:NULL]);
  
  // Reset
  XCTAssertTrue([self.repository resetToCommit:commit mode:kGCResetMode_Hard error:NULL]);
  
  // Apply stash again and restore index
  XCTAssertTrue([self.repository applyStash:stash3 restoreIndex:YES error:NULL]);
  [self assertGitCLTOutputEqualsString:@"A  bar.txt\n M foo.txt\nM  hello_world.txt\n?? test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Drop stash
  XCTAssertTrue([self.repository dropStash:stash3 error:NULL]);
  
  // Check stash list
  XCTAssertEqualObjects([self.repository listStashes:NULL], @[]);
}

@end
