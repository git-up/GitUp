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

#import "WindowController.h"
#import "Document.h"

@implementation WindowController

- (void)dealloc {
  self.window.contentView = nil;  // Work around a strange bug in OS X 10.10 affected restored windows only where they remain retained for a couple seconds after the NSDocument was closed
}

- (void)windowDidLoad {
  [super windowDidLoad];

  self.window.delegate = self;
}

- (NSString*)windowTitleForDocumentDisplayName:(NSString*)displayName {
  NSString* displayMode = NSLocalizedString([(Document*)self.document windowMode], nil);
  if (@available(macOS 11, *)) {
    return [NSString stringWithFormat:@"%@ — %@", displayName, displayMode];
  } else {
    return [NSString stringWithFormat:@"%@ • %@", displayName, displayMode];
  }
}

- (NSUndoManager*)windowWillReturnUndoManager:(NSWindow*)window {
  return [(Document*)self.document undoManager];
}

@end
