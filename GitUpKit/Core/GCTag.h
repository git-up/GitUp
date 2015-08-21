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

#import "GCObject.h"
#import "GCReference.h"
#import "GCRepository.h"

@class GCCommit;

@interface GCTagAnnotation : GCObject
@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) NSString* message;  // Raw message including trailing newline
@property(nonatomic, readonly) NSString* tagger;
@end

@interface GCTagAnnotation (Extensions)
- (BOOL)isEqualToTagAnnotation:(GCTagAnnotation*)annotation;
@end

@interface GCTag : GCReference
@end

@interface GCTag (Extensions)
- (BOOL)isEqualToTag:(GCTag*)tag;
@end

// Changing the commit of a tag is not supported since this wouldn't be reliable for annotated tags e.g. if tag is signed
@interface GCRepository (GCTag)
+ (BOOL)isValidTagName:(NSString*)name;

- (GCTag*)findTagWithName:(NSString*)name error:(NSError**)error;
- (NSArray*)listTags:(NSError**)error;  // git tag

- (GCCommit*)lookupCommitForTag:(GCTag*)tag annotation:(GCTagAnnotation**)annotation error:(NSError**)error;  // git show-ref {tag}

- (GCTag*)createLightweightTagWithCommit:(GCCommit*)commit name:(NSString*)name force:(BOOL)force error:(NSError**)error;  // git tag {-f} {name} {commit}
- (GCTag*)createAnnotatedTagWithAnnotation:(GCTagAnnotation*)annotation force:(BOOL)force error:(NSError**)error;  // (?)
- (GCTag*)createAnnotatedTagWithCommit:(GCCommit*)commit name:(NSString*)name message:(NSString*)message force:(BOOL)force annotation:(GCTagAnnotation**)annotation error:(NSError**)error;  // git tag {-f} -a {name} -m {message} {commit}
- (BOOL)setName:(NSString*)name forTag:(GCTag*)tag force:(BOOL)force error:(NSError**)error;  // (?)
- (BOOL)deleteTag:(GCTag*)tag error:(NSError**)error;  // git tag -d {tag}
@end
