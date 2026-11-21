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
        @"notes": self.notes,
        @"tags": self.tags,
    } mutableCopy];
    if (self.startDate) d[@"startDate"] = self.startDate;
    if (self.stats) d[@"stats"] = self.stats.propertyList;
    return d;
}

+ (NSString *)deviceKeyForProduct:(nullable NSNumber *)product serialNumber:(nullable NSNumber *)serial
{
    if (product == nil && serial == nil) return @"";
    return [NSString stringWithFormat:@"p%@-s%@", product ?: @"", serial ?: @""];
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
