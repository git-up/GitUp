**[Pull requests](https://github.com/git-up/GitUp/pulls) are welcome but be aware that GitUp is used for production work by many thousands of developers around the world, so the bar is very high. The last thing we want is letting the code quality slip or introducing a regression.**

**If you are unsure your contribution would be valuable to GitUp, or are looking for contributions to work on, check out the [dedicated topics](http://forums.gitup.co/c/contributions) in the GitUp community forums.**

The following is a list of absolute requirements for PRs (not following them would result in immediate rejection):

1. The coding style MUST be followed exactly (there is no style guide available but you can figure out from browsing the source)
2. You MUST use 2-spaces for indentation instead of tabs
3. Additions to `Core/` MUST have associated unit tests
4. Each commit MUST be a single change (e.g. adding a function or fixing a bug, but not both at once)
5. Each commit MUST be self-contained i.e. GitUp builds and remains fully functional when building it at this very commit
6. Commits MUST NOT change dozens or hundreds of files at once (outside of absolutely trivial changes likes updating the copyright year)
 - Properly reviewing such a diff is close to impossible and there's a fair chance of a hidden regression sneaking in only to be discovered weeks later
 - Find a way to break the change into a series of logical changes affecting only a subset of the files each
7. Commit messages MUST have:
 - A clear and concise title that starts with an uppercase and doesn't end with a period e.g. "Changed app bundle ID to com.example.gitup" not "updated bundle id."
 - Unless it is trivial, a detailed summary explaining the change using full sentences and with punctuation (no need to wrap at 80 characters but keep lines to a reasonable length)
8. The pull request MUST contain as few commits as needed
9. The pull request MUST NOT contain fixup or revert commits (flatten them beforehand using GitUp!)
10. The pull request MUST be rebased on latest `master` when sent

**Be aware that GitUp is under [GPL v3 license](http://www.gnu.org/licenses/gpl-3.0.txt), so any contribution you make will be GPL'ed.**
