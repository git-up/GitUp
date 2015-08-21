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

#import "GCDiff.h"

typedef NS_ENUM(NSUInteger, GCResetMode) {
  kGCResetMode_Soft = 0,
  kGCResetMode_Mixed,
  kGCResetMode_Hard
};

@interface GCRepository (Reset)
- (BOOL)resetToHEAD:(GCResetMode)mode error:(NSError**)error;  // git reset {--soft | --mixed | --hard} HEAD
- (BOOL)resetToTag:(GCTag*)tag mode:(GCResetMode)mode error:(NSError**)error;  // git reset {--soft | --mixed | --hard} {tag}
- (BOOL)resetToCommit:(GCCommit*)commit mode:(GCResetMode)mode error:(NSError**)error;  // git reset {--soft | --mixed | --hard} {commit}
@end
