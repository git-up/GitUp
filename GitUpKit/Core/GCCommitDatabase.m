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

#import <sqlite3.h>

#import "GCPrivate.h"

#define __UNIQUE_RELATIONS__ 1
#define __CHECK_CONSISTENCY__ 0

#define kSchemaVersion 3

#define kTipsTableName "tips"
#define kCommitsTableName "commits"
#define kRelationsTableName "relations"
#define kUsersTableName "users"

#define kFTSPrefix "fts_"
#define kFTSMessagesTableName kFTSPrefix "messages"
#define kFTSDiffsTableName kFTSPrefix "diffs"
#define kFTSUsersTableName kFTSPrefix "users"

#define kMinWordLength 2
#define kWordCacheSize 1024

#define kMaxFileSizeForTextDiff (32 * 1024 * 1024)  // libgit2 default is 512 MiB

#define IS_ALPHANUMERICAL(c) (((c) >= '0' && (c) <= '9') || ((c) >= 'A' && (c) <= 'Z') || ((c) >= 'a' && (c) <='z'))
#define IS_DELIMITER(c) (((c) < 0x80) && !IS_ALPHANUMERICAL(c) && ((c) != '_'))  // Don't split tokens on '_'

#define SET_BIT(a, n) (a[(n) / CHAR_BIT] |= (1 << ((n) % CHAR_BIT)))
#define GET_BIT(a, n) (a[(n) / CHAR_BIT] & (1 << ((n) % CHAR_BIT)))

#define LOG_SQLITE_ERROR(__CODE__) \
  do { \
    XLOG_DEBUG_CHECK((__CODE__ != SQLITE_OK) && (__CODE__ != SQLITE_DONE)); \
    XLOG_ERROR(@"sqlite3 error (%i): %s", __CODE__, sqlite3_errmsg(_database)); \
  } \
  while (0)

#define CHECK_SQLITE_FUNCTION_CALL(__FAIL_ACTION__, __STATUS__, __COMPARISON__) \
  do { \
    if (!(__STATUS__ __COMPARISON__)) { \
      LOG_SQLITE_ERROR(__STATUS__); \
      if (error) { \
        *error = _NewSQLiteError(__STATUS__, sqlite3_errmsg(_database)); \
      } \
      __FAIL_ACTION__; \
    } \
  } while(0)

#define CALL_SQLITE_FUNCTION_RETURN(__RETURN_VALUE_ON_ERROR__, __FUNCTION__, ...) \
  do { \
    int __callResult = __FUNCTION__(__VA_ARGS__); \
    CHECK_SQLITE_FUNCTION_CALL(return __RETURN_VALUE_ON_ERROR__, __callResult, == SQLITE_OK); \
  } while(0)

#define CALL_SQLITE_FUNCTION_GOTO(__GOTO_LABEL__, __FUNCTION__, ...) \
  do { \
    int __callResult = __FUNCTION__(__VA_ARGS__); \
    CHECK_SQLITE_FUNCTION_CALL(goto __GOTO_LABEL__, __callResult, == SQLITE_OK); \
  } while(0)

typedef NS_ENUM(int, Statement) {
  kStatement_BeginTransaction = 0,
  kStatement_ListTipSHA1s,
  kStatement_FindCommitID,
  kStatement_LookupCommitParentIDs,
  kStatement_AddTip,
  kStatement_AddCommit,
  kStatement_FindUserID,
  kStatement_AddUser,
  kStatement_AddRelation,
  kStatement_DeleteTip,
  kStatement_RetainCommit,
  kStatement_ReleaseCommit,
  kStatement_DeleteOrphanCommit,
  kStatement_DeleteCommitRelations,
  kStatement_AddFTSUser,
  kStatement_AddFTSMessage,
  kStatement_AddFTSDiff,
  kStatement_EndTransaction,
  kStatement_SearchCommits,
  kNumStatements
};

typedef struct {
  const unsigned char* start;
  size_t length;
} Word;

typedef struct {
  git_commit* commit;
  sqlite3_int64 childID;
} Item;

NSString* const SQLiteErrorDomain = @"SQLiteErrorDomain";

static NSError* _NewSQLiteError(int code, const char* message) {
  return [NSError errorWithDomain:SQLiteErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:message]}];
}

// TODO: Consider using triggers to handle retain/release
// TODO: Garbage collect users table
@implementation GCCommitDatabase {
  sqlite3* _database;
  sqlite3_stmt** _statements;
  BOOL _ready;
}

static void _SQLiteLog(void* unused, int error, const char* message) {
  if ((error & 0xFF) == SQLITE_NOTICE) {
    XLOG_INFO(@"SQLite (%i): %s", error, message);
  } else if ((error & 0xFF) == SQLITE_WARNING) {
    const char* ignore = "2file renamed while open";  // TODO: This is sometimes triggered by sqlite3_step()?
    if (strncmp(message, ignore, sizeof(ignore) - 1)) {
      XLOG_WARNING(@"SQLite (%i): %s", error, message);
    }
  }
}

+ (void)initialize {
  XLOG_CHECK(sqlite3_compileoption_used("THREADSAFE=2"));
  XLOG_CHECK(sqlite3_compileoption_used("ENABLE_FTS3"));
  XLOG_CHECK(sqlite3_compileoption_used("ENABLE_FTS3_PARENTHESIS"));
  
  sqlite3_config(SQLITE_CONFIG_LOG, _SQLiteLog, NULL);
}

static int _CaseInsensitiveUTF8Compare(void* context, int length1, const void* bytes1, int length2, const void* bytes2) {
  CFStringRef string1 = CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, bytes1, length1, kCFStringEncodingUTF8, false, kCFAllocatorNull);
  CFStringRef string2 = CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, bytes2, length2, kCFStringEncodingUTF8, false, kCFAllocatorNull);
  CFComparisonResult result;
  if (string1 && string2) {
    result = CFStringCompare(string1, string2, kCFCompareCaseInsensitive);
    CFRelease(string2);
    CFRelease(string1);
  } else if (string1) {
    result = 1;
    CFRelease(string1);
  } else if (string2) {
    result = -1;
    CFRelease(string2);
  } else {
    result = 0;
  }
  return result;
}

- (BOOL)_initializeDatabase:(NSString*)path error:(NSError**)error {
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_open_v2, path.fileSystemRepresentation, &_database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_SHAREDCACHE, NULL);
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_extended_result_codes, _database, true);
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "PRAGMA page_size = 32768", NULL, NULL, NULL);  // Default appears to be 4096 on OS X
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "PRAGMA cache_size = 500", NULL, NULL, NULL);  // Default appears to be 500 on OS X
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "PRAGMA journal_mode = WAL", NULL, NULL, NULL);
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_wal_autocheckpoint, _database, 0);
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_create_collation, _database, "utf8", SQLITE_UTF8, NULL, _CaseInsensitiveUTF8Compare);
  if (_options & kGCCommitDatabaseOptions_QueryOnly) {
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "PRAGMA query_only = 1", NULL, NULL, NULL);
  }
  return YES;
}

