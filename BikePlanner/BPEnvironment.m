//
//  BPEnvironment.m
//  BikePlanner
//

#import "BPEnvironment.h"

@implementation BPEnvironment

+ (NSString *) stringForKey:(NSString *)key default:(NSString *)def
{
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return [s length] ? s : def;
}

+ (NSURL *) brouterServerURL
{
    return [NSURL URLWithString:[self stringForKey:@"BPBRouterServer" default:@"https://brouter.de"]];
}

+ (NSURL *) brouterProfileURLForName:(NSString *)profileName
{
    NSString *s = [NSString stringWithFormat:@"brouter/profiles2/%@.brf", profileName];
    return [NSURL URLWithString:s relativeToURL:[self brouterServerURL]].absoluteURL;
}

+ (NSURL *) overpassURL
{
    return [NSURL URLWithString:[self stringForKey:@"BPOverpassURL" default:@"https://overpass-api.de/api/interpreter"]];
}

+ (BOOL) streetViewDisabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"BPDisableStreetView"];
}

+ (BOOL) tilesDisabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"BPDisableTiles"];
}

+ (BOOL) getInitialRegion:(MKCoordinateRegion * _Nullable)region
{
    NSArray<NSString *> *c = [[[NSUserDefaults standardUserDefaults] stringForKey:@"BPInitialRegion"]
                              componentsSeparatedByString:@","];
    if (c.count != 3) return NO;
    double span = [c[2] doubleValue];
    if (span <= 0) return NO;
    if (region) {
        *region = MKCoordinateRegionMake(CLLocationCoordinate2DMake([c[0] doubleValue], [c[1] doubleValue]),
                                         MKCoordinateSpanMake(span, span));
    }
    return YES;
}

+ (CLLocationCoordinate2D) defaultPosition
{
    NSArray<NSString *> *c = [[[NSUserDefaults standardUserDefaults] stringForKey:@"BPDefaultPosition"]
                              componentsSeparatedByString:@","];
    if (c.count == 2) {
        CLLocationCoordinate2D p = CLLocationCoordinate2DMake([c[0] doubleValue], [c[1] doubleValue]);
        if (CLLocationCoordinate2DIsValid(p)) return p;
    }
    return CLLocationCoordinate2DMake(44.1249234, 0.4961707); // Laplume
}

+ (double) initialRadiusKm
{
    double r = [[NSUserDefaults standardUserDefaults] doubleForKey:@"BPInitialRadiusKm"];
    return (r > 0) ? r : 80;
}

+ (BOOL) locationDisabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"BPDisableLocation"];
}

+ (BOOL) isUnitTestHost
{
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    return env[@"XCTestConfigurationFilePath"] != nil || env[@"XCTestBundlePath"] != nil;
}

@end
