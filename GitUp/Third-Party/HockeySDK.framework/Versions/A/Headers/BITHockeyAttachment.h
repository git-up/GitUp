#import <Foundation/Foundation.h>

/**
 Provides support to add binary attachments to crash reports
 
 This is used by `[BITCrashManagerDelegate attachmentForCrashManager:]`
 */
@interface BITHockeyAttachment : NSObject<NSCoding>

/**
 The filename the attachment should get
 */
@property (nonatomic, readonly, strong) NSString *filename;

/**
 The attachment data as NSData object
 */
@property (nonatomic, readonly, strong) NSData *hockeyAttachmentData;

/**
 The content type of your data as MIME type
 */
@property (nonatomic, readonly, strong) NSString *contentType;

/**
 Create an BITHockeyAttachment instance with a given filename and NSData object
 
 @param filename             The filename the attachment should get. If nil will get a automatically generated filename
 @param hockeyAttachmentData The attachment data as NSData. The instance will be ignore if this is set to nil!
 @param contentType          The content type of your data as MIME type. If nil will be set to "application/octet-stream"
 
 @return An instsance of BITHockeyAttachment
 */
- (instancetype)initWithFilename:(NSString *)filename
            hockeyAttachmentData:(NSData *)hockeyAttachmentData
                     contentType:(NSString *)contentType;

@end