// Emails are considered case-insensitive with "COLLATE NOCASE" which only works with ASCII characters but that should be fine for emails
// TODO: Does the order of columns inside a table affect performance?
- (BOOL)_initializeSchema:(int)version error:(NSError**)error {
  // Users table
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE TABLE " kUsersTableName "("
                              "_id_ INTEGER PRIMARY KEY,"
                              "email TEXT NOT NULL COLLATE NOCASE,"
                              "name TEXT COLLATE utf8"
                              ")", NULL, NULL, NULL);
  
  // Index to ensure unique email/name combinations and to search for users
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE UNIQUE INDEX " kUsersTableName "_email_name on " kUsersTableName "(email, name)", NULL, NULL, NULL);
  
  // Commits table (with implicit index for "sha1")
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE TABLE " kCommitsTableName "("
                              "_id_ INTEGER PRIMARY KEY,"
                              "retain_count INTEGER NOT NULL,"
                              "sha1 BLOB UNIQUE NOT NULL,"
                              "time INTEGER NOT NULL,"
                              "offset INTEGER NOT NULL,"
                              "author INTEGER NOT NULL,"
                              "committer INTEGER NOT NULL,"
                              "parent_sha1s BLOB NOT NULL,"
                              "message TEXT NOT NULL"
                              ")", NULL, NULL, NULL);
  
  // Relations table
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE TABLE " kRelationsTableName "("
                              "_id_ INTEGER PRIMARY KEY,"
                              "child INTEGER NOT NULL,"
                              "parent INTEGER NOT NULL"
                              ")", NULL, NULL, NULL);
  
  // Index for finding parents of a given child (works as a covering index too)
#if __UNIQUE_RELATIONS__
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE UNIQUE INDEX " kRelationsTableName "_child_parent on " kRelationsTableName "(child, parent)", NULL, NULL, NULL);
#endif
  
  // Tips table
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE TABLE " kTipsTableName "("
                              "_id_ INTEGER PRIMARY KEY,"
                              "`commit` INTEGER NOT NULL"
                              ")", NULL, NULL, NULL);
  
  // FTS for commit messages (external content)
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE VIRTUAL TABLE " kFTSMessagesTableName " USING fts4(content='" kCommitsTableName "', message, tokenize=unicode61 'tokenchars=_')", NULL, NULL, NULL);  // Don't split tokens on '_'
  
  // FTS for commit diffs (stored content)
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE VIRTUAL TABLE " kFTSDiffsTableName " USING fts4(added, deleted, tokenize=unicode61 'tokenchars=_')", NULL, NULL, NULL);  // Don't split tokens on '_'
  
  // FTS for users (external content)
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE VIRTUAL TABLE " kFTSUsersTableName " USING fts4(content='" kUsersTableName "', email, name, tokenize=unicode61)", NULL, NULL, NULL);
  
  // Save version
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, [[NSString stringWithFormat:@"PRAGMA user_version = %i", version] UTF8String], NULL, NULL, NULL);
  
  return YES;
}

// DELETE triggers are required because we must delete from FTS *before* deleting from content table which is impractical to do in -_removeCommitsForTip
// We don't need INSERT or UPDATE triggers since we never update content that is indexed by FTS
- (BOOL)_initializeTriggers:(NSError**)error {
  
  // Triggers for FTS commits
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "\
    CREATE TRIGGER " kCommitsTableName "_before_delete BEFORE DELETE ON " kCommitsTableName " BEGIN \
      DELETE FROM " kFTSMessagesTableName " WHERE docid=old.rowid; \
      DELETE FROM " kFTSDiffsTableName " WHERE docid=old.rowid; \
    END; \
  ", NULL, NULL, NULL);
  
  // Triggers for FTS users
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "\
    CREATE TRIGGER " kUsersTableName "_before_delete BEFORE DELETE ON " kUsersTableName " BEGIN \
      DELETE FROM " kFTSUsersTableName " WHERE docid=old.rowid; \
    END; \
  ", NULL, NULL, NULL);
  
  return YES;
}

- (BOOL)_initializeDeferredIndexes:(NSError**)error {
  // Indexes for finding commits by author or comitter
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE INDEX " kCommitsTableName "_author on " kCommitsTableName "(author)", NULL, NULL, NULL);
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE INDEX " kCommitsTableName "_committer on " kCommitsTableName "(committer)", NULL, NULL, NULL);
  
#if !__UNIQUE_RELATIONS__
  // Index for finding parents of a given child (works as a covering index too)
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE INDEX " kRelationsTableName "_child_parent on " kRelationsTableName "(child, parent)", NULL, NULL, NULL);
#endif
  
  // Index for deleting tips by commit ID
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_exec, _database, "CREATE INDEX " kTipsTableName "_commit on " kTipsTableName "(`commit`)", NULL, NULL, NULL);
  
  return YES;
}

