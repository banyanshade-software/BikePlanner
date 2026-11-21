//
//  RARideStats.m
//  RideAnalyzer
//

#import "RARideStats.h"
#import "RAHeatmap.h"
#import "RARideAnalysis.h"

const NSInteger RATerrainCount = 5;
const NSInteger RARideStatsVersion = 2; // 2: track (R10)

static const double RAMovingSpeedStats = 3.0 / 3.6; // m/s, as RARideAnalysis

RATerrain RATerrainOfSlope(double slope)
{
    if (slope < -1) return RATerrainDescent;
    if (slope < 1) return RATerrainFlat;
    if (slope < 4) return RATerrainGentle;
    if (slope < 8) return RATerrainClimb;
    return RATerrainSteep;
}

static NSArray<NSString *> *RATerrainKeys(void)
{
    return @[ @"descent", @"flat", @"gentle", @"climb", @"steep" ];
}

@implementation RATerrainStats

- (double)speed
{
    return self.time > 0 ? self.distance / self.time * 3.6 : NAN;
}

- (double)heartRate
{
    return self.heartRateTime > 0 ? self.heartRateSum / self.heartRateTime : NAN;
}

- (double)power
{
    return self.powerTime > 0 ? self.powerSum / self.powerTime : NAN;
}

- (double)climbingSpeed
{
    return self.time > 0 ? self.ascent / self.time * 3600 : NAN;
}

- (void)add:(RATerrainStats *)other
{
    self.time += other.time;
    self.distance += other.distance;
    self.ascent += other.ascent;
    self.heartRateSum += other.heartRateSum;
    self.heartRateTime += other.heartRateTime;
    self.powerSum += other.powerSum;
    self.powerTime += other.powerTime;
}

- (NSDictionary *)propertyList
{
    return @{ @"time": @(self.time), @"distance": @(self.distance), @"ascent": @(self.ascent),
              @"hrSum": @(self.heartRateSum), @"hrTime": @(self.heartRateTime),
              @"powerSum": @(self.powerSum), @"powerTime": @(self.powerTime) };
}

+ (RATerrainStats *)statsWithPropertyList:(nullable NSDictionary *)plist
{
    RATerrainStats *t = [[RATerrainStats alloc] init];
    if (![plist isKindOfClass:[NSDictionary class]]) return t;
    double (^num)(NSString *) = ^double(NSString *k) {
        id v = plist[k];
        return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : 0;
    };
    t.time = num(@"time");
    t.distance = num(@"distance");
    t.ascent = num(@"ascent");
    t.heartRateSum = num(@"hrSum");
    t.heartRateTime = num(@"hrTime");
    t.powerSum = num(@"powerSum");
    t.powerTime = num(@"powerTime");
    return t;
}

@end

@implementation RARideStats
{
    NSArray<RATerrainStats *> *_terrains;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _version = RARideStatsVersion;
        _total = [[RATerrainStats alloc] init];
        NSMutableArray *t = [NSMutableArray array];
        for (NSInteger i = 0; i < RATerrainCount; i++) [t addObject:[[RATerrainStats alloc] init]];
        _terrains = t;
        _maxHeartRate = NAN;
        _maxPower = NAN;
        _calories = NAN;
        _track = [NSData data];
    }
    return self;
}

- (RATerrainStats *)statsForTerrain:(RATerrain)terrain
{
    if (terrain < 0 || terrain >= RATerrainCount) return _total;
    return _terrains[(NSUInteger)terrain];
}

+ (RARideStats *)statsOfAnalysis:(RARideAnalysis *)a
{
    RARideStats *s = [[RARideStats alloc] init];
    s.maxSpeed = a.maxSpeed;
    s.maxHeartRate = a.maxHeartRate;
    s.maxPower = a.maxPower;
    s.calories = a.calories != nil ? a.calories.doubleValue : NAN;
    s.track = [RAHeatmap packedTrackOfTrace:a.trace tolerance:8];
    if (!a.hasTimes) return s;
    // each moving interval goes to the terrain of the slope at its end
    for (NSUInteger i = 1; i < a.count; i++) {
        double dt = a.elapsed[i].doubleValue - a.elapsed[i - 1].doubleValue;
        double dd = a.distances[i].doubleValue - a.distances[i - 1].doubleValue;
        if (dt <= 0 || dd / dt <= RAMovingSpeedStats) continue;
        RATerrainStats *t = [s statsForTerrain:RATerrainOfSlope(a.slopes[i].doubleValue)];
        RATerrainStats *interval = [[RATerrainStats alloc] init];
        interval.time = dt;
        interval.distance = dd;
        interval.ascent = MAX(0, a.altitudes[i].doubleValue - a.altitudes[i - 1].doubleValue);
        double hr = a.heartRates[i].doubleValue, power = a.powers[i].doubleValue;
        if (RAHasValue(hr)) { interval.heartRateSum = hr * dt; interval.heartRateTime = dt; }
        if (RAHasValue(power)) { interval.powerSum = power * dt; interval.powerTime = dt; }
        [t add:interval];
        [s.total add:interval];
    }
    s.movingTime = s.total.time;
    return s;
}

- (NSDictionary *)propertyList
{
    NSMutableDictionary *terrains = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < RATerrainCount; i++) terrains[RATerrainKeys()[(NSUInteger)i]] = _terrains[(NSUInteger)i].propertyList;
    NSMutableDictionary *d = [@{ @"version": @(self.version), @"movingTime": @(self.movingTime),
                                 @"maxSpeed": @(self.maxSpeed), @"total": self.total.propertyList,
                                 @"terrains": terrains, @"track": self.track } mutableCopy];
    // NaN cannot go into a property list: absent means no value
    if (!isnan(self.maxHeartRate)) d[@"maxHR"] = @(self.maxHeartRate);
    if (!isnan(self.maxPower)) d[@"maxPower"] = @(self.maxPower);
    if (!isnan(self.calories)) d[@"calories"] = @(self.calories);
    return d;
}

+ (nullable RARideStats *)statsWithPropertyList:(nullable NSDictionary *)plist
{
    if (![plist isKindOfClass:[NSDictionary class]]) return nil;
    id version = plist[@"version"];
    if (![version isKindOfClass:[NSNumber class]] || [version integerValue] != RARideStatsVersion) return nil;
    RARideStats *s = [[RARideStats alloc] init];
    id v;
    if ([(v = plist[@"movingTime"]) isKindOfClass:[NSNumber class]]) s.movingTime = [v doubleValue];
    if ([(v = plist[@"maxSpeed"]) isKindOfClass:[NSNumber class]]) s.maxSpeed = [v doubleValue];
    if ([(v = plist[@"maxHR"]) isKindOfClass:[NSNumber class]]) s.maxHeartRate = [v doubleValue];
    if ([(v = plist[@"maxPower"]) isKindOfClass:[NSNumber class]]) s.maxPower = [v doubleValue];
    if ([(v = plist[@"calories"]) isKindOfClass:[NSNumber class]]) s.calories = [v doubleValue];
    if ([(v = plist[@"track"]) isKindOfClass:[NSData class]]) s.track = v;
    [s.total add:[RATerrainStats statsWithPropertyList:plist[@"total"]]];
    id terrains = plist[@"terrains"];
    for (NSInteger i = 0; i < RATerrainCount; i++) {
        NSDictionary *t = [terrains isKindOfClass:[NSDictionary class]] ? terrains[RATerrainKeys()[(NSUInteger)i]] : nil;
        [[s statsForTerrain:(RATerrain)i] add:[RATerrainStats statsWithPropertyList:t]];
    }
    return s;
}

@end
