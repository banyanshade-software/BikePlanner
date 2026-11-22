//
//  RAPowerSettings.m
//  RideAnalyzer
//

#import "RAPowerSettings.h"

NSString *const RAPowerEfficiency = @"efficiency";
NSString *const RAPowerWheelInertia = @"wheelInertia";
NSString *const RAPowerRollingScale = @"rollingScale";
NSString *const RAPowerPressureExponent = @"pressureExponent";
NSString *const RAPowerPressureMinFactor = @"pressureMinFactor";
NSString *const RAPowerPressureMaxFactor = @"pressureMaxFactor";
NSString *const RAPowerSpeedSmoothing = @"speedSmoothing";
NSString *const RAPowerAccelerationWindow = @"accelerationWindow";
NSString *const RAPowerFreewheelingIsZero = @"freewheelingIsZero";
NSString *const RAPowerRiderWeight = @"riderWeight";
NSString *const RAPowerCdAUpright = @"cdAUpright";
NSString *const RAPowerCdAFlatBar = @"cdAFlatBar";
NSString *const RAPowerCdAHoods = @"cdAHoods";
NSString *const RAPowerCdADrops = @"cdADrops";
NSString *const RAPowerWeightRoad = @"weightRoad";
NSString *const RAPowerWeightHybrid = @"weightHybrid";
NSString *const RAPowerWeightGravel = @"weightGravel";
NSString *const RAPowerWeightMountain = @"weightMountain";
NSString *const RAPowerWeightElectric = @"weightElectric";

@implementation RAPowerSettings
{
    NSDictionary<NSString *, NSNumber *> *_values;
}

/// key → [default, minimum, maximum]
+ (NSDictionary<NSString *, NSArray<NSNumber *> *> *)specs
{
    return @{ RAPowerEfficiency: @[ @0.97, @0.85, @1.0 ], RAPowerWheelInertia: @[ @1.5, @0, @5 ],
              RAPowerRollingScale: @[ @1.0, @0.3, @3 ],
              RAPowerPressureExponent: @[ @0.4, @0, @1.5 ], RAPowerPressureMinFactor: @[ @0.7, @0.3, @1 ],
              RAPowerPressureMaxFactor: @[ @1.5, @1, @3 ],
              RAPowerSpeedSmoothing: @[ @5, @0, @30 ], RAPowerAccelerationWindow: @[ @6, @1, @30 ],
              RAPowerFreewheelingIsZero: @[ @1, @0, @1 ], RAPowerRiderWeight: @[ @75, @30, @200 ],
              RAPowerCdAUpright: @[ @0.55, @0.15, @1.2 ], RAPowerCdAFlatBar: @[ @0.45, @0.15, @1.2 ],
              RAPowerCdAHoods: @[ @0.36, @0.15, @1.2 ], RAPowerCdADrops: @[ @0.30, @0.15, @1.2 ],
              RAPowerWeightRoad: @[ @9, @4, @40 ], RAPowerWeightHybrid: @[ @11, @4, @40 ],
              RAPowerWeightGravel: @[ @10, @4, @40 ], RAPowerWeightMountain: @[ @13, @4, @40 ],
              RAPowerWeightElectric: @[ @23, @4, @40 ] };
}

+ (NSArray<NSString *> *)allParameters
{
    NSMutableArray *all = [NSMutableArray array];
    for (NSString *g in [self groups]) [all addObjectsFromArray:[self parametersOfGroup:g]];
    return all;
}