- (BOOL)_initializeStatements:(NSError**)error {
  _statements = calloc(kNumStatements, sizeof(sqlite3_stmt*));
  
  if (!(_options & kGCCommitDatabaseOptions_QueryOnly)) {
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "BEGIN IMMEDIATE TRANSACTION", -1, &_statements[kStatement_BeginTransaction], NULL);
    
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "SELECT " kCommitsTableName ".sha1 FROM " kCommitsTableName " JOIN " kTipsTableName " ON " kTipsTableName ".`commit`=" kCommitsTableName "._id_" , -1, &_statements[kStatement_ListTipSHA1s], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "SELECT _id_ FROM " kCommitsTableName " WHERE sha1=?1", -1, &_statements[kStatement_FindCommitID], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "SELECT parent FROM " kRelationsTableName " WHERE child=?1", -1, &_statements[kStatement_LookupCommitParentIDs], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "SELECT _id_ FROM " kUsersTableName " WHERE email=?1 AND name=?2", -1, &_statements[kStatement_FindUserID], NULL);
    
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "INSERT INTO " kTipsTableName " VALUES (NULL, ?1)", -1, &_statements[kStatement_AddTip], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "INSERT INTO " kCommitsTableName " VALUES (NULL, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)", -1, &_statements[kStatement_AddCommit], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "INSERT INTO " kUsersTableName " VALUES (NULL, ?1, ?2)", -1, &_statements[kStatement_AddUser], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "INSERT INTO " kRelationsTableName " VALUES (NULL, ?1, ?2)", -1, &_statements[kStatement_AddRelation], NULL);
    
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "UPDATE " kCommitsTableName " SET retain_count=retain_count+1 WHERE _id_=?1", -1, &_statements[kStatement_RetainCommit], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "UPDATE " kCommitsTableName " SET retain_count=retain_count-1 WHERE _id_=?1", -1, &_statements[kStatement_ReleaseCommit], NULL);
    
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "DELETE FROM " kTipsTableName " WHERE `commit`=?1", -1, &_statements[kStatement_DeleteTip], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "DELETE FROM " kCommitsTableName " WHERE _id_=?1 AND retain_count=0", -1, &_statements[kStatement_DeleteOrphanCommit], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "DELETE FROM " kRelationsTableName " WHERE child=?1 OR parent=?1", -1, &_statements[kStatement_DeleteCommitRelations], NULL);
    
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "INSERT INTO " kFTSUsersTableName "(docid, email, name) VALUES(?1, ?2, ?3)", -1, &_statements[kStatement_AddFTSUser], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "INSERT INTO " kFTSMessagesTableName "(docid, message) VALUES(?1, ?2)", -1, &_statements[kStatement_AddFTSMessage], NULL);
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "INSERT INTO " kFTSDiffsTableName "(docid, added, deleted) VALUES(?1, ?2, ?3)", -1, &_statements[kStatement_AddFTSDiff], NULL);
    
    CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "END TRANSACTION", -1, &_statements[kStatement_EndTransaction], NULL);
  }
  
  CALL_SQLITE_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, " \
                              SELECT sha1, time FROM " kFTSMessagesTableName " JOIN " kCommitsTableName " ON " kCommitsTableName ".rowid=" kFTSMessagesTableName ".docid WHERE " kFTSMessagesTableName " MATCH ?1 \
                              UNION \
                              SELECT sha1, time FROM " kFTSDiffsTableName " JOIN " kCommitsTableName " ON " kCommitsTableName ".rowid=" kFTSDiffsTableName ".docid WHERE " kFTSDiffsTableName " MATCH ?1 \
                              UNION \
                              SELECT sha1, time FROM " kFTSUsersTableName " JOIN " kUsersTableName " ON " kUsersTableName ".rowid=" kFTSUsersTableName ".docid JOIN " kCommitsTableName " ON " kCommitsTableName ".author=" kUsersTableName "._id_ WHERE " kFTSUsersTableName " MATCH ?1 \
                              UNION \
                              SELECT sha1, time FROM " kFTSUsersTableName " JOIN " kUsersTableName " ON " kUsersTableName ".rowid=" kFTSUsersTableName ".docid JOIN " kCommitsTableName " ON " kCommitsTableName ".committer=" kUsersTableName "._id_ WHERE " kFTSUsersTableName " MATCH ?1 \
                              ORDER BY time DESC", -1, &_statements[kStatement_SearchCommits], NULL);
  
  return YES;
}

- (BOOL)_hasTables {
  BOOL result = NO;
  sqlite3_stmt* statement;
  if (sqlite3_prepare_v2(_database, "SELECT 1 FROM sqlite_master", -1, &statement, NULL) == SQLITE_OK) {
    if (sqlite3_step(statement) == SQLITE_ROW) {
      result = YES;
    }
    sqlite3_finalize(statement);
  }
  return result;
}

- (int)_readVersion {
  int version = 0;
  sqlite3_stmt* statement;
  if (sqlite3_prepare_v2(_database, "PRAGMA user_version", -1, &statement, NULL) == SQLITE_OK) {
    if (sqlite3_step(statement) == SQLITE_ROW) {
      version = sqlite3_column_int(statement, 0);
    }
    sqlite3_finalize(statement);
  }
  return version;
}

- (BOOL)_checkReady:(NSError**)error {
  sqlite3_stmt* statement;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, sqlite3_prepare_v2, _database, "SELECT 1 FROM sqlite_master WHERE type='trigger'", -1, &statement, NULL);
  int result = sqlite3_step(statement);
  CALL_LIBGIT2_FUNCTION_RETURN(NO, sqlite3_finalize, statement);
  if (result == SQLITE_ROW) {
    _ready = YES;
  } else {
    XLOG_DEBUG_CHECK(result == SQLITE_DONE);
  }
  return YES;
}

- (instancetype)initWithRepository:(GCRepository*)repository databasePath:(NSString*)path options:(GCCommitDatabaseOptions)options error:(NSError**)error {
  if ((self = [super init])) {
    _repository = repository;
    _databasePath = [path copy];
    _options = options;
    
    if (![self _initializeDatabase:path error:error]) {
      [self release];
      return nil;
    }
    
    int version = 2 * kSchemaVersion + (_options & kGCCommitDatabaseOptions_IndexDiffs ? 1 : 0);
    if ([self _hasTables]) {
      NSInteger currentVersion = [self _readVersion];
      if (currentVersion == version) {
        if (![self _checkReady:error]) {
          [self release];
          return nil;
        }
      } else {
        if (_options & kGCCommitDatabaseOptions_QueryOnly) {
          GC_SET_GENERIC_ERROR(@"Database is query-only");
          [self release];
          return nil;
        }
        sqlite3_close(_database);
        _database = NULL;
        XLOG_WARNING(@"Commit database for \"%@\" has an incompatible version (%li) and must be regenerated", _repository.repositoryPath, (long)currentVersion);
        if (![[NSFileManager defaultManager] removeItemAtPath:path error:error] || ![self _initializeDatabase:path error:error] || ![self _initializeSchema:version error:error]) {
          [self release];
          return nil;
        }
      }
    } else {
      if (![self _initializeSchema:version error:error]) {
        [self release];
        return nil;
      }
    }
    
    if (![self _initializeStatements:error]) {
      [self release];
      return nil;
    }
  }
  return self;
}

- (void)dealloc {
  if (_statements) {
    for (int i = 0; i < kNumStatements; ++i) {
      sqlite3_finalize(_statements[i]);
    }
    free(_statements);
  }
  sqlite3_close(_database);
  
  [_databasePath release];
  
  [super dealloc];
}

#if DEBUG
static  // Ensure function is inlined per C99 specs by leaving "static" out
#endif
inline unsigned int _hash_buffer(const unsigned char *key, size_t length) {
  unsigned int h = 0;
  const unsigned char* max = key + length;
  while (key < max) {
#if 1
    h = *key++ + (h << 6) + (h << 16) - h;  // SDBM (seems to produces fewer false positives for about the same speed as SAX)
#else
    h ^= (h << 5) + (h >> 2) + *key++;  // SAX
#endif
  }
  return h;
}

