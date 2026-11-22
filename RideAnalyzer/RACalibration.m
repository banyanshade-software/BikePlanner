//
//  RACalibration.m
//  RideAnalyzer
//

#import "RACalibration.h"
#import "RAEquipment.h"
#import "RAPower.h"
#import "RARide.h"
#import "RARideStats.h"

@implementation RACalibrationResult
@end

@implementation RACalibration

+ (NSArray<RACalibrationResult *> *)calibrateRides:(NSArray<RARide *> *)rides equipment:(RAEquipment *)equipment
{
    // samples per bike: [y, rolling energy (current model), air work, measured energy, time, mass part]
    NSMutableDictionary<NSString *, NSMutableArray<NSArray<NSNumber *> *> *> *samples = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *ridesOfBike = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, RAPowerModel *> *models = [NSMutableDictionary dictionary];
    for (RARide *r in rides) {
        RARideStats *stats = r.stats;
        if (!stats || stats.total.powerTime < 120) continue;
        RABike *bike = [equipment bikeOfRide:r];
        NSString *key = bike.identifier ?: @"";
        RAPowerModel *m = [RAPowerModel modelForRide:r equipment:equipment];
        models[key] = m;
        for (RATerrain t = RATerrainFlat; t <= RATerrainSteep; t++) {
            RATerrainStats *s = [stats statsForTerrain:t];
            if (s.powerTime < 120 || s.time <= 0) continue;
            double measured = s.powerSum / s.powerTime * s.time;       // J over the moving time
            double rolling = m.crr * s.rollingWork;
            for (NSString *c in s.surfaceWorks) rolling += [m crrOnSurface:c] * s.surfaceWorks[c].doubleValue;
            rolling *= m.mass;
            double fixed = m.mass * s.gravityWork + (m.mass + m.wheelInertia) * s.inertiaWork;
            double y = m.efficiency * measured - fixed;
            if (!samples[key]) samples[key] = [NSMutableArray array];
            [samples[key] addObject:@[ @(y), @(rolling), @(s.airWork), @(measured), @(s.time), @(fixed),
                                       @(m.cdA), @(m.efficiency) ]];
            if (!ridesOfBike[key]) ridesOfBike[key] = [NSMutableSet set];
            [ridesOfBike[key] addObject:r.identifier];
        }
    }
    NSMutableArray<RACalibrationResult *> *results = [NSMutableArray array];
    for (NSString *key in samples) {
        NSArray<NSArray<NSNumber *> *> *list = samples[key];
        RACalibrationResult *res = [[RACalibrationResult alloc] init];
        res.bikeID = key;
        res.bikeName = [equipment bikeWithID:key].name ?: NSLocalizedString(@"No bike", @"calibration");
        res.rideCount = ridesOfBike[key].count;
        res.sampleCount = list.count;
        // least squares: y = k R + c A
        double rr = 0, ra = 0, aa = 0, ry = 0, ay = 0;
        for (NSArray<NSNumber *> *s in list) {
            double y = s[0].doubleValue, R = s[1].doubleValue, A = s[2].doubleValue;
            rr += R * R; ra += R * A; aa += A * A; ry += R * y; ay += A * y;
        }
        double det = rr * aa - ra * ra;
        double k = NAN, c = NAN;
        if (list.count >= 3 && det > 1e-9 * rr * aa) {
            k = (ry * aa - ay * ra) / det;
            c = (rr * ay - ra * ry) / det;
        }
        res.valid = isfinite(k) && isfinite(c) && k >= 0.3 && k <= 3 && c >= 0.15 && c <= 1.0;
        if (!res.valid) {
            res.note = list.count < 3
                ? NSLocalizedString(@"Not enough data: at least 3 stretches of 2 minutes with a power meter.", @"calibration")
                : NSLocalizedString(@"The rides do not separate rolling resistance from air drag (speeds too alike), or "
                                    @"the fit is out of the plausible range: nothing to apply.", @"calibration");
            k = 1;
            c = list.firstObject[6].doubleValue;
        }
        res.rollingFactor = k;
        res.cdA = c;
        // the estimate before and after, against the measure (power at the pedals over each sample)
        double before = 0, after = 0, meas = 0, eb = 0, ea = 0, time = 0;
        for (NSArray<NSNumber *> *s in list) {
            double R = s[1].doubleValue, A = s[2].doubleValue, fixed = s[5].doubleValue, t = s[4].doubleValue;
            double cdA0 = s[6].doubleValue, eta = s[7].doubleValue;
            double pb = MAX(0, fixed + R + cdA0 * A) / eta / t, pa = MAX(0, fixed + k * R + c * A) / eta / t;
            double pm = s[3].doubleValue / t;
            before += pb * t; after += pa * t; meas += pm * t; time += t;
            eb += (pb - pm) * (pb - pm); ea += (pa - pm) * (pa - pm);
        }
        res.estimatedBefore = time > 0 ? before / time : NAN;
        res.estimatedAfter = time > 0 ? after / time : NAN;
        res.measured = time > 0 ? meas / time : NAN;
        res.errorBefore = sqrt(eb / list.count);
        res.errorAfter = sqrt(ea / list.count);
        [results addObject:res];
    }
    [results sortUsingComparator:^NSComparisonResult(RACalibrationResult *a, RACalibrationResult *b) {
        return a.sampleCount > b.sampleCount ? NSOrderedAscending : a.sampleCount < b.sampleCount ? NSOrderedDescending : NSOrderedSame;
    }];
    return results;
}

@end
