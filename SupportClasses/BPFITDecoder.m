//
//  BPFITDecoder.m
//  BikePlanner
//
//  Minimal FIT decoder (#76).
//

#import "BPFITDecoder.h"

static NSString *const BPFITErrorDomain = @"BPFITDecoder";

enum {
    BPFITMesgFileId = 0,
    BPFITMesgSport = 12,
    BPFITMesgSession = 18,
    BPFITMesgRecord = 20,
    BPFITMesgCoursePoint = 32,
    BPFITFieldTimestamp = 253,
    // record
    BPFITRecordLat = 0, BPFITRecordLon = 1, BPFITRecordAltitude = 2, BPFITRecordEnhancedAltitude = 78,
    // course_point
    BPFITCoursePointTimestamp = 1, BPFITCoursePointLat = 2, BPFITCoursePointLon = 3, BPFITCoursePointType = 5,
    BPFITCoursePointName = 6,
    // file_id (#82)
    BPFITFileIdType = 0, BPFITFileIdManufacturer = 1, BPFITFileIdProduct = 2, BPFITFileIdSerialNumber = 3,
    BPFITFileIdTimeCreated = 4,
    // sport: sport; session: sport
    BPFITSportSport = 0, BPFITSessionSport = 5,
};

// seconds between 1970-01-01 and the FIT epoch, 1989-12-31 00:00 UTC
static const NSTimeInterval BPFITEpoch = 631065600;

typedef struct {
    uint8_t num, size, baseType;
} BPFITField;

// a definition message: the layout of the data messages of a local type
@interface BPFITDefinition : NSObject {
@public
    uint16_t global;
    BOOL bigEndian;
    NSUInteger fieldCount;
    BPFITField fields[256];
    NSUInteger developerSize; // bytes of developer fields after the fields
}
@end
@implementation BPFITDefinition
@end

@implementation BPFITDecoder {
    NSMutableArray<CLLocation *> *_records;
    NSMutableArray<CLLocation *> *_coursePoints;
    NSMutableArray<NSNumber *> *_coursePointTypes;
    NSMutableArray<NSString *> *_coursePointNames;
    NSUInteger _timedRecords;
}

+ (BOOL)isFITData:(NSData *)data
{
    if (data.length < 12) return NO;
    const uint8_t *b = data.bytes;
    return (b[0] == 12 || b[0] == 14) && memcmp(b + 8, ".FIT", 4) == 0;
}

static uint16_t BPFITCRC(const uint8_t *bytes, NSUInteger length)
{
    static const uint16_t table[16] = { 0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
                                        0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400 };
    uint16_t crc = 0;
    for (NSUInteger i = 0; i < length; i++) {
        uint16_t t = table[crc & 0xF];
        crc = (crc >> 4) & 0x0FFF;
        crc = crc ^ t ^ table[bytes[i] & 0xF];
        t = table[crc & 0xF];
        crc = (crc >> 4) & 0x0FFF;
        crc = crc ^ t ^ table[(bytes[i] >> 4) & 0xF];
    }
    return crc;
}

static uint64_t BPFITReadUInt(const uint8_t *p, NSUInteger size, BOOL bigEndian)
{
    uint64_t v = 0;
    for (NSUInteger i = 0; i < size; i++) {
        NSUInteger shift = bigEndian ? (size - 1 - i) * 8 : i * 8;
        v |= (uint64_t)p[i] << shift;
    }
    return v;
}

- (BOOL)fail:(NSString *)reason error:(NSError * _Nullable *)error
{
    if (error) {
        NSString *d = [NSString stringWithFormat:NSLocalizedString(@"The FIT file is damaged (%@).", @"FIT import"), reason];
        *error = [NSError errorWithDomain:BPFITErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: d }];
    }
    return NO;
}