// TODO: Skip common English words
// TODO: Skip programming keywords
// This uses a simple hash-based cache to reduce the lines to their unique words
// There can be false positives i.e. words repeated more than once in the result, but that's an acceptable speed trade-off considering SQLite FTS will fix this anyway
static void _ExtractUniqueWordsFromLines(NSMutableData* lines, NSMutableData* words) {
  GC_LIST_ALLOCATE(list, kWordCacheSize, Word);
  unsigned char* cache = calloc(kWordCacheSize / CHAR_BIT, sizeof(char));
  Word* wordPtr;
  
  const unsigned char* max = (unsigned char*)lines.bytes + lines.length;
  const unsigned char* current = lines.bytes;
  const unsigned char* start = NULL;
  do {
    if ((current == max) || IS_DELIMITER(*current)) {
      if (start != NULL) {
        size_t length = current - start;
        unsigned int hash = _hash_buffer(start, length);
        if (length >= kMinWordLength) {
          if (!GET_BIT(cache, hash % kWordCacheSize)) {
            Word word = {start, length};
            GC_LIST_APPEND(list, &word);
            SET_BIT(cache, hash % kWordCacheSize);
          }
        }
        start = NULL;
      }
    } else {
      if (start == NULL) {
        start = current;
      }
    }
    ++current;
  } while (current <= max);
  
  char space = ' ';
  GC_LIST_FOR_LOOP_POINTER(list, wordPtr) {
    [words appendBytes:wordPtr->start length:wordPtr->length];
    [words appendBytes:&space length:1];
  }
  
  free(cache);
  GC_LIST_FREE(list);
}

// We don't use the GCDiff wrappers because we need the best possible performance
// TODO: Consider indexing file names
static BOOL _ProcessDiff(git_repository* repo, git_commit* commit, git_commit* parent, NSMutableData* addedLines, NSMutableData* deletedLines) {
  BOOL success = NO;
  git_tree* newTree;
  int status = git_commit_tree(&newTree, commit);
  if (status == GIT_OK) {
    git_tree* oldTree = NULL;
    if (parent) {
      status = git_commit_tree(&oldTree, parent);
    }
    if (status == GIT_OK) {
      git_diff_options diffOptions = GIT_DIFF_OPTIONS_INIT;
      diffOptions.ignore_submodules = GIT_SUBMODULE_IGNORE_ALL;
      diffOptions.max_size = kMaxFileSizeForTextDiff;
      diffOptions.context_lines = 0;
      diffOptions.interhunk_lines = 0;
      git_diff* diff;
      status = git_diff_tree_to_tree(&diff, repo, oldTree, newTree, &diffOptions);
      if (status == GIT_OK) {
        git_diff_find_options findOptions = GIT_DIFF_FIND_OPTIONS_INIT;
        findOptions.flags = GIT_DIFF_FIND_RENAMES;  // We need to find renames to avoid generated added/deleted lines when just renaming a file
        status = git_diff_find_similar(diff, &findOptions);
        if (status == GIT_OK) {
          success = YES;
          for (size_t i = 0, iMax = git_diff_num_deltas(diff); i < iMax; ++i) {
            git_patch* patch;
            status = git_patch_from_diff(&patch, diff, i);
            if (status == GIT_OK) {
              for (size_t j = 0, jMax = git_patch_num_hunks(patch); j < jMax; ++j) {
                for (size_t k = 0, kMax = git_patch_num_lines_in_hunk(patch, j); k < kMax; ++k) {
                  const git_diff_line* line;
                  if (git_patch_get_line_in_hunk(&line, patch, j, k) == GIT_OK) {
                    if (line->origin == GIT_DIFF_LINE_ADDITION) {
                      [addedLines appendBytes:line->content length:line->content_len];
                    } else if (line->origin == GIT_DIFF_LINE_DELETION) {
                      [deletedLines appendBytes:line->content length:line->content_len];
                    }
                  } else {
                    XLOG_DEBUG_UNREACHABLE();
                    success = NO;
                  }
                }
              }
              git_patch_free(patch);
            } else {
              LOG_LIBGIT2_ERROR(status);
              success = NO;
              break;
            }
          }
        } else {
          LOG_LIBGIT2_ERROR(status);
        }
        git_diff_free(diff);
      } else {
        LOG_LIBGIT2_ERROR(status);
      }
      git_tree_free(oldTree);
    } else {
      LOG_LIBGIT2_ERROR(status);
    }
    git_tree_free(newTree);
  } else {
    LOG_LIBGIT2_ERROR(status);
  }
  return success;
}

