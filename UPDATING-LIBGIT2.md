### Update Fork From Upstream

- Checkout https://github.com/git-up/libgit2
- Switch to `gitup` branch
- Add upstream remote at https://github.com/libgit2/libgit2 with `git remote add upstream git@github.com:libgit2/libgit2.git`
- Fetch from upstream with `git fetch --all`
- Make sure `gitup` branch current tip is tagged with the corresponding date e.g. `2015-12-02` and push tag
- Rebased `gitup` branch on top of upstream

### Test Fork

- Run `./update-xcode.sh`
- Select `libgit2_clar` project
- Enable address sanitizer
- Set environment variable `ASAN_OPTIONS` to `allocator_may_return_null=1`
- Run to run all default tests
- Run again passing `-sonline` as an argument to run online tests

### Update and Test GitUp

- Force push `gitup` branch to remote
- Force update `libgit2` submodule
- Open GitUp Xcode project
- Select `GitUpKit (OS X)` target and run tests
- Verify `GitUpKit (iOS)` builds
- Commit and push
