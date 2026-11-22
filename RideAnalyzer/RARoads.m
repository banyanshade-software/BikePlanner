//
//  RARoads.m
//  RideAnalyzer
//

#import "RARoads.h"
#import "RAComputation.h"
#import "RAGarminConnect.h"
#import "RARideAnalysis.h"
#import "BRouterGeoJSON.h"

NSString *const RARoadNone = @"none";
NSString *const RASurfaceClassPaved = @"paved";
NSString *const RASurfaceClassUnpaved = @"unpaved";
NSString *const RASurfaceClassUnknown = @"unknown";
const NSInteger RARoadMatchVersion = 1;

static const double RACellSize = 0.01;           // degrees
static const double RAMatchDistance = 30;        // m: farther, no way
static const NSTimeInterval RACacheLifetime = 180 * 86400;

#pragma mark - rolling factor

double RARollingFactorOfTags(NSDictionary<NSString *, NSString *> *tags)
{
    NSString *surface = tags[@"surface"] ?: @"", *smoothness = tags[@"smoothness"] ?: @"";
    NSString *highway = tags[@"highway"] ?: @"", *tracktype = tags[@"tracktype"] ?: @"";
    if (surface.length) {
        if ([@[ @"asphalt", @"paved", @"concrete", @"chipseal" ] containsObject:surface] || [surface hasPrefix:@"concrete:"]) {
            if ([smoothness isEqualToString:@"excellent"]) return 1.15;
            if ([smoothness isEqualToString:@"intermediate"]) return 1.45;
            if ([@[ @"bad", @"very_bad", @"horrible" ] containsObject:smoothness]) return 1.7;
            return 1.3;
        }
        if ([surface isEqualToString:@"paving_stones"] || [@[ @"wood", @"metal" ] containsObject:surface]) return 1.5;
        if ([surface isEqualToString:@"compacted"]) return 1.8;
        if ([surface isEqualToString:@"fine_gravel"]) return 2.0;
        if ([@[ @"sett", @"cobblestone", @"unhewn_cobblestone" ] containsObject:surface]) return 2.2;
        if ([@[ @"gravel", @"pebblestone", @"unpaved", @"rock" ] containsObject:surface]) return 2.5;
        if ([@[ @"dirt", @"earth", @"ground", @"mud", @"sand", @"grass", @"woodchips" ] containsObject:surface]) return 3.0;
    }
    if ([highway isEqualToString:@"track"]) {
        if ([tracktype isEqualToString:@"grade1"]) return 1.4;
        if ([tracktype isEqualToString:@"grade2"]) return 1.9;
        if ([tracktype isEqualToString:@"grade3"]) return 2.5;
        if ([tracktype isEqualToString:@"grade4"] || [tracktype isEqualToString:@"grade5"]) return 3.0;
        return 2.5;
    }
    if ([@[ @"path", @"footway", @"bridleway" ] containsObject:highway]) return 2.0;
    return 1.3;     // roads, cycleways, pedestrian streets: asphalt as a rule
}

#pragma mark - match

@implementation RARoadMatch

- (instancetype)init
{
    self = [super init];
    if (self) {
        _version = RARoadMatchVersion;
        _date = [NSDate date];
        _runs = @[];
    }
    return self;
}

+ (RARoadMatch *)matchWithRoadClasses:(NSArray<NSString *> *)roads surfaces:(NSArray<NSString *> *)surfaces
                              factors:(NSArray<NSNumber *> *)factors
{
    RARoadMatch *m = [[RARoadMatch alloc] init];
    NSMutableArray<NSArray *> *runs = [NSMutableArray array];
    for (NSUInteger i = 0; i < roads.count; i++) {
        NSArray *last = runs.lastObject;
        if (last && [last[0] isEqualToString:roads[i]] && [last[1] isEqualToString:surfaces[i]]
            && [last[2] doubleValue] == factors[i].doubleValue) {
            runs[runs.count - 1] = @[ last[0], last[1], last[2], @(i) ];
        } else {
            [runs addObject:@[ roads[i], surfaces[i], factors[i], @(i) ]];
        }
    }
    m.runs = runs;
    m.pointCount = roads.count;
    return m;
}

