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

#define kNotationSeparator @"##### NOTATION #####\n\n"
#define kGraphSeparator @"##### GRAPH #####\n\n"

@interface GIGraphTests : XCTestCase
@end

@implementation GIGraphTests

+ (NSArray*)testInvocations {
  NSMutableArray* array = [NSMutableArray arrayWithArray:[super testInvocations]];
  NSString* folder = [[@__FILE__ stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"GIGraph-Tests"];
  NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL];
  XLOG_DEBUG_CHECK(files);
  for (NSString* file in files) {
    if (![file.pathExtension isEqualToString:@"txt"]) {
      continue;
    }
    NSString* name = [file stringByDeletingPathExtension];
    NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:[self instanceMethodSignatureForSelector:@selector(_test:)]];
    invocation.selector = NSSelectorFromString([NSString stringWithFormat:@"%@:", name]);
    NSString* path = [folder stringByAppendingPathComponent:file];
    [invocation setArgument:&path atIndex:2];
    [invocation retainArguments];
    [array addObject:invocation];
  }
  return array;
}

- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector {
  return [super methodSignatureForSelector:@selector(_test:)];
}

- (void)forwardInvocation:(NSInvocation*)invocation {
  invocation.selector = @selector(_test:);
  [invocation invokeWithTarget:self];
}

- (void)_test:(NSString*)file {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  
  // Parse file
  NSString* contents = [[NSString alloc] initWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertNotNil(contents);
  NSRange range1 = [contents rangeOfString:kNotationSeparator options:0 range:NSMakeRange(0, contents.length)];
  XCTAssertNotEqual(range1.location, NSNotFound);
  NSRange range2 = [contents rangeOfString:kGraphSeparator options:0 range:NSMakeRange(range1.location + range1.length, contents.length - range1.location - range1.length)];
  XCTAssertNotEqual(range2.location, NSNotFound);
  NSDictionary* options = nil;
  if (range1.location > 0) {
    NSMutableString* json = [NSMutableString string];
    for (NSString* line in [[contents substringWithRange:NSMakeRange(0, range1.location)] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
      if (line.length && ([line characterAtIndex:0] != '#')) {
        [json appendString:line];
        [json appendString:@"\n"];
      }
    }
    options = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
  }
  NSString* notation = [contents substringWithRange:NSMakeRange(range1.location + range1.length, range2.location - range1.location - range1.length)];
  NSString* expected = [contents substringWithRange:NSMakeRange(range2.location + range2.length, contents.length - range2.location - range2.length)];
  
  // Create mock repository from notation
  GCRepository* repository = [[GCSQLiteRepository alloc] initWithDatabase:path error:NULL];
  XCTAssertNotNil(repository);
  XCTAssertNotNil([repository createMockCommitHierarchyFromNotation:notation force:NO error:NULL]);
  
  // Load history
  GCHistory* history = [repository loadHistoryUsingSorting:kGCHistorySorting_None error:NULL];
  XCTAssertNotNil(history);
  
  // Create graph
  GIGraphOptions graphOptions = 0;
  if ([[options valueForKey:@"showVirtualTips"] boolValue]) {
    graphOptions |= kGIGraphOption_ShowVirtualTips;
  }
  if ([[options valueForKey:@"skipTagTips"] boolValue]) {
    graphOptions |= kGIGraphOption_SkipStandaloneTagTips;
  }
  if ([[options valueForKey:@"skipRemoteBranchTips"] boolValue]) {
    graphOptions |= kGIGraphOption_SkipStandaloneRemoteBranchTips;
  }
  if ([[options valueForKey:@"preserveUpstreamTips"] boolValue]) {
    graphOptions |= kGIGraphOption_PreserveUpstreamRemoteBranchTips;
  }
  GIGraph* graph = [[GIGraph alloc] initWithHistory:history options:graphOptions];
  XCTAssertNotNil(graph);
  
  // Compare graph with expected
  NSMutableString* string = [[NSMutableString alloc] init];
  NSUInteger index = 0;
  for (GILayer* layer in graph.layers) {
    [string appendFormat:@"[%04lu]", index];
    for (GINode* node in layer.nodes) {
      if (node.dummy) {
        [string appendFormat:@" (%@)", node.commit.message];
      } else {
        [string appendFormat:@" %@", node.commit.message];
      }
    }
    [string appendString:@"\n"];
    ++index;
  }
  XCTAssertEqualObjects(string, expected);
  
  // Destroy repository
  repository = nil;
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
}

@end
