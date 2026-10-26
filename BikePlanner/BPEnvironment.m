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

+ (BOOL) isUnitTestHost
{
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    return env[@"XCTestConfigurationFilePath"] != nil || env[@"XCTestBundlePath"] != nil;
}

@end
