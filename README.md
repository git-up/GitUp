[![Build Status](https://travis-ci.org/git-up/GitUp.svg?branch=master)](https://travis-ci.org/git-up/GitUp)

GitUp
=====

**Work quickly, safely, and without headaches. The Git interface you've been missing all your life has finally arrived.**

<p align="center">
<img src="https://i.imgur.com/JuQIxJu.png" width="50%" height="50%"><img src="https://i.imgur.com/9rgXktz.png" width="50%" height="50%">
</p>

Git recently celebrated its 10 years anniversary, but most engineers are still confused by its intricacy (3 of the [top 5 questions of all time](http://stackoverflow.com/questions?sort=votes) on Stack Overflow are Git related). Since Git turns even simple actions into mystifying commands (“git add” to stage versus “git reset HEAD” to unstage anyone?), it’s no surprise users waste time, get frustrated, distract the rest of their team for help, or worse, screw up their repo!

GitUp is a bet to invent a new Git interaction model that lets engineers of all levels work quickly, safely, and without headaches. It's unlike any other Git client out there from the way it’s built (it interacts directly with the Git database on disk), to the way it works (you manipulate the repository graph instead of manipulating commits).

With GitUp, you get a truly efficient Git client for Mac:
- A **live and interactive repo graph** (edit, reorder, fixup, merge commits…),
- **Unlimited undo / redo** of almost all operations (even rebases and merges),
- Time Machine like **snapshots for 1-click rollbacks** to previous repo states,
- Features that don’t even exist natively in Git like a **visual commit splitter** or a **unified reflog browser**,
- **Instant search across the entire repo** including diff contents, 
- A **ridiculously fast UI**, often faster than the command line.

*GitUp was created by [@swisspol](https://github.com/swisspol) in late 2014 as a bet to reinvent the way developers interact with Git. After several months of work, it was made available in pre-release early 2015 and reached the [top of Hacker News](https://news.ycombinator.com/item?id=9653978) along with being [featured by Product Hunt](http://www.producthunt.com/tech/gitup-1) and [Daring Fireball](http://daringfireball.net/linked/2015/06/04/gitup). 30,000 lines of code later, GitUp reached 1.0 mid-August 2015 and was released open source as a gift to the developer community.*

Getting Started
===============

**Learn all about GitUp and download the latest release from http://gitup.co.**

**Read the [docs](https://github.com/git-up/GitUp/wiki) and use [GitHub Issues](https://github.com/git-up/GitUp/issues) for support & feedback.**

Releases notes are available at https://github.com/git-up/GitUp/releases. Builds tagged with a `v` (e.g. `v1.2.3`) are released on the "Stable" channel, while builds tagged with a `b` (e.g. `b1234`) are only released on the "Continuous" channel. You can change the update channel used by GitUp in the app preferences.

To build GitUp yourself, simply run the command `git clone --recursive https://github.com/git-up/GitUp.git` in Terminal, then open the `GitUp/GitUp.xcodeproj` Xcode project and hit Run.

**IMPORTANT:** If you do not have an Apple ID with a developer account for code signing Mac apps, the build  will fail with a code signing error. Simply delete the "Code Signing Identity" build setting of the "Application" target to work around the issue:

<p align="center">
<img src="http://i.imgur.com/dWpJExk.png">
</p>

**Alternatively**, if you do have a developer account, you can create the file "Xcode-Configurations/DEVELOPMENT_TEAM.xcconfig" with the following build setting as its content:
> DEVELOPMENT_TEAM = [Your TeamID]

For a more detailed description of this, you can have a look at the comments at the end of the file "Xcode-Configurations/Base.xcconfig". 

GitUpKit
========

**GitUp is built as a thin layer on top of a reusable generic Git toolkit called "GitUpKit". This means that you can use that same GitUpKit framework to build your very own Git UI!**

*GitUpKit has a very different goal than [ObjectiveGit](https://github.com/libgit2/objective-git). Instead of offering extensive raw bindings to [libgit2](https://github.com/libgit2/libgit2), GitUpKit only uses a minimal subset of libgit2 and reimplements everything else on top of it (it has its own "rebase engine" for instance).
This allows it to expose a very tight and consistent API, that completely follows Obj-C conventions and hides away the libgit2 complexity and sometimes inconsistencies. GitUpKit adds on top of that a number of exclusive and powerful features, from undo/redo and Time Machine like snapshots, to entire drop-in UI components.*

Architecture
------------

The GitUpKit source code is organized as 2 independent layers communicating only through the use of public APIs:

**Base Layer (depends on Foundation only and is compatible with OS X and iOS)**
- `Core/`: wrapper around the required minimal functionality of [libgit2](https://github.com/libgit2/libgit2), on top of which is then implemented all the Git functionality required by GitUp (note that GitUp uses a [slightly customized fork](https://github.com/git-up/libgit2/tree/gitup) of libgit2)
- `Extensions/`: categories on the `Core` classes to add convenience features implemented only using the public APIs

**UI Layer (depends on AppKit and is compatible with OS X only)**
- `Interface/`: low-level view classes e.g. `GIGraphView` to render the GitUp Map view
- `Utilities/`: interface utility classes e.g. the base view controller class `GIViewController`
- `Components/`: reusable single-view view controllers e.g. `GIDiffContentsViewController` to render a diff
- `Views/`: high-level reusable multi-views view controllers e.g. `GIAdvancedCommitViewController` to implement the entire GitUp Advanced Commit view

**IMPORTANT**: If the preprocessor constant `DEBUG` is defined to a non-zero value when building GitUpKit (this is the default when building in "Debug" configuration), a number of extra consistency checks are enabled at run time as well as extra logging. Be aware that this overhead can significantly affect performance.

GitUpKit API
------------

Using the GitUpKit API should be pretty straightforward since it is organized by functionality (e.g. repository, branches, commits, interface components, etc...) and a best effort has been made to name functions clearly.

Regarding the "Core" APIs, the best way to learn them is to peruse the associated unit tests - for instance see [the branch tests](GitUpKit/Core/GCBranch-Tests.m) for the branch API.

Here is some sample code to get you started (error handling is left as an exercise to the reader):

**Opening and browsing a repository:**
```objc
// Open repo
GCRepository* repo = [[GCRepository alloc] initWithExistingLocalRepository:<PATH> error:NULL];

// Make sure repo is clean
assert([repo checkClean:kGCCleanCheckOption_IgnoreUntrackedFiles error:NULL]);

// List all branches
NSArray* branches = [repo listAllBranches:NULL];
NSLog(@"%@", branches);

// Lookup HEAD
GCLocalBranch* headBranch;  // This would be nil if the HEAD is detached
GCCommit* headCommit;
[repo lookupHEADCurrentCommit:&headCommit branch:&headBranch error:NULL];
NSLog(@"%@ = %@", headBranch, headCommit);

// Load the *entire* repo history in memory for fast access, including all commits, branches and tags
GCHistory* history = [repo loadHistoryUsingSorting:kGCHistorySorting_ReverseChronological error:NULL];
assert(history);
NSLog(@"%lu commits total", history.allCommits.count);
NSLog(@"%@\n%@", history.rootCommits, history.leafCommits);
```

**Modifying a repository:**
```objc
// Take a snapshot of the repo
GCSnapshot* snapshot = [repo takeSnapshot:NULL];

// Create a new branch and check it out
GCLocalBranch* newBranch = [repo createLocalBranchFromCommit:headCommit withName:@"temp" force:NO error:NULL];
NSLog(@"%@", newBranch);
assert([repo checkoutLocalBranch:newBranch options:0 error:NULL]);

// Add a file to the index
[[NSData data] writeToFile:[repo.workingDirectoryPath stringByAppendingPathComponent:@"empty.data"] atomically:YES];
assert([repo addFileToIndex:@"empty.data" error:NULL]);

// Check index status
GCDiff* diff = [repo diffRepositoryIndexWithHEAD:nil options:0 maxInterHunkLines:0 maxContextLines:0 error:NULL];
assert(diff.deltas.count == 1);
NSLog(@"%@", diff);

// Create a commit
GCCommit* newCommit = [repo createCommitFromHEADWithMessage:@"Added file" error:NULL];
assert(newCommit);
NSLog(@"%@", newCommit);

// Restore repo to saved snapshot before topic branch and commit were created
BOOL success = [repo restoreSnapshot:snapshot withOptions:kGCSnapshotOption_IncludeAll reflogMessage:@"Rolled back" didUpdateReferences:NULL error:NULL];
assert(success);
  
// Make sure topic branch is gone
assert([repo findLocalBranchWithName:@"temp" error:NULL] == nil);
  
// Update workdir and index to match HEAD
assert([repo resetToHEAD:kGCResetMode_Hard error:NULL]);
```

Complete Example #1: GitDown
----------------------------

[GitDown](Examples/GitDown) is a very basic app that prompts the user for a repo and displays an interactive and live-updating list of its stashes (all with ~20 lines of code in `-[AppDelegate applicationDidFinishLaunching:]`):

<p align="center">
<img src="http://i.imgur.com/ZfxM7su.png">
</p>

Through GitUpKit, this basic app also gets for free unlimited undo/redo, unified and side-by-side diffs, text selection and copy, keyboard shortcuts, etc...

This source code also demonstrates how to use some other GitUpKit view controllers as well as building a customized one.

Complete Example #2: GitDiff
----------------------------

[GitDiff](Examples/GitDiff) demonstrates how to create a view controller that displays a live updating diff between `HEAD` and the workdir à la `git diff HEAD`:

<p align="center">
<img src="http://i.imgur.com/29hxDcJ.png">
</p>

Complete Example #3: GitY
-------------------------

[GitY](Examples/GitY) is a [GitX](http://gitx.frim.nl/) clone built using GitUpKit and less than 200 lines of code:

<p align="center">
<img src="http://i.imgur.com/6cuPcT4.png">
</p>

Complete Example #4: iGit
-------------------------

[iGit](Examples/iGit) is a test iOS app that simply uses GitUpKit to clone a GitHub repo and perform a commit.

Contributing
============

See [CONTRIBUTING.md](CONTRIBUTING.md).

Credits
=======

- [@swisspol](https://github.com/swisspol): concept and code
- [@wwayneee](https://github.com/wwayneee): UI design
- [@jayeb](https://github.com/jayeb): website

*Also a big thanks to the fine [libgit2](https://libgit2.github.com/) contributors without whom GitUp would have never existed!*

License
=======

GitUp is copyright 2015-2018 Pierre-Olivier Latour and available under [GPL v3 license](http://www.gnu.org/licenses/gpl-3.0.txt). See the [LICENSE](LICENSE) file in the project for more information.

**IMPORTANT:** GitUp includes some other open-source projects and such projects remain under their own license.