- (BOOL)_addCommitsForTip:(const git_oid*)tipOID handler:(BOOL (^)())handler error:(NSError**)error {
  BOOL success = NO;
  GC_LIST_ALLOCATE(row, 16, Item);
  GC_LIST_ALLOCATE(newRow, 16, Item);
  git_commit* mainParent = NULL;
  NSMutableData* addedLines = [[NSMutableData alloc] initWithCapacity:(64 * 1024)];
  NSMutableData* deletedLines = [[NSMutableData alloc] initWithCapacity:(64 * 1024)];
  NSMutableData* addedWords = [[NSMutableData alloc] initWithCapacity:(32 * 1024)];
  NSMutableData* deletedWords = [[NSMutableData alloc] initWithCapacity:(32 * 1024)];
  sqlite3_stmt** statements = _statements;
  BOOL indexDiffs = _options & kGCCommitDatabaseOptions_IndexDiffs ? YES : NO;
  git_commit* commit;
  int result;
  int status;
  Item item;
  const Item* itemPtr;
  
  // Check if commit is already in database
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_blob, statements[kStatement_FindCommitID], 1, tipOID, GIT_OID_RAWSZ, SQLITE_STATIC);
  result = sqlite3_step(statements[kStatement_FindCommitID]);
  if (result == SQLITE_ROW) {
    sqlite3_int64 tipID = sqlite3_column_int64(statements[kStatement_FindCommitID], 0);
    CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_FindCommitID]);
    
    // Create tip
    CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddTip], 1, tipID);
    result = sqlite3_step(statements[kStatement_AddTip]);
    CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
    CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddTip]);
    XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
    
    // Retain commit
    CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_RetainCommit], 1, tipID);
    result = sqlite3_step(statements[kStatement_RetainCommit]);
    CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
    CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_RetainCommit]);
    XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
    
    success = YES;
    goto cleanup;
  }
  CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_FindCommitID]);
  
  // Load tip commit and queue it
  status = git_commit_lookup(&commit, _repository.private, tipOID);
  if (status == GIT_ENOTFOUND) {
    XLOG_WARNING(@"Missing tip commit %s from repository \"%@\"", git_oid_tostr_s(tipOID), _repository.repositoryPath);
    success = YES;
    goto cleanup;
  }
  CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
  item.commit = commit;
  item.childID = 0;
  GC_LIST_APPEND(row, &item);
  
  // Create commits for the tip and its ancestors
  while (1) {
    for (size_t i = 0; i < GC_LIST_COUNT(row); ++i) {
      itemPtr = GC_LIST_ITEM_POINTER(row, i);
      unsigned int parentCount = git_commit_parentcount(itemPtr->commit);
      const git_signature* author = git_commit_author(itemPtr->commit);
      const git_signature* committer = git_commit_committer(itemPtr->commit);
      
      // Bind retain count (always 1 as the commit is either retained by the tip or by its parent)
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int, statements[kStatement_AddCommit], 1, 1);
      
      // Bind commit SHA1
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_blob, statements[kStatement_AddCommit], 2, git_commit_id(itemPtr->commit), GIT_OID_RAWSZ, SQLITE_STATIC);
      
      // Bind commit date
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddCommit], 3, committer->when.time);
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int, statements[kStatement_AddCommit], 4, committer->when.offset);
      
      // Bind commit author
      sqlite3_int64 authorID;
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_FindUserID], 1, author->email, -1, SQLITE_STATIC);
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_FindUserID], 2, author->name, -1, SQLITE_STATIC);
      result = sqlite3_step(statements[kStatement_FindUserID]);
      if (result == SQLITE_ROW) {
        authorID = sqlite3_column_int64(statements[kStatement_FindUserID], 0);
      } else {
        CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
        
        // Create user
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddUser], 1, author->email, -1, SQLITE_STATIC);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddUser], 2, author->name, -1, SQLITE_STATIC);
        result = sqlite3_step(statements[kStatement_AddUser]);
        CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
        authorID = sqlite3_last_insert_rowid(_database);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddUser]);
        XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
        
        // Update users FTS
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddFTSUser], 1, authorID);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddFTSUser], 2, author->email, -1, SQLITE_STATIC);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddFTSUser], 3, author->name, -1, SQLITE_STATIC);
        result = sqlite3_step(statements[kStatement_AddFTSUser]);
        CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddFTSUser]);
        XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
      }
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddCommit], 5, authorID);
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_FindUserID]);
      
      // Bind commit committer
      sqlite3_int64 committerID;
      if (!strcmp(committer->email, author->email) && ((committer->name == author->name) || (committer->name && author->name && !strcmp(committer->name, author->name)))) {
        committerID = authorID;  // Fast path for common case
      } else {
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_FindUserID], 1, committer->email, -1, SQLITE_STATIC);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_FindUserID], 2, committer->name, -1, SQLITE_STATIC);
        result = sqlite3_step(statements[kStatement_FindUserID]);
        if (result == SQLITE_ROW) {
          committerID = sqlite3_column_int64(statements[kStatement_FindUserID], 0);
        } else {
          CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
          
          // Create user
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddUser], 1, committer->email, -1, SQLITE_STATIC);
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddUser], 2, committer->name, -1, SQLITE_STATIC);
          result = sqlite3_step(statements[kStatement_AddUser]);
          CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
          committerID = sqlite3_last_insert_rowid(_database);
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddUser]);
          XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
          
          // Update users FTS
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddFTSUser], 1, committerID);
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddFTSUser], 2, committer->email, -1, SQLITE_STATIC);
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddFTSUser], 3, committer->name, -1, SQLITE_STATIC);
          result = sqlite3_step(statements[kStatement_AddFTSUser]);
          CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddFTSUser]);
          XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
        }
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_FindUserID]);
      }
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddCommit], 6, committerID);
      
      // Bind commit parent SHA1s
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wvla"
      git_oid parents[parentCount];
#pragma clang diagnostic pop
      for (unsigned int j = 0; j < parentCount; ++j) {
        git_oid_cpy(&parents[j], git_commit_parent_id(itemPtr->commit, j));
      }
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_blob, statements[kStatement_AddCommit], 7, parents, (int)sizeof(parents), SQLITE_STATIC);
      
      // Bind commit message
      const char* message = git_commit_message(itemPtr->commit);  // This already trims leading newlines
      size_t length = strlen(message);
      if (length) {
        while (message[length - 1] == '\n') {  // Trim trailing newlines
          --length;
        }
      }
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddCommit], 8, message, (int)length, SQLITE_STATIC);
      
      // Create commit
      sqlite3_int64 commitID;
      result = sqlite3_step(statements[kStatement_AddCommit]);
      if (result == SQLITE_CONSTRAINT_UNIQUE) {  // This can happen when a row contains a commit that was already created while processing an earlier row
        XLOG_DEBUG_CHECK(itemPtr->childID);
        XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 0);
        sqlite3_reset(statements[kStatement_AddCommit]);
        
        // Commit already exists in database so just fetch its ID...
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_blob, statements[kStatement_FindCommitID], 1, git_commit_id(itemPtr->commit), GIT_OID_RAWSZ, SQLITE_STATIC);
        result = sqlite3_step(statements[kStatement_FindCommitID]);
        CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_ROW);
        commitID = sqlite3_column_int64(statements[kStatement_FindCommitID], 0);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_FindCommitID]);
        
        // ...and retain it because of relation we are about to create
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_RetainCommit], 1, commitID);
        result = sqlite3_step(statements[kStatement_RetainCommit]);
        CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_RetainCommit]);
        XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
        
        // Don't follow parents later on
        parentCount = 0;
        
      } else {
        CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
        commitID = sqlite3_last_insert_rowid(_database);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddCommit]);
        XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
        
        // Update messages FTS
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddFTSMessage], 1, commitID);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_AddFTSMessage], 2, message, (int)length, SQLITE_STATIC);
        result = sqlite3_step(statements[kStatement_AddFTSMessage]);
        CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddFTSMessage]);
        XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
        
        // Update diffs FTS
        if (indexDiffs) {
          if (parentCount) {
            status = git_commit_parent(&mainParent, itemPtr->commit, 0);
          } else {
            status = GIT_OK;
          }
          addedLines.length = 0;
          deletedLines.length = 0;
          if ((status == GIT_OK) && _ProcessDiff(_repository.private, itemPtr->commit, mainParent, addedLines, deletedLines)) {
            if (addedLines.length || deletedLines.length) {
              CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddFTSDiff], 1, commitID);
              addedWords.length = 0;
              _ExtractUniqueWordsFromLines(addedLines, addedWords);
              CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_blob, statements[kStatement_AddFTSDiff], 2, addedWords.bytes, (int)addedWords.length, SQLITE_STATIC);
              deletedWords.length = 0;
              _ExtractUniqueWordsFromLines(deletedLines, deletedWords);
              CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_blob, statements[kStatement_AddFTSDiff], 3, deletedWords.bytes, (int)deletedWords.length, SQLITE_STATIC);
              result = sqlite3_step(statements[kStatement_AddFTSDiff]);
              CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
              CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddFTSDiff]);
              XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
            }
          } else {
            XLOG_WARNING(@"Unable to compute diff for commit %s from repository \"%@\"", git_oid_tostr_s(git_commit_id(itemPtr->commit)), _repository.repositoryPath);
          }
        }
        
        // Call handler
        if (!handler()) {
          if (error) {
            *error = GCNewError(kGCErrorCode_UserCancelled, @"");
          }
          goto cleanup;
        }
      }
      
      // Create relation with child unless currently processing tip commit...
      if (itemPtr->childID) {
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddRelation], 1, itemPtr->childID);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddRelation], 2, commitID);
        result = sqlite3_step(statements[kStatement_AddRelation]);
