#include "repository.h"
#include "common.h"
#include "types.h"
#include "oid.h"
#include "buffer.h"

/**
 * @file git2/gitup_repository.h
 * @brief Git repository management routines
 * @defgroup git_repository Git repository management routines
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

/**
 * Update or rewrite the gitlink in the workdir
 */
GIT_EXTERN(int) gitup_repository_update_gitlink(
    git_repository *repo, int use_relative_path);

/**
 * Locate the path to the local configuration file
 *
 * The returned path may be used on any `git_config` call to load the local
 * configuration file.
 *
 * @param repo The repository whose local configuration file to find
 * @param out Pointer to a user-allocated git_buf in which to store the path
 * @return 0 if a local configuration file has been found. Its path will be stored in `out`.
 */
GIT_EXTERN(int) gitup_repository_local_config_path(git_buf *out, git_repository *repo);

/** @} */
GIT_END_DECL
