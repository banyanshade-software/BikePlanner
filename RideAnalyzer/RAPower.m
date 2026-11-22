//
//  RAPower.m
//  RideAnalyzer
//

#import "RAPower.h"
#import "RASurfaceFactors.h"
#import "RAPowerSettings.h"
#import "RAEquipment.h"
#import "RARide.h"
#import "RARideAnalysis.h"
#import "RARideStats.h"

const double RAGravity = 9.81;
const double RADrivetrainEfficiency = 0.97;
const double RAWheelInertia = 1.5;
NSString *const RAPowerGravity = @"gravity";
NSString *const RAPowerRolling = @"rolling";
NSString *const RAPowerAir = @"air";
NSString *const RAPowerInertia = @"inertia";
NSString *const RAPowerLosses = @"losses";
NSString *const RAPowerTotal = @"total";

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
        _tyreCrr = 0.005;
        _surfaceFactors = [RASurfaceFactors factorsWithOverrides:nil];
        _cdA = [RABike defaultCdAForPosition:RAPositionFlatBar];
        _efficiency = RADrivetrainEfficiency;
        _wheelInertia = RAWheelInertia;
        _speedSmoothing = 5;
        _accelerationWindow = 6;
        _freewheelingIsZero = YES;
    }
    return self;
}

+ (instancetype)modelForRide:(nullable RARide *)ride equipment:(nullable RAEquipment *)equipment
{
    RAPowerModel *m = [[RAPowerModel alloc] init];
    RAEquipment *e = equipment ?: [[RAEquipment alloc] init];
    RAPowerSettings *settings = e.powerSettings;      // #94: the library's parameters
    m.surfaceFactors = e.effectiveSurfaceFactors;
    m.efficiency = settings.efficiency;
    m.wheelInertia = settings.wheelInertia;
    m.speedSmoothing = settings.speedSmoothing;
    m.accelerationWindow = settings.accelerationWindow;
    m.freewheelingIsZero = settings.freewheelingIsZero;
    m.cdA = [settings cdAForPosition:RAPositionFlatBar];
    m.tyreCrr = 0.005;
    RABike *bike = ride ? [e bikeOfRide:(RARide *)ride] : [e bikeWithID:e.defaultBikeID];
    m.mass = [e riderWeightAtDate:ride.startDate] + (bike ? [e weightOfBike:(RABike *)bike] : 12);   // weighing of the day (R11)
    RASurface usual = RASurfaceAsphalt;
    if (bike) {
        m.cdA = [e cdAOfBike:(RABike *)bike];
        m.tyreCrr = [e crrOfBike:bike.identifier atDate:ride.startDate ?: [NSDate date]];
        usual = bike.surface;
    }
    m.tyreCrr *= settings.rollingScale;                // the calibration
    m.crr = m.tyreCrr * [e factorOfBikeSurface:usual];
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
    return [self powerAtSpeed:speed slope:slope acceleration:acceleration headwind:headwind airDensity:density crr:self.crr];
}

- (double)powerAtSpeed:(double)speed slope:(double)slope acceleration:(double)acceleration
              headwind:(double)headwind airDensity:(double)density crr:(double)crr
{
    if (!(speed > 0)) return 0;
    double theta = atan(slope / 100);
    double air = speed + headwind;
    double force = self.mass * RAGravity * (sin(theta) + crr * cos(theta)) + (self.mass + self.wheelInertia) * acceleration
                 + 0.5 * density * self.cdA * air * fabs(air);
    double p = force * speed / self.efficiency;
    return p > 0 ? p : 0;
}

- (NSArray<NSNumber *> *)powersOfAnalysis:(RARideAnalysis *)a wind:(nullable RAWindProvider)wind
{
    NSUInteger n = a.count;
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:n];
    double temperature = a.hasTemperature ? a.averageTemperature : NAN;
    // speed smoothed over 5 s (the sensor's when the file has it: RARideAnalysis.speeds), acceleration over 6 s
    double *v = calloc(MAX(n, (NSUInteger)1), sizeof(double));
    NSUInteger lo = 0, hi = 0;
    for (NSUInteger i = 0; i < n; i++) {
        double t = a.elapsed[i].doubleValue;
        double half = self.speedSmoothing / 2;
        while (lo < i && t - a.elapsed[lo].doubleValue > half) lo++;
        if (hi < i) hi = i;
        while (hi + 1 < n && a.elapsed[hi + 1].doubleValue - t <= half) hi++;
        double sum = 0;
        NSUInteger count = 0;
        for (NSUInteger k = lo; k <= hi; k++) {
            double s = a.speeds[k].doubleValue;
            if (RAHasValue(s)) { sum += s; count++; }
        }
        v[i] = count ? sum / count / 3.6 : NAN;
    }
    for (NSUInteger i = 0; i < n; i++) {
        BOOL moving = a.hasTimes && isfinite(v[i]) && v[i] > 3.0 / 3.6;
        double cadence = a.hasCadence ? a.cadences[i].doubleValue : RANoValue;
        if (!moving) { [out addObject:@(RANoValue)]; continue; }
        if (self.freewheelingIsZero && a.hasCadence && RAHasValue(cadence) && cadence <= 0) {     // freewheeling
            [out addObject:@0];
            continue;
        }
        NSUInteger p0 = i, p1 = i;
        double t = a.elapsed[i].doubleValue, halfWindow = self.accelerationWindow / 2;
        while (p0 > 0 && t - a.elapsed[p0 - 1].doubleValue <= halfWindow) p0--;
        while (p1 + 1 < n && a.elapsed[p1 + 1].doubleValue - t <= halfWindow) p1++;
        double dt = a.elapsed[p1].doubleValue - a.elapsed[p0].doubleValue;
        double acc = dt > 0 && isfinite(v[p0]) && isfinite(v[p1]) ? (v[p1] - v[p0]) / dt : 0;
        double headwind = 0;
        RAWind *w = wind ? wind(i) : nil;
        NSUInteger h0 = i >= 2 ? i - 2 : 0, h1 = MIN(i + 2, n - 1);
        if (w && h1 > h0) {
            CLLocationCoordinate2D p = a.trace[h0].coordinate, q = a.trace[h1].coordinate;
            headwind = [w headwindForHeading:[RAPowerModel headingFromLatitude:p.latitude longitude:p.longitude
                                                                    toLatitude:q.latitude longitude:q.longitude]];
        }
        double rho = [RAPowerModel airDensityAtAltitude:a.altitudes[i].doubleValue
                                            temperature:a.hasTemperature ? a.temperatures[i].doubleValue : temperature];
        double slope = a.slopes[i].doubleValue;
        // R8: the surface of the road of the point when known
        NSString *category = a.surfaceCategories && i < a.surfaceCategories.count ? a.surfaceCategories[i] : @"";
        [out addObject:@([self powerAtSpeed:v[i] slope:RAHasValue(slope) ? slope : 0 acceleration:acc
                                   headwind:headwind airDensity:rho crr:[self crrOnSurface:category]])];
    }
    free(v);
    return out;
}