#if __UNIQUE_RELATIONS__
        if (result == SQLITE_CONSTRAINT_UNIQUE) {  // This can happen for degenerated commits with duplicate parents
          XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 0);
          sqlite3_reset(statements[kStatement_AddRelation]);
          
          // Release commit that was previously retained
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_ReleaseCommit], 1, commitID);
          result = sqlite3_step(statements[kStatement_ReleaseCommit]);
          CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_ReleaseCommit]);
          XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
          
        } else
#endif
        {
          CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddRelation]);
          XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
        }
      }
      // ...in which case create tip instead
      else {
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddTip], 1, commitID);
        result = sqlite3_step(statements[kStatement_AddTip]);
        CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddTip]);
        XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
      }
      
      // Follow parents unless already in database
      for (unsigned int j = 0; j < parentCount; ++j) {
        const git_oid* parentOID = git_commit_parent_id(itemPtr->commit, j);
        
        // Check if parent is already in database
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_blob, statements[kStatement_FindCommitID], 1, parentOID, GIT_OID_RAWSZ, SQLITE_STATIC);
        result = sqlite3_step(statements[kStatement_FindCommitID]);
        if (result == SQLITE_DONE) {
          
          // Load parent commit and queue it
          git_commit* parentCommit;
          if (indexDiffs && (j == 0)) {
            if (mainParent) {
              parentCommit = mainParent;  // Fast path
              mainParent = NULL;
              status = GIT_OK;
            } else {
              parentCommit = NULL;  // Required to silence warning
              status = GIT_ENOTFOUND;
            }
          } else {
            status = git_commit_lookup(&parentCommit, _repository.private, parentOID);
          }
          if (status != GIT_ENOTFOUND) {
            CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
            item.commit = parentCommit;
            item.childID = commitID;
            GC_LIST_APPEND(newRow, &item);
          } else {
            XLOG_WARNING(@"Missing commit %s from repository \"%@\"", git_oid_tostr_s(parentOID), _repository.repositoryPath);
          }
          
        } else {
          CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_ROW);
          sqlite3_int64 parentID = sqlite3_column_int64(statements[kStatement_FindCommitID], 0);
          
          // Create relation with existing parent
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddRelation], 1, commitID);
          CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_AddRelation], 2, parentID);
          result = sqlite3_step(statements[kStatement_AddRelation]);
#if __UNIQUE_RELATIONS__
          if (result == SQLITE_CONSTRAINT_UNIQUE) {  // This can happen for degenerated commits with duplicate parents
            XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 0);
            sqlite3_reset(statements[kStatement_AddRelation]);
          } else
#endif
          {
            CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
            CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_AddRelation]);
            XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
            
            // Retain existing parent
            CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_RetainCommit], 1, parentID);
            result = sqlite3_step(statements[kStatement_RetainCommit]);
            CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
            CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_RetainCommit]);
            XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
          }
        }
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_FindCommitID]);
      }
      
      git_commit_free(mainParent);
      mainParent = NULL;
    }
    GC_LIST_FOR_LOOP_POINTER(row, itemPtr) {
      git_commit_free(itemPtr->commit);
    }
    GC_LIST_RESET(row);
    
    // Check if there are no more commits to follow
    if (GC_LIST_COUNT(newRow) == 0) {
      break;
    }
    GC_LIST_SWAP(newRow, row);
  }
  
  // We're done
  success = YES;
  
cleanup:
  [deletedWords release];
  [addedWords release];
  [deletedLines release];
  [addedLines release];
  git_commit_free(mainParent);
  GC_LIST_FOR_LOOP_POINTER(newRow, itemPtr) {
    git_commit_free(itemPtr->commit);
  }
  GC_LIST_FREE(newRow);
  GC_LIST_FOR_LOOP_POINTER(row, itemPtr) {
    git_commit_free(itemPtr->commit);
  }
  GC_LIST_FREE(row);
  return success;
}

