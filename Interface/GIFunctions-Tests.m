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

#import "GCTestCase.h"
#import "GIPrivate.h"

@implementation GCTests (GIFunctions)

#define TEST_DATE_FORMATTING(year1, month1, day1, hour1, minute1, second1, year2, month2, day2, hour2, minute2, second2, expected) \
do { \
  NSCalendar* calendar = [NSCalendar currentCalendar]; \
  \
  NSDateComponents* components1 = [[NSDateComponents alloc] init]; \
  components1.year = year1; \
  components1.month = month1; \
  components1.day = day1; \
  components1.hour = hour1; \
  components1.minute = minute1; \
  components1.second = second1; \
  NSDate* date1 = [calendar dateFromComponents:components1]; \
  \
  NSDateComponents* components2 = [[NSDateComponents alloc] init]; \
  components2.year = year2; \
  components2.month = month2; \
  components2.day = day2; \
  components2.hour = hour2; \
  components2.minute = minute2; \
  components2.second = second2; \
  NSDate* date2 = [calendar dateFromComponents:components2]; \
  \
  XCTAssertEqualObjects(GIFormatRelativeDateDifference(date1, date2, YES), expected); \
} while (0)

- (void)testDateFormatting {
  TEST_DATE_FORMATTING(2000, 1, 1, 0, 0, 0,
                       2001, 1, 1, 0, 0, 0,
                       @"Future");
  TEST_DATE_FORMATTING(2000, 1, 1, 0, 0, 0,
                       2000, 1, 1, 0, 0, 0,
                       @"Just now");
  TEST_DATE_FORMATTING(2000, 1, 1, 0, 2, 0,
                       2000, 1, 1, 0, 0, 0,
                       @"Minutes ago");
  TEST_DATE_FORMATTING(2000, 1, 1, 0, 5, 0,
                       2000, 1, 1, 0, 0, 0,
                       @"5 minutes ago");
  TEST_DATE_FORMATTING(2000, 1, 1, 0, 29, 0,
                       2000, 1, 1, 0, 0, 0,
                       @"25 minutes ago");
  TEST_DATE_FORMATTING(2000, 1, 1, 1, 10, 0,
                       2000, 1, 1, 0, 0, 0,
                       @"An hour ago");
  TEST_DATE_FORMATTING(2000, 1, 1, 3, 30, 0,
                       2000, 1, 1, 0, 0, 0,
                       @"3 hours ago");
  TEST_DATE_FORMATTING(2000, 1, 1, 4, 30, 0,
                       2000, 1, 1, 0, 0, 0,
                       @"Today, 12 AM");
  TEST_DATE_FORMATTING(2000, 1, 1, 22, 30, 0,
                       2000, 1, 1, 13, 10, 0,
                       @"Today, 1 PM");
  TEST_DATE_FORMATTING(2000, 1, 2, 4, 30, 0,
                       2000, 1, 1, 1, 10, 0,
                       @"Yesterday");
  TEST_DATE_FORMATTING(2000, 1, 5, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"This Monday");
  TEST_DATE_FORMATTING(2000, 1, 9, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"Last Monday");
  TEST_DATE_FORMATTING(2000, 1, 11, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"A week ago");
  TEST_DATE_FORMATTING(2000, 1, 18, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"2 weeks ago");
  TEST_DATE_FORMATTING(2000, 1, 28, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"3 weeks ago");
  TEST_DATE_FORMATTING(2000, 2, 1, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"4 weeks ago");
  TEST_DATE_FORMATTING(2000, 2, 20, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"A month ago");
  TEST_DATE_FORMATTING(2000, 7, 1, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"5 months ago");
  TEST_DATE_FORMATTING(2001, 3, 1, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"A year ago");
  TEST_DATE_FORMATTING(2002, 4, 1, 0, 0, 0,
                       2000, 1, 3, 0, 0, 0,
                       @"2 years ago");
}

- (void)testHighlightingRange {
  CFRange deletedRange;
  CFRange addedRange;
  {
    const char* before = "____\n";
    const char* after = "__added__\n";
    GIComputeHighlightRanges(before, strlen(before), [[NSString stringWithUTF8String:before] length], &deletedRange, after, strlen(after), [[NSString stringWithUTF8String:after] length], &addedRange);
    XCTAssertEqual(deletedRange.location, 2);
    XCTAssertEqual(deletedRange.length, 0);
    XCTAssertEqual(addedRange.location, 2);
    XCTAssertEqual(addedRange.length, 5);
  }
  {
    const char* before = "__deleted__\n";
    const char* after = "____\n";
    GIComputeHighlightRanges(before, strlen(before), [[NSString stringWithUTF8String:before] length], &deletedRange, after, strlen(after), [[NSString stringWithUTF8String:after] length], &addedRange);
    XCTAssertEqual(deletedRange.location, 2);
    XCTAssertEqual(deletedRange.length, 7);
    XCTAssertEqual(addedRange.location, 2);
    XCTAssertEqual(addedRange.length, 0);
  }
  {
    const char* before = "__before__\n";
    const char* after = "__after__\n";
    GIComputeHighlightRanges(before, strlen(before), [[NSString stringWithUTF8String:before] length], &deletedRange, after, strlen(after), [[NSString stringWithUTF8String:after] length], &addedRange);
    XCTAssertEqual(deletedRange.location, 2);
    XCTAssertEqual(deletedRange.length, 6);
    XCTAssertEqual(addedRange.location, 2);
    XCTAssertEqual(addedRange.length, 5);
  }
  {
    const char* before = "The 2010 year";
    const char* after = "The 2011 year";
    GIComputeHighlightRanges(before, strlen(before), [[NSString stringWithUTF8String:before] length], &deletedRange, after, strlen(after), [[NSString stringWithUTF8String:after] length], &addedRange);
    XCTAssertEqual(deletedRange.location, 7);
    XCTAssertEqual(deletedRange.length, 1);
    XCTAssertEqual(addedRange.location, 7);
    XCTAssertEqual(addedRange.length, 1);
  }
  {
    const char* before = "succesfully";
    const char* after = "successfully";
    GIComputeHighlightRanges(before, strlen(before), [[NSString stringWithUTF8String:before] length], &deletedRange, after, strlen(after), [[NSString stringWithUTF8String:after] length], &addedRange);
    XCTAssertEqual(deletedRange.location, 6);
    XCTAssertEqual(deletedRange.length, 0);
    XCTAssertEqual(addedRange.location, 6);
    XCTAssertEqual(addedRange.length, 1);
  }
  {
    const char* before = "francais";
    const char* after = "français";
    GIComputeHighlightRanges(before, strlen(before), [[NSString stringWithUTF8String:before] length], &deletedRange, after, strlen(after), [[NSString stringWithUTF8String:after] length], &addedRange);
    XCTAssertEqual(deletedRange.location, 4);
    XCTAssertEqual(deletedRange.length, 1);
    XCTAssertEqual(addedRange.location, 4);
    XCTAssertEqual(addedRange.length, 1);
  }
  {
    const char* before = "_é_äu_è_";
    const char* after = "_é_aü_è_";
    GIComputeHighlightRanges(before, strlen(before), [[NSString stringWithUTF8String:before] length], &deletedRange, after, strlen(after), [[NSString stringWithUTF8String:after] length], &addedRange);
    XCTAssertEqual(deletedRange.location, 3);
    XCTAssertEqual(deletedRange.length, 2);
    XCTAssertEqual(addedRange.location, 3);
    XCTAssertEqual(addedRange.length, 2);
  }
}

@end
