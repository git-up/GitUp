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

#if DEBUG
#define kToolPortName "co.gitup.mac-debug"
#else
#define kToolPortName "co.gitup.mac"
#endif

#define kToolCommand_Help "help"
#define kToolCommand_Open "open"
#define kToolCommand_Map "map"
#define kToolCommand_Commit "commit"
#define kToolCommand_Stash "stash"

#define kToolDictionaryKey_Command @"command"  // NSString
#define kToolDictionaryKey_Repository @"repository"  // NSString

#define kToolDictionaryKey_Error @"error"  // NSString