- (NSDictionary *)propertyList
{
    return @{ @"version": @(self.version), @"date": self.date, @"pointCount": @(self.pointCount), @"runs": self.runs };
}

+ (nullable RARoadMatch *)matchWithPropertyList:(nullable id)plist
{
    if (![plist isKindOfClass:[NSDictionary class]] || ![plist[@"runs"] isKindOfClass:[NSArray class]]) return nil;
    RARoadMatch *m = [[RARoadMatch alloc] init];
    m.version = [plist[@"version"] integerValue];
    if ([plist[@"date"] isKindOfClass:[NSDate class]]) m.date = plist[@"date"];
    m.pointCount = (NSUInteger)[plist[@"pointCount"] integerValue];
    NSMutableArray<NSArray *> *runs = [NSMutableArray array];
    for (NSArray *r in plist[@"runs"]) {
        if (![r isKindOfClass:[NSArray class]] || r.count != 4 || ![r[0] isKindOfClass:[NSString class]]
            || ![r[1] isKindOfClass:[NSString class]] || ![r[2] isKindOfClass:[NSNumber class]] || ![r[3] isKindOfClass:[NSNumber class]]) {
            return nil;
        }
        [runs addObject:r];
    }
    m.runs = runs;
    return m;
}

/// the run of a point of the file (the last one past the end)
- (nullable NSArray *)runAtIndex:(NSUInteger)index
{
    // runs are in order of their last index: binary search
    NSUInteger lo = 0, hi = self.runs.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if ([self.runs[mid][3] unsignedIntegerValue] < index) lo = mid + 1; else hi = mid;
    }
    return lo < self.runs.count ? self.runs[lo] : self.runs.lastObject;
}

- (NSArray<NSNumber *> *)rollingFactorsFrom:(NSUInteger)first count:(NSUInteger)count
{
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:count];
    NSUInteger r = 0;
    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger index = first + i;
        while (r + 1 < self.runs.count && [self.runs[r][3] unsignedIntegerValue] < index) r++;
        [out addObject:self.runs.count ? self.runs[r][2] : @0];
    }
    return out;
}

- (NSString *)roadClassAtIndex:(NSUInteger)fileIndex
{
    return [self runAtIndex:fileIndex][0] ?: RARoadNone;
}

- (NSString *)surfaceClassAtIndex:(NSUInteger)fileIndex
{
    return [self runAtIndex:fileIndex][1] ?: RASurfaceClassUnknown;
}

- (double)matchedFraction
{
    if (self.pointCount == 0) return 0;
    NSUInteger matched = 0, start = 0;
    for (NSArray *r in self.runs) {
        NSUInteger end = [r[3] unsignedIntegerValue];
        if (![r[0] isEqualToString:RARoadNone]) matched += end + 1 - start;
        start = end + 1;
    }
    return (double)matched / self.pointCount;
}

@end

@implementation RARoadRow

- (double)speed
{
    return self.time > 0 ? self.distance / self.time * 3.6 : NAN;
}

@end

@implementation RARoadMatch (Rows)

+ (NSString *)nameOfRoadClass:(NSString *)c
{
    NSDictionary *names = @{ @"cycleway": NSLocalizedString(@"Cycleways", @"road class"),
                             @"path": NSLocalizedString(@"Paths", @"road class"),
                             @"track": NSLocalizedString(@"Tracks", @"road class"),
                             @"small": NSLocalizedString(@"Small roads", @"road class"),
                             @"tertiary": NSLocalizedString(@"Tertiary roads", @"road class"),
                             @"secondary": NSLocalizedString(@"Secondary roads", @"road class"),
                             @"primary": NSLocalizedString(@"Main roads", @"road class"),
                             @"other": NSLocalizedString(@"Other", @"road class"),
                             RARoadNone: NSLocalizedString(@"Not on a mapped way", @"road class") };
    return names[c] ?: c;
}

