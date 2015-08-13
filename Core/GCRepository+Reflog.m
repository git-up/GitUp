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

#if __has_feature(objc_arc)
#error This file requires MRC
#endif

#import "GCPrivate.h"

@implementation GCReflogEntry {
  GCRepository* _repository;
  NSMutableArray* _references;
  NSMutableArray* _messages;
  git_oid _fromOID;
  git_oid _toOID;
  git_time _time;
}

static inline GCCommit* _LoadCommit(GCRepository* repository, const git_oid* oid) {
  git_commit* commit;
  int status = git_commit_lookup(&commit, repository.private, oid);
  if (status != GIT_OK) {
    XLOG_WARNING(@"Unable to find commit %s in \"%@\" (%i): %@", git_oid_tostr_s(oid), repository.repositoryPath, status, GetLastGitErrorMessage());
    return nil;
  }
  return [[GCCommit alloc] initWithRepository:repository commit:commit];
}

- (id)initWithRepository:(GCRepository*)repository entry:(const git_reflog_entry*)entry {
  if ((self = [super init])) {
    _repository = repository;
    
    git_oid_cpy(&_fromOID, git_reflog_entry_id_old(entry));
    if (!git_oid_iszero(&_fromOID)) {
      _fromSHA1 = [GCGitOIDToSHA1(&_fromOID) retain];
      _fromCommit = _LoadCommit(_repository, &_fromOID);
    }
    git_oid_cpy(&_toOID, git_reflog_entry_id_new(entry));
    if (!git_oid_iszero(&_toOID)) {
      _toSHA1 = [GCGitOIDToSHA1(&_toOID) retain];
      _toCommit = _LoadCommit(_repository, &_toOID);
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }
    const git_signature* signature = git_reflog_entry_committer(entry);
    _time = signature->when;
    _committerName = [[NSString alloc] initWithUTF8String:signature->name];
    _committerEmail = [[NSString alloc] initWithUTF8String:signature->email];
    
    _references = [[NSMutableArray alloc] init];
    _messages = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  [_fromSHA1 release];
  [_fromCommit release];
  [_toSHA1 release];
  [_toCommit release];
  [_committerName release];
  [_committerEmail release];
  
  [_references release];
  [_messages release];
  
  [super dealloc];
}

- (const git_oid*)fromOID {
  return &_fromOID;
}

- (const git_oid*)toOID {
  return &_toOID;
}

- (NSDate*)date {
  return [NSDate dateWithTimeIntervalSince1970:_time.time];
}

- (NSTimeZone*)timeZone {
  return [NSTimeZone timeZoneForSecondsFromGMT:(_time.offset * 60)];
}

static inline BOOL _CStringHasPrefix(const char* string, const char* prefix) {
  return !strncmp(string, prefix, strlen(prefix));
}

static inline GCReflogActions _ActionsFromMessage(const char* message) {
  
  if (_CStringHasPrefix(message, kGCReflogCustomPrefix)) {
    return kGCReflogAction_GitUp;
  }
  
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Commit)) {
    return kGCReflogAction_Commit;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Commit_Initial)) {
    return kGCReflogAction_InitialCommit;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Commit_Amend)) {
    return kGCReflogAction_AmendCommit;
  }
  
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Checkout)) {
    return kGCReflogAction_Checkout;
  }
  
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Branch_Created)) {
    return kGCReflogAction_CreateBranch;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Branch_Renamed)) {
    return kGCReflogAction_RenameBranch;
  }
  
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Merge)) {
    return kGCReflogAction_Merge;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Reset)) {
    return kGCReflogAction_Reset;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Rebase)) {
    return kGCReflogAction_Rebase;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_CherryPick)) {
    return kGCReflogAction_CherryPick;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Revert)) {
    return kGCReflogAction_Revert;
  }
  
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Fetch)) {
    return kGCReflogAction_Fetch;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Push)) {
    return kGCReflogAction_Push;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Pull)) {
    return kGCReflogAction_Pull;
  }
  if (_CStringHasPrefix(message, kGCReflogMessagePrefix_Git_Clone)) {
    return kGCReflogAction_Clone;
  }
  
  return 0;
}

- (void)addReference:(GCReference*)reference withMessage:(const char*)message {
  XLOG_DEBUG_CHECK(reference.repository == _repository);
  NSString* string = message ? [NSString stringWithUTF8String:message] : @"";
  NSUInteger index = [_references indexOfObject:reference];
  if (index == NSNotFound) {
    [_references addObject:reference];
    [_messages addObject:string];
  } else if (![_messages[index] isEqualToString:string]) {
    XLOG_WARNING(@"Reflog for reference '%@' has mismatching entries", reference.name);
  }
  if (message && message[0]) {
    _actions |= _ActionsFromMessage(message);
  }
}

- (NSComparisonResult)reverseTimeCompare:(GCReflogEntry*)entry {
  git_time_t time1 = _time.time;
  git_time_t time2 = entry->_time.time;
  if (time1 < time2) {
    return NSOrderedDescending;
  } else if (time1 > time2) {
    return NSOrderedAscending;
  }
  return NSOrderedSame;
}

- (NSString*)description {
  NSMutableString* string = [NSMutableString stringWithFormat:@"%@ -> %@", _fromSHA1, _toSHA1];
  NSUInteger index = 0;
  for (GCReference* reference in _references) {
    [string appendFormat:@"\n  %@: %@", reference.fullName, _messages[index]];
    ++index;
  }
  return string;
}

