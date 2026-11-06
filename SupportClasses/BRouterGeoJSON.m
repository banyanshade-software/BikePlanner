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

// appends the segment ending at point `end` to runs of class `cls` (consecutive segments of the same class: one run)
static void BPAddRun(NSMutableArray<NSArray *> *runs, NSString *cls, NSUInteger end)
{
    if ([runs.lastObject[0] isEqualToString:cls]) [runs removeLastObject];
    [runs addObject:@[cls, @(end)]];
}

// points after the last segment found: in the last run
static void BPCloseRuns(NSMutableArray<NSArray *> *runs, NSUInteger pointCount)
{
    if (runs.count && [runs.lastObject[1] unsignedIntegerValue] + 1 < pointCount) {
        runs[runs.count - 1] = @[runs.lastObject[0], @(pointCount - 1)];
    }
}

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

    // messages: a header row, then one row per way segment, with its Distance (m) and WayTags ("k=v k=v"), ending
    // at Longitude / Latitude (degrees × 1e6), a point of the geometry
    NSMutableDictionary<NSString *, NSNumber *> *roads = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *surfaces = [NSMutableDictionary dictionary];
    NSMutableArray<NSArray *> *runs = [NSMutableArray array], *surfaceRuns = [NSMutableArray array];
    NSUInteger runStart = 0; // first point not in a run yet
    NSArray<NSArray *> *messages = props[@"messages"];
    if ([messages isKindOfClass:[NSArray class]] && messages.count > 1) {
        NSArray *header = messages[0];
        NSUInteger iDist = [header indexOfObject:@"Distance"], iTags = [header indexOfObject:@"WayTags"];
        NSUInteger iLon = [header indexOfObject:@"Longitude"], iLat = [header indexOfObject:@"Latitude"];
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
                // the segment ends at the next point of the geometry at its position (#54); not found: its points
                // go to the next segment
                if (iLon == NSNotFound || iLat == NSNotFound || row.count <= MAX(iLon, iLat)) continue;
                long lon = [row[iLon] integerValue], lat = [row[iLat] integerValue];
                for (NSUInteger k = MAX(runStart, 1); k < points.count; k++) {
                    CLLocationCoordinate2D c = points[k].coordinate;
                    if (lround(c.longitude * 1e6) != lon || lround(c.latitude * 1e6) != lat) continue;
                    BPAddRun(runs, rc, k);
                    BPAddRun(surfaceRuns, sc, k);
                    runStart = k + 1;
                    break;
                }
            }
        }
    }
    BPCloseRuns(runs, points.count);
    BPCloseRuns(surfaceRuns, points.count);
    r->_roadStats = roads;
    r->_surfaceStats = surfaces;
    r->_roadRuns = runs;
    r->_surfaceRuns = surfaceRuns;
    return r;
}

@end
