//
//  RAPower.m
//  RideAnalyzer
//

#import "RAPower.h"
#import "RAEquipment.h"
#import "RARide.h"
#import "RARideAnalysis.h"
#import "RARideStats.h"

const double RAGravity = 9.81;
const double RADrivetrainEfficiency = 0.97;

@implementation RAWind

+ (instancetype)windWithSpeed:(double)speed fromDirection:(double)direction
{
    RAWind *w = [[RAWind alloc] init];
    w.speed = speed;
    w.fromDirection = direction;
    return w;
}

- (double)headwindForHeading:(double)heading
{
    // a wind from the direction the rider goes to is a headwind
    return self.speed * cos((self.fromDirection - heading) * M_PI / 180);
}

@end

@implementation RAPowerModel

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mass = 75 + 12;
        _crr = 0.005;
        _cdA = [RABike defaultCdAForPosition:RAPositionFlatBar];
        _efficiency = RADrivetrainEfficiency;
    }
    return self;
}

+ (instancetype)modelForRide:(nullable RARide *)ride equipment:(nullable RAEquipment *)equipment
{
    RAPowerModel *m = [[RAPowerModel alloc] init];
    RAEquipment *e = equipment ?: [[RAEquipment alloc] init];
    RABike *bike = ride ? [e bikeOfRide:(RARide *)ride] : [e bikeWithID:e.defaultBikeID];
    m.mass = e.effectiveRiderWeight + (bike ? bike.effectiveWeight : 12);
    if (bike) {
        m.cdA = bike.effectiveCdA;
        m.crr = [e crrOfBike:bike.identifier atDate:ride.startDate ?: [NSDate date]];
    }
    return m;
}

+ (double)airDensityAtAltitude:(double)altitude temperature:(double)temperature
{
    double t = isnan(temperature) ? 15 : temperature;
    double h = isnan(altitude) ? 0 : MAX(-400, MIN(altitude, 9000));
    // barometric formula (scale height ~8.4 km) and ideal gas, from 1.225 kg/m³ at sea level and 15 °C
    return 1.225 * exp(-h / 8434) * 288.15 / (t + 273.15);
}

+ (double)headingFromLatitude:(double)lat1 longitude:(double)lon1 toLatitude:(double)lat2 longitude:(double)lon2
{
    double p1 = lat1 * M_PI / 180, p2 = lat2 * M_PI / 180, dl = (lon2 - lon1) * M_PI / 180;
    double y = sin(dl) * cos(p2);
    double x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl);
    double h = atan2(y, x) * 180 / M_PI;
    return fmod(h + 360, 360);
}

- (double)powerAtSpeed:(double)speed slope:(double)slope acceleration:(double)acceleration
              headwind:(double)headwind airDensity:(double)density
{
    if (!(speed > 0)) return 0;
    double theta = atan(slope / 100);
    double air = speed + headwind;
    double force = self.mass * RAGravity * (sin(theta) + self.crr * cos(theta)) + self.mass * acceleration
                 + 0.5 * density * self.cdA * air * fabs(air);
    double p = force * speed / self.efficiency;
    return p > 0 ? p : 0;
}

- (NSArray<NSNumber *> *)powersOfAnalysis:(RARideAnalysis *)a wind:(nullable RAWindProvider)wind
{
    NSUInteger n = a.count;
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:n];
    double temperature = a.hasTemperature ? a.averageTemperature : NAN;
    for (NSUInteger i = 0; i < n; i++) {
        double v = a.speeds[i].doubleValue / 3.6;
        BOOL moving = a.hasTimes && RAHasValue(v) && v > 3.0 / 3.6;
        if (!moving) { [out addObject:@(RANoValue)]; continue; }
        // acceleration over the neighbouring points (about ±2 records), heading over the next and previous ones
        NSUInteger lo = i >= 2 ? i - 2 : 0, hi = MIN(i + 2, n - 1);
        double dt = a.elapsed[hi].doubleValue - a.elapsed[lo].doubleValue;
        double v0 = a.speeds[lo].doubleValue / 3.6, v1 = a.speeds[hi].doubleValue / 3.6;
        double acc = dt > 0 && RAHasValue(v0) && RAHasValue(v1) ? (v1 - v0) / dt : 0;
        double headwind = 0;
        RAWind *w = wind ? wind(i) : nil;
        if (w && hi > lo) {
            CLLocationCoordinate2D p = a.trace[lo].coordinate, q = a.trace[hi].coordinate;
            headwind = [w headwindForHeading:[RAPowerModel headingFromLatitude:p.latitude longitude:p.longitude
                                                                    toLatitude:q.latitude longitude:q.longitude]];
        }
        double rho = [RAPowerModel airDensityAtAltitude:a.altitudes[i].doubleValue
                                            temperature:a.hasTemperature ? a.temperatures[i].doubleValue : temperature];
        double slope = a.slopes[i].doubleValue;
        [out addObject:@([self powerAtSpeed:v slope:RAHasValue(slope) ? slope : 0 acceleration:acc
                                   headwind:headwind airDensity:rho])];
    }
    return out;
}

- (double)averagePowerOfStats:(RATerrainStats *)t
{
    if (t.time <= 0) return NAN;
    double energy = self.mass * (t.gravityWork + t.inertiaWork) + self.mass * self.crr * t.rollingWork
                  + self.cdA * t.airWork;
    double p = energy / self.efficiency / t.time;
    return p > 0 ? p : 0;
}

@end
