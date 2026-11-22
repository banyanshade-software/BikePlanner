//
//  RARideStats.m
//  RideAnalyzer
//

#import "RARideStats.h"
#import "RAHeatmap.h"
#import "RAClimbs.h"
#import "RARideAnalysis.h"

const NSInteger RATerrainCount = 5;
const NSInteger RARideStatsVersion = 5; // 2: track (R10); 3: work sums of the estimated power (R11); 4: climbs (R7);
                                        // 5: no work while freewheeling

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
    self.gravityWork += other.gravityWork;
    self.rollingWork += other.rollingWork;
    self.surfaceRollingWork += other.surfaceRollingWork;
    self.inertiaWork += other.inertiaWork;
    self.airWork += other.airWork;
    self.estimatedPowerSum += other.estimatedPowerSum;
}

- (NSDictionary *)propertyList
{
    return @{ @"time": @(self.time), @"distance": @(self.distance), @"ascent": @(self.ascent),
              @"hrSum": @(self.heartRateSum), @"hrTime": @(self.heartRateTime),
              @"powerSum": @(self.powerSum), @"powerTime": @(self.powerTime),
              @"gravityWork": @(self.gravityWork), @"rollingWork": @(self.rollingWork),
              @"surfaceRollingWork": @(self.surfaceRollingWork),
              @"inertiaWork": @(self.inertiaWork), @"airWork": @(self.airWork) };
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
    t.gravityWork = num(@"gravityWork");
    t.rollingWork = num(@"rollingWork");
    t.surfaceRollingWork = num(@"surfaceRollingWork");
    t.inertiaWork = num(@"inertiaWork");
    t.airWork = num(@"airWork");
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
        _climbs = @[];
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
    return [self statsOfAnalysis:a wind:nil];
}

+ (nullable RATerrainStats *)statsOfIntervalAtIndex:(NSUInteger)i ofAnalysis:(RARideAnalysis *)a
                                               wind:(nullable RAWindProvider)wind
{
    if (!a.hasTimes || i == 0 || i >= a.count) return nil;
    double dt = a.elapsed[i].doubleValue - a.elapsed[i - 1].doubleValue;
    double dd = a.distances[i].doubleValue - a.distances[i - 1].doubleValue;
    if (dt <= 0 || dd / dt <= RAMovingSpeedStats) return nil;
    RATerrainStats *interval = [[RATerrainStats alloc] init];
    interval.time = dt;
    interval.distance = dd;
    interval.ascent = MAX(0, a.altitudes[i].doubleValue - a.altitudes[i - 1].doubleValue);
    double hr = a.heartRates[i].doubleValue, power = a.powers[i].doubleValue;
    if (RAHasValue(hr)) { interval.heartRateSum = hr * dt; interval.heartRateTime = dt; }
    if (RAHasValue(power) && !a.powerIsEstimated) { interval.powerSum = power * dt; interval.powerTime = dt; }
    // work of the forces (R11): slope of the point, speed and acceleration of the interval; none while freewheeling
    // (cadence 0, when the file has the cadence): the time still counts, so the average includes these zeros
    double cadence = a.hasCadence ? a.cadences[i].doubleValue : RANoValue;
    if (a.hasCadence && RAHasValue(cadence) && cadence <= 0) return interval;
    double slope = a.slopes[i].doubleValue, theta = atan((RAHasValue(slope) ? slope : 0) / 100);
    double v = dd / dt;
    double vPrev = 0;
    if (i >= 2) {
        double dtp = a.elapsed[i - 1].doubleValue - a.elapsed[i - 2].doubleValue;
        double ddp = a.distances[i - 1].doubleValue - a.distances[i - 2].doubleValue;
        vPrev = dtp > 0 ? ddp / dtp : 0;
    }
    double acc = vPrev > RAMovingSpeedStats ? (v - vPrev) / dt : 0;
    double headwind = 0;
    RAWind *w = wind ? wind(i) : nil;
    if (w) {
        CLLocationCoordinate2D p = a.trace[i - 1].coordinate, q = a.trace[i].coordinate;
        headwind = [w headwindForHeading:[RAPowerModel headingFromLatitude:p.latitude longitude:p.longitude
                                                                toLatitude:q.latitude longitude:q.longitude]];
    }
    double temperature = a.hasTemperature ? a.temperatures[i].doubleValue : NAN;
    double rho = [RAPowerModel airDensityAtAltitude:a.altitudes[i].doubleValue
                                        temperature:RAHasValue(temperature) ? temperature : a.averageTemperature];
    // the air: the speed of the sensor when the file has it (GPS distances are noisier), else of the interval
    double s0 = a.speeds[i - 1].doubleValue, s1 = a.speeds[i].doubleValue;
    double sensor = RAHasValue(s0) && RAHasValue(s1) && s0 > 0 && s1 > 0 ? (s0 + s1) / 2 / 3.6 : v;
    double air = sensor + headwind;
    interval.gravityWork = RAGravity * sin(theta) * dd;
    // R8: the surface of the road when known (its factor of the tyres' Crr), else the bike's usual roads (at power time)
    double factor = a.rollingFactors && i < a.rollingFactors.count ? a.rollingFactors[i].doubleValue : 0;
    if (factor > 0) interval.surfaceRollingWork = RAGravity * cos(theta) * dd * factor;
    else interval.rollingWork = RAGravity * cos(theta) * dd;
    interval.inertiaWork = acc * dd;
    interval.airWork = 0.5 * rho * air * fabs(air) * dd;
    return interval;
}