- (double)crrOnSurface:(NSString *)category
{
    if (category.length == 0) return self.crr;
    NSNumber *f = self.surfaceFactors[category];
    return self.tyreCrr * (f != nil ? f.doubleValue : [RASurfaceFactors defaultFactorOfCategory:category]);
}

- (double)averagePowerOfStats:(RATerrainStats *)t
{
    if (t.time <= 0) return NAN;
    double rolling = self.crr * t.rollingWork;
    for (NSString *category in t.surfaceWorks) rolling += [self crrOnSurface:category] * t.surfaceWorks[category].doubleValue;
    double energy = self.mass * t.gravityWork + (self.mass + self.wheelInertia) * t.inertiaWork
                  + self.mass * rolling + self.cdA * t.airWork;
    double p = energy / self.efficiency / t.time;
    return p > 0 ? p : 0;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    RAPowerModel *m = [[RAPowerModel alloc] init];
    m.mass = self.mass;
    m.crr = self.crr;
    m.tyreCrr = self.tyreCrr;
    m.surfaceFactors = self.surfaceFactors;
    m.cdA = self.cdA;
    m.wheelInertia = self.wheelInertia;
    m.efficiency = self.efficiency;
    m.speedSmoothing = self.speedSmoothing;
    m.accelerationWindow = self.accelerationWindow;
    m.freewheelingIsZero = self.freewheelingIsZero;
    return m;
}

- (nullable NSDictionary<NSString *, NSNumber *> *)breakdownOfStats:(RATerrainStats *)t
{
    if (t.time <= 0) return nil;
    double rolling = self.crr * t.rollingWork;
    for (NSString *category in t.surfaceWorks) rolling += [self crrOnSurface:category] * t.surfaceWorks[category].doubleValue;
    double gravity = self.mass * t.gravityWork / t.time, inertia = (self.mass + self.wheelInertia) * t.inertiaWork / t.time;
    double roll = self.mass * rolling / t.time, air = self.cdA * t.airWork / t.time;
    double wheel = gravity + inertia + roll + air;
    return @{ RAPowerGravity: @(gravity), RAPowerRolling: @(roll), RAPowerAir: @(air), RAPowerInertia: @(inertia),
              RAPowerLosses: @(MAX(0, wheel) * (1 / self.efficiency - 1)), RAPowerTotal: @([self averagePowerOfStats:t]) };
}

- (NSArray<NSArray *> *)sensitivityOfStats:(RATerrainStats *)t
{
    double base = [self averagePowerOfStats:t];
    if (!isfinite(base)) return @[];
    NSMutableArray<NSArray *> *out = [NSMutableArray array];
    void (^add)(NSString *, NSString *, void (^)(RAPowerModel *)) = ^(NSString *name, NSString *change, void (^apply)(RAPowerModel *)) {
        RAPowerModel *m = [self copy];
        apply(m);
        [out addObject:@[ name, change, @([m averagePowerOfStats:t] - base) ]];
    };
    add(NSLocalizedString(@"Rider and bike", @"sensitivity"), @"+5 kg", ^(RAPowerModel *m) { m.mass += 5; });
    add(NSLocalizedString(@"Rolling resistance", @"sensitivity"), @"+10 %", ^(RAPowerModel *m) {
        m.crr *= 1.1;
        m.tyreCrr *= 1.1;
    });
    add(NSLocalizedString(@"Air drag (CdA)", @"sensitivity"), @"+10 %", ^(RAPowerModel *m) { m.cdA *= 1.1; });
    add(NSLocalizedString(@"Drivetrain efficiency", @"sensitivity"), NSLocalizedString(@"−2 points", @"sensitivity"),
        ^(RAPowerModel *m) { m.efficiency -= 0.02; });
    return out;
}

@end
