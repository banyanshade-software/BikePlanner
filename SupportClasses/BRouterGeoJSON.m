//
//  BRouterGeoJSON.m
//  BikePlanner
//

#import "BRouterGeoJSON.h"

NSString *const BPRoadCycleway  = @"cycleway";
NSString *const BPRoadPath      = @"path";
NSString *const BPRoadTrack     = @"track";
NSString *const BPRoadSmall     = @"small";
NSString *const BPRoadTertiary  = @"tertiary";
NSString *const BPRoadSecondary = @"secondary";
NSString *const BPRoadPrimary   = @"primary";
NSString *const BPRoadOther     = @"other";
NSString *const BPSurfacePaved   = @"paved";
NSString *const BPSurfaceUnpaved = @"unpaved";
NSString *const BPSurfaceUnknown = @"unknown";

@implementation BRouterGeoJSON

static NSError *BPGeoJSONError(NSString *message)
{
    return [NSError errorWithDomain:@"BRouterGeoJSON" code:1 userInfo:@{ NSLocalizedDescriptionKey: message }];
}

+ (NSString *)roadClassForTags:(NSDictionary<NSString *, NSString *> *)tags
{
    NSString *h = tags[@"highway"];
    if (!h.length) return BPRoadOther; // ferry, etc.
    if ([h isEqualToString:@"cycleway"]) return BPRoadCycleway;
    if ([@[@"path", @"footway", @"bridleway", @"pedestrian", @"steps"] containsObject:h]) return BPRoadPath;
    if ([h isEqualToString:@"track"]) return BPRoadTrack;
    if ([@[@"unclassified", @"residential", @"living_street", @"service", @"road"] containsObject:h]) return BPRoadSmall;
    if ([h hasPrefix:@"tertiary"]) return BPRoadTertiary;
    if ([h hasPrefix:@"secondary"]) return BPRoadSecondary;
    if ([h hasPrefix:@"primary"] || [h hasPrefix:@"trunk"]) return BPRoadPrimary;
    return BPRoadOther;
}

+ (NSString *)surfaceClassForTags:(NSDictionary<NSString *, NSString *> *)tags
{
    NSString *s = tags[@"surface"];
    if (!s.length) return BPSurfaceUnknown;
    static NSSet *paved, *unpaved;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        paved = [NSSet setWithArray:@[ @"paved", @"asphalt", @"concrete", @"paving_stones", @"sett", @"cobblestone",
                                       @"unhewn_cobblestone", @"metal", @"wood", @"chipseal" ]];
        unpaved = [NSSet setWithArray:@[ @"unpaved", @"gravel", @"fine_gravel", @"compacted", @"dirt", @"earth",
                                         @"ground", @"grass", @"sand", @"mud", @"pebblestone", @"woodchips", @"rock",
                                         @"grass_paver" ]];
    });
    if ([paved containsObject:s] || [s hasPrefix:@"concrete:"]) return BPSurfacePaved;
    if ([unpaved containsObject:s]) return BPSurfaceUnpaved;
    return BPSurfaceUnknown;
}

+ (nullable instancetype)routeWithData:(NSData *)data error:(NSError **)error
{
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    NSDictionary *feature = [json isKindOfClass:[NSDictionary class]] ? [json[@"features"] firstObject] : nil;
    NSArray *coords = feature[@"geometry"][@"coordinates"];
    NSDictionary *props = feature[@"properties"];
    if (![coords isKindOfClass:[NSArray class]] || ![props isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) *error = BPGeoJSONError(@"not a BRouter route (GeoJSON)");
        return nil;
    }
    BRouterGeoJSON *r = [[BRouterGeoJSON alloc] init];
    NSMutableArray<CLLocation *> *points = [NSMutableArray arrayWithCapacity:coords.count];
    for (NSArray<NSNumber *> *c in coords) {
        if (![c isKindOfClass:[NSArray class]] || c.count < 2) continue;
        CLLocationCoordinate2D p = CLLocationCoordinate2DMake(c[1].doubleValue, c[0].doubleValue);
        [points addObject:[[CLLocation alloc] initWithCoordinate:p altitude:(c.count > 2 ? c[2].doubleValue : 0)
                                              horizontalAccuracy:kCLLocationAccuracyBest
                                                verticalAccuracy:kCLLocationAccuracyBest timestamp:[NSDate date]]];
    }
    r->_points = points;

    NSMutableDictionary<NSString *, NSString *> *info = [NSMutableDictionary dictionary];
    for (NSArray<NSString *> *k in @[ @[@"track-length", @"n-track-length-m"], @[@"filtered ascend", @"filtered-ascend"],
                                      @[@"total-time", @"n-time-seconds"], @[@"total-energy", @"n-energy-j"],
                                      @[@"cost", @"cost"] ]) {
        id v = props[k[0]];
        if (v) info[k[1]] = [v description];
    }
    r->_info = info;

    // messages: a header row, then one row per way segment, with its Distance (m) and WayTags ("k=v k=v")
    NSMutableDictionary<NSString *, NSNumber *> *roads = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *surfaces = [NSMutableDictionary dictionary];
    NSArray<NSArray *> *messages = props[@"messages"];
    if ([messages isKindOfClass:[NSArray class]] && messages.count > 1) {
        NSArray *header = messages[0];
        NSUInteger iDist = [header indexOfObject:@"Distance"], iTags = [header indexOfObject:@"WayTags"];
        if (iDist != NSNotFound && iTags != NSNotFound) {
            for (NSUInteger i = 1; i < messages.count; i++) {
                NSArray *row = messages[i];
                if (![row isKindOfClass:[NSArray class]] || row.count <= MAX(iDist, iTags)) continue;
                double d = [row[iDist] doubleValue];
                NSMutableDictionary *tags = [NSMutableDictionary dictionary];
                for (NSString *kv in [[row[iTags] description] componentsSeparatedByString:@" "]) {
                    NSRange eq = [kv rangeOfString:@"="];
                    if (eq.location != NSNotFound) tags[[kv substringToIndex:eq.location]] = [kv substringFromIndex:eq.location + 1];
                }
                NSString *rc = [self roadClassForTags:tags], *sc = [self surfaceClassForTags:tags];
                roads[rc] = @(roads[rc].doubleValue + d);
                surfaces[sc] = @(surfaces[sc].doubleValue + d);
            }
        }
    }
    r->_roadStats = roads;
    r->_surfaceStats = surfaces;
    return r;
}

@end
