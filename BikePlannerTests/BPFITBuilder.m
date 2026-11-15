//
//  BPFITBuilder.m
//  BikePlannerTests
//

#import "BPFITBuilder.h"

@implementation BPFITBuilder {
    NSMutableData *_records;
    NSMutableDictionary<NSNumber *, NSDictionary *> *_definitions; // local → fields, bigEndian, developer size
}

+ (int32_t)semicircles:(double)degrees
{
    return (int32_t)llround(degrees * 2147483648.0 / 180.0);
}

+ (uint32_t)fitTimestamp:(NSDate *)date
{
    return (uint32_t)(date.timeIntervalSince1970 - 631065600);
}

+ (uint16_t)crcOfData:(NSData *)data
{
    static const uint16_t table[16] = { 0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
                                        0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400 };
    uint16_t crc = 0;
    const uint8_t *b = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        uint16_t t = table[crc & 0xF];
        crc = (crc >> 4) & 0x0FFF;
        crc = crc ^ t ^ table[b[i] & 0xF];
        t = table[crc & 0xF];
        crc = (crc >> 4) & 0x0FFF;
        crc = crc ^ t ^ table[(b[i] >> 4) & 0xF];
    }
    return crc;
}

- (instancetype)init
{
    if (self = [super init]) {
        _records = [NSMutableData data];
        _definitions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)appendByte:(uint8_t)b
{
    [_records appendBytes:&b length:1];
}

- (void)appendInteger:(uint64_t)v size:(NSUInteger)size bigEndian:(BOOL)bigEndian
{
    for (NSUInteger i = 0; i < size; i++) {
        NSUInteger shift = bigEndian ? (size - 1 - i) * 8 : i * 8;
        [self appendByte:(uint8_t)(v >> shift)];
    }
}

- (void)defineLocal:(uint8_t)local global:(uint16_t)global fields:(NSArray<NSArray<NSNumber *> *> *)fields
{
    [self defineLocal:local global:global fields:fields bigEndian:NO developerSizes:nil];
}

- (void)defineLocal:(uint8_t)local global:(uint16_t)global fields:(NSArray<NSArray<NSNumber *> *> *)fields
          bigEndian:(BOOL)bigEndian developerSizes:(nullable NSArray<NSNumber *> *)developerSizes
{
    [self appendByte:0x40 | (developerSizes.count ? 0x20 : 0) | (local & 0xF)];
    [self appendByte:0];
    [self appendByte:bigEndian ? 1 : 0];
    [self appendInteger:global size:2 bigEndian:bigEndian];
    [self appendByte:(uint8_t)fields.count];
    for (NSArray<NSNumber *> *f in fields) {
        [self appendByte:f[0].unsignedCharValue];
        [self appendByte:f[1].unsignedCharValue];
        [self appendByte:f[2].unsignedCharValue];
    }
    NSUInteger devSize = 0;
    if (developerSizes.count) {
        [self appendByte:(uint8_t)developerSizes.count];
        [developerSizes enumerateObjectsUsingBlock:^(NSNumber *size, NSUInteger i, BOOL *stop) {
            [self appendByte:(uint8_t)i];
            [self appendByte:size.unsignedCharValue];
            [self appendByte:0];
        }];
        for (NSNumber *n in developerSizes) devSize += n.unsignedIntegerValue;
    }
    _definitions[@(local)] = @{ @"fields": fields, @"big": @(bigEndian), @"dev": @(devSize) };
}

- (void)appendValues:(NSArray *)values local:(uint8_t)local
{
    NSDictionary *def = _definitions[@(local)];
    NSArray<NSArray<NSNumber *> *> *fields = def[@"fields"];
    NSAssert(fields.count == values.count, @"one value per field");
    BOOL big = [def[@"big"] boolValue];
    [fields enumerateObjectsUsingBlock:^(NSArray<NSNumber *> *f, NSUInteger i, BOOL *stop) {
        NSUInteger size = f[1].unsignedIntegerValue;
        id v = values[i];
        if ([v isKindOfClass:[NSString class]]) {
            NSData *s = [v dataUsingEncoding:NSUTF8StringEncoding];
            for (NSUInteger k = 0; k < size; k++) [self appendByte:k < s.length ? ((const uint8_t *)s.bytes)[k] : 0];
        } else {
            [self appendInteger:(uint64_t)[v longLongValue] size:size bigEndian:big];
        }
    }];
    for (NSUInteger k = 0; k < [def[@"dev"] unsignedIntegerValue]; k++) [self appendByte:0xAB];
}

- (void)dataLocal:(uint8_t)local values:(NSArray *)values
{
    [self appendByte:local & 0xF];
    [self appendValues:values local:local];
}

- (void)compressedLocal:(uint8_t)local timeOffset:(uint8_t)offset values:(NSArray *)values
{
    [self appendByte:0x80 | ((local & 0x3) << 5) | (offset & 0x1F)];
    [self appendValues:values local:local];
}

- (NSData *)data
{
    NSMutableData *file = [NSMutableData data];
    uint8_t header[12] = { 14, 0x20, 0x47, 0x08, 0, 0, 0, 0, '.', 'F', 'I', 'T' };
    uint32_t size = (uint32_t)_records.length;
    for (int i = 0; i < 4; i++) header[4 + i] = (uint8_t)(size >> (8 * i));
    [file appendBytes:header length:12];
    uint16_t hcrc = [BPFITBuilder crcOfData:file];
    [file appendBytes:&hcrc length:2]; // little-endian host
    [file appendData:_records];
    uint16_t crc = [BPFITBuilder crcOfData:file];
    [file appendBytes:&crc length:2];
    return file;
}

@end
