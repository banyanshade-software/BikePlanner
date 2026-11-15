//
//  BPFITBuilder.h
//  BikePlannerTests
//
//  Writes small FIT files for the tests of the FIT import (#76): definition and data messages (little- or
//  big-endian, developer fields), compressed timestamp headers, 14-byte header and CRCs.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// FIT base types used by the fixtures
enum { BPFITEnum = 0x00, BPFITUInt8 = 0x02, BPFITSInt16 = 0x83, BPFITUInt16 = 0x84, BPFITSInt32 = 0x85,
       BPFITUInt32 = 0x86, BPFITString = 0x07 };

@interface BPFITBuilder : NSObject

/// degrees → semicircles
+ (int32_t)semicircles:(double)degrees;
/// date → FIT timestamp (seconds since 1989-12-31 00:00 UTC)
+ (uint32_t)fitTimestamp:(NSDate *)date;
+ (uint16_t)crcOfData:(NSData *)data;

/// fields: @[ @[num, size, baseType], … ]; developerSizes: sizes of developer fields (written as zeros)
- (void)defineLocal:(uint8_t)local global:(uint16_t)global fields:(NSArray<NSArray<NSNumber *> *> *)fields
          bigEndian:(BOOL)bigEndian developerSizes:(nullable NSArray<NSNumber *> *)developerSizes;
- (void)defineLocal:(uint8_t)local global:(uint16_t)global fields:(NSArray<NSArray<NSNumber *> *> *)fields;
/// one value per field: NSNumber (integer) or NSString
- (void)dataLocal:(uint8_t)local values:(NSArray *)values;
/// compressed timestamp header (local 0–3, offset 0–31)
- (void)compressedLocal:(uint8_t)local timeOffset:(uint8_t)offset values:(NSArray *)values;
/// the file: header (14 bytes, with CRC), records, file CRC
- (NSData *)data;

@end

NS_ASSUME_NONNULL_END
