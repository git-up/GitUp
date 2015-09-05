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

@class GCObject;

/**
 * This class is optimized to be fast when you have a lot of calls to
 * - addObject: , -containsObject: and -removeObject: methods.
 */
@interface GCOrderedSet : NSObject

/**
 * Accessing this property is CPU-expensive.
 * It makes a copy of internal storage, filtered by existing objects.
 * Try to store the value somewhere else and don't access this property if you don't have to.
 */
@property(nonatomic, readonly) NSArray* objects;

/**
 * NOTE: Usually it is unnecessary to add an object, then remove it, then add it again.
 * But if you will do this, it will appear in the object array
 * at the SAME PLACE AS IT WAS ADDED.
 */
- (void)addObject:(GCObject*)object;
- (BOOL)containsObject:(GCObject*)object;
- (void)removeObject:(GCObject*)object;

@end
