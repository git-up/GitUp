[![Build Status](https://travis-ci.org/git-up/GitUp.svg?branch=master)](https://travis-ci.org/git-up/GitUp)

GitUp
=====

**Work quickly, safely, and without headaches. The Git interface you've been missing all your life has finally arrived.**

<p align="center">
<img src="http://i.imgur.com/t6iC9TC.png">
</p>

Git recently celebrated its 10 years anniversary, but most engineers are still confused by its intricacy (3 of the [top 5 questions of all time](http://stackoverflow.com/questions?sort=votes) on Stack Overflow are Git related). Since Git turns even simple actions into mystifying commands (“git add” to stage versus “git reset HEAD” to unstage anyone?), it’s no surprise users waste time, get frustrated, distract the rest of their team for help, or worse, screw up their repo!

GitUp is a bet to invent a new Git interaction model that lets engineers work quickly, safely, and without headaches. It's unlike any other Git client out there from the way it’s built (it interacts directly with the Git database on disk), to the way it works (you manipulate the repository graph instead of manipulating commits).

With GitUp, you get a truly efficient Git client for Mac:
- A live and interactive repo graph (edit, reorder, fixup, merge commits…),
- Unlimited undo / redo of almost all operations (even rebases and merges),
- Time Machine like snapshots for 1-click rollbacks to previous repo states,
- Features that don’t even exist natively in Git like a visual commit splitter or a unified reflog browser,
- Instant search across the entire repo including diff contents, 
- A ridiculously fast UI, often faster than the command line.

*GitUp was created by [@swisspol](https://github.com/swisspol) in late 2014 as a bet to reinvent the way developers interact with Git. After several months of work, it was made available in pre-release early 2015 and reached the [top of Hacker News](https://news.ycombinator.com/item?id=9653978) along with being [featured by Product Hunt](http://www.producthunt.com/tech/gitup-1) and [Daring Fireball](http://daringfireball.net/linked/2015/06/04/gitup). 30,000 lines of code later, GitUp reached 1.0 mid-August 2015 and was released open source as a gift to the developer community.*

Getting Started
===============

**Learn all about GitUp and download the latest stable release for Mac OS X 10.8+ from http://gitup.co.**

**Read the [docs](http://forums.gitup.co/c/docs) and visit the [community forums](http://forums.gitup.co/) for support & feedback.**

Releases notes are available at https://github.com/git-up/GitUp/releases. Builds tagged with a `v` (e.g. `v1.2.3`) are released on the "Stable" channel, while builds tagged with a `b` (e.g. `b1234`) are only released on the "Continuous" channel. You can change the update channel used by GitUp in the app preferences.

To build GitUp yourself, simply run these commands in Terminal:

1. `git clone https://github.com/git-up/GitUp.git`
2. `cd GitUp`
3. `git submodule update --init --recursive`

Then open the `GitUp.xcodeproj` Xcode project.

GitUp Architecture
==================

GitUp is built as 3 cleanly separated layers communicating only through the use of public APIs:

**Foundation Layer (depends on Foundation only)**
- `Core/`: wrapper around the required minimal functionality of [libgit2](https://github.com/libgit2/libgit2), on top of which is then implemented all the Git functionality required by GitUp (note that GitUp uses a [slightly customized fork](https://github.com/git-up/libgit2/tree/gitup) of libgit2)
- `Extensions/`: categories on the `Core` classes to add convenience features implemented only using the public APIs

**UI Layer (depends on AppKit)**
- `Interface/`: low-level view classes e.g. `GIGraphView` to render the GitUp Map view
- `Utilities/`: interface utility classes e.g. the base view controller class `GIViewController`
- `Components/`: reusable single-view view controllers e.g. `GIDiffContentsViewController` to render a diff
- `Views/`: high-level reusable multi-views view controllers e.g. `GIAdvancedCommitViewController` to implement the entire GitUp Advanced Commit view

**Application Layer**
- `Application/`: essentially the "glue code" connecting all the above layers together into an actual app (and therefore not really clean code contrary to the rest of GitUp)

**The Foundation and UI layer are for all intents and purposes an SDK, with which it should be quite easy to build other Git tools or even entire apps:**

Here's the pseudo-code to display a live-updating GitUp stash view:
```objc
GCRepository* repo = [[GCLiveRepository alloc] initWithExistingLocalRepository:<PATH> error:NULL];
GIDiffViewController* vc = [[GIStashListViewController alloc] initWithRepository:repo];
[<WINDOW>.contentView addSubview:vc.view];
```

Here's the pseudo-code to display a diff view between a commit and its parent:
```objc
GCRepository* repo = [[GCLiveRepository alloc] initWithExistingLocalRepository:<PATH> error:NULL];
GCCommit* c1 = [repo findCommitWithSHA1:<SHA1> error:NULL];
GCCommit* c2 = [[repo lookupParentsForCommit:c1 error:NULL] firstObject];  // Follow main line
GIDiffViewController* vc = [[GIDiffViewController alloc] initWithRepository:repo];
[vc setCommit:c1 withParentCommit:c2];
[<WINDOW>.contentView addSubview:vc.view];
```

Here's the pseudo-code to display a live-updating Advanced Commit view:
```objc
GCLiveRepository* repo = [[GCLiveRepository alloc] initWithExistingLocalRepository:<PATH> error:NULL];
GIAdvancedCommitViewController* vc = [[GIAdvancedCommitViewController alloc] initWithRepository:repo];
[<WINDOW>.contentView addSubview:vc.view];
```

Contributing
============

[Pull requests](https://github.com/git-up/GitUp/pulls) are welcome but be aware that GitUp is used for production work by many thousands of developers around the world, so the bar is very high. The last thing we want is letting the code quality slip or introducing a regression.

The following is a list of absolute requirements for PRs (not following them would result in immediate rejection):
- The coding style of GitUp MUST be followed
- Additions to `Core/` MUST have associated unit tests
- Commit messages MUST have:
 - A capitalized clear and concise title e.g. "Changed app bundle ID to com.example.gitup" not "updated bundle id"
 - A detailed summary explaining the change unless it is trivial (no need to wrap at 80 characters but keep lines to a reasonnable length)
- The pull request MUST contain as few commits as need MUST NOT contain fixup or revert commits (flatten 
- The pull request MUST be rebased on latest `master` when sent

**Be aware that GitUp is under [GPL v3 license](http://www.gnu.org/licenses/gpl-3.0.txt), so any contribution you make will be GPL'ed.**

Credits
=======

- [@swisspol](https://github.com/swisspol): concept and code
- [@wwayneee](https://github.com/wwayneee): UI design
- [@jayeb](https://github.com/jayeb): website

*Also a big thanks to the fine [libgit2](https://libgit2.github.com/) contributors without whom GitUp would have never existed!*

License
=======

GitUp is copyright 2015 Pierre-Olivier Latour and available under [GPL v3 license](http://www.gnu.org/licenses/gpl-3.0.txt). See the [LICENSE](LICENSE) file in the project for more information.

**IMPORTANT:** GitUp includes some other open-source projects and such projects remain under their own license.
