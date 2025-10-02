//  Copyright (C) 2015-2020 Pierre-Olivier Latour <info@pol-online.net>
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

#import "GICustomToolbarItem.h"

@implementation GICustomToolbarItem

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  self.primaryControl.enabled = enabled;
  self.secondaryControl.enabled = enabled;
}

- (void)validate {
  [GICustomToolbarItem validateAsUserInterfaceItem:self];
  if (self.enabled) {
    [GICustomToolbarItem validateAsUserInterfaceItem:self.primaryControl];
    [GICustomToolbarItem validateAsUserInterfaceItem:self.secondaryControl];
  }
}

+ (void)validateAsUserInterfaceItem:(id)sender {
  SEL action = [sender action];
  if (!action) return;
  id target = [sender target];
  id validator = [NSApp targetForAction:action to:target from:sender];
  if (!validator || ![validator respondsToSelector:action]) {
    [sender setEnabled:NO];
  } else if ([validator respondsToSelector:@selector(validateUserInterfaceItem:)]) {
    [sender setEnabled:[validator validateUserInterfaceItem:(id)sender]];
  } else {
    [sender setEnabled:YES];
  }
}

@end