+ (instancetype)settingsWithOverrides:(nullable NSDictionary<NSString *, NSNumber *> *)overrides
{
    RAPowerSettings *s = [[RAPowerSettings alloc] init];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSDictionary *specs = [self specs];
    for (NSString *k in specs) {
        NSArray<NSNumber *> *spec = specs[k];
        id v = overrides[k];
        double x = [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : spec[0].doubleValue;
        if (!isfinite(x)) x = spec[0].doubleValue;
        values[k] = @(MIN(MAX(x, spec[1].doubleValue), spec[2].doubleValue));
    }
    s->_values = values;
    return s;
}

+ (instancetype)defaultSettings
{
    return [self settingsWithOverrides:nil];
}

- (double)valueForParameter:(NSString *)key
{
    return _values[key].doubleValue;
}

- (double)efficiency { return [self valueForParameter:RAPowerEfficiency]; }
- (double)wheelInertia { return [self valueForParameter:RAPowerWheelInertia]; }
- (double)rollingScale { return [self valueForParameter:RAPowerRollingScale]; }
- (double)pressureExponent { return [self valueForParameter:RAPowerPressureExponent]; }
- (double)pressureMinFactor { return [self valueForParameter:RAPowerPressureMinFactor]; }
- (double)pressureMaxFactor { return MAX([self valueForParameter:RAPowerPressureMaxFactor], self.pressureMinFactor); }
- (double)speedSmoothing { return [self valueForParameter:RAPowerSpeedSmoothing]; }
- (double)accelerationWindow { return [self valueForParameter:RAPowerAccelerationWindow]; }
- (BOOL)freewheelingIsZero { return [self valueForParameter:RAPowerFreewheelingIsZero] >= 0.5; }
- (double)riderWeight { return [self valueForParameter:RAPowerRiderWeight]; }

- (double)cdAForPosition:(NSInteger)position
{
    NSArray *keys = @[ RAPowerCdAUpright, RAPowerCdAFlatBar, RAPowerCdAHoods, RAPowerCdADrops ];
    return position >= 0 && position < (NSInteger)keys.count ? [self valueForParameter:keys[(NSUInteger)position]] : 0.45;
}

- (double)weightForKind:(NSInteger)kind
{
    NSArray *keys = @[ RAPowerWeightRoad, RAPowerWeightHybrid, RAPowerWeightGravel, RAPowerWeightMountain, RAPowerWeightElectric ];
    return kind >= 0 && kind < (NSInteger)keys.count ? [self valueForParameter:keys[(NSUInteger)kind]] : 12;
}

#pragma mark - description

+ (NSArray<NSString *> *)groups
{
    return @[ @"drivetrain", @"rolling", @"signal", @"masses", @"air" ];
}

+ (NSArray<NSString *> *)parametersOfGroup:(NSString *)group
{
    NSDictionary *g = @{ @"drivetrain": @[ RAPowerEfficiency ],
                         @"rolling": @[ RAPowerRollingScale, RAPowerPressureExponent, RAPowerPressureMinFactor,
                                        RAPowerPressureMaxFactor ],
                         @"signal": @[ RAPowerSpeedSmoothing, RAPowerAccelerationWindow, RAPowerFreewheelingIsZero ],
                         @"masses": @[ RAPowerRiderWeight, RAPowerWheelInertia, RAPowerWeightRoad, RAPowerWeightHybrid,
                                       RAPowerWeightGravel, RAPowerWeightMountain, RAPowerWeightElectric ],
                         @"air": @[ RAPowerCdAUpright, RAPowerCdAFlatBar, RAPowerCdAHoods, RAPowerCdADrops ] };
    return g[group] ?: @[];
}

+ (NSString *)nameOfGroup:(NSString *)group
{
    NSDictionary *n = @{ @"drivetrain": NSLocalizedString(@"Drivetrain", @"power settings"),
                         @"rolling": NSLocalizedString(@"Rolling resistance (the surfaces: Surface Factors…)", @"power settings"),
                         @"signal": NSLocalizedString(@"Speed and cadence of the file", @"power settings"),
                         @"masses": NSLocalizedString(@"Masses (when not entered)", @"power settings"),
                         @"air": NSLocalizedString(@"Air drag CdA by position (when not entered)", @"power settings") };
    return n[group] ?: group;
}

+ (NSString *)nameOfParameter:(NSString *)k
{
    NSDictionary *n = @{
        RAPowerEfficiency: NSLocalizedString(@"Drivetrain efficiency", @"power settings"),
        RAPowerWheelInertia: NSLocalizedString(@"Wheel inertia", @"power settings"),
        RAPowerRollingScale: NSLocalizedString(@"Crr multiplier (calibration)", @"power settings"),
        RAPowerPressureExponent: NSLocalizedString(@"Pressure exponent", @"power settings"),
        RAPowerPressureMinFactor: NSLocalizedString(@"Pressure correction, minimum", @"power settings"),
        RAPowerPressureMaxFactor: NSLocalizedString(@"Pressure correction, maximum", @"power settings"),
        RAPowerSpeedSmoothing: NSLocalizedString(@"Speed smoothing", @"power settings"),
        RAPowerAccelerationWindow: NSLocalizedString(@"Acceleration window", @"power settings"),
        RAPowerFreewheelingIsZero: NSLocalizedString(@"Cadence 0: no power", @"power settings"),
        RAPowerRiderWeight: NSLocalizedString(@"Rider weight", @"power settings"),
        RAPowerCdAUpright: NSLocalizedString(@"Upright", @"power settings"),
        RAPowerCdAFlatBar: NSLocalizedString(@"Flat bar", @"power settings"),
        RAPowerCdAHoods: NSLocalizedString(@"Hoods", @"power settings"),
        RAPowerCdADrops: NSLocalizedString(@"Drops", @"power settings"),
        RAPowerWeightRoad: NSLocalizedString(@"Road bike", @"power settings"),
        RAPowerWeightHybrid: NSLocalizedString(@"Hybrid bike", @"power settings"),
        RAPowerWeightGravel: NSLocalizedString(@"Gravel bike", @"power settings"),
        RAPowerWeightMountain: NSLocalizedString(@"Mountain bike", @"power settings"),
        RAPowerWeightElectric: NSLocalizedString(@"Electric bike", @"power settings") };
    return n[k] ?: k;
}

+ (NSString *)unitOfParameter:(NSString *)k
{
    if ([@[ RAPowerWheelInertia, RAPowerRiderWeight ] containsObject:k] || [k hasPrefix:@"weight"]) return @"kg";
    if ([k hasPrefix:@"cdA"]) return @"m²";
    if ([@[ RAPowerSpeedSmoothing, RAPowerAccelerationWindow ] containsObject:k]) return @"s";
    if ([k isEqualToString:RAPowerRollingScale] || [k hasPrefix:@"pressureM"]) return @"×";
    return @"";
}

+ (NSString *)explanationOfParameter:(NSString *)k
{
    NSDictionary *e = @{
        RAPowerEfficiency: NSLocalizedString(@"Share of the power at the pedals that reaches the wheel (chain, bearings): "
                                             @"0.95–0.98 for a clean chain.", @"power settings"),
        RAPowerWheelInertia: NSLocalizedString(@"Mass added in the accelerations only, for the rotation of the wheels "
                                               @"(about their rims and tyres).", @"power settings"),
        RAPowerRollingScale: NSLocalizedString(@"Multiplies every Crr; set by the calibration on rides with a power "
                                               @"meter.", @"power settings"),
        RAPowerPressureExponent: NSLocalizedString(@"Below the pressure of the test, the Crr grows as (test / pressure) "
                                                   @"to this power.", @"power settings"),
        RAPowerPressureMinFactor: NSLocalizedString(@"Bounds of that correction.", @"power settings"),
        RAPowerPressureMaxFactor: NSLocalizedString(@"Bounds of that correction.", @"power settings"),
        RAPowerSpeedSmoothing: NSLocalizedString(@"The speed is averaged over this time (GPS noise).", @"power settings"),
        RAPowerAccelerationWindow: NSLocalizedString(@"The acceleration is measured over this time.", @"power settings"),
        RAPowerFreewheelingIsZero: NSLocalizedString(@"When the file has the cadence, no power while not pedalling "
                                                     @"(the stats are computed again).", @"power settings"),
        RAPowerRiderWeight: NSLocalizedString(@"When neither the equipment nor Garmin Connect gives it.", @"power settings") };
    if ([k hasPrefix:@"weight"]) return NSLocalizedString(@"Typical weight of the kind, with bags and bottles.", @"power settings");
    if ([k hasPrefix:@"cdA"]) return NSLocalizedString(@"Drag area of bike and rider in that position.", @"power settings");
    return e[k] ?: @"";
}

+ (double)defaultOfParameter:(NSString *)key { return [self specs][key][0].doubleValue; }
+ (double)minimumOfParameter:(NSString *)key { return [self specs][key][1].doubleValue; }
+ (double)maximumOfParameter:(NSString *)key { return [self specs][key][2].doubleValue; }

+ (BOOL)isSwitch:(NSString *)key
{
    return [key isEqualToString:RAPowerFreewheelingIsZero];
}

+ (BOOL)changesStats:(NSString *)key
{
    return [key isEqualToString:RAPowerFreewheelingIsZero];
}

@end
