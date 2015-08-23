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

// We only test resetting to commit since resetting to HEAD or tag is the same implementation codepath
@implementation GCSingleCommitRepositoryTests (GCRepository_Reset)

- (void)testReset {
  // Modify and add files to working directory
  [self updateFileAtPath:@"hello_world.txt" withString:@"Bonjour le monde!\n"];
  [self updateFileAtPath:@"test.txt" withString:@"This is a test\n"];
  [self assertGitCLTOutputEqualsString:@" M hello_world.txt\n?? test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Hard reset
  XCTAssertTrue([self.repository resetToCommit:self.initialCommit mode:kGCResetMode_Hard error:NULL]);
  [self assertGitCLTOutputEqualsString:@"?? test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Modify file in working directory again
  [self updateFileAtPath:@"hello_world.txt" withString:@"Bonjour le monde!\n"];
  
  // Update index and commit changes
  XCTAssertTrue([self.repository addAllFilesToIndex:NULL]);
  GCCommit* commit = [self.repository createCommitFromHEADWithMessage:@"Update 1" error:NULL];
  XCTAssertNotNil(commit);
  [self assertGitCLTOutputEqualsString:@"" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
  
  // Soft reset
  XCTAssertTrue([self.repository resetToCommit:self.initialCommit mode:kGCResetMode_Soft error:NULL]);
  [self assertGitCLTOutputEqualsString:@"M  hello_world.txt\nA  test.txt\n" withRepository:self.repository command:@"status", @"--ignored", @"--porcelain", nil];
}

@end
