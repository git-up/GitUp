#include "common.h"
#include "oid.h"
#include "types.h"
#include "branch.h"

/**
 * @file git2/branch.h
 * @brief Git branch parsing routines
 * @defgroup git_branch Git branch management
 * @ingroup Git
 * @{
 */

GIT_BEGIN_DECL
// PATCH
// These functions are aliases and can be safely removed.
// Use `git_#{func}` instead.
// Replace and remove this file later.
GIT_EXTERN(int) gitup_branch_upstream_name(git_buf *out, git_repository *repo, const char *refname);
GIT_EXTERN(int) gitup_branch_upstream_remote(git_buf *buf, git_repository *repo, const char *refname);
GIT_EXTERN(int) gitup_branch_upstream_merge(git_buf *buf, git_repository *repo, const char *refname);

/** @} */
GIT_END_DECL