- (BOOL)decodeData:(NSData *)data error:(NSError * _Nullable *)error
{
    _records = [NSMutableArray array];
    _coursePoints = [NSMutableArray array];
    _coursePointTypes = [NSMutableArray array];
    _coursePointNames = [NSMutableArray array];
    _timedRecords = 0;
    _fileType = nil;
    _manufacturer = nil;
    _product = nil;
    _serialNumber = nil;
    _timeCreated = nil;
    _sport = nil;
    if (![BPFITDecoder isFITData:data]) return [self fail:@"header" error:error];
    const uint8_t *b = data.bytes;
    NSUInteger headerSize = b[0];
    NSUInteger dataSize = (NSUInteger)BPFITReadUInt(b + 4, 4, NO);
    NSUInteger end = headerSize + dataSize;
    if (data.length < end + 2) return [self fail:@"truncated" error:error];
    // header CRC: optional (0 = not computed); file CRC over header and records
    if (headerSize == 14) {
        uint16_t hcrc = (uint16_t)BPFITReadUInt(b + 12, 2, NO);
        if (hcrc != 0 && hcrc != BPFITCRC(b, 12)) return [self fail:@"header CRC" error:error];
    }
    if (BPFITReadUInt(b + end, 2, NO) != BPFITCRC(b, end)) return [self fail:@"CRC" error:error];

    BPFITDefinition *defs[16] = { nil };
    uint32_t lastTimestamp = 0;
    NSUInteger i = headerSize;
    while (i < end) {
        uint8_t h = b[i++];
        BPFITDefinition *def;
        BOOL compressed = (h & 0x80) != 0;
        if (compressed) {
            def = defs[(h >> 5) & 0x3];
        } else if (h & 0x40) {
            // definition message: reserved, architecture, global message number, fields, developer fields
            if (i + 5 > end) return [self fail:@"definition" error:error];
            BPFITDefinition *d = [[BPFITDefinition alloc] init];
            d->bigEndian = b[i + 1] == 1;
            d->global = (uint16_t)BPFITReadUInt(b + i + 2, 2, d->bigEndian);
            d->fieldCount = b[i + 4];
            i += 5;
            if (i + 3 * d->fieldCount > end) return [self fail:@"definition" error:error];
            for (NSUInteger k = 0; k < d->fieldCount; k++, i += 3) {
                d->fields[k] = (BPFITField){ b[i], b[i + 1], b[i + 2] };
            }
            if (h & 0x20) {
                if (i >= end) return [self fail:@"definition" error:error];
                NSUInteger n = b[i++];
                if (i + 3 * n > end) return [self fail:@"definition" error:error];
                for (NSUInteger k = 0; k < n; k++, i += 3) d->developerSize += b[i + 1];
            }
            defs[h & 0xF] = d;
            continue;
        } else {
            def = defs[h & 0xF];
        }
        if (!def) return [self fail:@"undefined message" error:error];

        // data message
        NSDictionary<NSNumber *, NSNumber *> *values = nil;
        NSString *name = nil;
        BOOL wanted = def->global == BPFITMesgRecord || def->global == BPFITMesgCoursePoint
            || def->global == BPFITMesgFileId || def->global == BPFITMesgSport || def->global == BPFITMesgSession;
        NSMutableDictionary<NSNumber *, NSNumber *> *v = wanted ? [NSMutableDictionary dictionary] : nil;
        for (NSUInteger k = 0; k < def->fieldCount; k++) {
            BPFITField f = def->fields[k];
            if (i + f.size > end) return [self fail:@"truncated message" error:error];
            if (v) {
                uint8_t type = f.baseType & 0x1F;
                if (type == 7) { // string, NUL-terminated or padded
                    if (def->global == BPFITMesgCoursePoint && f.num == BPFITCoursePointName) {
                        NSUInteger len = strnlen((const char *)b + i, f.size);
                        name = [[NSString alloc] initWithBytes:b + i length:len encoding:NSUTF8StringEncoding];
                    }
                } else if (f.size == 1 || f.size == 2 || f.size == 4) {
                    uint64_t raw = BPFITReadUInt(b + i, f.size, def->bigEndian);
                    BOOL invalid = raw == (f.size == 1 ? 0xFF : f.size == 2 ? 0xFFFF : 0xFFFFFFFF);
                    if (type == 10 || type == 11 || type == 12) invalid = raw == 0; // uint8z, uint16z, uint32z
                    BOOL isSigned = type == 1 || type == 3 || type == 5;
                    if (isSigned) {
                        int64_t s = f.size == 1 ? (int8_t)raw : f.size == 2 ? (int16_t)raw : (int32_t)raw;
                        invalid = raw == (f.size == 1 ? 0x7F : f.size == 2 ? 0x7FFF : 0x7FFFFFFF);
                        if (!invalid) v[@(f.num)] = @(s);
                    } else if (!invalid) {
                        v[@(f.num)] = @(raw);
                    }
                }
            }
            i += f.size;
        }
        if (i + def->developerSize > end) return [self fail:@"truncated message" error:error];
        i += def->developerSize;
        values = v;

        // timestamps: a field 253 resets the reference; a compressed header gives the low 5 bits
        NSNumber *ts = values[@(BPFITFieldTimestamp)];
        if (ts != nil) {
            lastTimestamp = ts.unsignedIntValue;
        } else if (compressed) {
            uint32_t offset = h & 0x1F;
            uint32_t t = (lastTimestamp & ~(uint32_t)0x1F) + offset;
            if (offset < (lastTimestamp & 0x1F)) t += 0x20;
            lastTimestamp = t;
        }
        if (!values) continue;

        if (def->global == BPFITMesgFileId) {
            if (_fileType == nil) { // the first file_id describes the file
                _fileType = values[@(BPFITFileIdType)];
                _manufacturer = values[@(BPFITFileIdManufacturer)];
                _product = values[@(BPFITFileIdProduct)];
                _serialNumber = values[@(BPFITFileIdSerialNumber)];
                NSNumber *t = values[@(BPFITFileIdTimeCreated)];
                if (t != nil) _timeCreated = [NSDate dateWithTimeIntervalSince1970:BPFITEpoch + t.unsignedIntValue];
                if (_fileType == nil) _fileType = @0xFF;
            }
            continue;
        }
        if (def->global == BPFITMesgSport || def->global == BPFITMesgSession) {
            NSNumber *sport = values[@(def->global == BPFITMesgSport ? BPFITSportSport : BPFITSessionSport)];
            if (sport != nil && _sport == nil) _sport = sport;
            continue;
        }
        if (def->global == BPFITMesgRecord) {
            NSNumber *lat = values[@(BPFITRecordLat)], *lon = values[@(BPFITRecordLon)];
            if (lat == nil || lon == nil) continue; // no position: GPS lost, indoor
            NSNumber *alt = values[@(BPFITRecordEnhancedAltitude)] ?: values[@(BPFITRecordAltitude)];
            NSDate *date = lastTimestamp ? [NSDate dateWithTimeIntervalSince1970:BPFITEpoch + lastTimestamp] : [NSDate date];
            CLLocation *loc = [self locationWithLat:lat lon:lon altitude:alt date:date];
            if (loc) {
                [_records addObject:loc];
                if (lastTimestamp) _timedRecords++;
            }
        } else {
            NSNumber *lat = values[@(BPFITCoursePointLat)], *lon = values[@(BPFITCoursePointLon)];
            if (lat == nil || lon == nil) continue;
            NSNumber *t = values[@(BPFITCoursePointTimestamp)];
            NSDate *date = t != nil ? [NSDate dateWithTimeIntervalSince1970:BPFITEpoch + t.unsignedIntValue] : [NSDate date];
            CLLocation *loc = [self locationWithLat:lat lon:lon altitude:nil date:date];
            if (!loc) continue;
            [_coursePoints addObject:loc];
            [_coursePointTypes addObject:values[@(BPFITCoursePointType)] ?: @0xFF];
            [_coursePointNames addObject:[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @""];
        }
    }
    return YES;
}

- (nullable CLLocation *)locationWithLat:(NSNumber *)lat lon:(NSNumber *)lon altitude:(nullable NSNumber *)alt date:(NSDate *)date
{
    // semicircles → degrees; altitude: scale 5, offset 500 m
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat.doubleValue * 180.0 / 2147483648.0,
                                                          lon.doubleValue * 180.0 / 2147483648.0);
    if (!CLLocationCoordinate2DIsValid(c)) return nil;
    double altitude = alt != nil ? alt.doubleValue / 5.0 - 500.0 : 0;
    return [[CLLocation alloc] initWithCoordinate:c altitude:altitude horizontalAccuracy:kCLLocationAccuracyBest
                                 verticalAccuracy:kCLLocationAccuracyBest timestamp:date];
}

- (NSArray<CLLocation *> *)records { return [_records copy] ?: @[]; }
- (BOOL)hasTimes { return _records.count > 0 && _timedRecords == _records.count; }
- (NSArray<CLLocation *> *)coursePoints { return [_coursePoints copy] ?: @[]; }
- (NSArray<NSNumber *> *)coursePointTypes { return [_coursePointTypes copy] ?: @[]; }
- (NSArray<NSString *> *)coursePointNames { return [_coursePointNames copy] ?: @[]; }

@end
