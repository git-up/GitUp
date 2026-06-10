### Update Fork From Upstream

- Checkout https://github.com/git-up/libgit2
- Switch to the GitUp-maintained branch, e.g. `maint/v1.9`
- Add the upstream libgit2 remote if needed with `git remote add upstream git@github.com:libgit2/libgit2.git`
- Fetch from upstream with `git fetch --all`
- Rebase the GitUp-maintained branch on top of the matching upstream libgit2 branch
- Tag the updated branch tip with the corresponding date, e.g. `2015-12-02`
- Push the updated branch and tag

### Test Fork

These steps test the libgit2 fork itself. They are optional for rebuilding GitUp's vendored `libgit2.xcframework`.

- From the libgit2 checkout, run `./update-xcode.sh` if the generated libgit2 Xcode test project or `include/git2/sys/features.h` needs to be refreshed
- Open the generated libgit2 Xcode project
- Select the `libgit2_clar` scheme
- Enable address sanitizer
- Set `ASAN_OPTIONS` to `allocator_may_return_null=1`
- Run the default tests
- Run again passing `-sonline` to run online tests

### Update and Test GitUp

- Update the `GitUpKit/Third-Party/libgit2` submodule to the new GitUp-maintained branch commit
- Install CMake if needed with `brew install cmake`
- From `GitUpKit/Third-Party`, run `./rebuild-libgit2.sh`
- Verify `GitUpKit/Third-Party/libgit2.xcframework` was rebuilt
- Build `GitUpKit (macOS)` from `GitUp/GitUp.xcodeproj`
- Build the `Tool` scheme from `GitUp/GitUp.xcodeproj`
- Verify `GitUpKit (iOS)` if the iOS target is expected to build
- Commit the submodule update, rebuilt `libgit2.xcframework`, and any related project or script changes
