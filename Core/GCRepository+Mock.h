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

#import "GCRepository.h"

/*
 The notation for a mock commit hierarchy is described using a simple plain text format:

 m0 - m1<master> - m2 - m3[origin/master]
  \
  t0(m0) - t1 - t2{temp} - t3 - t4<topic>

 - Each line describes a series of commits to be created in order from left to right
 - Lines are processed in order from top to bottom
 - Empty lines or lines starting with "#" are ignored
 - A commit is formatted as "message(parents){tag}<local_branch>[remote_branch]"
  - "message" is required and *must* be unique (it *cannot* contain whitespace characters either)
  - "(parents)" is optional
   - If present, it must be a comma separated list of *previously* created commits identified by their messages
   - If not present and if the commit message has a numerical suffix greater than zero, then a single parent is automatically assumed by decrementing the suffix e.g. "foo12" -> "foo11"
  - "{tag}" is optional and if present indicates the name of a lightweight tag to be created that points to this commit
  - "<local_branch>" is optional and if present indicates the name of a local branch to be created that points to this commit
  - "[remote_branch]" is optional and if present indicates the name of a local branch to be created that points to this commit
  - The commit author and committer are always set to "user <user@domain.com>"
  - The commit date is automatically set to 2001-01-01 00:00:00 GMT for the very first commit created and increased by 1 second for each commit created afterwards
 - All whitespace and non-alphanumerical characters are ignored (for instance the "-" and "\" are only present to help visualizing the notation result)
*/

@interface GCRepository (Mock)
- (NSArray*)createMockCommitHierarchyFromNotation:(NSString*)notation force:(BOOL)force error:(NSError**)error;
@end

@interface GCHistory (Mock)
- (NSString*)notationFromMockCommitHierarchy;
- (GCHistoryCommit*)mockCommitWithName:(NSString*)name;
@end