+ (NSString *)nameOfSurfaceClass:(NSString *)c
{
    NSDictionary *names = @{ RASurfaceClassPaved: NSLocalizedString(@"Paved", @"surface class"),
                             RASurfaceClassUnpaved: NSLocalizedString(@"Unpaved", @"surface class"),
                             RASurfaceClassUnknown: NSLocalizedString(@"Unknown surface", @"surface class") };
    return names[c] ?: c;
}

- (NSArray<RARoadRow *> *)rowsForAnalysis:(RARideAnalysis *)a
{
    NSMutableDictionary<NSString *, RARoadRow *> *rows = [NSMutableDictionary dictionary];
    RARoadRow *(^row)(NSString *, NSString *) = ^RARoadRow *(NSString *kind, NSString *name) {
        RARoadRow *r = rows[kind];
        if (!r) {
            r = [[RARoadRow alloc] init];
            r.kind = kind;
            r.name = name;
            rows[kind] = r;
        }
        return r;
    };
    for (NSUInteger i = 1; i < a.count; i++) {
        double dd = a.distances[i].doubleValue - a.distances[i - 1].doubleValue;
        double dt = a.elapsed[i].doubleValue - a.elapsed[i - 1].doubleValue;
        BOOL moving = a.hasTimes && dt > 0 && dd / dt > 3 / 3.6;
        NSUInteger index = a.firstFileIndex + i;
        NSString *road = [self roadClassAtIndex:index], *surface = [self surfaceClassAtIndex:index];
        for (RARoadRow *r in @[ row([@"road:" stringByAppendingString:road], [RARoadMatch nameOfRoadClass:road]),
                                row([@"surface:" stringByAppendingString:surface], [RARoadMatch nameOfSurfaceClass:surface]) ]) {
            r.distance += dd;
            if (moving) r.time += dt;
        }
    }
    NSArray<RARoadRow *> *(^sorted)(NSString *) = ^NSArray<RARoadRow *> *(NSString *prefix) {
        NSArray *part = [rows.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind BEGINSWITH %@", prefix]];
        return [part sortedArrayUsingComparator:^NSComparisonResult(RARoadRow *x, RARoadRow *y) {
            return x.distance > y.distance ? NSOrderedAscending : x.distance < y.distance ? NSOrderedDescending : NSOrderedSame;
        }];
    };
    return [sorted(@"road:") arrayByAddingObjectsFromArray:sorted(@"surface:")];
}

@end

#pragma mark - matcher

typedef struct { float lat, lon; } RAWayPoint;

/// a piece of way, in local meters around the trace
typedef struct {
    double ax, ay, bx, by;
    NSUInteger way;
} RASegment;

static NSURLSession *RASession;

@implementation RARoadMatcher

+ (nullable NSURLSession *)session
{
    return RASession;
}

+ (void)setSession:(nullable NSURLSession *)session
{
    RASession = session;
}

+ (BOOL)findsRoadsAutomatically
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"RANoAutomaticRoads"]) return NO;
    return RASession != nil || NSClassFromString(@"XCTestCase") == nil;
}

+ (NSArray<NSURL *> *)overpassServers
{
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    id specs = [[NSUserDefaults standardUserDefaults] objectForKey:@"RAOverpassServers"];
    if ([specs isKindOfClass:[NSString class]]) specs = @[ specs ];
    if ([specs isKindOfClass:[NSArray class]]) {
        for (id s in specs) {
            NSURL *u = [s isKindOfClass:[NSString class]] ? [NSURL URLWithString:s] : nil;
            if (u.scheme) [urls addObject:u];
        }
    }
    if (urls.count) return urls;
    return @[ [NSURL URLWithString:@"https://overpass-api.de/api/interpreter"],
              [NSURL URLWithString:@"https://overpass.kumi.systems/api/interpreter"] ];
}

