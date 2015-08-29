//  Copyright (C) 2015 Pierre-Olivier Latour <info@pol-online.net>
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

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

void GIComputeModifiedRanges(NSString* beforeString, NSRange* beforeRange, NSString* afterString, NSRange* afterRange);
NSString* GIFormatDateRelativelyFromNow(NSDate* date, BOOL showApproximateTime);
NSString* GIFormatRelativeDateDifference(NSDate* fromDate, NSDate* toDate, BOOL showApproximateTime);
void GICGContextAddRoundedRect(CGContextRef context, CGRect rect, CGFloat radius);

#ifdef __cplusplus
}
#endif
