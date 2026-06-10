#include "submodule.h"

GIT_BEGIN_DECL

/**
 * Retains a submodule
 *
 * @param submodule Submodule object
 */
GIT_EXTERN(void) gitup_submodule_dup(git_submodule *submodule);

GIT_END_DECL
