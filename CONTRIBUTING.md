**[Pull requests](https://github.com/git-up/GitUp/pulls?q=is%3Apr) are welcome but be aware that GitUp is used for production work by many thousands of developers around the world, so the bar is very high. The last thing we want is letting the code quality slip or introducing a regression.**

**If you are unsure your contribution would be valuable to GitUp, or are looking for contributions to work on, check out the opened [GitHub Issues](https://github.com/git-up/GitUp/issues).**

**You must accept the terms of the [GitUp Contributor License Agreement](https://github.com/git-up/GitUp/wiki/GITUP-CONTRIBUTOR-LICENSE-AGREEMENT) before your pull request can be merged into upstream. To do so, you must include "I AGREE TO THE GITUP CONTRIBUTOR LICENSE AGREEMENT" somewhere in the description of your pull request.**

The following is a list of absolute requirements for PRs (not following them would result in immediate rejection):

1. The coding style MUST be followed exactly, which is trivial thanks to [Clang Format](http://clang.llvm.org/docs/ClangFormat.html)
  - Install Clang Format then simply run `./format-source.sh` to ensure your PR is styled correctly
2. Additions to `Core/` MUST have associated unit tests
3. Each commit MUST be a single change (e.g. adding a function or fixing a bug, but not both at once)
4. Each commit MUST be self-contained i.e. GitUp builds and remains fully functional when building it at this very commit
5. Commits MUST NOT change dozens or hundreds of files at once (outside of absolutely trivial changes like updating the copyright year)
  - Properly reviewing such a diff is close to impossible and there's a fair chance of a hidden regression sneaking in only to be discovered weeks later
  - Find a way to break the change into a series of logical changes affecting only a subset of the files each
6. Commit messages MUST have:
  - A clear and concise title that starts with an uppercase and doesn't end with a period e.g. "Changed app bundle ID to com.example.gitup" not "updated bundle id."
  - Unless it is trivial, a detailed summary explaining the change using full sentences and with punctuation (no need to wrap at 80 characters but keep lines to a reasonable length)
7. The pull request MUST contain as few commits as needed
8. The pull request MUST NOT contain fixup or revert commits (flatten them beforehand using GitUp!)
9. The pull request MUST be rebased on latest `master` when sent
