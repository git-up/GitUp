//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#define MAKE_ERROR(message) [NSError errorWithDomain:@"App" code:-1 userInfo:@{NSLocalizedDescriptionKey : message}]

#define kUserDefaultsKey_FirstLaunch @"FirstLaunch"  // BOOL
#define kUserDefaultsKey_SkipInstallCLT @"SkipInstallCLT"  // BOOL
#define kUserDefaultsKey_LastVersion @"LastVersion"  // NSUInteger
#define kUserDefaultsKey_ReleaseChannel @"ReleaseChannel"  // NSString
#define kUserDefaultsKey_CheckInterval @"CheckInterval"  // NSInteger
#define kUserDefaultsKey_SimpleCommit @"SimpleCommit"  // BOOL
#define kUserDefaultsKey_DisableSparkle @"DisableSparkle"  // BOOL
#define kUserDefaultsKey_DiffWhitespaceMode @"DiffWhitespaceMode"  // NSUInteger
#define kUserDefaultsKey_ShowWelcomeWindow @"ShowWelcomeWindow"  // BOOL
#define kUserDefaultsKey_Theme @"Theme"  // NSString

#define kRepositoryUserInfoKey_SkipSubmoduleCheck @"SkipSubmoduleCheck"  // BOOL
#define kRepositoryUserInfoKey_MainWindowFrame @"MainWindowFrame"  // NSString
#define kRepositoryUserInfoKey_IndexDiffs @"IndexDiffs"  // BOOL

#define kURL_AppCast @"https://s3-us-west-2.amazonaws.com/gitup-builds/%@/appcast.xml"

#define kURL_Issues @"https://github.com/git-up/GitUp/issues"
#define kURL_Wiki @"https://github.com/git-up/GitUp/wiki"
#define kURL_ReleaseNotes @"https://github.com/git-up/GitUp/releases"
