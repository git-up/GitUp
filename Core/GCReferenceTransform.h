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

#import "GCRepository.h"

@class GCObject, GCCommit;

@interface GCReferenceTransform : NSObject
@property(nonatomic, readonly) GCRepository* repository;  // NOT RETAINED
@property(nonatomic, readonly, getter=isIdentity) BOOL identity;  // Transform is empty and does nothing
- (instancetype)initWithRepository:(GCRepository*)repository reflogMessage:(NSString*)message;
- (void)setSymbolicTarget:(NSString*)target forReference:(GCReference*)reference;
- (void)setDirectTarget:(GCObject*)target forReference:(GCReference*)reference;
- (void)deleteReference:(GCReference*)reference;
- (void)setSymbolicTargetForHEAD:(NSString*)target;
- (void)setDirectTargetForHEAD:(GCObject*)target;
@end

@interface GCRepository (GCReferenceTransform)
- (BOOL)applyReferenceTransform:(GCReferenceTransform*)transform error:(NSError**)error;
@end
