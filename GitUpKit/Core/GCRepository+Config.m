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

#import "GCPrivate.h"

static inline GCConfigLevel _ConfigLevelFromLevel(git_config_level_t level) {
  switch (level) {
    case GIT_CONFIG_LEVEL_PROGRAMDATA: break;
    case GIT_CONFIG_LEVEL_SYSTEM: return kGCConfigLevel_System;
    case GIT_CONFIG_LEVEL_XDG: return kGCConfigLevel_XDG;
    case GIT_CONFIG_LEVEL_GLOBAL: return kGCConfigLevel_Global;
    case GIT_CONFIG_LEVEL_LOCAL: return kGCConfigLevel_Local;
#if DEBUG
    case GIT_CONFIG_LEVEL_APP: return kGCConfigLevel_XDG;  // For unit tests only
#else
    case GIT_CONFIG_LEVEL_APP: break;
#endif
    case GIT_CONFIG_HIGHEST_LEVEL: break;
  }
  XLOG_DEBUG_UNREACHABLE();
  return 0;
}

static inline git_config_level_t _ConfigLevelToLevel(GCConfigLevel level) {
  switch (level) {
    case kGCConfigLevel_System: return GIT_CONFIG_LEVEL_SYSTEM;
    case kGCConfigLevel_XDG: return GIT_CONFIG_LEVEL_XDG;
    case kGCConfigLevel_Global: return GIT_CONFIG_LEVEL_GLOBAL;
    case kGCConfigLevel_Local: return GIT_CONFIG_LEVEL_LOCAL;
  }
  XLOG_DEBUG_UNREACHABLE();
  return 0;
}

@implementation GCConfigOption

- (id)initWithLevel:(GCConfigLevel)level variable:(NSString*)variable value:(NSString*)value {
  if ((self = [super init])) {
    _level = level;
    _variable = variable;
    _value = value;
  }
  return self;
}

- (id)initWithEntry:(const git_config_entry*)entry {
  return [self initWithLevel:_ConfigLevelFromLevel(entry->level) variable:[NSString stringWithUTF8String:entry->name] value:[NSString stringWithUTF8String:entry->value]];
}

- (NSString*)description {
  const char* levels[] = {"System", "XDG", "Global", "Local"};
  return [NSString stringWithFormat:@"[%s] %@ = \"%@\"", levels[_level], _variable, _value];
}

@end

@implementation GCRepository (GCConfig)

static inline int _FindConfig(git_repository* repo, GCConfigLevel level, git_buf* buffer) {
  switch (level) {
    case kGCConfigLevel_System: return git_config_find_system(buffer);
    case kGCConfigLevel_XDG: return git_config_find_xdg(buffer);
    case kGCConfigLevel_Global: return git_config_find_global(buffer);
    case kGCConfigLevel_Local: return git_config_find_local(repo, buffer);
  }
  return GIT_ERROR;
}

- (NSString*)findFilePathForConfigurationLevel:(GCConfigLevel)level error:(NSError**)error {
  git_buf buffer = {0};
  CALL_LIBGIT2_FUNCTION_RETURN(nil, _FindConfig, self.private, level, &buffer);
  NSString* path = [NSString stringWithUTF8String:buffer.ptr];
  git_buf_free(&buffer);
  return path;
}

- (GCConfigOption*)readConfigOptionForVariable:(NSString*)variable error:(NSError**)error {
  return [self readConfigOptionForLevel:NSNotFound variable:variable error:error];
}

- (GCConfigOption*)readConfigOptionForLevel:(GCConfigLevel)level variable:(NSString*)variable error:(NSError**)error {
  GCConfigOption* option = nil;
  git_config* multiConfig = NULL;
  git_config* levelConfig = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_config, &multiConfig, self.private);
  git_config_entry* entry;
  if (level == (GCConfigLevel)NSNotFound) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_get_entry, &entry, multiConfig, variable.UTF8String);
  } else {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_open_level, &levelConfig, multiConfig, _ConfigLevelToLevel(level));
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_get_entry, &entry, levelConfig, variable.UTF8String);
  }
  option = [[GCConfigOption alloc] initWithEntry:entry];
  git_config_entry_free(entry);
  
cleanup:
  git_config_free(levelConfig);
  git_config_free(multiConfig);
  return option;
}

- (BOOL)writeConfigOptionForLevel:(GCConfigLevel)level variable:(NSString*)variable withValue:(NSString*)value error:(NSError**)error {
  BOOL success = NO;
  git_config* multiConfig = NULL;
  git_config* levelConfig = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_config, &multiConfig, self.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_open_level, &levelConfig, multiConfig, _ConfigLevelToLevel(level));
  if (value) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_set_string, levelConfig, variable.UTF8String, value.UTF8String);  // git_config_set_string() is the primitive
  } else {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_delete_entry, levelConfig, variable.UTF8String);
  }
  success = YES;
  
cleanup:
  git_config_free(levelConfig);
  git_config_free(multiConfig);
  return success;
}

static NSArray* _ReadConfig(git_config* config, NSError** error) {
  BOOL success = NO;
  NSMutableArray* array = [NSMutableArray array];
  git_config_iterator* iterator = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_iterator_new, &iterator, config);  // This takes a snapshot internally
  while (1) {
    git_config_entry* entry;
    int status = git_config_next(&entry, iterator);
    if (status == GIT_ITEROVER) {
      break;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
    [array addObject:[[GCConfigOption alloc] initWithEntry:entry]];
  }
  success = YES;
  
cleanup:
  git_config_iterator_free(iterator);
  return success ? array : nil;
}

- (NSArray*)readConfigForLevel:(GCConfigLevel)level error:(NSError**)error {
  NSArray* array = nil;
  git_config* config1 = NULL;
  git_config* config2 = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_config, &config1, self.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_open_level, &config2, config1, _ConfigLevelToLevel(level));
  array = _ReadConfig(config2, error);
  
cleanup:
  git_config_free(config1);
  git_config_free(config2);
  return array;
}

- (NSArray*)readAllConfigs:(NSError**)error {
  NSArray* array = nil;
  git_config* config = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_config, &config, self.private);
  array = _ReadConfig(config, error);
  
cleanup:
  git_config_free(config);
  return array;
}

@end
