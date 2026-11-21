//
//  RATrends.m
//  RideAnalyzer
//

#import "RATrends.h"
#import "RARide.h"

const NSTimeInterval RATrendMinimumTime = 120;

@implementation RATrendPoint
@end

@implementation RARecord
@end

@implementation RATrends

+ (double)value:(RATrendMeasure)measure of:(RATerrainStats *)t
{
    if (t.time < RATrendMinimumTime) return NAN;
    double v = NAN;
    switch (measure) {
        case RATrendSpeed: v = t.speed; break;
        case RATrendHeartRate: v = t.heartRate; break;
        case RATrendPower: v = t.power; break;
        case RATrendPowerPerBeat: v = t.heartRate > 0 ? t.power / t.heartRate : NAN; break;
        case RATrendSpeedPerBeat: v = t.heartRate > 0 ? t.speed / t.heartRate * 100 : NAN; break;
        case RATrendClimbingSpeed: v = t.climbingSpeed; break;
    }
    return isfinite(v) && v > 0 ? v : NAN;
}

/// the start of the period of a date (local calendar; weeks as the locale starts them)
+ (NSDate *)startOfPeriod:(NSCalendarUnit)unit forDate:(NSDate *)date
{
    NSDate *start = nil;
    NSTimeInterval length = 0;
    [[NSCalendar currentCalendar] rangeOfUnit:unit startDate:&start interval:&length forDate:date];
    return start ?: date;
}

+ (NSCalendarUnit)unitOfGrouping:(RATrendGrouping)grouping
{
    return grouping == RATrendPerWeek ? NSCalendarUnitWeekOfYear : NSCalendarUnitMonth;
}

+ (NSArray<RARide *> *)datedRidesWithStats:(NSArray<RARide *> *)rides
{
    NSMutableArray<RARide *> *kept = [NSMutableArray array];
    for (RARide *r in rides) if (r.stats && r.startDate) [kept addObject:r];
    [kept sortUsingComparator:^NSComparisonResult(RARide *a, RARide *b) { return [a.startDate compare:(NSDate *)b.startDate]; }];
    return kept;
}

+ (NSArray<RATrendPoint *> *)pointsForRides:(NSArray<RARide *> *)rides measure:(RATrendMeasure)measure
                                    terrain:(RATerrain)terrain grouping:(RATrendGrouping)grouping
{
    NSMutableArray<RATrendPoint *> *points = [NSMutableArray array];
    NSArray<RARide *> *sorted = [self datedRidesWithStats:rides];
    if (grouping == RATrendPerRide) {
        for (RARide *r in sorted) {
            double v = [self value:measure of:[r.stats statsForTerrain:terrain]];
            if (isnan(v)) continue;
            RATrendPoint *p = [[RATrendPoint alloc] init];
            p.date = (NSDate *)r.startDate;
            p.value = v;
            p.rides = 1;
            p.ride = r;
            [points addObject:p];
        }
        return points;
    }
    NSCalendarUnit unit = [self unitOfGrouping:grouping];
    __block NSDate *current = nil;          // the period being summed (the block below reads the latest values)
    __block RATerrainStats *sum = nil;
    __block NSUInteger count = 0;
    void (^flush)(void) = ^{
        if (!current) return;
        double v = [self value:measure of:sum];
        if (isnan(v)) return;
        RATrendPoint *p = [[RATrendPoint alloc] init];
        p.date = current;
        p.value = v;
        p.rides = count;
        [points addObject:p];
    };
    for (RARide *r in sorted) {
        NSDate *start = [self startOfPeriod:unit forDate:(NSDate *)r.startDate];
        if (!current || ![start isEqualToDate:current]) {
            flush();
            current = start;
            sum = [[RATerrainStats alloc] init];
            count = 0;
        }
        RATerrainStats *t = [r.stats statsForTerrain:terrain];
        if (t.time > 0) {
            [sum add:t];
            count++;
        }
    }
    flush();
    return points;
}

+ (nullable NSArray<NSNumber *> *)trendLineOfPoints:(NSArray<RATrendPoint *> *)points
{
    if (points.count < 2) return nil;
    double t0 = points.firstObject.date.timeIntervalSinceReferenceDate;
    double n = points.count, sx = 0, sy = 0, sxx = 0, sxy = 0;
    for (RATrendPoint *p in points) {
        double x = (p.date.timeIntervalSinceReferenceDate - t0) / 86400, y = p.value;
        sx += x; sy += y; sxx += x * x; sxy += x * y;
    }
    double d = n * sxx - sx * sx;
    double slope = d != 0 ? (n * sxy - sx * sy) / d : 0;
    double intercept = (sy - slope * sx) / n;
    double xEnd = (points.lastObject.date.timeIntervalSinceReferenceDate - t0) / 86400;
    return @[ @(intercept), @(intercept + slope * xEnd) ];
}

