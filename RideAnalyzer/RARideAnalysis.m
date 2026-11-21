//
//  RARideAnalysis.m
//  RideAnalyzer
//

#import "RARideAnalysis.h"
#import "RARide.h"
#import "BPTrackReader.h"

const double RANoValue = NAN;

static const double RAMovingSpeed = 3.0 / 3.6;   // m/s: below, a pause
static const double RASlopeSpan = 100;           // meters over which the slope is measured

static NSArray<NSNumber *> *RANumbers(const double *values, NSUInteger count)
{
    NSMutableArray<NSNumber *> *a = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [a addObject:@(values[i])];
    return a;
}

@implementation RARideAnalysis

+ (nullable instancetype)analysisOfData:(NSData *)data
{
    BPTrackReader *r = [BPTrackReader readerWithData:data error:NULL];
    if (!r || r.trace.count < 2) return nil;
    return [[self alloc] initWithTrace:r.trace metrics:r.metrics calories:r.calories hasTimes:r.hasTimes];
}

- (instancetype)initWithTrace:(NSArray<CLLocation *> *)trace
                      metrics:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)metrics
                     calories:(nullable NSNumber *)calories
                     hasTimes:(BOOL)hasTimes
{
    self = [super init];
    if (!self) return nil;
    NSUInteger n = trace.count;
    _trace = [trace copy];
    _count = n;
    _hasTimes = hasTimes;
    _calories = calories;

    NSMutableData *buffer = [NSMutableData dataWithLength:sizeof(double) * MAX(n, (NSUInteger)1) * 9];
    double *dist = buffer.mutableBytes, *tm = dist + n, *alt = tm + n, *spd = alt + n, *slp = spd + n,
           *hrt = slp + n, *cdc = hrt + n, *pwr = cdc + n, *tmp = pwr + n;
    NSDate *t0 = trace.firstObject.timestamp;
    BOOL recordedSpeed = NO;
    for (NSUInteger i = 0; i < n; i++) {
        CLLocation *l = trace[i];
        dist[i] = i ? dist[i - 1] + [l distanceFromLocation:trace[i - 1]] : 0;
        tm[i] = hasTimes ? [l.timestamp timeIntervalSinceDate:t0] : 0;
        alt[i] = l.altitude;
        NSDictionary<NSString *, NSNumber *> *m = i < metrics.count ? metrics[i] : @{};
        spd[i] = m[@"speed"] != nil ? m[@"speed"].doubleValue * 3.6 : RANoValue;
        if (m[@"speed"] != nil) recordedSpeed = YES;
        hrt[i] = m[@"hr"] != nil ? m[@"hr"].doubleValue : RANoValue;
        cdc[i] = m[@"cadence"] != nil ? m[@"cadence"].doubleValue : RANoValue;
        pwr[i] = m[@"power"] != nil ? m[@"power"].doubleValue : RANoValue;
        tmp[i] = m[@"temperature"] != nil ? m[@"temperature"].doubleValue : RANoValue;
        if (RAHasValue(hrt[i])) _hasHeartRate = YES;
        if (RAHasValue(cdc[i])) _hasCadence = YES;
        if (RAHasValue(pwr[i])) _hasPower = YES;
        if (RAHasValue(tmp[i])) _hasTemperature = YES;
    }

    // speed: recorded, else over the neighbouring points
    for (NSUInteger i = 0; i < n; i++) {
        if (recordedSpeed && RAHasValue(spd[i])) continue;
        NSUInteger a = i > 0 ? i - 1 : 0, b = i + 1 < n ? i + 1 : n - 1;
        double dt = tm[b] - tm[a];
        spd[i] = hasTimes && dt > 0 ? (dist[b] - dist[a]) / dt * 3.6 : RANoValue;
    }

    // slope over about RASlopeSpan meters centered on the point
    NSUInteger lo = 0, hi = 0;
    for (NSUInteger i = 0; i < n; i++) {
        while (lo < i && dist[i] - dist[lo + 1] >= RASlopeSpan / 2) lo++;
        if (hi < i) hi = i;
        while (hi + 1 < n && dist[hi] - dist[i] < RASlopeSpan / 2) hi++;
        double span = dist[hi] - dist[lo];
        slp[i] = span > 1 ? (alt[hi] - alt[lo]) / span * 100 : 0;
    }

    // summary
    _distance = n ? dist[n - 1] : 0;
    _ascent = [RARide ascentOfTrace:trace threshold:3];
    _elapsedTime = n ? tm[n - 1] : 0;
    double moving = 0, maxSpeed = 0;
    double hrSum = 0, hrMax = 0, powSum = 0, powMax = 0, cadSum = 0, tempSum = 0;
    NSUInteger hrCount = 0, powCount = 0, cadCount = 0, tempCount = 0;
    for (NSUInteger i = 0; i < n; i++) {
        BOOL isMoving = NO;
        if (i > 0 && hasTimes) {
            double dt = tm[i] - tm[i - 1];
            if (dt > 0 && (dist[i] - dist[i - 1]) / dt > RAMovingSpeed) {
                moving += dt;
                isMoving = YES;
            }
        }
        if (RAHasValue(spd[i])) maxSpeed = MAX(maxSpeed, spd[i]);
        if (RAHasValue(hrt[i])) { hrSum += hrt[i]; hrMax = MAX(hrMax, hrt[i]); hrCount++; }
        if (RAHasValue(pwr[i])) {
            powMax = MAX(powMax, pwr[i]);
            if (isMoving || !hasTimes) { powSum += pwr[i]; powCount++; }
        }
        if (RAHasValue(cdc[i]) && cdc[i] > 0) { cadSum += cdc[i]; cadCount++; }
        if (RAHasValue(tmp[i])) { tempSum += tmp[i]; tempCount++; }
    }
    _movingTime = moving;
    _pauseTime = MAX(0, _elapsedTime - moving);
    _averageSpeed = moving > 0 ? _distance / moving * 3.6 : 0;
    _maxSpeed = maxSpeed;
    _averageHeartRate = hrCount ? hrSum / hrCount : RANoValue;
    _maxHeartRate = hrCount ? hrMax : RANoValue;
    _averagePower = powCount ? powSum / powCount : RANoValue;
    _maxPower = _hasPower ? powMax : RANoValue;
    _averageCadence = cadCount ? cadSum / cadCount : RANoValue;
    _averageTemperature = tempCount ? tempSum / tempCount : RANoValue;

    _distances = RANumbers(dist, n);
    _elapsed = RANumbers(tm, n);
    _altitudes = RANumbers(alt, n);
    _speeds = RANumbers(spd, n);
    _slopes = RANumbers(slp, n);
    _heartRates = RANumbers(hrt, n);
    _cadences = RANumbers(cdc, n);
    _powers = RANumbers(pwr, n);
    _temperatures = RANumbers(tmp, n);
    return self;
}

