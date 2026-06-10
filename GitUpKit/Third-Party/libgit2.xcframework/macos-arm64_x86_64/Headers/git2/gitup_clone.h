#include "clone.h"
#include "common.h"
#include "types.h"
#include "indexer.h"
#include "checkout.h"
#include "remote.h"
#include "transport.h"

/**
 * @file git2/clone.h
 * @brief Git cloning routines
 * @defgroup git_clone Git cloning routines
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

GIT_EXTERN(int) gitup_clone_into(git_repository *repo,
                            git_remote *remote,
                            const git_fetch_options *fetch_opts,
                            const git_checkout_options *checkout_opts,
                            const char *branch);

GIT_END_DECL