+ (NSArray<RATrendPoint *> *)totalsForRides:(NSArray<RARide *> *)rides measure:(RATotalMeasure)measure
                                     period:(RAPeriod)period
{
    NSMutableArray<RARide *> *dated = [NSMutableArray array];
    for (RARide *r in rides) if (r.startDate) [dated addObject:r];
    [dated sortUsingComparator:^NSComparisonResult(RARide *a, RARide *b) { return [a.startDate compare:(NSDate *)b.startDate]; }];
    if (dated.count == 0) return @[];
    NSCalendarUnit unit = period == RAPeriodWeek ? NSCalendarUnitWeekOfYear
                        : period == RAPeriodMonth ? NSCalendarUnitMonth : NSCalendarUnitYear;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSMutableArray<RATrendPoint *> *points = [NSMutableArray array];
    NSDate *periodStart = [self startOfPeriod:unit forDate:(NSDate *)dated.firstObject.startDate];
    NSDate *last = [self startOfPeriod:unit forDate:(NSDate *)dated.lastObject.startDate];
    NSUInteger i = 0;
    while ([periodStart compare:last] != NSOrderedDescending) {
        NSDate *next = [cal dateByAddingUnit:unit value:1 toDate:periodStart options:0];
        if (!next) break;
        RATrendPoint *p = [[RATrendPoint alloc] init];
        p.date = periodStart;
        double v = 0;
        while (i < dated.count && [dated[i].startDate compare:next] == NSOrderedAscending) {
            RARide *r = dated[i++];
            p.rides++;
            switch (measure) {
                case RATotalDistance: v += r.distance / 1000; break;
                case RATotalAscent: v += r.ascent; break;
                case RATotalTime: v += (r.stats ? r.stats.movingTime : r.duration) / 3600; break;
                case RATotalRides: v += 1; break;
            }
        }
        p.value = v;
        [points addObject:p];
        periodStart = next;
    }
    return points;
}

+ (NSArray<RARecord *> *)recordsForRides:(NSArray<RARide *> *)rides
{
    NSMutableArray<RARecord *> *records = [NSMutableArray array];
    void (^add)(NSString *, double (^)(RARide *), NSString *(^)(double)) =
        ^(NSString *title, double (^value)(RARide *), NSString *(^format)(double)) {
            RARide *best = nil;
            double bestValue = 0;
            for (RARide *r in rides) {
                double v = value(r);
                if (isfinite(v) && v > bestValue) { best = r; bestValue = v; }
            }
            if (!best) return;
            RARecord *rec = [[RARecord alloc] init];
            rec.title = title;
            rec.ride = best;
            rec.value = format(bestValue);
            [records addObject:rec];
        };
    add(NSLocalizedString(@"Longest ride", @"record"), ^double(RARide *r) { return r.distance; },
        ^NSString *(double v) { return [NSString localizedStringWithFormat:@"%.1f km", v / 1000]; });
    add(NSLocalizedString(@"Most ascent", @"record"), ^double(RARide *r) { return r.ascent; },
        ^NSString *(double v) { return [NSString localizedStringWithFormat:@"%.0f m", v]; });
    add(NSLocalizedString(@"Best average speed (over 50 km)", @"record"), ^double(RARide *r) {
            if (r.distance < 50000) return NAN;
            return r.stats ? r.stats.total.speed : r.averageSpeed;
        }, ^NSString *(double v) { return [NSString localizedStringWithFormat:@"%.1f km/h", v]; });
    add(NSLocalizedString(@"Longest moving time", @"record"), ^double(RARide *r) { return r.stats ? r.stats.movingTime : NAN; },
        ^NSString *(double v) {
            long m = lround(v / 60);
            return [NSString localizedStringWithFormat:NSLocalizedString(@"%ld h %02ld", @"duration: hours, minutes"), m / 60, m % 60];
        });
    add(NSLocalizedString(@"Highest power", @"record"), ^double(RARide *r) { return r.stats ? r.stats.maxPower : NAN; },
        ^NSString *(double v) { return [NSString localizedStringWithFormat:@"%.0f W", v]; });
    return records;
}

+ (NSString *)nameOfMeasure:(RATrendMeasure)measure
{
    switch (measure) {
        case RATrendSpeed: return NSLocalizedString(@"Average speed (km/h)", @"trend");
        case RATrendHeartRate: return NSLocalizedString(@"Average heart rate (bpm)", @"trend");
        case RATrendPower: return NSLocalizedString(@"Average power (W)", @"trend");
        case RATrendPowerPerBeat: return NSLocalizedString(@"Watts per beat (W/bpm)", @"trend");
        case RATrendSpeedPerBeat: return NSLocalizedString(@"Speed per heart rate (km/h per 100 bpm)", @"trend");
        case RATrendClimbingSpeed: return NSLocalizedString(@"Climbing speed (VAM, m/h)", @"trend");
    }
    return @"";
}

+ (NSString *)nameOfTerrain:(RATerrain)terrain
{
    switch (terrain) {
        case RATerrainAll: return NSLocalizedString(@"All terrain", @"terrain");
        case RATerrainDescent: return NSLocalizedString(@"Descents (< −1 %)", @"terrain");
        case RATerrainFlat: return NSLocalizedString(@"Flat (−1 to 1 %)", @"terrain");
        case RATerrainGentle: return NSLocalizedString(@"Climbs of 1 to 4 %", @"terrain");
        case RATerrainClimb: return NSLocalizedString(@"Climbs of 4 to 8 %", @"terrain");
        case RATerrainSteep: return NSLocalizedString(@"Climbs over 8 %", @"terrain");
    }
    return @"";
}

+ (NSString *)nameOfTotal:(RATotalMeasure)measure
{
    switch (measure) {
        case RATotalDistance: return NSLocalizedString(@"Distance (km)", @"total");
        case RATotalAscent: return NSLocalizedString(@"Ascent (m)", @"total");
        case RATotalTime: return NSLocalizedString(@"Moving time (h)", @"total");
        case RATotalRides: return NSLocalizedString(@"Rides", @"total");
    }
    return @"";
}

@end