- (void)useEstimatedPowers:(NSArray<NSNumber *> *)powers
{
    if ((_hasPower && !_powerIsEstimated) || powers.count != _count) return;
    double sum = 0, max = 0;
    NSUInteger count = 0;
    BOOL any = NO;
    for (NSUInteger i = 0; i < _count; i++) {
        double p = powers[i].doubleValue;
        if (!RAHasValue(p)) continue;
        any = YES;
        max = MAX(max, p);
        sum += p;                // the estimate exists only where the ride moves: the average is over the moving time
        count++;
    }
    _powers = [powers copy];
    _hasPower = any;
    _powerIsEstimated = any;
    _averagePower = count ? sum / count : RANoValue;
    _maxPower = any ? max : RANoValue;
}

- (NSUInteger)indexAtDistance:(double)distance
{
    if (_count == 0) return 0;
    NSUInteger lo = 0, hi = _count - 1;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (_distances[mid].doubleValue < distance) lo = mid + 1;
        else hi = mid;
    }
    if (lo > 0 && fabs(_distances[lo - 1].doubleValue - distance) < fabs(_distances[lo].doubleValue - distance)) lo--;
    return lo;
}

@end

@implementation RATrackColoring

// class boundaries, lowest first: speed km/h, slope %, fractions of the max heart rate, of the average power
static NSArray<NSNumber *> *RABounds(RAColorMode mode)
{
    switch (mode) {
        case RAColorBySpeed: return @[ @18, @24, @30 ];
        case RAColorBySlope: return @[ @-4, @-1, @1, @4, @8 ];
        case RAColorByHeartRate: return @[ @0.6, @0.7, @0.8, @0.9 ];
        case RAColorByPower: return @[ @0.5, @0.8, @1.1, @1.5 ];
    }
    return @[];
}

