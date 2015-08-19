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

Credits
=======

- [@swisspol](https://github.com/swisspol): concept and code
- [@wwayneee](https://github.com/wwayneee): UI design
- [@jayeb](https://github.com/jayeb): website

*Also a big thanks to the fine [libgit2](https://libgit2.github.com/) contributors without whom GitUp would have never existed!*

License
=======

GitUp is copyright 2015 Pierre-Olivier Latour and available under [GPL v3 license](http://www.gnu.org/licenses/gpl-3.0.txt). See the [LICENSE](LICENSE) file in the project for more information.

IMPORTANT: GitUp includes some other open-source projects and such projects remain under their own license.

Contributors Welcome - Maintainers Needed
=========================================

Congratulations, you made it this far! GitUp is a very modern and quite large open source app used by thousands of developers around the world. May we interest you in becoming a contributor (send a PR) or, even better, a maintainer (reach out to help@gitup.co)?
