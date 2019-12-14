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

#import "FontSizeTransformer.h"
#import <GitUpKit/GIAppKit.h>

static NSArray* sizes;

@implementation FontSizeTransformer

+ (void)initialize {
  // Match the system font picker
  sizes = @[ @9, @10, @11, @12, @13, @14, @18, @24 ];
}

+ (Class)transformedValueClass {
  return [NSNumber class];
}

+ (BOOL)allowsReverseTransformation {
  return YES;
}

- (id)transformedValue:(id)fontSizeValue {
  NSUInteger idx = [sizes indexOfObject:fontSizeValue];
  if (idx == NSNotFound) {
    // If the user default is set externally, fallback to the default index.
    return @1;
  }

  return @(idx);
}

- (id)reverseTransformedValue:(id)indexValue {
  NSUInteger idx = [indexValue unsignedIntegerValue];
  if (idx >= sizes.count) {
    return @(GIDefaultFontSize);
  }

  return sizes[idx];
}

@end