+ (NSURL *)cacheDirectory
{
    NSString *custom = [[NSUserDefaults standardUserDefaults] stringForKey:@"RAWaysCacheDirectory"];
    if (custom.length) return [NSURL fileURLWithPath:custom isDirectory:YES];
    NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject
                    ?: [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    return [caches URLByAppendingPathComponent:@"RideAnalyzer/OSMWays" isDirectory:YES];
}

static NSString *RACellKey(long lat, long lon)
{
    return [NSString stringWithFormat:@"%ld_%ld", lat, lon];
}

static void RACellOfKey(NSString *key, long *lat, long *lon)
{
    NSArray<NSString *> *p = [key componentsSeparatedByString:@"_"];
    *lat = p.count == 2 ? p[0].integerValue : 0;
    *lon = p.count == 2 ? p[1].integerValue : 0;
}

+ (NSArray<NSString *> *)cellsOfTrace:(NSArray<CLLocation *> *)trace
{
    NSMutableOrderedSet<NSString *> *cells = [NSMutableOrderedSet orderedSet];
    for (CLLocation *l in trace) {
        CLLocationCoordinate2D c = l.coordinate;
        if (!CLLocationCoordinate2DIsValid(c)) continue;
        long la = (long)floor(c.latitude / RACellSize), lo = (long)floor(c.longitude / RACellSize);
        [cells addObject:RACellKey(la, lo)];
        // near a border (60 m): the way may be in the next cell
        double mLat = 60.0 / 111195, mLon = 60.0 / (111195 * MAX(0.1, cos(c.latitude * M_PI / 180)));
        double fLat = c.latitude / RACellSize - la, fLon = c.longitude / RACellSize - lo;
        long dla = fLat * RACellSize < mLat ? -1 : (1 - fLat) * RACellSize < mLat ? 1 : 0;
        long dlo = fLon * RACellSize < mLon ? -1 : (1 - fLon) * RACellSize < mLon ? 1 : 0;
        if (dla) [cells addObject:RACellKey(la + dla, lo)];
        if (dlo) [cells addObject:RACellKey(la, lo + dlo)];
        if (dla && dlo) [cells addObject:RACellKey(la + dla, lo + dlo)];
    }
    return cells.array;
}

+ (NSString *)queryForCells:(NSArray<NSString *> *)cells
{
    NSMutableString *q = [NSMutableString stringWithString:@"[out:json][timeout:120];("];
    for (NSString *k in cells) {
        long la, lo;
        RACellOfKey(k, &la, &lo);
        [q appendFormat:@"way[\"highway\"](%.2f,%.2f,%.2f,%.2f);", la * RACellSize, lo * RACellSize,
         (la + 1) * RACellSize, (lo + 1) * RACellSize];
    }
    [q appendString:@");out tags geom;"];
    return q;
}

#pragma mark cache

+ (NSURL *)cacheFileOfCell:(NSString *)cell
{
    return [[self cacheDirectory] URLByAppendingPathComponent:[cell stringByAppendingPathExtension:@"plist"]];
}

/// the ways of a cell in the cache ([tags, points]), nil when absent or too old
+ (nullable NSArray<NSArray *> *)cachedWaysOfCell:(NSString *)cell
{
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfURL:[self cacheFileOfCell:cell]];
    NSDate *date = d[@"date"];
    if (![date isKindOfClass:[NSDate class]] || -[date timeIntervalSinceNow] > RACacheLifetime) return nil;
    NSArray *ways = d[@"ways"];
    return [ways isKindOfClass:[NSArray class]] ? ways : nil;
}

+ (void)cacheWays:(NSArray<NSArray *> *)ways ofCell:(NSString *)cell
{
    NSURL *dir = [self cacheDirectory];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    [@{ @"date": [NSDate date], @"ways": ways } writeToURL:[self cacheFileOfCell:cell] atomically:YES];
}

#pragma mark Overpass

