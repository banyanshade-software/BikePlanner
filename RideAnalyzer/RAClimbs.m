//
//  RAClimbs.m
//  RideAnalyzer
//

#import "RAClimbs.h"
#import "RAComputation.h"
#import "RARideAnalysis.h"
#import "RARideStats.h"
#import "RARide.h"

static const double RAClimbMinGain = 30;        // m
static const double RAClimbMinLength = 300;     // m
static const double RAClimbMinGradient = 3;     // %
static const double RAClimbDropTolerance = 10;  // m (or a quarter of the gain)
static const double RASameClimbRadius = 150;    // m

#pragma mark - climb

@implementation RAClimb

- (instancetype)init
{
    self = [super init];
    if (self) _stats = [[RATerrainStats alloc] init];
    return self;
}

- (double)averageGradient
{
    return self.length > 0 ? self.gain / self.length * 100 : 0;
}

- (double)time
{
    return self.stats.time > 0 ? self.stats.time : NAN;
}

- (double)climbingSpeed
{
    return self.stats.time > 0 ? self.gain / self.stats.time * 3600 : NAN;
}

- (NSDictionary *)propertyList
{
    return @{ @"start": @[ @(self.start.latitude), @(self.start.longitude) ],
              @"end": @[ @(self.end.latitude), @(self.end.longitude) ],
              @"startDistance": @(self.startDistance), @"length": @(self.length), @"gain": @(self.gain),
              @"maxGradient": @(self.maxGradient), @"stats": self.stats.propertyList };
}

static BOOL RACoordinate(id value, CLLocationCoordinate2D *c)
{
    if (![value isKindOfClass:[NSArray class]] || [value count] != 2) return NO;
    id lat = value[0], lon = value[1];
    if (![lat isKindOfClass:[NSNumber class]] || ![lon isKindOfClass:[NSNumber class]]) return NO;
    *c = CLLocationCoordinate2DMake([lat doubleValue], [lon doubleValue]);
    return CLLocationCoordinate2DIsValid(*c);
}

+ (nullable RAClimb *)climbWithPropertyList:(nullable id)plist
{
    if (![plist isKindOfClass:[NSDictionary class]]) return nil;
    CLLocationCoordinate2D start, end;
    if (!RACoordinate(plist[@"start"], &start) || !RACoordinate(plist[@"end"], &end)) return nil;
    RAClimb *c = [[RAClimb alloc] init];
    c.start = start;
    c.end = end;
    double (^num)(NSString *) = ^double(NSString *k) {
        id v = plist[k];
        return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : 0;
    };
    c.startDistance = num(@"startDistance");
    c.length = num(@"length");
    c.gain = num(@"gain");
    c.maxGradient = num(@"maxGradient");
    c.stats = [RATerrainStats statsWithPropertyList:plist[@"stats"]];
    return c;
}

static double RAMeters(CLLocationCoordinate2D a, CLLocationCoordinate2D b)
{
    CLLocation *la = [[CLLocation alloc] initWithLatitude:a.latitude longitude:a.longitude];
    CLLocation *lb = [[CLLocation alloc] initWithLatitude:b.latitude longitude:b.longitude];
    return [la distanceFromLocation:lb];
}

- (BOOL)isSameClimbAs:(RAClimb *)other
{
    if (RAMeters(self.start, other.start) > RASameClimbRadius) return NO;
    if (RAMeters(self.end, other.end) > RASameClimbRadius) return NO;
    double longest = MAX(self.length, other.length);
    return longest > 0 && fabs(self.length - other.length) / longest < 0.15;
}

@end

#pragma mark - detection

@implementation RAClimbDetector

+ (NSArray<RAClimb *> *)climbsOfAnalysis:(RARideAnalysis *)a wind:(nullable RAWindProvider)wind
{
    NSUInteger n = a.count;
    if (n < 3) return @[];
    // altitudes smoothed over 5 points (GPS and barometer noise)
    double *alt = malloc(n * sizeof(double));
    for (NSUInteger i = 0; i < n; i++) {
        double sum = 0;
        NSUInteger count = 0;
        for (NSUInteger j = (i >= 2 ? i - 2 : 0); j <= MIN(i + 2, n - 1); j++) {
            double v = a.altitudes[j].doubleValue;
            if (RAHasValue(v)) { sum += v; count++; }
        }
        alt[i] = count ? sum / count : 0;
    }
    NSMutableArray<RAClimb *> *climbs = [NSMutableArray array];
    NSUInteger low = 0, high = 0;
    for (NSUInteger i = 1; i <= n; i++) {
        BOOL last = i == n;
        if (!last) {
            if (alt[i] > alt[high]) high = i;
            double gain = alt[high] - alt[low];
            BOOL dropped = alt[high] - alt[i] > MAX(RAClimbDropTolerance, gain / 4);
            if (!dropped) {
                if (alt[i] < alt[low]) low = high = i;    // still going down before any climb: a lower start
                continue;
            }
        }
        // the climb low → high ends here (the road went down too much, or the ride ended)
        [self addClimbFrom:low to:high altitudes:alt analysis:a wind:wind to:climbs];
        if (last) break;
        low = high = i;
    }
    free(alt);
    return climbs;
}

