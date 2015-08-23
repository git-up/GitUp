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

/* Original license from https://github.com/libgit2/libgit2-backends/ follows */

/*
 * This file is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License, version 2,
 * as published by the Free Software Foundation.
 *
 * In addition to the permissions in the GNU General Public License,
 * the authors give you unlimited permission to link the compiled
 * version of this file into combinations with other programs,
 * and to distribute those combinations without any restriction
 * coming from the use of this file.  (The General Public License
 * restrictions do apply in other respects; for example, they cover
 * modification of the file, and distribution when not linked into
 * a combined executable.)
 *
 * This file is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING.  If not, write to
 * the Free Software Foundation, 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import <sqlite3.h>

#import "GCPrivate.h"

#define ODB_TABLE_NAME "libgit2_odb"
#define REFDB_TABLE_NAME "libgit2_refdb"

#pragma mark - odb_backend

typedef struct {
  git_odb_backend parent;
  sqlite3* db;
  sqlite3_stmt* exists;
  sqlite3_stmt* exists_prefix;
  sqlite3_stmt* read;
  sqlite3_stmt* read_prefix;
  sqlite3_stmt* read_header;
  sqlite3_stmt* write;
  sqlite3_stmt* foreach;
} sqlite3_odb;

static int _odb_backend_init_db(sqlite3* db) {
  static const char* sql_check = "SELECT name FROM sqlite_master WHERE type='table' AND name='" ODB_TABLE_NAME "';";
  static const char* sql_creat =
    "CREATE TABLE '" ODB_TABLE_NAME "' ("
    "'oid' CHARACTER(20) PRIMARY KEY NOT NULL,"
    "'type' INTEGER NOT NULL,"
    "'size' INTEGER NOT NULL,"
    "'data' BLOB);";
  
  sqlite3_stmt* st_check;
  if (sqlite3_prepare_v2(db, sql_check, -1, &st_check, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  
  int error;
  switch (sqlite3_step(st_check)) {
    
    case SQLITE_DONE:
      if (sqlite3_exec(db, sql_creat, NULL, NULL, NULL) != SQLITE_OK) {
        error = GIT_ERROR;
      } else {
        error = GIT_OK;
      }
      break;
    
    case SQLITE_ROW:
      error = GIT_OK;
      break;
    
    default:
      error = GIT_ERROR;
      break;
    
  }
  
  sqlite3_finalize(st_check);
  return error;
}

static int _odb_backend_init_statements(sqlite3_odb* backend) {
  static const char* sql_exists =
    "SELECT 1 FROM '" ODB_TABLE_NAME "' WHERE oid = ?1";
  static const char* sql_exists_prefix =
    "SELECT oid FROM '" ODB_TABLE_NAME "' WHERE substr(HEX(oid), 1, ?1) = UPPER(?2)";
  static const char* sql_read =
    "SELECT type, size, data FROM '" ODB_TABLE_NAME "' WHERE oid = ?1";
  static const char* sql_read_prefix =
    "SELECT oid, type, size, data FROM '" ODB_TABLE_NAME "' WHERE substr(HEX(oid), 1, ?1) = UPPER(?2)";
  static const char* sql_read_header =
    "SELECT type, size FROM '" ODB_TABLE_NAME "' WHERE oid = ?1";
  static const char* sql_write =
    "INSERT OR IGNORE INTO '" ODB_TABLE_NAME "' VALUES (?1, ?2, ?3, ?4)";  // Just ignore if attempting to insert an already existing object
  static const char* sql_foreach =
    "SELECT oid FROM '" ODB_TABLE_NAME "'";
  
  if (sqlite3_prepare_v2(backend->db, sql_exists, -1, &backend->exists, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_exists_prefix, -1, &backend->exists_prefix, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_read, -1, &backend->read, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_read_prefix, -1, &backend->read_prefix, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_read_header, -1, &backend->read_header, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_write, -1, &backend->write, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_foreach, -1, &backend->foreach, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  
  return GIT_OK;
}

static int _odb_read_header(size_t* len_out, git_otype* type_out, git_odb_backend* _backend, const git_oid* oid) {
  XLOG_DEBUG_CHECK(len_out && type_out && _backend && oid);
  sqlite3_odb* backend = (sqlite3_odb*)_backend;
  int error = GIT_ERROR;
  
  if (sqlite3_bind_blob(backend->read_header, 1, oid->id, GIT_OID_RAWSZ, SQLITE_STATIC) == SQLITE_OK) {
    if (sqlite3_step(backend->read_header) == SQLITE_ROW) {
      *type_out = sqlite3_column_int(backend->read_header, 0);
      *len_out = sqlite3_column_int(backend->read_header, 1);
      // assert(sqlite3_step(backend->read_header) == SQLITE_DONE);
      error = GIT_OK;
    } else {
      error = GIT_ENOTFOUND;
    }
  }
  sqlite3_reset(backend->read_header);
  
  return error;
}

static int _odb_read(void** data_out, size_t* len_out, git_otype* type_out, git_odb_backend* _backend, const git_oid* oid) {
  XLOG_DEBUG_CHECK(data_out && len_out && type_out && _backend && oid);
  sqlite3_odb* backend = (sqlite3_odb*)_backend;
  int error = GIT_ERROR;
  
  if (sqlite3_bind_blob(backend->read, 1, oid->id, GIT_OID_RAWSZ, SQLITE_STATIC) == SQLITE_OK) {
    if (sqlite3_step(backend->read) == SQLITE_ROW) {
      *type_out = sqlite3_column_int(backend->read, 0);
      *len_out = sqlite3_column_int(backend->read, 1);
      *data_out = git_odb_backend_malloc(_backend, *len_out);
      bcopy(sqlite3_column_blob(backend->read, 2), *data_out, *len_out);
      // assert(sqlite3_step(backend->read) == SQLITE_DONE);
      error = GIT_OK;
    } else {
      error = GIT_ENOTFOUND;
    }
  }
  sqlite3_reset(backend->read);
  
  return error;
}

// TODO: Optimize lookup avoiding HEX conversion
static int _odb_read_prefix(git_oid* oid_out, void** data_out, size_t* len_out, git_otype* type_out, git_odb_backend* _backend, const git_oid* short_oid, size_t len) {
  XLOG_DEBUG_CHECK(oid_out && data_out && len_out && type_out && _backend && short_oid);
  sqlite3_odb* backend = (sqlite3_odb*)_backend;
  int error = GIT_ERROR;
  
  if (len >= GIT_OID_HEXSZ) {
    error = _odb_read(data_out, len_out, type_out, _backend, short_oid);
    if (error == GIT_OK) {
      git_oid_cpy(oid_out, short_oid);
    }
  } else {
    if (sqlite3_bind_int(backend->read_prefix, 1, (int)len) == SQLITE_OK) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wvla"
      char buffer[len + 1];
#pragma clang diagnostic pop
      assert(git_oid_tostr(buffer, len + 1, short_oid));
      if (sqlite3_bind_text(backend->read_prefix, 2, buffer, (int)len, SQLITE_STATIC) == SQLITE_OK) {
        int result = sqlite3_step(backend->read_prefix);
        if (result == SQLITE_ROW) {
          XLOG_DEBUG_CHECK(sqlite3_column_bytes(backend->read_prefix, 0) == GIT_OID_RAWSZ);
          const void* oid = sqlite3_column_blob(backend->read_prefix, 0);
          git_oid_cpy(oid_out, oid);
          *type_out = sqlite3_column_int(backend->read_prefix, 1);
          *len_out = sqlite3_column_int(backend->read_prefix, 2);
          *data_out = git_odb_backend_malloc(_backend, *len_out);
          bcopy(sqlite3_column_blob(backend->read_prefix, 3), *data_out, *len_out);
          // assert(sqlite3_step(backend->read_prefix) == SQLITE_DONE);
          error = GIT_OK;
        } else if (result == SQLITE_DONE) {
          error = GIT_ENOTFOUND;
        }
      }
    }
    sqlite3_reset(backend->read_prefix);
  }
  
  return error;
}

static int _odb_exists(git_odb_backend* _backend, const git_oid* oid) {
  XLOG_DEBUG_CHECK(_backend && oid);
  sqlite3_odb* backend = (sqlite3_odb*)_backend;
  int exists = 0;
  
  if (sqlite3_bind_blob(backend->exists, 1, oid->id, GIT_OID_RAWSZ, SQLITE_STATIC) == SQLITE_OK) {
    if (sqlite3_step(backend->exists) == SQLITE_ROW) {
      // assert(sqlite3_step(backend->exists) == SQLITE_DONE);
      exists = 1;
    }
  }
  sqlite3_reset(backend->exists);
  
  return exists;
}

// TODO: Optimize lookup avoiding HEX conversion
static int _odb_exists_prefix(git_oid* oid_out, git_odb_backend* _backend, const git_oid* short_oid, size_t len) {  // WARNING: "len" is in hexadecimal characters, not bytes!
  XLOG_DEBUG_CHECK(oid_out && _backend && short_oid);
  sqlite3_odb* backend = (sqlite3_odb*)_backend;
  int error = GIT_ERROR;
  
  if (len >= GIT_OID_HEXSZ) {
    if (_odb_exists(_backend, short_oid)) {
      git_oid_cpy(oid_out, short_oid);
      error = GIT_OK;
    } else {
      error = GIT_ENOTFOUND;
    }
  } else {
    if (sqlite3_bind_int(backend->exists_prefix, 1, (int)len) == SQLITE_OK) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wvla"
      char buffer[len + 1];
#pragma clang diagnostic pop
      assert(git_oid_tostr(buffer, len + 1, short_oid));
      if (sqlite3_bind_text(backend->exists_prefix, 2, buffer, (int)len, SQLITE_STATIC) == SQLITE_OK) {
        int result = sqlite3_step(backend->exists_prefix);
        if (result == SQLITE_ROW) {
          XLOG_DEBUG_CHECK(sqlite3_column_bytes(backend->exists_prefix, 0) == GIT_OID_RAWSZ);
          const void* oid = sqlite3_column_blob(backend->exists_prefix, 0);
          git_oid_cpy(oid_out, oid);
          // assert(sqlite3_step(backend->exists_prefix) == SQLITE_DONE);
          error = GIT_OK;
        } else if (result == SQLITE_DONE) {
          error = GIT_ENOTFOUND;
        }
      }
    }
    sqlite3_reset(backend->exists_prefix);
  }
  
  return error;
}

static int _odb_write(git_odb_backend* _backend, const git_oid* oid, const void* data, size_t len, git_otype type) {
  XLOG_DEBUG_CHECK(_backend && oid && data);
  sqlite3_odb* backend = (sqlite3_odb*)_backend;
  int error = GIT_ERROR;
  
  if (sqlite3_bind_blob(backend->write, 1, oid->id, GIT_OID_RAWSZ, SQLITE_STATIC) == SQLITE_OK) {
    if (sqlite3_bind_int(backend->write, 2, type) == SQLITE_OK) {
      if (sqlite3_bind_int(backend->write, 3, (int)len) == SQLITE_OK) {
        if (sqlite3_bind_blob(backend->write, 4, data, (int)len, SQLITE_STATIC) == SQLITE_OK) {
          if (sqlite3_step(backend->write) == SQLITE_DONE) {
            error = GIT_OK;
          }
        }
      }
    }
  }
  sqlite3_reset(backend->write);
  
  return error;
}

static void _odb_free(git_odb_backend* _backend) {
  XLOG_DEBUG_CHECK(_backend);
  sqlite3_odb* backend = (sqlite3_odb*)_backend;
  
  sqlite3_finalize(backend->exists);
  sqlite3_finalize(backend->exists_prefix);
  sqlite3_finalize(backend->read);
  sqlite3_finalize(backend->read_prefix);
  sqlite3_finalize(backend->read_header);
  sqlite3_finalize(backend->write);
  sqlite3_finalize(backend->foreach);
  sqlite3_close(backend->db);
  
  free(backend);
}

static int _odb_foreach(git_odb_backend* _backend, git_odb_foreach_cb cb, void* payload) {
  XLOG_DEBUG_CHECK(_backend && cb);
  sqlite3_odb* backend = (sqlite3_odb*)_backend;
  int error = GIT_ERROR;
  
  while (1) {
    int result = sqlite3_step(backend->foreach);
    if (result == SQLITE_ROW) {
      XLOG_DEBUG_CHECK(sqlite3_column_bytes(backend->foreach, 0) == GIT_OID_RAWSZ);
      error = cb(sqlite3_column_blob(backend->foreach, 0), payload);
      if (error) {
        break;
      }
    } else if (result == SQLITE_DONE) {
      error = GIT_OK;
      break;
    } else {
      break;
    }
  }
  sqlite3_reset(backend->foreach);
  
  return error;
}

// TODO: Add debug lock to ensure only used by one thread at a time
// TODO: Use transactions for write if matching operations
static int git_odb_backend_sqlite3(git_odb_backend** backend_out, const char* sqlite_db) {
  int error = GIT_ERROR;
  
  sqlite3_odb* backend = calloc(1, sizeof(sqlite3_odb));
  git_odb_init_backend(&backend->parent, GIT_ODB_BACKEND_VERSION);
  if (sqlite3_open_v2(sqlite_db, &backend->db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
    goto cleanup;
  }
  error = _odb_backend_init_db(backend->db);
  if (error < 0) {
    goto cleanup;
  }
  error = _odb_backend_init_statements(backend);
  if (error < 0) {
    goto cleanup;
  }
  
  backend->parent.read = &_odb_read;
  backend->parent.read_prefix = &_odb_read_prefix;
  backend->parent.read_header = &_odb_read_header;  // This is actually optional and if not implemented read() will be used instead
  backend->parent.write = &_odb_write;
//  backend->parent.writestream =
//  backend->parent.readstream = 
  backend->parent.exists = &_odb_exists;
  backend->parent.exists_prefix = &_odb_exists_prefix;
//  backend->parent.refresh =
  backend->parent.foreach = &_odb_foreach;
//  backend->parent.writepack =
  backend->parent.free = &_odb_free;
  
  *backend_out = (git_odb_backend *)backend;
  return GIT_OK;
  
cleanup:
  _odb_free((git_odb_backend *)backend);
  return error;
}

#pragma mark - refdb_backend

typedef struct {
  git_refdb_backend parent;
  sqlite3* db;
  
  sqlite3_stmt* exists;
  sqlite3_stmt* lookup;
  sqlite3_stmt* iterate;
  sqlite3_stmt* write;
  sqlite3_stmt* rename;
  sqlite3_stmt* delete;
  sqlite3_stmt* delete_oid;
  sqlite3_stmt* delete_target;
} sqlite3_refdb;

typedef struct {
  git_reference_iterator parent;
  sqlite3_stmt* statement;
} sqlite3_refdb_iterator;

static int _refdb_backend_init_db(sqlite3* db) {
  static const char* sql_check = "SELECT name FROM sqlite_master WHERE type='table' AND name='" REFDB_TABLE_NAME "';";
  static const char* sql_creat =
    "CREATE TABLE '" REFDB_TABLE_NAME "' ("
    "'name' TEXT PRIMARY KEY NOT NULL,"
    "'oid' CHARACTER(20),"
    "'target' TEXT);";
  
  sqlite3_stmt* st_check;
  if (sqlite3_prepare_v2(db, sql_check, -1, &st_check, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  
  int error;
  switch (sqlite3_step(st_check)) {
    
    case SQLITE_DONE:
      if (sqlite3_exec(db, sql_creat, NULL, NULL, NULL) != SQLITE_OK) {
        error = GIT_ERROR;
      } else {
        error = GIT_OK;
      }
      break;
    
    case SQLITE_ROW:
      error = GIT_OK;
      break;
    
    default:
      error = GIT_ERROR;
      break;
    
  }
  
  sqlite3_finalize(st_check);
  return error;
}

static int _refdb_backend_init_statements(sqlite3_refdb* backend) {
  static const char* sql_exists =
    "SELECT 1 FROM '" REFDB_TABLE_NAME "' WHERE name = ?1";
  static const char* sql_lookup =
    "SELECT name, oid, target FROM '" REFDB_TABLE_NAME "' WHERE name = ?1";
  static const char* sql_iterate =
    "SELECT name, oid, target FROM '" REFDB_TABLE_NAME "' WHERE name != 'HEAD' ORDER BY name ASC";
  static const char* sql_delete =
    "DELETE FROM '" REFDB_TABLE_NAME "' WHERE name = ?1";
  static const char* sql_delete_oid =
    "DELETE FROM '" REFDB_TABLE_NAME "' WHERE name = ?1 AND oid = ?2";
  static const char* sql_delete_target =
    "DELETE FROM '" REFDB_TABLE_NAME "' WHERE name = ?1 AND target = ?2";
  static const char* sql_write =
    "INSERT OR REPLACE INTO '" REFDB_TABLE_NAME "' (name, oid, target) VALUES (?1, ?2, ?3)";
  static const char* sql_rename =
    "UPDATE '" REFDB_TABLE_NAME "' SET name = ?2 WHERE name = ?1";
  
  if (sqlite3_prepare_v2(backend->db, sql_exists, -1, &backend->exists, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_lookup, -1, &backend->lookup, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_iterate, -1, &backend->iterate, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_delete, -1, &backend->delete, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_delete_oid, -1, &backend->delete_oid, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_delete_target, -1, &backend->delete_target, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_write, -1, &backend->write, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  if (sqlite3_prepare_v2(backend->db, sql_rename, -1, &backend->rename, NULL) != SQLITE_OK) {
    return GIT_ERROR;
  }
  
  return GIT_OK;
}

static int _refdb_exists(int* exists, git_refdb_backend* _backend, const char* ref_name) {
  XLOG_DEBUG_CHECK(exists && _backend && ref_name);
  sqlite3_refdb* backend = (sqlite3_refdb*)_backend;
  int error = GIT_ERROR;
  
  *exists = 0;
  if (sqlite3_bind_text(backend->exists, 1, ref_name, -1, SQLITE_STATIC) == SQLITE_OK) {
    int result = sqlite3_step(backend->exists);
    if (result == SQLITE_ROW) {
      *exists = 1;
      // assert(sqlite3_step(backend->exists) == SQLITE_DONE);
      error = GIT_OK;
    } else if (result == SQLITE_DONE) {
      error = GIT_OK;
    }
  }
  sqlite3_reset(backend->exists);
  
  return error;
}

static git_reference* _refdb_create_reference(git_reference** reference_out, sqlite3_stmt* statement) {
  int error = GIT_ERROR;
  const char* name = (const char*)sqlite3_column_text(statement, 0);
  const void* oid = sqlite3_column_blob(statement, 1);
  XLOG_DEBUG_CHECK(!oid || (sqlite3_column_bytes(statement, 1) == GIT_OID_RAWSZ));
  const char* target = (const char*)sqlite3_column_text(statement, 2);
  if (target) {
    *reference_out = git_reference__alloc_symbolic(name, target);
    error = GIT_OK;
  } else if (oid) {
    *reference_out = git_reference__alloc(name, oid, NULL);
    error = GIT_OK;
  }
  return error;
}

static int _refdb_lookup(git_reference** reference_out, git_refdb_backend* _backend, const char* ref_name) {
  XLOG_DEBUG_CHECK(reference_out && _backend && ref_name);
  sqlite3_refdb* backend = (sqlite3_refdb*)_backend;
  int error = GIT_ERROR;
  
  *reference_out = NULL;
  
  if (sqlite3_bind_text(backend->lookup, 1, ref_name, -1, SQLITE_STATIC) == SQLITE_OK) {
    int result = sqlite3_step(backend->lookup);
    if (result == SQLITE_ROW) {
      error = _refdb_create_reference(reference_out, backend->lookup);
      // assert(sqlite3_step(backend->lookup) == SQLITE_DONE);
    } else if (result == SQLITE_DONE) {
      error = GIT_ENOTFOUND;
    }
  }
  sqlite3_reset(backend->lookup);
  
  return error;
}

static int _refdb_iterator_next(git_reference** reference_out, git_reference_iterator* _iterator) {
  XLOG_DEBUG_CHECK(reference_out && _iterator);
  sqlite3_refdb_iterator* iterator = (sqlite3_refdb_iterator*)_iterator;
  int error = GIT_ERROR;
  
  *reference_out = NULL;
  
  int result = sqlite3_step(iterator->statement);
  if (result == SQLITE_ROW) {
    error = _refdb_create_reference(reference_out, iterator->statement);
  } else if (result == SQLITE_DONE) {
    error = GIT_ITEROVER;
  }
  
  return error;
}

static int _refdb_iterator_next_name(const char** ref_name_out, git_reference_iterator* _iterator) {
  XLOG_DEBUG_CHECK(ref_name_out && _iterator);
  sqlite3_refdb_iterator* iterator = (sqlite3_refdb_iterator*)_iterator;
  int error = GIT_ERROR;
  
  *ref_name_out = NULL;
  
  int result = sqlite3_step(iterator->statement);
  if (result == SQLITE_ROW) {
    *ref_name_out = (const char*)sqlite3_column_text(iterator->statement, 0);  // TODO: Should we copy the string?
    error = GIT_OK;
  } else if (result == SQLITE_DONE) {
    error = GIT_ITEROVER;
  }
  
  return error;
}

static void _refdb_iterator_free(git_reference_iterator* _iterator) {
  XLOG_DEBUG_CHECK(_iterator);
  sqlite3_refdb_iterator* iterator = (sqlite3_refdb_iterator*)_iterator;
  
  sqlite3_reset(iterator->statement);
  
  free(iterator);
}

static int _refdb_iterator(git_reference_iterator** iterator_out, git_refdb_backend* _backend, const char* glob) {
  XLOG_DEBUG_CHECK(iterator_out && _backend && !glob);
  sqlite3_refdb* backend = (sqlite3_refdb*)_backend;
  
  sqlite3_refdb_iterator* iterator = calloc(1, sizeof(sqlite3_refdb_iterator));
  iterator->parent.next = &_refdb_iterator_next;
  iterator->parent.next_name = &_refdb_iterator_next_name;
  iterator->parent.free = &_refdb_iterator_free;
  iterator->statement = backend->iterate;
  *iterator_out = (git_reference_iterator*)iterator;
  
  return GIT_OK;
}

static int _refdb_write(git_refdb_backend* _backend, const git_reference* ref, int force, const git_signature* who, const char* message, const git_oid* old_id, const char* old_target) {
  XLOG_DEBUG_CHECK(_backend && ref && (old_id || old_target || (!old_id && !old_target)));
  sqlite3_refdb* backend = (sqlite3_refdb*)_backend;
  
  git_reference* oldRef;
  int error = _refdb_lookup(&oldRef, _backend, git_reference_name(ref));
  if (error == GIT_OK) {
    if (force) {
      if (old_id) {
        if ((git_reference_type(oldRef) != GIT_REF_OID) || !git_oid_equal(git_reference_target(oldRef), old_id)) {
          error = GIT_EMODIFIED;
        }
      } else if (old_target) {
        if ((git_reference_type(oldRef) != GIT_REF_SYMBOLIC) && strcmp(git_reference_symbolic_target(oldRef), old_target)) {
          error = GIT_EMODIFIED;
        }
      }
    } else {
      error = GIT_EEXISTS;
    }
    git_reference_free(oldRef);
  } else if (error == GIT_ENOTFOUND) {
    error = GIT_OK;
  }
  
  if (error == GIT_OK) {
    error = GIT_ERROR;
    if (sqlite3_bind_text(backend->write, 1, git_reference_name(ref), -1, SQLITE_STATIC) == SQLITE_OK) {
      int result = SQLITE_ERROR;
      if (git_reference_type(ref) == GIT_REF_OID) {
        result = sqlite3_bind_blob(backend->write, 2, git_reference_target(ref)->id, GIT_OID_RAWSZ, SQLITE_STATIC);
        if (result == SQLITE_OK) {
          result = sqlite3_bind_null(backend->write, 3);
        }
      } else if (git_reference_type(ref) == GIT_REF_SYMBOLIC) {
        result = sqlite3_bind_null(backend->write, 2);
        if (result == SQLITE_OK) {
          result = sqlite3_bind_text(backend->write, 3, git_reference_symbolic_target(ref), -1, SQLITE_STATIC);
        }
      }
      if (result == SQLITE_OK) {
        result = sqlite3_step(backend->write);
        if (result == SQLITE_DONE) {
          error = GIT_OK;
        }
      }
    }
    sqlite3_reset(backend->write);
  }
  
  return error;
}

// TODO: Update reflog if available
static int _refdb_rename(git_reference** reference_out, git_refdb_backend* _backend, const char* old_name, const char* new_name, int force, const git_signature* who, const char* message) {
  XLOG_DEBUG_CHECK(reference_out && _backend && old_name && new_name);
  sqlite3_refdb* backend = (sqlite3_refdb*)_backend;
  
  *reference_out = NULL;
  
  int exists;
  int error = _refdb_exists(&exists, _backend, new_name);
  if (error == GIT_OK) {
    if (exists && !force) {
      error = GIT_EEXISTS;
    } else {
      if (exists) {
        if (sqlite3_bind_text(backend->delete, 1, new_name, -1, SQLITE_STATIC) == SQLITE_OK) {
          if (sqlite3_step(backend->delete) == SQLITE_DONE) {
            error = GIT_OK;
          }
        }
        sqlite3_reset(backend->delete);
      }
      
      if (error == GIT_OK) {
        error = GIT_ERROR;
        if (sqlite3_bind_text(backend->rename, 1, old_name, -1, SQLITE_STATIC) == SQLITE_OK) {
          if (sqlite3_bind_text(backend->rename, 2, new_name, -1, SQLITE_STATIC) == SQLITE_OK) {
            if (sqlite3_step(backend->rename) == SQLITE_DONE) {
              if (sqlite3_changes(backend->db) == 1) {
                error = _refdb_lookup(reference_out, _backend, new_name);
              } else {
                error = GIT_ENOTFOUND;
              }
            }
          }
        }
        sqlite3_reset(backend->rename);
      }
    }
  }
  
  return error;
}

static int _refdb_del(git_refdb_backend* _backend, const char* ref_name, const git_oid* old_id, const char* old_target) {
  XLOG_DEBUG_CHECK(_backend && ref_name && (old_id || old_target || (!old_id && !old_target)));
  sqlite3_refdb* backend = (sqlite3_refdb*)_backend;
  BOOL shouldDelete = NO;
  
  git_reference* oldRef;
  int error = _refdb_lookup(&oldRef, _backend, ref_name);
  if (error == GIT_OK) {
    if (old_id) {
      if ((git_reference_type(oldRef) == GIT_REF_OID) && git_oid_equal(git_reference_target(oldRef), old_id)) {
        shouldDelete = YES;
      }
    } else if (old_target) {
      if ((git_reference_type(oldRef) == GIT_REF_SYMBOLIC) && !strcmp(git_reference_symbolic_target(oldRef), old_target)) {
        shouldDelete = YES;
      }
    } else {
      shouldDelete = YES;
    }
    git_reference_free(oldRef);
  }
  
  if (shouldDelete) {
    if (sqlite3_bind_text(backend->delete, 1, ref_name, -1, SQLITE_STATIC) == SQLITE_OK) {
      if (sqlite3_step(backend->delete) == SQLITE_DONE) {
        error = sqlite3_changes(backend->db) == 1 ? GIT_OK : GIT_ENOTFOUND;
      }
    }
    sqlite3_reset(backend->delete);
  }
  
  return error;
}

static int _refdb_has_log(git_refdb_backend* _backend, const char* refname) {
  return 0;
}

static int _refdb_ensure_log(git_refdb_backend* _backend, const char* refname) {
  XLOG_DEBUG_UNREACHABLE();
  return GIT_ERROR;
}

static void _refdb_free(git_refdb_backend* _backend) {
  XLOG_DEBUG_CHECK(_backend);
  sqlite3_refdb* backend = (sqlite3_refdb*)_backend;
  
  sqlite3_finalize(backend->exists);
  sqlite3_finalize(backend->lookup);
  sqlite3_finalize(backend->iterate);
  sqlite3_finalize(backend->write);
  sqlite3_finalize(backend->rename);
  sqlite3_finalize(backend->delete);
  sqlite3_finalize(backend->delete_oid);
  sqlite3_finalize(backend->delete_target);
  sqlite3_close(backend->db);
  
  free(backend);
}

static int _refdb_reflog_read(git_reflog** reflog_out, git_refdb_backend* _backend, const char* name) {
  XLOG_DEBUG_UNREACHABLE();
  return GIT_ERROR;
}

static int _refdb_reflog_write(git_refdb_backend* _backend, git_reflog* reflog) {
  XLOG_DEBUG_UNREACHABLE();
  return GIT_ERROR;
}

static int _refdb_reflog_rename(git_refdb_backend* _backend, const char* old_name, const char* new_name) {
  XLOG_DEBUG_UNREACHABLE();
  return GIT_ERROR;
}

static int _refdb_reflog_delete(git_refdb_backend* _backend, const char* name) {
  return GIT_OK;
}

// TODO: Add debug lock to ensure only used by one thread at a time
// TODO: Use transactions for write if matching operations
static int git_refdb_backend_sqlite3(git_refdb_backend** backend_out, const char* sqlite_db) {
  int error = GIT_ERROR;

  sqlite3_refdb* backend = calloc(1, sizeof(sqlite3_refdb));
  git_refdb_init_backend(&backend->parent, GIT_REFDB_BACKEND_VERSION);
  
  if (sqlite3_open_v2(sqlite_db, &backend->db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
    goto cleanup;
  }
  error = _refdb_backend_init_db(backend->db);
  if (error < 0) {
    goto cleanup;
  }
  error = _refdb_backend_init_statements(backend);
  if (error < 0) {
    goto cleanup;
  }
  
  backend->parent.exists = &_refdb_exists;
  backend->parent.lookup = &_refdb_lookup;
  backend->parent.iterator = &_refdb_iterator;
  backend->parent.write = &_refdb_write;
  backend->parent.rename = &_refdb_rename;
  backend->parent.del = &_refdb_del;
//  backend->parent.compress
  backend->parent.has_log = &_refdb_has_log;
  backend->parent.ensure_log = &_refdb_ensure_log;
  backend->parent.free = &_refdb_free;
  backend->parent.reflog_read = &_refdb_reflog_read;
  backend->parent.reflog_write = &_refdb_reflog_write;
  backend->parent.reflog_rename = &_refdb_reflog_rename;
  backend->parent.reflog_delete = &_refdb_reflog_delete;
//  backend->parent.lock
//  backend->parent.unlock
  
  *backend_out = (git_refdb_backend*)backend;
  return GIT_OK;
  
cleanup:
  _refdb_free((git_refdb_backend*)backend);
  return error;
}

#pragma mark - GCSQLiteRepository

@implementation GCSQLiteRepository {
  git_odb* _objectDB;
  git_odb_backend* _objectBackend;  // Not retained
  git_refdb* _referenceDB;
  git_refdb_backend* _referenceBackend;  // Not retained
  NSString* _configPath;
}

- (instancetype)initWithDatabase:(NSString*)databasePath error:(NSError**)error {
  return [self initWithDatabase:databasePath config:nil localRepositoryContents:nil error:error];
}

static int _ForeachCallback(const git_oid* oid, void* payload) {
  void** params = (void**)payload;
  git_odb* sourceODB = params[0];
  git_odb_backend* destBackend = params[1];
  
  git_odb_object* object;
  int error = git_odb_read(&object, sourceODB, oid);
  if (error == GIT_OK) {
    XLOG_DEBUG_CHECK(git_oid_equal(git_odb_object_id(object), oid));
    error = _odb_write(destBackend, oid, git_odb_object_data(object), git_odb_object_size(object), git_odb_object_type(object));
    git_odb_object_free(object);
  }
  return error;
}

- (BOOL)_copyLocalRepository:(NSString*)path error:(NSError**)error {
  BOOL success = NO;
  git_repository* repository = NULL;
  git_odb* odb = NULL;
  git_reference* headReference = NULL;
  git_reference_iterator* iterator = NULL;
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_open, &repository, path.fileSystemRepresentation);
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_odb, &odb, repository);
  void* params[] = {odb, _objectBackend};
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_odb_foreach, odb, _ForeachCallback, params);
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_lookup, &headReference, repository, kHEADReferenceFullName);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, _refdb_write, _referenceBackend, headReference, 0, NULL, NULL, NULL, NULL);
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_iterator_new, &iterator, repository);
  while (1) {
    git_reference* reference;
    int status = git_reference_next(&reference, iterator);
    if (status == GIT_ITEROVER) {
      break;
    }
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, _refdb_write, _referenceBackend, reference, 0, NULL, NULL, NULL, NULL);
    git_reference_free(reference);
  }
  
  success = YES;
  
cleanup:
  git_reference_iterator_free(iterator);
  git_reference_free(headReference);
  git_odb_free(odb);
  git_repository_free(repository);
  return success;
}

- (instancetype)initWithDatabase:(NSString*)databasePath config:(NSString*)configPath localRepositoryContents:(NSString*)localPath error:(NSError**)error {
  BOOL success = NO;
  git_repository* repository = NULL;
  git_config* config = NULL;
  
  if (sqlite3_threadsafe() == 0) {
    GC_SET_GENERIC_ERROR(@"SQLite3 not thread safe");
    goto cleanup;
  }
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_odb_new, &_objectDB);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_odb_backend_sqlite3, &_objectBackend, databasePath.fileSystemRepresentation);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_odb_add_backend, _objectDB, _objectBackend, 0);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_wrap_odb, &repository, _objectDB);  // This just allocates a git_repository structure and calls git_repository_set_odb()
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_refdb_new, &_referenceDB, repository);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_refdb_backend_sqlite3, &_referenceBackend, databasePath.fileSystemRepresentation);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_refdb_set_backend, _referenceDB, _referenceBackend);
  git_repository_set_refdb(repository, _referenceDB);
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_new, &config);
  if (configPath) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_add_file_ondisk, config, configPath.fileSystemRepresentation, GIT_CONFIG_LEVEL_LOCAL, false);
  } else {
    _configPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_config_add_file_ondisk, config, _configPath.fileSystemRepresentation, GIT_CONFIG_LEVEL_LOCAL, false);
  }
  git_repository_set_config(repository, config);
  
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_set_bare, repository);  // Repository is blank at this point and has no index so no need to remove it
  
  if (localPath) {
    if (![self _copyLocalRepository:localPath error:error]) {
      goto cleanup;
    }
  } else {
    git_reference* reference;
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_symbolic_create, &reference, repository, kHEADReferenceFullName, "refs/heads/master", false, NULL);
    git_reference_free(reference);
  }
  success = YES;
  
cleanup:
  git_config_free(config);
  if (success) {
    return [super initWithRepository:repository error:error];
  }
  git_repository_free(repository);
  return nil;
}

- (void)dealloc {
  if (_configPath) {
    unlink(_configPath.fileSystemRepresentation);
  }
  git_refdb_free(_referenceDB);
  git_odb_free(_objectDB);
}

@end