static inline BOOL _EqualEntries(GCReflogEntry* entry1, GCReflogEntry* entry2) {
  return git_oid_equal(&entry1->_fromOID, &entry2->_fromOID) && git_oid_equal(&entry1->_toOID, &entry2->_toOID) && (entry1->_time.time == entry2->_time.time);
}

static Boolean _EntryEqualCallBack(const void* value1, const void* value2) {
  GCReflogEntry* entry1 = (GCReflogEntry*)value1;
  GCReflogEntry* entry2 = (GCReflogEntry*)value2;
  return _EqualEntries(entry1, entry2);
}

static CFHashCode _EntryHashCallBack(const void* value) {
  GCReflogEntry* entry = (GCReflogEntry*)value;
  return *((CFHashCode*)&entry->_fromOID);
}

@end

@implementation GCReflogEntry (Extensions)

- (BOOL)isEqualToReflogEntry:(GCReflogEntry*)entry {
  return (self == entry) || _EqualEntries(self, entry);
}

- (BOOL)isEqual:(id)object {
  if (![object isKindOfClass:[GCReflogEntry class]]) {
    return NO;
  }
  return [self isEqualToReflogEntry:object];
}

@end

@implementation GCRepository (Reflog)

- (NSArray*)loadReflogEntriesForReference:(GCReference*)reference error:(NSError**)error {
  NSMutableArray* entries = [[NSMutableArray alloc] init];
  if (git_reference_has_log(self.private, git_reference_name(reference.private))) {
    git_reflog* reflog;
    CALL_LIBGIT2_FUNCTION_RETURN(nil, git_reflog_read, &reflog, self.private, git_reference_name(reference.private));
    for (size_t i = 0, count = git_reflog_entrycount(reflog); i < count; ++i) {
      const git_reflog_entry* entry = git_reflog_entry_byindex(reflog, i);
      if (!git_oid_equal(git_reflog_entry_id_new(entry), git_reflog_entry_id_old(entry))) {  // Skip no-op entries
        GCReflogEntry* reflogEntry = [[GCReflogEntry alloc] initWithRepository:self entry:entry];
        [reflogEntry addReference:reference withMessage:git_reflog_entry_message(entry)];
        [entries addObject:reflogEntry];
        [reflogEntry release];
      }
    }
    git_reflog_free(reflog);
    [entries sortUsingSelector:@selector(reverseTimeCompare:)];
  }
  return [entries autorelease];
}

- (NSArray*)loadAllReflogEntries:(NSError**)error {
  NSMutableArray* entries = [[NSMutableArray alloc] init];
  CFSetCallBacks callbacks = {0, NULL, NULL, NULL, _EntryEqualCallBack, _EntryHashCallBack};
  CFMutableSetRef cache = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
  BOOL success = [self enumerateReferencesWithOptions:(kGCReferenceEnumerationOption_IncludeHEAD | kGCReferenceEnumerationOption_RetainReferences) error:error usingBlock:^BOOL(git_reference* rawReference) {
    
    if (git_reference_has_log(self.private, git_reference_name(rawReference))) {
      git_reflog* reflog;
      CALL_LIBGIT2_FUNCTION_RETURN(NO, git_reflog_read, &reflog, self.private, git_reference_name(rawReference));
      GCReference* reference = nil;
      if (git_reference_is_tag(rawReference)) {
        reference = [[GCHistoryTag alloc] initWithRepository:self reference:rawReference];
      } else if (git_reference_is_branch(rawReference)) {
        reference = [[GCHistoryLocalBranch alloc] initWithRepository:self reference:rawReference];
      } else if (git_reference_is_remote(rawReference)) {
        reference = [[GCHistoryRemoteBranch alloc] initWithRepository:self reference:rawReference];
      } else {
        reference = [[GCReference alloc] initWithRepository:self reference:rawReference];
      }
      
      for (size_t i = 0, count = git_reflog_entrycount(reflog); i < count; ++i) {
        const git_reflog_entry* entry = git_reflog_entry_byindex(reflog, i);
        if (!git_oid_equal(git_reflog_entry_id_new(entry), git_reflog_entry_id_old(entry))) {  // Skip no-op entries
          GCReflogEntry* reflogEntry = [[GCReflogEntry alloc] initWithRepository:self entry:entry];
          GCReflogEntry* existingEntry = CFSetGetValue(cache, (const void*)reflogEntry);
          if (existingEntry) {
            XLOG_DEBUG_CHECK([existingEntry.date isEqualToDate:reflogEntry.date]);
            XLOG_DEBUG_CHECK([existingEntry.committerName isEqualToString:reflogEntry.committerName]);
            XLOG_DEBUG_CHECK([existingEntry.committerEmail isEqualToString:reflogEntry.committerEmail]);
            [existingEntry addReference:reference withMessage:git_reflog_entry_message(entry)];
          } else {
            [reflogEntry addReference:reference withMessage:git_reflog_entry_message(entry)];
            [entries addObject:reflogEntry];
            CFSetAddValue(cache, (const void*)reflogEntry);
          }
          [reflogEntry release];
        }
      }
      
      [reference release];
      git_reflog_free(reflog);
    } else {
      git_reference_free(rawReference);
    }
    return YES;
    
  }];
  CFRelease(cache);
  if (!success) {
    [entries release];
    return nil;
  }
  [entries sortUsingSelector:@selector(reverseTimeCompare:)];
  return [entries autorelease];
}

@end