/// the ways of an Overpass answer: [tags (highway, surface, smoothness, tracktype), packed points]
+ (nullable NSArray<NSArray *> *)waysOfOverpassJSON:(id)json
{
    if (![json isKindOfClass:[NSDictionary class]] || ![json[@"elements"] isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray<NSArray *> *ways = [NSMutableArray array];
    for (NSDictionary *e in json[@"elements"]) {
        if (![e isKindOfClass:[NSDictionary class]] || ![e[@"type"] isEqual:@"way"]) continue;
        NSDictionary *tags = [e[@"tags"] isKindOfClass:[NSDictionary class]] ? e[@"tags"] : @{};
        NSArray *geometry = [e[@"geometry"] isKindOfClass:[NSArray class]] ? e[@"geometry"] : @[];
        NSMutableData *points = [NSMutableData data];
        for (NSDictionary *g in geometry) {
            if (![g isKindOfClass:[NSDictionary class]]) continue;
            RAWayPoint p = { [g[@"lat"] floatValue], [g[@"lon"] floatValue] };
            [points appendBytes:&p length:sizeof p];
        }
        if (points.length < 2 * sizeof(RAWayPoint)) continue;
        NSMutableDictionary *kept = [NSMutableDictionary dictionary];
        for (NSString *k in @[ @"highway", @"surface", @"smoothness", @"tracktype" ]) {
            if ([tags[k] isKindOfClass:[NSString class]]) kept[k] = tags[k];
        }
        if (!kept[@"highway"]) continue;
        [ways addObject:@[ kept, points ]];
    }
    return ways;
}

/// a POST to the servers in turn, waiting for the answer (in the background)
+ (nullable NSData *)overpassAnswerOfQuery:(NSString *)query cancellation:(nullable RACancellation *)cancellation
                                     error:(NSError **)outError
{
    if (!RASession && NSClassFromString(@"XCTestCase")) {     // unit tests: never the real service
        if (outError) *outError = [NSError errorWithDomain:@"RARoads" code:2 userInfo:@{ NSLocalizedDescriptionKey: @"no stub" }];
        return nil;
    }
    NSURLSession *session = RASession ?: [NSURLSession sharedSession];
    NSError *last = nil;
    for (NSURL *server in [self overpassServers]) {
        if (cancellation.cancelled) return nil;
        NSMutableURLRequest *r = [RAEnvironment requestWithURL:server];
        r.HTTPMethod = @"POST";
        r.timeoutInterval = 150;
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
        NSString *body = [@"data=" stringByAppendingString:[query stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @""];
        r.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
        [r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSData *answer = nil;
        __block NSError *error = nil;
        __block NSInteger status = 0;
        NSURLSessionDataTask *task = [session dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
            answer = d;
            error = e;
            status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
            dispatch_semaphore_signal(done);
        }];
        [task resume];
        while (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC))) != 0) {
            if (cancellation.cancelled) {
                [task cancel];
                dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
                return nil;
            }
        }
        if (!error && status == 200 && answer.length) return answer;
        last = error ?: [NSError errorWithDomain:@"RARoads" code:status userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"OpenStreetMap (Overpass) answered with an "
                                                                                    @"error (HTTP %ld).", @"roads"), (long)status] }];
    }
    if (outError) *outError = last ?: [NSError errorWithDomain:@"RARoads" code:0 userInfo:@{
        NSLocalizedDescriptionKey: NSLocalizedString(@"OpenStreetMap (Overpass) could not be reached.", @"roads") }];
    return nil;
}