+ (BOOL)analysis:(RARideAnalysis *)analysis supportsMode:(RAColorMode)mode
{
    switch (mode) {
        case RAColorBySpeed: return analysis.hasTimes || [analysis.speeds indexOfObjectPassingTest:
            ^BOOL(NSNumber *v, NSUInteger i, BOOL *stop) { return RAHasValue(v.doubleValue); }] != NSNotFound;
        case RAColorBySlope: return YES;
        case RAColorByHeartRate: return analysis.hasHeartRate;
        case RAColorByPower: return analysis.hasPower;
    }
    return NO;
}

+ (NSArray<NSNumber *> *)classesOfAnalysis:(RARideAnalysis *)analysis mode:(RAColorMode)mode
{
    NSArray<NSNumber *> *values;
    double scale = 1;
    switch (mode) {
        case RAColorBySpeed: values = analysis.speeds; break;
        case RAColorBySlope: values = analysis.slopes; break;
        case RAColorByHeartRate:
            values = analysis.heartRates;
            scale = RAHasValue(analysis.maxHeartRate) && analysis.maxHeartRate > 0 ? 1 / analysis.maxHeartRate : 0;
            break;
        case RAColorByPower:
            values = analysis.powers;
            scale = RAHasValue(analysis.averagePower) && analysis.averagePower > 0 ? 1 / analysis.averagePower : 0;
            break;
    }
    NSArray<NSNumber *> *bounds = RABounds(mode);
    NSMutableArray<NSNumber *> *classes = [NSMutableArray arrayWithCapacity:analysis.count];
    for (NSUInteger i = 0; i < analysis.count; i++) {
        double v = i < values.count ? values[i].doubleValue : RANoValue;
        if (!RAHasValue(v) || scale == 0) {
            [classes addObject:@(-1)];
            continue;
        }
        v *= scale;
        NSInteger c = 0;
        while ((NSUInteger)c < bounds.count && v >= bounds[(NSUInteger)c].doubleValue) c++;
        [classes addObject:@(c)];
    }
    return classes;
}

+ (NSArray<NSString *> *)legendForMode:(RAColorMode)mode analysis:(RARideAnalysis *)analysis
{
    NSArray<NSNumber *> *bounds = RABounds(mode);
    double scale = 1;
    NSString *unit = @"";
    switch (mode) {
        case RAColorBySpeed: unit = @" km/h"; break;
        case RAColorBySlope: unit = @" %"; break;
        case RAColorByHeartRate: scale = RAHasValue(analysis.maxHeartRate) ? analysis.maxHeartRate : 0; unit = @" bpm"; break;
        case RAColorByPower: scale = RAHasValue(analysis.averagePower) ? analysis.averagePower : 0; unit = @" W"; break;
    }
    NSMutableArray<NSString *> *legend = [NSMutableArray array];
    for (NSUInteger c = 0; c <= bounds.count; c++) {
        double low = c > 0 ? bounds[c - 1].doubleValue * scale : 0;
        double high = c < bounds.count ? bounds[c].doubleValue * scale : 0;
        NSString *s;
        if (c == 0) s = [NSString localizedStringWithFormat:@"< %.0f%@", high, unit];
        else if (c == bounds.count) s = [NSString localizedStringWithFormat:@"> %.0f%@", low, unit];
        else s = [NSString localizedStringWithFormat:@"%.0f–%.0f%@", low, high, unit];
        [legend addObject:s];
    }
    return legend;
}

@end
