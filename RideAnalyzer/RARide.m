//
//  RARide.m
//  RideAnalyzer
//

#import "RARide.h"
#import "RARideStats.h"

static const double RAAscentThreshold = 3.0; // meters

@implementation RARide

- (instancetype)init
{
    self = [super init];
    if (self) {
        _identifier = [NSUUID UUID].UUIDString;
        _name = @"";
        _format = @"";
        _fileName = @"";
        _contentHash = @"";
        _deviceKey = @"";
        _deviceName = @"";
        _sport = @"";
        _garminActivityID = @"";
        _bikeID = @"";
        _notes = @"";
        _tags = @[];
    }
    return self;
}

- (instancetype)initWithTrace:(NSArray<CLLocation *> *)trace name:(NSString *)name
{
    self = [self init];
    if (self) {
        _name = [name copy];
        _distance = [RARide distanceOfTrace:trace];
        _ascent = [RARide ascentOfTrace:trace threshold:RAAscentThreshold];
        NSDate *first = trace.firstObject.timestamp;
        NSDate *last = trace.lastObject.timestamp;
        _startDate = first;
        NSTimeInterval d = (first && last) ? [last timeIntervalSinceDate:first] : 0;
        _duration = d > 0 ? d : 0;
    }
    return self;
}

- (nullable instancetype)initWithPropertyList:(NSDictionary *)plist
{
    NSString *identifier = plist[@"identifier"];
    NSString *fileName = plist[@"fileName"];
    if (![identifier isKindOfClass:[NSString class]] || ![fileName isKindOfClass:[NSString class]]) return nil;
    self = [self init];
    if (self) {
        _identifier = [identifier copy];
        _fileName = [fileName copy];
        id v;
        if ([(v = plist[@"name"]) isKindOfClass:[NSString class]]) _name = [v copy];
        if ([(v = plist[@"startDate"]) isKindOfClass:[NSDate class]]) _startDate = v;
        if ([(v = plist[@"distance"]) isKindOfClass:[NSNumber class]]) _distance = [v doubleValue];
        if ([(v = plist[@"ascent"]) isKindOfClass:[NSNumber class]]) _ascent = [v doubleValue];
        if ([(v = plist[@"duration"]) isKindOfClass:[NSNumber class]]) _duration = [v doubleValue];
        if ([(v = plist[@"format"]) isKindOfClass:[NSString class]]) _format = [v copy];
        if ([(v = plist[@"contentHash"]) isKindOfClass:[NSString class]]) _contentHash = [v copy];
        if ([(v = plist[@"deviceKey"]) isKindOfClass:[NSString class]]) _deviceKey = [v copy];
        if ([(v = plist[@"deviceName"]) isKindOfClass:[NSString class]]) _deviceName = [v copy];
        if ([(v = plist[@"sport"]) isKindOfClass:[NSString class]]) _sport = [v copy];
        if ([(v = plist[@"garminActivityID"]) isKindOfClass:[NSString class]]) _garminActivityID = [v copy];
        if ([(v = plist[@"bikeID"]) isKindOfClass:[NSString class]]) _bikeID = [v copy];
        if ([(v = plist[@"trimStart"]) isKindOfClass:[NSNumber class]]) _trimStart = MAX(0, [v doubleValue]);
        if ([(v = plist[@"trimEnd"]) isKindOfClass:[NSNumber class]]) _trimEnd = MAX(0, [v doubleValue]);
        if ([(v = plist[@"notes"]) isKindOfClass:[NSString class]]) _notes = [v copy];
        _stats = [RARideStats statsWithPropertyList:plist[@"stats"]];
        if ([(v = plist[@"tags"]) isKindOfClass:[NSArray class]]) {
            NSMutableArray<NSString *> *tags = [NSMutableArray array];
            for (id t in v) if ([t isKindOfClass:[NSString class]]) [tags addObject:t];
            _tags = tags;
        }
    }
    return self;
}

