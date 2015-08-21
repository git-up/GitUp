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

typedef NS_ENUM(NSUInteger, GCConfigLevel) {
  kGCConfigLevel_System = 0,  // $(prefix)/etc/gitconfig: system-wide configuration file
  kGCConfigLevel_XDG,  // $XDG_CONFIG_HOME/git/config: second user-specific configuration file
  kGCConfigLevel_Global,  // ~/.gitconfig: user-specific configuration file
  kGCConfigLevel_Local  // $GIT_DIR/config: repository specific configuration file
};

@interface GCConfigOption : NSObject
@property(nonatomic, readonly) GCConfigLevel level;
@property(nonatomic, readonly) NSString* variable;  // Normalized to lower-case
@property(nonatomic, readonly) NSString* value;  // May be nil
@end

@interface GCRepository (GCConfig)
- (NSString*)findFilePathForConfigurationLevel:(GCConfigLevel)level error:(NSError**)error;

- (GCConfigOption*)readConfigOptionForVariable:(NSString*)variable error:(NSError**)error;
- (GCConfigOption*)readConfigOptionForLevel:(GCConfigLevel)level variable:(NSString*)variable error:(NSError**)error;
- (BOOL)writeConfigOptionForLevel:(GCConfigLevel)level variable:(NSString*)variable withValue:(NSString*)value error:(NSError**)error;  // Pass a nil value to delete the option

- (NSArray*)readConfigForLevel:(GCConfigLevel)level error:(NSError**)error;
- (NSArray*)readAllConfigs:(NSError**)error;  // Does not de-duplicate variables
@end
