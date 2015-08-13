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

#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GIPrivate.h"

#define TEST_BITS(c, m) ((c & (m)) == (m))

void GIComputeHighlightRanges(const char* deletedBytes, NSUInteger deletedCount, CFIndex deletedLength, CFRange* deletedRange, const char* addedBytes, NSUInteger addedCount, CFIndex addedLength, CFRange* addedRange) {
  const char* deletedMin = deletedBytes;
  const char* deletedMax = deletedBytes + deletedCount;
  const char* addedMin = addedBytes;
  const char* addedMax = addedBytes + addedCount;
  
  CFIndex start = 0;
  size_t remaining = 0;
  while ((deletedMin < deletedMax) && (addedMin < addedMax)) {
    if (*deletedMin != *addedMin) {
      break;
    }
    if (remaining == 0) {
      unsigned char byte = *(unsigned char*)deletedMin;
      if (TEST_BITS(byte, 0b11000000)) {
        remaining = 2;
      } else if (TEST_BITS(byte, 0b11100000)) {
        remaining = 3;
      } else if (TEST_BITS(byte, 0b11110000)) {
        remaining = 4;
      } else if (TEST_BITS(byte, 0b11111000)) {
        remaining = 5;
      } else if (TEST_BITS(byte, 0b11111100)) {
        remaining = 6;
      } else {
        XLOG_DEBUG_CHECK(!(byte & (1 << 7)));
        remaining = 1;
      }
    }
    ++deletedMin;
    ++addedMin;
    --remaining;
    if (remaining == 0) {
      ++start;
    }
  }
  
  CFIndex end = 0;
  const char* deletedByte = deletedMax - 1;
  const char* addedByte = addedMax - 1;
  while ((deletedByte >= deletedMin) && (addedByte >= addedMin)) {
    if (*deletedByte != *addedByte) {
      break;
    }
    unsigned char byte = *(unsigned char*)deletedByte;
    if ((!(byte & (1 << 7))) || TEST_BITS(byte, 0b11000000)) {  // 0xxxxxxx or 11xxxxxx indicates a UTF-8 single byte or multi-byte start
      ++end;
    }
    --deletedByte;
    --addedByte;
  }
  
  *deletedRange = CFRangeMake(start, deletedLength - end - start);
  XLOG_DEBUG_CHECK(deletedRange->length >= 0);
  *addedRange = CFRangeMake(start, addedLength - end - start);
  XLOG_DEBUG_CHECK(addedRange->length >= 0);
}

void GIComputeModifiedRanges(NSString* beforeString, NSRange* beforeRange, NSString* afterString, NSRange* afterRange) {
  const char* before = beforeString.UTF8String;
  const char* after = afterString.UTF8String;
  GIComputeHighlightRanges(before, strlen(before), beforeString.length, (CFRange*)beforeRange, after, strlen(after), afterString.length, (CFRange*)afterRange);
}

NSString* GIFormatDateRelativelyFromNow(NSDate* date, BOOL showApproximateTime) {
  return GIFormatRelativeDateDifference([NSDate date], date, showApproximateTime);
}

static NSString* _WeekdayName(NSInteger index) {
  switch (index) {
    case 1: return NSLocalizedString(@"Sunday", nil);
    case 2: return NSLocalizedString(@"Monday", nil);
    case 3: return NSLocalizedString(@"Tuesday", nil);
    case 4: return NSLocalizedString(@"Wednesday", nil);
    case 5: return NSLocalizedString(@"Thursday", nil);
    case 6: return NSLocalizedString(@"Friday", nil);
    case 7: return NSLocalizedString(@"Saturday", nil);
  }
  XLOG_DEBUG_UNREACHABLE();
  return nil;
}

