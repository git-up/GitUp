//
//  NSWindow+Loading.m
//  Application
//
//  Created by Dmitry Lobanov on 22.10.2019.
//

#import "NSWindow+Loading.h"

#import <AppKit/AppKit.h>


@implementation NSWindow (Loading)
+ (id)loadWindowFromBundleXibWithName:(NSString *)name expectedClass:(Class)expectedClass {
  NSBundle *mainBundle = [NSBundle mainBundle];
  NSArray *objects = @[];
  [mainBundle loadNibNamed:name owner:self topLevelObjects:&objects];
  NSArray *filteredObjects = [objects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
    return [evaluatedObject isKindOfClass:expectedClass];
  }]];
  return filteredObjects.firstObject;
}
@end