- (BOOL)_removeCommitsForTip:(const git_oid*)tipOID handler:(BOOL (^)())handler error:(NSError**)error {
  BOOL success = NO;
  GC_LIST_ALLOCATE(row, 16, sqlite3_int64);
  GC_LIST_ALLOCATE(newRow, 16, sqlite3_int64);
  sqlite3_stmt** statements = _statements;
  sqlite3_int64* int64Ptr;
  int result;
  
  // Convert tip commit OID to tip commit ID and queue it
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_blob, statements[kStatement_FindCommitID], 1, tipOID, GIT_OID_RAWSZ, SQLITE_STATIC);
  result = sqlite3_step(statements[kStatement_FindCommitID]);
  if (result == SQLITE_DONE) {
    XLOG_DEBUG_UNREACHABLE();
    CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_FindCommitID]);
    success = YES;
    goto cleanup;
  }
  CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_ROW);
  sqlite3_int64 tipID = sqlite3_column_int64(statements[kStatement_FindCommitID], 0);
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_FindCommitID]);
  GC_LIST_APPEND(row, &tipID);
  
  // Delete tip
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_DeleteTip], 1, tipID);
  result = sqlite3_step(statements[kStatement_DeleteTip]);
  CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_DeleteTip]);
  XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
  
  // Release commit and all its ancestors
  while (1) {
    GC_LIST_FOR_LOOP_POINTER(row, int64Ptr) {
      sqlite3_int64 commitID = *int64Ptr;
      size_t oldCount = GC_LIST_COUNT(newRow);
      
      // Follow and queue parents
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_LookupCommitParentIDs], 1, commitID);
      result = sqlite3_step(statements[kStatement_LookupCommitParentIDs]);
      while (result == SQLITE_ROW) {
        sqlite3_int64 parentID = sqlite3_column_int64(statements[kStatement_LookupCommitParentIDs], 0);
        GC_LIST_APPEND(newRow, &parentID);
        result = sqlite3_step(statements[kStatement_LookupCommitParentIDs]);
      }
      CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_LookupCommitParentIDs]);
      
      // Release commit
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_ReleaseCommit], 1, commitID);
      result = sqlite3_step(statements[kStatement_ReleaseCommit]);
      CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_ReleaseCommit]);
      XLOG_DEBUG_CHECK(sqlite3_changes(_database) == 1);
      
      // Attempt to delete commit if retain count is zero
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_DeleteOrphanCommit], 1, commitID);
      result = sqlite3_step(statements[kStatement_DeleteOrphanCommit]);
      CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
      CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_DeleteOrphanCommit]);
      if (sqlite3_changes(_database) == 0) {
        GC_LIST_TRUNCATE(newRow, oldCount);  // Dequeue parents if commit is still in use
      } else {
        // Delete corresponding relations
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_int64, statements[kStatement_DeleteCommitRelations], 1, commitID);
        result = sqlite3_step(statements[kStatement_DeleteCommitRelations]);
        CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
        CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_DeleteCommitRelations]);
        XLOG_DEBUG_CHECK(sqlite3_changes(_database) > 0);
        
        // Call handler
        if (!handler()) {
          if (error) {
            *error = GCNewError(kGCErrorCode_UserCancelled, @"");
          }
          goto cleanup;
        }
      }
    }
    if (GC_LIST_COUNT(newRow) == 0) {
      break;
    }
    GC_LIST_SWAP(newRow, row);
    GC_LIST_RESET(newRow);
  }
  
  // We're done
  success = YES;
  
cleanup:
  GC_LIST_FREE(newRow);
  GC_LIST_FREE(row);
  return success;
}

// TODO: Use a custom container instead of GC_LIST + CFSet combo
// TODO: Vacuum database when needed (this is expensive as it actually copies the database to rebuild it)
- (BOOL)updateWithProgressHandler:(GCCommitDatabaseProgressHandler)handler error:(NSError**)error {
  XLOG_DEBUG_CHECK(!(_options & kGCCommitDatabaseOptions_QueryOnly));
  BOOL success = NO;
  GC_LIST_ALLOCATE(oldTips, 64, git_oid);
  GC_LIST_ALLOCATE(newTips, 64, git_oid);
  CFSetCallBacks callbacks = {0, GCOIDCopyCallBack, GCFreeReleaseCallBack, NULL, GCOIDEqualCallBack, GCOIDHashCallBack};
  CFMutableSetRef oldSet = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
  CFMutableSetRef newSet = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
  sqlite3_stmt** statements = _statements;
  __block NSUInteger addedCommits = 0;
  __block NSUInteger removedCommits = 0;
  CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
  int result;
  
  // Load old tip SHA1 (already unique)
  while (1) {
    result = sqlite3_step(statements[kStatement_ListTipSHA1s]);
    if (result == SQLITE_DONE) {
      break;
    }
    CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_ROW);
    XLOG_DEBUG_CHECK(sqlite3_column_bytes(statements[kStatement_ListTipSHA1s], 0) == GIT_OID_RAWSZ);
    const git_oid* oid = sqlite3_column_blob(statements[kStatement_ListTipSHA1s], 0);
    GC_LIST_APPEND(oldTips, oid);
    XLOG_DEBUG_CHECK(!CFSetContainsValue(oldSet, oid));
    CFSetAddValue(oldSet, oid);
  }
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_ListTipSHA1s]);
  XLOG_DEBUG_CHECK(_ready || !GC_LIST_COUNT(oldTips));
  
  // Load new tips (ensure unique)
  if (![_repository enumerateReferencesWithOptions:kGCReferenceEnumerationOption_IncludeHEAD error:error usingBlock:^BOOL(git_reference* reference) {
    
    if (git_reference_type(reference) == GIT_REF_OID) {  // We don't care about symbolic references as they eventually point to a direct one anyway
      const git_oid* oid = git_reference_target(reference);
      git_object* object = NULL;
      git_commit* commit = NULL;
      int status = git_object_lookup(&object, _repository.private, oid, GIT_OBJ_ANY);
      if (status == GIT_OK) {
        if (git_object_type(object) == GIT_OBJ_COMMIT) {
          commit = (git_commit*)object;
          object = NULL;
        } else if (git_object_type(object) == GIT_OBJ_TAG) {
          status = git_object_peel((git_object**)&commit, object, GIT_OBJ_COMMIT);
        } else {
          XLOG_DEBUG_UNREACHABLE();
          status = GIT_EUSER;
        }
      }
      if (status == GIT_OK) {
        oid = git_commit_id(commit);
        if (!CFSetContainsValue(newSet, oid)) {
          GC_LIST_APPEND(newTips, oid);
          CFSetAddValue(newSet, oid);
        }
      } else if (status != GIT_EUSER) {
        LOG_LIBGIT2_ERROR(status);
      }
      git_commit_free(commit);
      git_object_free(object);
    }
    return YES;
    
  }]) {
    goto cleanup;
  }
  
  // Begin transaction
  result = sqlite3_step(statements[kStatement_BeginTransaction]);
  CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_BeginTransaction]);
  
  // Find added tips
  const git_oid* newTip;
  GC_LIST_FOR_LOOP_POINTER(newTips, newTip) {
    if (!CFSetContainsValue(oldSet, newTip)) {
      if (![self _addCommitsForTip:newTip handler:^BOOL{
        ++addedCommits;
        return !handler || handler(!_ready, addedCommits, removedCommits);
      } error:error]) {
        goto cleanup;
      }
    }
  }
  
  // Find removed tips
  const git_oid* oldTip;
  GC_LIST_FOR_LOOP_POINTER(oldTips, oldTip) {
    if (!CFSetContainsValue(newSet, oldTip)) {
      if (![self _removeCommitsForTip:oldTip handler:^BOOL{
        ++removedCommits;
        return !handler || handler(!_ready, addedCommits, removedCommits);
      } error:error]) {
        goto cleanup;
      }
    }
  }
  
  // Finish database initialization if needed
  if (!_ready) {
    if (![self _initializeDeferredIndexes:error] || ![self _initializeTriggers:error]) {
      goto cleanup;
    }
  }
  
  // End transaction
  result = sqlite3_step(statements[kStatement_EndTransaction]);
  CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_EndTransaction]);
  
  // WAL manual checkpoint (ignore errors)
  result = sqlite3_wal_checkpoint_v2(_database, NULL, _ready ? SQLITE_CHECKPOINT_FULL : SQLITE_CHECKPOINT_TRUNCATE, NULL, NULL);
  if (result != SQLITE_OK) {
    XLOG_ERROR(@"Failed checkpointing commit database at \"%@\" (%i): %s", _databasePath, result, sqlite3_errmsg(_database));
    XLOG_DEBUG_UNREACHABLE();
  }
  
  // We're done
  XLOG_VERBOSE(@"Commit database for \"%@\" %s in %.3f seconds (%lu added, %lu removed)", _repository.repositoryPath, _ready ? "updated" : "initialized", CFAbsoluteTimeGetCurrent() - time, (unsigned long)addedCommits, (unsigned long)removedCommits);
  _ready = YES;
  success = YES;
  