+ (void)addClimbFrom:(NSUInteger)low to:(NSUInteger)high altitudes:(const double *)alt analysis:(RARideAnalysis *)a
                wind:(nullable RAWindProvider)wind to:(NSMutableArray<RAClimb *> *)climbs
{
    if (high <= low) return;
    // the climb starts where the road leaves the bottom: after a flat or a bump that comes back down near it
    double bottom = alt[low];
    for (NSUInteger j = low + 1; j < high; j++) {
        if (alt[j] <= bottom + 1.5) low = j;
    }
    double length = a.distances[high].doubleValue - a.distances[low].doubleValue;
    double gain = alt[high] - alt[low];
    if (gain < RAClimbMinGain || length < RAClimbMinLength || gain / length * 100 < RAClimbMinGradient) return;
    RAClimb *c = [[RAClimb alloc] init];
    c.start = a.trace[low].coordinate;
    c.end = a.trace[high].coordinate;
    c.startDistance = a.distances[low].doubleValue;
    c.length = length;
    c.gain = gain;
    double maxGradient = 0;
    for (NSUInteger i = low; i <= high; i++) {
        double s = a.slopes[i].doubleValue;
        if (RAHasValue(s)) maxGradient = MAX(maxGradient, s);
        if (i > low) {
            RATerrainStats *interval = [RARideStats statsOfIntervalAtIndex:i ofAnalysis:a wind:wind];
            if (interval) [c.stats add:interval];
        }
    }
    c.maxGradient = maxGradient;
    [climbs addObject:c];
}

@end

#pragma mark - same climbs over several rides

@implementation RAClimbPassage
@end

@implementation RAClimbGroup
{
    NSMutableArray<RAClimbPassage *> *_passages;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _passages = [NSMutableArray array];
        _name = @"";
    }
    return self;
}

- (NSArray<RAClimbPassage *> *)passages
{
    return [_passages copy];
}

- (RAClimb *)reference
{
    return _passages.firstObject.climb;
}

- (nullable RAClimbPassage *)best
{
    RAClimbPassage *best = nil;
    for (RAClimbPassage *p in _passages) {
        if (isnan(p.climb.time)) continue;
        if (!best || p.climb.time < best.climb.time) best = p;
    }
    return best;
}

- (NSUInteger)rankOfPassage:(RAClimbPassage *)passage
{
    if (isnan(passage.climb.time)) return 0;
    NSUInteger rank = 1;
    for (RAClimbPassage *p in _passages) {
        if (p != passage && !isnan(p.climb.time) && p.climb.time < passage.climb.time) rank++;
    }
    return rank;
}

+ (NSArray<RAClimbGroup *> *)groupsOfRides:(NSArray<RARide *> *)rides
{
    return [self groupsOfRides:rides cancellation:nil] ?: @[];
}

+ (nullable NSArray<RAClimbGroup *> *)groupsOfRides:(NSArray<RARide *> *)rides cancellation:(nullable RACancellation *)cancellation
{
    NSArray<RARide *> *sorted = [rides sortedArrayUsingComparator:^NSComparisonResult(RARide *x, RARide *y) {
        if (!x.startDate || !y.startDate) return x.startDate ? NSOrderedAscending : y.startDate ? NSOrderedDescending : NSOrderedSame;
        return [x.startDate compare:(NSDate *)y.startDate];
    }];
    NSMutableArray<RAClimbGroup *> *groups = [NSMutableArray array];
    for (RARide *r in sorted) {
        if (cancellation.cancelled) return nil;
        for (RAClimb *c in r.stats.climbs ?: @[]) {
            RAClimbGroup *group = nil;
            for (RAClimbGroup *g in groups) {
                if ([g.reference isSameClimbAs:c]) { group = g; break; }
            }
            if (!group) {
                group = [[RAClimbGroup alloc] init];
                [groups addObject:group];
            }
            RAClimbPassage *p = [[RAClimbPassage alloc] init];
            p.ride = r;
            p.climb = c;
            p.date = r.startDate;
            [group->_passages addObject:p];
        }
    }
    // the most ridden first, then the longest climbs
    [groups sortUsingComparator:^NSComparisonResult(RAClimbGroup *x, RAClimbGroup *y) {
        if (x.passages.count != y.passages.count) return x.passages.count > y.passages.count ? NSOrderedAscending : NSOrderedDescending;
        return x.reference.gain > y.reference.gain ? NSOrderedAscending : x.reference.gain < y.reference.gain ? NSOrderedDescending : NSOrderedSame;
    }];
    return groups;
}

@end
