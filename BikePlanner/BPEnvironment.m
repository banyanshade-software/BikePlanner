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

+ (NSArray<NSString *> *) overpassServerSpecs
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id list = [ud objectForKey:@"BPOverpassServers"];
    if ([list isKindOfClass:[NSArray class]] && [list count]) return list;
    NSString *single = [ud stringForKey:@"BPOverpassURL"];
    if (single.length) return @[ single ];
    // owner's decisions (#84): not the Russian VK instance; overpass.openstreetmap.fr answers 403 "only available to
    // white-listed usages" (2026-11-17): left out. Europe: two zones inscribed in the Geofabrik extract, avoiding
    // North Africa (Z1 37.5–71° N, 10° W–30° E; Z2 Andalusia and the Algarve)
    return @[ @"https://overpass-api.de/api/interpreter",
              @"https://overpass.private.coffee/api/interpreter",
              @"https://ovp.dresel.systems/api/interpreter 37.5,-10,71,30;36,-9.5,37.5,-2" ];
}

+ (NSURL *) garminConnectURL
{
    return [NSURL URLWithString:[self stringForKey:@"BPGarminConnectURL" default:@"https://connect.garmin.com"]];
}

+ (NSString *) poiCacheDirectory
{
    NSString *d = [[NSUserDefaults standardUserDefaults] stringForKey:@"BPPOICacheDirectory"];
    if (d.length) return d;
    if ([self isUnitTestHost]) return [NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-poi-cache-tests"];
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
    return [caches stringByAppendingPathComponent:@"POICache"];
}

+ (NSURL *) overpassURL
{
    return [NSURL URLWithString:[self stringForKey:@"BPOverpassURL" default:@"https://overpass-api.de/api/interpreter"]];
}

+ (NSURL *) googleMapsEmbedURL
{
    return [NSURL URLWithString:[self stringForKey:@"BPGoogleMapsEmbedURL" default:@"https://www.google.com/maps/embed/v1/"]];
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

+ (BPStartPosition) startPosition
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![ud objectForKey:@"BPStartPosition"]) return BPStartPositionRemarkableSite;
    NSInteger p = [ud integerForKey:@"BPStartPosition"];
    return (p >= BPStartPositionLocation && p <= BPStartPositionRemarkableSite) ? p : BPStartPositionRemarkableSite;
}

static NSUInteger BPRadiusForKey(NSString *key, NSUInteger def)
{
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    NSInteger r = [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
    return (r > 0 && r <= 10000) ? (NSUInteger)r : def;
}

+ (NSUInteger) poiSearchRadius
{
    return BPRadiusForKey(@"BPPOISearchRadius", 1500);
}

+ (NSUInteger) sightSearchRadius
{
    return BPRadiusForKey(@"BPSightSearchRadius", 1000);
}

+ (NSInteger) remarkableSiteIndex
{
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"BPRemarkableSiteIndex"];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : -1;
}

+ (BOOL) locationDisabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"BPDisableLocation"];
}

+ (NSString *) userAgent
{
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    return [NSString stringWithFormat:@"BikePlanner/%@ (build %@; +https://github.com/banyanshade-software/BikePlanner)",
            info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"];
}

+ (NSMutableURLRequest *) requestWithURL:(NSURL *)url
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    return req;
}

+ (BOOL) isUnitTestHost
{
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    return env[@"XCTestConfigurationFilePath"] != nil || env[@"XCTestBundlePath"] != nil;
}

@end