/// the ways of these cells: from the cache, else from Overpass (20 cells per request), then cached
+ (nullable NSArray<NSArray *> *)waysOfCells:(NSArray<NSString *> *)cells cancellation:(nullable RACancellation *)cancellation
                                       error:(NSError **)error
{
    NSMutableArray<NSArray *> *ways = [NSMutableArray array];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *c in cells) {
        NSArray *cached = [self cachedWaysOfCell:c];
        if (cached) [ways addObjectsFromArray:cached]; else [missing addObject:c];
    }
    for (NSUInteger from = 0; from < missing.count; from += 20) {
        if (cancellation.cancelled) return nil;
        NSArray<NSString *> *group = [missing subarrayWithRange:NSMakeRange(from, MIN(20u, missing.count - from))];
        NSData *answer = [self overpassAnswerOfQuery:[self queryForCells:group] cancellation:cancellation error:error];
        if (!answer) return nil;
        NSArray<NSArray *> *found = [self waysOfOverpassJSON:[NSJSONSerialization JSONObjectWithData:answer options:0 error:NULL]];
        if (!found) {
            if (error) *error = [NSError errorWithDomain:@"RARoads" code:1 userInfo:@{
                NSLocalizedDescriptionKey: NSLocalizedString(@"Unexpected answer from OpenStreetMap (Overpass).", @"roads") }];
            return nil;
        }
        // each cell keeps the ways that cross it (a way of several cells goes to each)
        for (NSString *c in group) {
            long la, lo;
            RACellOfKey(c, &la, &lo);
            double s = la * RACellSize - 0.0005, w = lo * RACellSize - 0.0005;
            double n = (la + 1) * RACellSize + 0.0005, e = (lo + 1) * RACellSize + 0.0005;
            NSMutableArray<NSArray *> *mine = [NSMutableArray array];
            for (NSArray *way in found) {
                NSData *pts = way[1];
                const RAWayPoint *p = pts.bytes;
                NSUInteger count = pts.length / sizeof(RAWayPoint);
                for (NSUInteger i = 1; i < count; i++) {
                    double minLat = MIN(p[i - 1].lat, p[i].lat), maxLat = MAX(p[i - 1].lat, p[i].lat);
                    double minLon = MIN(p[i - 1].lon, p[i].lon), maxLon = MAX(p[i - 1].lon, p[i].lon);
                    if (maxLat >= s && minLat <= n && maxLon >= w && minLon <= e) { [mine addObject:way]; break; }
                }
            }
            [self cacheWays:mine ofCell:c];
        }
        [ways addObjectsFromArray:found];
    }
    return ways;
}

+ (nullable RARoadMatch *)matchTrace:(NSArray<CLLocation *> *)trace cancellation:(nullable RACancellation *)cancellation
                               error:(NSError **)error
{
    NSArray<NSArray *> *ways = [self waysOfCells:[self cellsOfTrace:trace] cancellation:cancellation error:error];
    if (!ways || cancellation.cancelled) return nil;
    return [self matchTrace:trace toWays:ways];
}

#pragma mark matching

static double RADistanceToSegment(double px, double py, RASegment s, double *heading)
{
    double dx = s.bx - s.ax, dy = s.by - s.ay, len2 = dx * dx + dy * dy;
    double t = len2 > 0 ? ((px - s.ax) * dx + (py - s.ay) * dy) / len2 : 0;
    t = MAX(0, MIN(1, t));
    double cx = s.ax + t * dx, cy = s.ay + t * dy;
    if (heading) *heading = atan2(dx, dy) * 180 / M_PI;
    return hypot(px - cx, py - cy);
}

/// difference of two directions, a way being ridden both ways: 0…90°
static double RAAngle(double a, double b)
{
    double d = fmod(fabs(a - b), 180);
    return d > 90 ? 180 - d : d;
}