#if __CHECK_CONSISTENCY__
  // Check consistency
  [self _checkConsistency];
#endif
  
cleanup:
  if (!success) {
    for (int i = 0; i < kNumStatements; ++i) {
      sqlite3_reset(_statements[i]);  // If the update failed, make sure to reset all statements to ensure they are in clean state for next time and release the database writer lock
    }
  }
  CFRelease(newSet);
  CFRelease(oldSet);
  GC_LIST_FREE(newTips);
  GC_LIST_FREE(oldTips);
  return success;
}

- (NSArray*)findCommitsMatching:(NSString*)match error:(NSError**)error {
  return [self findCommitsUsingHistory:nil matching:match error:error];
}

- (NSArray*)findCommitsUsingHistory:(GCHistory*)history matching:(NSString*)match error:(NSError**)error {
  BOOL success = NO;
  NSMutableArray* results = [NSMutableArray array];
  sqlite3_stmt** statements = _statements;
  
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_bind_text, statements[kStatement_SearchCommits], 1, match.UTF8String, -1, SQLITE_STATIC);
  while (1) {
    int result = sqlite3_step(statements[kStatement_SearchCommits]);
    if (result != SQLITE_ROW) {
      CHECK_SQLITE_FUNCTION_CALL(goto cleanup, result, == SQLITE_DONE);
      break;
    }
    XLOG_DEBUG_CHECK(sqlite3_column_bytes(statements[kStatement_SearchCommits], 0) == GIT_OID_RAWSZ);
    const git_oid* oid = sqlite3_column_blob(statements[kStatement_SearchCommits], 0);
    if (history) {
      GCHistoryCommit* commit = [history historyCommitForOID:oid];
      if (commit) {
        [results addObject:commit];
      }
    } else {
      git_commit* rawCommit;
      int status = git_commit_lookup(&rawCommit, _repository.private, oid);
      if (status == GIT_ENOTFOUND) {
        continue;
      }
      CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
      GCCommit* commit = [[GCCommit alloc] initWithRepository:_repository commit:rawCommit];
      [results addObject:commit];
      [commit release];
    }
  }
  CALL_SQLITE_FUNCTION_GOTO(cleanup, sqlite3_reset, statements[kStatement_SearchCommits]);
  success = YES;
  
cleanup:
  if (!success) {
    sqlite3_reset(statements[kStatement_SearchCommits]);
  }
  return success ? results : nil;
}

#if __CHECK_CONSISTENCY__

// TODO: Test users table consistency
- (void)_checkConsistency {
  sqlite3_stmt* statement1;
  if (sqlite3_prepare_v2(_database, "SELECT _id_, retain_count FROM " kCommitsTableName, -1, &statement1, NULL) == SQLITE_OK) {
    sqlite3_stmt* statement2;
    if (sqlite3_prepare_v2(_database, "SELECT COUNT(*) FROM " kRelationsTableName " WHERE parent=?1", -1, &statement2, NULL) == SQLITE_OK) {
      sqlite3_stmt* statement3;
      if (sqlite3_prepare_v2(_database, "SELECT 1 FROM " kTipsTableName " WHERE `commit`=?1", -1, &statement3, NULL) == SQLITE_OK) {
        while (1) {
          int result = sqlite3_step(statement1);
          if (result != SQLITE_ROW) {
            XLOG_DEBUG_CHECK(result == SQLITE_DONE);
            break;
          }
          sqlite3_int64 commitID = sqlite3_column_int64(statement1, 0);
          int retainCount = sqlite3_column_int(statement1, 1);
          
          sqlite3_bind_int64(statement2, 1, commitID);
          if (sqlite3_step(statement2) != SQLITE_ROW) {
            XLOG_DEBUG_UNREACHABLE();
            break;
          }
          int count = sqlite3_column_int(statement2, 0);
          sqlite3_reset(statement2);
          
          sqlite3_bind_int64(statement3, 1, commitID);
          result = sqlite3_step(statement3);
          if (result == SQLITE_ROW) {
            count += 1;
          } else {
            XLOG_DEBUG_CHECK(result == SQLITE_DONE);
          }
          sqlite3_reset(statement3);
          
          XLOG_DEBUG_CHECK(count == retainCount);
        }
        sqlite3_finalize(statement3);
      }
      sqlite3_finalize(statement2);
    }
    sqlite3_finalize(statement1);
  }
}

#endif

#if DEBUG

- (NSUInteger)_countRowsForTable:(const char*)table {
  NSUInteger count = NSNotFound;
  sqlite3_stmt* statement;
  if (sqlite3_prepare_v2(_database, [[NSString stringWithFormat:@"SELECT COUNT(*) FROM %s", table] UTF8String], -1, &statement, NULL) == SQLITE_OK) {
    if (sqlite3_step(statement) == SQLITE_ROW) {
      count = sqlite3_column_int(statement, 0);
    }
    sqlite3_finalize(statement);
  }
  return count;
}

- (NSUInteger)countTips {
  return [self _countRowsForTable:kTipsTableName];
}

- (NSUInteger)countCommits {
  return [self _countRowsForTable:kCommitsTableName];
}

- (NSUInteger)countRelations {
  return [self _countRowsForTable:kRelationsTableName];
}

- (NSUInteger)totalCommitRetainCount {
  NSUInteger count = NSNotFound;
  sqlite3_stmt* statement;
  if (sqlite3_prepare_v2(_database, "SELECT SUM(retain_count) FROM " kCommitsTableName, -1, &statement, NULL) == SQLITE_OK) {
    if (sqlite3_step(statement) == SQLITE_ROW) {
      count = sqlite3_column_int(statement, 0);
    }
    sqlite3_finalize(statement);
  }
  return count;
}

#endif

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@] \"%@\"", self.class, _databasePath];
}

@end