- (NSDictionary *)propertyList
{
    NSMutableDictionary *d = [@{
        @"identifier": self.identifier,
        @"name": self.name,
        @"distance": @(self.distance),
        @"ascent": @(self.ascent),
        @"duration": @(self.duration),
        @"format": self.format,
        @"fileName": self.fileName,
        @"contentHash": self.contentHash,
        @"deviceKey": self.deviceKey,
        @"deviceName": self.deviceName,
        @"sport": self.sport,
        @"garminActivityID": self.garminActivityID,
        @"bikeID": self.bikeID,
        @"notes": self.notes,
        @"tags": self.tags,
    } mutableCopy];
    if (self.startDate) d[@"startDate"] = self.startDate;
    if (self.trimStart > 0) d[@"trimStart"] = @(self.trimStart);
    if (self.trimEnd > 0) d[@"trimEnd"] = @(self.trimEnd);
    if (self.stats) d[@"stats"] = self.stats.propertyList;
    return d;
}

+ (NSString *)deviceKeyForProduct:(nullable NSNumber *)product serialNumber:(nullable NSNumber *)serial
{
    if (product == nil && serial == nil) return @"";
    return [NSString stringWithFormat:@"p%@-s%@", product ?: @"", serial ?: @""];
}

+ (nullable NSString *)nameOfGarminProduct:(NSInteger)product
{
    // from the garmin_product type of the FIT SDK profile (Profile.xlsx, also the Garmin FIT SDKs on GitHub); only
    // the cycling computers and a few watches. TO CHECK there when adding one: products of watches differ by
    // region and size, and nothing here could be verified against the SDK when it was written (2026-11-21).
    static NSDictionary<NSNumber *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @1036: @"Edge 500", @1169: @"Edge 800", @1325: @"Edge 200", @1561: @"Edge 510", @1567: @"Edge 810",
            @1836: @"Edge 1000", @2067: @"Edge 520", @2530: @"Edge 820", @2713: @"Edge 1030", @2909: @"Edge 130",
            @3112: @"Edge 520 Plus", @3121: @"Edge 530", @3122: @"Edge 830", @3558: @"Edge 130 Plus",
            @3570: @"Edge 1030 Plus", @3843: @"Edge 1040", @4061: @"Edge 540", @4062: @"Edge 840",
            @2544: @"fēnix 5S", @2604: @"fēnix 5X", @2697: @"fēnix 5", @2691: @"Forerunner 935",
            @3076: @"Forerunner 245", @3077: @"Forerunner 245 Music", @3113: @"Forerunner 945",
            @3589: @"Forerunner 745", @3652: @"Forerunner 945 LTE", @3869: @"Forerunner 55",
            @2700: @"vívoactive 3",
            @3308: @"vívomove Style",   // checked: the owner's watch (FIT file_id product, TCX export creator)
        };
    });
    return names[@(product)];
}

+ (NSInteger)productOfDeviceKey:(NSString *)deviceKey
{
    // p<product>-s<serial>
    if (![deviceKey hasPrefix:@"p"]) return 0;
    NSString *first = [deviceKey componentsSeparatedByString:@"-"].firstObject ?: @"";
    return [first substringFromIndex:1].integerValue;
}

- (BOOL)isTrimmed
{
    return self.trimStart > 0 || self.trimEnd > 0;
}

- (double)averageSpeed
{
    return self.duration > 0 ? self.distance / self.duration * 3.6 : 0;
}

+ (double)distanceOfTrace:(NSArray<CLLocation *> *)trace
{
    double total = 0;
    for (NSUInteger i = 1; i < trace.count; i++) {
        total += [trace[i] distanceFromLocation:trace[i - 1]];
    }
    return total;
}

+ (double)ascentOfTrace:(NSArray<CLLocation *> *)trace threshold:(double)threshold
{
    if (trace.count < 2) return 0;
    double total = 0;
    double reference = trace[0].altitude;
    for (NSUInteger i = 1; i < trace.count; i++) {
        double alt = trace[i].altitude;
        if (alt - reference >= threshold) {
            total += alt - reference;
            reference = alt;
        } else if (alt < reference) {
            reference = alt;
        }
    }
    return total;
}

- (BOOL)isProbablySameRideAs:(RARide *)other
{
    if (!self.startDate || !other.startDate) return NO;
    if (fabs([self.startDate timeIntervalSinceDate:other.startDate]) > 60) return NO;
    double longest = MAX(self.distance, other.distance);
    if (longest <= 0) return YES;
    return fabs(self.distance - other.distance) / longest <= 0.02;
}

@end
