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

@implementation GCEmptyRepositoryTests (GCConfig)

- (void)testConfig {
  if (!self.botMode) {
    XCTAssertNotNil([self.repository findFilePathForConfigurationLevel:kGCConfigLevel_Global error:NULL]);
  }
  XCTAssertNotNil([self.repository findFilePathForConfigurationLevel:kGCConfigLevel_Local error:NULL]);
  
  XCTAssertNil([self.repository readConfigOptionForVariable:@"unknown" error:NULL]);
  
  GCConfigOption* option = [self.repository readConfigOptionForVariable:@"core.bare" error:NULL];
  XCTAssertEqualObjects(option.value, @"false");
  XCTAssertEqual(option.level, kGCConfigLevel_Local);
  
  XCTAssertTrue([self.repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"foo.bar" withValue:@"hello world" error:NULL]);
  option = [self.repository readConfigOptionForVariable:@"foo.bar" error:NULL];
  XCTAssertEqual(option.level, kGCConfigLevel_Local);
  XCTAssertEqualObjects(option.variable, @"foo.bar");
  XCTAssertEqualObjects(option.value, @"hello world");
  XCTAssertNil([self.repository readConfigOptionForLevel:kGCConfigLevel_Global variable:@"foo.bar" error:NULL]);
  XCTAssertNotNil([self.repository readConfigOptionForLevel:kGCConfigLevel_Local variable:@"foo.bar" error:NULL]);
  XCTAssertTrue([self.repository writeConfigOptionForLevel:kGCConfigLevel_Local variable:@"foo.bar" withValue:nil error:NULL]);
  XCTAssertNil([self.repository readConfigOptionForVariable:@"foo.bar" error:NULL]);
  
  NSArray* config1 = [self.repository readConfigForLevel:kGCConfigLevel_Local error:NULL];
  XCTAssertEqual(config1.count, 6);
  
  NSArray* config2 = [self.repository readAllConfigs:NULL];
  XCTAssertEqual(config2.count, 8);
  option = config2.firstObject;
  XCTAssertEqualObjects(option.variable, @"core.repositoryformatversion");
  XCTAssertEqualObjects(option.value, @"0");
}

@end