+ (RARideStats *)statsOfAnalysis:(RARideAnalysis *)a wind:(nullable RAWindProvider)wind
{
    RARideStats *s = [[RARideStats alloc] init];
    s.maxSpeed = a.maxSpeed;
    s.maxHeartRate = a.maxHeartRate;
    s.maxPower = a.powerIsEstimated ? NAN : a.maxPower;
    s.calories = a.calories != nil ? a.calories.doubleValue : NAN;
    s.track = [RAHeatmap packedTrackOfTrace:a.trace tolerance:8];
    s.climbs = [RAClimbDetector climbsOfAnalysis:a wind:wind];
    s.usesRoads = a.rollingFactors != nil;
    if (!a.hasTimes) return s;
    // each moving interval goes to the terrain of the slope at its end
    for (NSUInteger i = 1; i < a.count; i++) {
        RATerrainStats *interval = [self statsOfIntervalAtIndex:i ofAnalysis:a wind:wind];
        if (!interval) continue;
        [[s statsForTerrain:RATerrainOfSlope(a.slopes[i].doubleValue)] add:interval];
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
                                 @"terrains": terrains, @"track": self.track,
                                 @"climbs": [self.climbs valueForKey:@"propertyList"],
                                 @"usesRoads": @(self.usesRoads) } mutableCopy];
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
    s.usesRoads = [plist[@"usesRoads"] boolValue];
    if ([(v = plist[@"climbs"]) isKindOfClass:[NSArray class]]) {
        NSMutableArray<RAClimb *> *climbs = [NSMutableArray array];
        for (id c in v) { RAClimb *climb = [RAClimb climbWithPropertyList:c]; if (climb) [climbs addObject:climb]; }
        s.climbs = climbs;
    }
    [s.total add:[RATerrainStats statsWithPropertyList:plist[@"total"]]];
    id terrains = plist[@"terrains"];
    for (NSInteger i = 0; i < RATerrainCount; i++) {
        NSDictionary *t = [terrains isKindOfClass:[NSDictionary class]] ? terrains[RATerrainKeys()[(NSUInteger)i]] : nil;
        [[s statsForTerrain:(RATerrain)i] add:[RATerrainStats statsWithPropertyList:t]];
    }
    return s;
}

@end