NSString* GIFormatRelativeDateDifference(NSDate* fromDate, NSDate* toDate, BOOL showApproximateTime) {
  if (toDate.timeIntervalSinceReferenceDate <= fromDate.timeIntervalSinceReferenceDate) {
    NSCalendar* calendar = [NSCalendar currentCalendar];
    NSDateComponents* components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitWeekOfYear | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:fromDate toDate:toDate options:0];
    if (components.year == 0) {  // Dates are less than 1 year apart
      if (components.month == 0) {  // Dates are less than 1 month apart
        NSDateComponents* fromComponents = [calendar components:(NSCalendarUnitWeekday | NSCalendarUnitWeekOfYear) fromDate:fromDate];
        NSDateComponents* toComponents = [calendar components:(NSCalendarUnitWeekday | NSCalendarUnitWeekOfYear | NSCalendarUnitHour) fromDate:toDate];
        if (components.weekOfYear == 0) {  // Dates are less than 1 week apart
          
          if (components.day == 0) {  // Dates are less than 1 day apart
            if (components.hour == 0) {  // Dates are less than 1 hour apart
              if (components.minute >= -1) {
                return NSLocalizedString(@"Just now", nil);
              }
              if (components.minute >= -4) {
                return NSLocalizedString(@"Minutes ago", nil);
              }
              return [NSString stringWithFormat:NSLocalizedString(@"%li minutes ago", nil), 5 * (-components.minute / 5)];  // Rounded to 5 minutes intervals
            }
            if (components.hour == -1) {
              return NSLocalizedString(@"An hour ago", nil);
            }
            if (components.hour >= -3) {
              return [NSString stringWithFormat:NSLocalizedString(@"%li hours ago", nil), -components.hour];
            }
            // Pass through!
          }
          
          if ((toComponents.weekOfYear == fromComponents.weekOfYear) && (toComponents.weekday == fromComponents.weekday)) {  // Dates are on the same day
            if (showApproximateTime) {
              if (toComponents.hour < 12) {
                return [NSString stringWithFormat:NSLocalizedString(@"Today, %li AM", nil), toComponents.hour == 0 ? 12 : toComponents.hour];
              }
              return [NSString stringWithFormat:NSLocalizedString(@"Today, %li PM", nil), toComponents.hour == 12 ? 12 : toComponents.hour - 12];
            }
            return NSLocalizedString(@"Today", nil);
          }
          
          if ((toComponents.weekday == fromComponents.weekday - 1) || ((fromComponents.weekday == 1) && (toComponents.weekday == 7))) {  // Dates are on consecutive days
            return NSLocalizedString(@"Yesterday", nil);
          }
          
          if (toComponents.weekOfYear == fromComponents.weekOfYear) {  // Dates are in the same week
            return [NSString stringWithFormat:NSLocalizedString(@"This %@", nil), _WeekdayName(toComponents.weekday)];
          }
          
          return [NSString stringWithFormat:NSLocalizedString(@"Last %@", nil), _WeekdayName(toComponents.weekday)];
          
        }
        if (components.weekOfYear == -1) {
          return NSLocalizedString(@"A week ago", nil);
        }
        return [NSString stringWithFormat:NSLocalizedString(@"%li weeks ago", nil), -components.weekOfYear];
      }
      if (components.month == -1) {
        return NSLocalizedString(@"A month ago", nil);
      }
      return [NSString stringWithFormat:NSLocalizedString(@"%li months ago", nil), -components.month];
    }
    if (components.year == -1) {
      return NSLocalizedString(@"A year ago", nil);
    }
    return [NSString stringWithFormat:NSLocalizedString(@"%li years ago", nil), -components.year];
  }
  return NSLocalizedString(@"Future", nil);
}

void GICGContextAddRoundedRect(CGContextRef context, CGRect rect, CGFloat radius) {
  CGContextMoveToPoint(context, rect.origin.x + radius, rect.origin.y);
  CGContextAddLineToPoint(context, rect.origin.x + rect.size.width - radius, rect.origin.y);
  CGContextAddQuadCurveToPoint(context, rect.origin.x + rect.size.width, rect.origin.y, rect.origin.x + rect.size.width, rect.origin.y + radius);
  CGContextAddLineToPoint(context, rect.origin.x + rect.size.width, rect.origin.y + rect.size.height - radius);
  CGContextAddQuadCurveToPoint(context, rect.origin.x + rect.size.width, rect.origin.y + rect.size.height, rect.origin.x + rect.size.width - radius, rect.origin.y + rect.size.height);
  CGContextAddLineToPoint(context, rect.origin.x + radius, rect.origin.y + rect.size.height);
  CGContextAddQuadCurveToPoint(context, rect.origin.x, rect.origin.y + rect.size.height, rect.origin.x, rect.origin.y + rect.size.height - radius);
  CGContextAddLineToPoint(context, rect.origin.x, rect.origin.y + radius);
  CGContextAddQuadCurveToPoint(context, rect.origin.x, rect.origin.y, rect.origin.x + radius, rect.origin.y);
}
