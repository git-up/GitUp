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

typedef NS_ENUM(NSUInteger, GCSubmoduleIgnoreMode) {
  kGCSubmoduleIgnoreMode_None = 0,  // Default in Git
  kGCSubmoduleIgnoreMode_Untracked,
  kGCSubmoduleIgnoreMode_Dirty,
  kGCSubmoduleIgnoreMode_All
};

typedef NS_ENUM(NSUInteger, GCSubmoduleFetchRecurseMode) {
  kGCSubmoduleFetchRecurseMode_No = 0,  // Default in Git
  kGCSubmoduleFetchRecurseMode_Yes,
  kGCSubmoduleFetchRecurseMode_OnDemand  // Only fetch if superproject points to an unknown submodule commit
};

typedef NS_ENUM(NSUInteger, GCSubmoduleUpdateMode) {
  kGCSubmoduleUpdateMode_None = 0,
  kGCSubmoduleUpdateMode_Checkout,  // Default in Git
  kGCSubmoduleUpdateMode_Rebase,
  kGCSubmoduleUpdateMode_Merge,
};

@interface GCSubmodule : NSObject
@property(nonatomic, readonly) GCRepository* repository;  // NOT RETAINED
@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) NSString* path;
@property(nonatomic, readonly) NSURL* URL;  // May be nil
@property(nonatomic, readonly) NSString* remoteBranchName;  // From .gitmodules (may be nil)
@property(nonatomic, readonly) GCSubmoduleIgnoreMode ignoreMode;  // From .gitmodules
@property(nonatomic, readonly) GCSubmoduleFetchRecurseMode fetchRecurseMode;  // From .gitmodules
@property(nonatomic, readonly) GCSubmoduleUpdateMode updateMode;  // From .gitmodules
@end

@interface GCRepository (GCSubmodule)
- (instancetype)initWithSubmodule:(GCSubmodule*)submodule error:(NSError**)error;  // (?)

- (BOOL)checkSubmoduleInitialized:(GCSubmodule*)submodule error:(NSError**)error;  // (?)
- (BOOL)checkAllSubmodulesInitialized:(BOOL)recursive error:(NSError**)error;  // (?)

- (GCSubmodule*)addSubmoduleWithURL:(NSURL*)url atPath:(NSString*)path recursive:(BOOL)recursive error:(NSError**)error;  // git submodule add {url} {path}
- (BOOL)initializeSubmodule:(GCSubmodule*)submodule recursive:(BOOL)recursive error:(NSError**)error;  // git submodule update --init {--recursive} {path}
- (BOOL)initializeAllSubmodules:(BOOL)recursive error:(NSError**)error;  // git submodule update --init {--recursive} - This will skip already initialized submodules

- (GCSubmodule*)lookupSubmoduleWithName:(NSString*)name error:(NSError**)error;  // git submodule
- (NSArray*)listSubmodules:(NSError**)error;  // git submodule
- (BOOL)updateSubmodule:(GCSubmodule*)submodule force:(BOOL)force error:(NSError**)error;  // git submodule update {--force} {submodule}
- (BOOL)updateAllSubmodulesResursively:(BOOL)force error:(NSError**)error;  // git submodule update --recursive {--force} (except this does not fetch) - This will skip uninitialized submodules

- (BOOL)addSubmoduleToRepositoryIndex:(GCSubmodule*)submodule error:(NSError**)error;  // git add {submodule}
@end
