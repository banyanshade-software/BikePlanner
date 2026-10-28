//
//  BPPreferences.m
//  BikePlanner
//

#import "BPPreferences.h"

NSString *const BPDefaultPositionKey = @"BPDefaultPosition";
NSString *const BPInitialRadiusKmKey = @"BPInitialRadiusKm";

static const CLLocationCoordinate2D kBPDefaultPosition = { 44.1249234, 0.4961707 }; // Laplume, as BPEnvironment
static const double kBPDefaultRadiusKm = 80;

@implementation BPPreferences {
    NSUserDefaults *ud;
}

+ (instancetype)shared
{
    static BPPreferences *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BPPreferences alloc] initWithUserDefaults:[NSUserDefaults standardUserDefaults]]; });
    return shared;
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults
{
    if (self = [super init]) {
        ud = userDefaults;
    }
    return self;
}

+ (NSString *)stringForPosition:(CLLocationCoordinate2D)p
{
    return [NSString stringWithFormat:@"%.6f,%.6f", p.latitude, p.longitude];
}

+ (void)registerDefaults
{
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        BPDefaultPositionKey: [self stringForPosition:kBPDefaultPosition],
        BPInitialRadiusKmKey: @(kBPDefaultRadiusKm) }];
}

- (CLLocationCoordinate2D)defaultPosition
{
    NSArray<NSString *> *c = [[ud stringForKey:BPDefaultPositionKey] componentsSeparatedByString:@","];
    if (c.count == 2) {
        CLLocationCoordinate2D p = CLLocationCoordinate2DMake(c[0].doubleValue, c[1].doubleValue);
        if (CLLocationCoordinate2DIsValid(p)) return p;
    }
    return kBPDefaultPosition;
}

- (void)setDefaultPosition:(CLLocationCoordinate2D)p
{
    if (!CLLocationCoordinate2DIsValid(p)) return;
    [ud setObject:[BPPreferences stringForPosition:p] forKey:BPDefaultPositionKey];
}

- (double)initialRadiusKm
{
    double r = [ud doubleForKey:BPInitialRadiusKmKey];
    return r > 0 ? r : kBPDefaultRadiusKm;
}

- (void)setInitialRadiusKm:(double)r
{
    if (r <= 0) return;
    [ud setDouble:r forKey:BPInitialRadiusKmKey];
}

@end
