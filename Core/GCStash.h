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

#import "GCCommit.h"

@interface GCStash : GCCommit
@property(nonatomic, readonly) GCCommit* baseCommit;
@property(nonatomic, readonly) GCCommit* indexCommit;
@property(nonatomic, readonly) GCCommit* untrackedCommit;  // May be nil
@end

@interface GCStashState : NSObject
@end

@interface GCRepository (GCStash)
- (GCStash*)saveStashWithMessage:(NSString*)message keepIndex:(BOOL)keepIndex includeUntracked:(BOOL)includeUntracked error:(NSError**)error;  // git stash {-k} {-u}
- (NSArray*)listStashes:(NSError**)error;  // git stash list
- (BOOL)applyStash:(GCStash*)stash restoreIndex:(BOOL)restoreIndex error:(NSError**)error;  // git stash apply {--index} {stash}
- (BOOL)dropStash:(GCStash*)stash error:(NSError**)error;  // git stash drop {stash}
- (BOOL)popStash:(GCStash*)stash restoreIndex:(BOOL)restoreIndex error:(NSError**)error;  // git stash pop {--index} {stash}

- (GCStashState*)saveStashState:(NSError**)error;
- (BOOL)restoreStashState:(GCStashState*)state error:(NSError**)error;
@end