+ (RARoadMatch *)matchTrace:(NSArray<CLLocation *> *)trace toWays:(NSArray<NSArray *> *)ways
{
    NSUInteger n = trace.count;
    if (n == 0) return [RARoadMatch matchWithRoadClasses:@[] surfaces:@[] factors:@[]];
    // local meters around the first point
    double lat0 = trace.firstObject.coordinate.latitude, lon0 = trace.firstObject.coordinate.longitude;
    double mx = 111195 * cos(lat0 * M_PI / 180), my = 111195;
    // the same way can come from several cells: once
    NSMutableArray<NSArray *> *unique = [NSMutableArray array];
    NSMutableSet<NSData *> *seen = [NSMutableSet set];
    for (NSArray *w in ways) {
        if (w.count < 2 || ![w[1] isKindOfClass:[NSData class]] || [seen containsObject:w[1]]) continue;
        [seen addObject:w[1]];
        [unique addObject:w];
    }
    // segments in a grid of 40 m buckets
    const double bucket = 40;
    NSMutableData *segments = [NSMutableData data];
    NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *grid = [NSMutableDictionary dictionary];
    for (NSUInteger w = 0; w < unique.count; w++) {
        NSData *pts = unique[w][1];
        const RAWayPoint *p = pts.bytes;
        NSUInteger count = pts.length / sizeof(RAWayPoint);
        for (NSUInteger i = 1; i < count; i++) {
            RASegment s = { (p[i - 1].lon - lon0) * mx, (p[i - 1].lat - lat0) * my, (p[i].lon - lon0) * mx, (p[i].lat - lat0) * my, w };
            NSUInteger index = segments.length / sizeof(RASegment);
            [segments appendBytes:&s length:sizeof s];
            long x0 = (long)floor((MIN(s.ax, s.bx) - RAMatchDistance) / bucket), x1 = (long)floor((MAX(s.ax, s.bx) + RAMatchDistance) / bucket);
            long y0 = (long)floor((MIN(s.ay, s.by) - RAMatchDistance) / bucket), y1 = (long)floor((MAX(s.ay, s.by) + RAMatchDistance) / bucket);
            if ((x1 - x0 + 1) * (y1 - y0 + 1) > 2500) continue;      // a giant segment far away: not ridden here
            for (long x = x0; x <= x1; x++) {
                for (long y = y0; y <= y1; y++) {
                    NSNumber *key = @((x << 32) ^ (y & 0xffffffffL));
                    NSMutableArray *list = grid[key];
                    if (!list) grid[key] = list = [NSMutableArray array];
                    [list addObject:@(index)];
                }
            }
        }
    }
    const RASegment *seg = segments.bytes;
    NSMutableArray<NSString *> *roads = [NSMutableArray arrayWithCapacity:n], *surfaces = [NSMutableArray arrayWithCapacity:n];
    NSMutableArray<NSNumber *> *factors = [NSMutableArray arrayWithCapacity:n];
    NSUInteger previous = NSNotFound;
    for (NSUInteger i = 0; i < n; i++) {
        CLLocationCoordinate2D c = trace[i].coordinate;
        double px = (c.longitude - lon0) * mx, py = (c.latitude - lat0) * my;
        // the direction of the track here (over the neighbours)
        CLLocationCoordinate2D a = trace[i >= 2 ? i - 2 : 0].coordinate, b = trace[MIN(i + 2, n - 1)].coordinate;
        double hx = (b.longitude - a.longitude) * mx, hy = (b.latitude - a.latitude) * my;
        BOOL hasHeading = hypot(hx, hy) > 5;
        double heading = atan2(hx, hy) * 180 / M_PI;
        long bx = (long)floor(px / bucket), by = (long)floor(py / bucket);
        NSArray<NSNumber *> *candidates = grid[@((bx << 32) ^ (by & 0xffffffffL))] ?: @[];
        double best = INFINITY, previousScore = INFINITY;
        NSUInteger bestWay = NSNotFound;
        for (NSNumber *k in candidates) {
            RASegment s = seg[k.unsignedIntegerValue];
            double h = 0;
            double d = RADistanceToSegment(px, py, s, &h);
            if (d > RAMatchDistance) continue;
            double score = d + (hasHeading ? RAAngle(heading, h) / 90 * 20 : 0);
            if (score < best) { best = score; bestWay = s.way; }
            if (s.way == previous && score < previousScore) previousScore = score;
        }
        // the way of the previous point while it stays about as good (crossings, parallel cycleways)
        if (previous != NSNotFound && previousScore <= best + 8) bestWay = previous;
        previous = bestWay;
        if (bestWay == NSNotFound) {
            [roads addObject:RARoadNone];
            [surfaces addObject:RASurfaceClassUnknown];
            [factors addObject:@0];
        } else {
            NSDictionary *tags = unique[bestWay][0];
            [roads addObject:[BRouterGeoJSON roadClassForTags:tags]];
            [surfaces addObject:[BRouterGeoJSON surfaceClassForTags:tags]];
            [factors addObject:@(RARollingFactorOfTags(tags))];
        }
    }
    return [RARoadMatch matchWithRoadClasses:roads surfaces:surfaces factors:factors];
}

@end
