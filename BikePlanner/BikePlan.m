//
//  BikePlan.m
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import "BikePlan.h"
#import "GPXParser.h"
#import "POILocation.h"
#import "BPEnvironment.h"
 
@interface NSArray (Insertion)
- (NSArray *)arrayByInsertingObject:(id)object atIndex:(NSUInteger)index;
- (NSArray *)arrayByReplacingObjectAtIndex:(NSUInteger)index withObject:(id)object;
- (NSArray *)arrayByRemovingObjectAtIndex:(NSUInteger)index;
@end

@implementation NSArray (Insertion)
- (NSArray *)arrayByRemovingObjectAtIndex:(NSUInteger)idx {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.count)];
    [indexes removeIndex:idx];
    NSArray *newArray = [self objectsAtIndexes:indexes];
    return newArray;
}
- (NSArray *)arrayByInsertingObject:(id)object atIndex:(NSUInteger)index {
    NSMutableArray *m = [self mutableCopy];
    [m insertObject:object atIndex:index];
    return [m copy];
}
- (NSArray *)arrayByReplacingObjectAtIndex:(NSUInteger)index withObject:(id)object {
    NSMutableArray *m = [self mutableCopy];
    [m replaceObjectAtIndex:index withObject:object];
    return [m copy];
}
@end


#pragma mark -

@interface BikePlan ()
@property (strong,nonatomic) NSArray <CLLocation *>*waypointsLocations;
// POI fetch timing (#12); 0 = default. Set by tests.
@property (nonatomic) NSTimeInterval poiMinRequestInterval;  // between two Overpass requests (default 2.8 s)
@property (nonatomic) NSTimeInterval poiRetryBaseDelay;      // first retry after an error, then doubled (default 2 s)
@property (nonatomic) NSUInteger poiMaxRetries;              // then wait for the next route change (default 5)
@end

static const NSTimeInterval kPOIMaxRetryDelay = 120;         // also caps Retry-After
static const double kPOISampleSpacingMeters = 1000;          // route points of the Overpass query (#12)
static const NSUInteger kPOIMaxSamplePoints = 300;


// a copy of the location as the given class (BPStageEndLocation or CLLocation)
static CLLocation *BPLocationAs(Class cls, CLLocation *loc)
{
    return [[cls alloc] initWithCoordinate:loc.coordinate altitude:loc.altitude horizontalAccuracy:loc.horizontalAccuracy
                          verticalAccuracy:loc.verticalAccuracy course:loc.course speed:loc.speed timestamp:loc.timestamp];
}

static CLLocation *BPPlainLocation(CLLocation *loc)
{
    return [loc isMemberOfClass:[CLLocation class]] ? loc : BPLocationAs([CLLocation class], loc);
}

@implementation BPStageEndLocation
+ (instancetype) locationFrom:(CLLocation *)loc
{
    return [loc isKindOfClass:self] ? (BPStageEndLocation *)loc : (BPStageEndLocation *)BPLocationAs(self, loc);
}
@end


@implementation BikePlan {
    NSArray <CLLocation *>*_waypointsLocations;
    TaggedPoly *_waypointPoly;
    TaggedPoly *_routePoly;
    TaggedPoly *_gpxDisplayedPoly;
    //NSMutableArray <POILocation *> *poiloc;
    //volatile int32_t poiNeedUpdate;
    volatile BOOL poiUpdateOnProgress;
    NSTimeInterval lastpoireq;
    NSTimer *poireqretrytimer;
    NSTimeInterval tpoineed;
    NSTimeInterval tpoireq;
    NSUInteger poiRetryCount;   // consecutive failed Overpass requests (#12)
}

- (instancetype)init
{
    self = [super init];
    if (!self) return self;
    self.brouterInfo = [[BrouterInfo alloc]init];
    self.waypointsLocations = [[NSMutableArray alloc]initWithCapacity:32];
    self.fetchPOI = YES;
    self.customPoiloc = [[NSMutableArray alloc]initWithCapacity:5];
    self.profileOverrides = @{};
    self.excludedPOIKeys = nil;
    
    return self;
}

- (NSString *)profileName
{
    return @"trekking";
}

- (void)setProfileOverrides:(NSDictionary<NSString *,NSString *> *)profileOverrides
{
    _profileOverrides = [profileOverrides copy] ?: @{};
}

#pragma mark -

- (NSArray *) waypointsLocations
{
    return _waypointsLocations;
}
//     [_docUndoMgr registerUndoWithTarget:self selector:@selector(undoSetWayPt:) object:_waypointsLocations];


- (NSArray <CLLocation *>*) removeWaypoints
{
    NSArray <CLLocation *>*old = _waypointsLocations;
    self.waypointsLocations = @[];
    return old;
}
- (NSArray <CLLocation *>*) removeWaypointAtIndex:(NSUInteger)idx
{
    NSArray <CLLocation *>*old = _waypointsLocations;
    //[_waypointsLocations removeObjectAtIndex:idx];
    self.waypointsLocations  = [_waypointsLocations arrayByRemovingObjectAtIndex:idx];
    return old;
}
- (NSArray <CLLocation *>*) appendWaypoint:(CLLocation *)loc
{
    NSArray <CLLocation *>*old = _waypointsLocations;
    //[_waypointsLocations addObject:loc];
    self.waypointsLocations  = [_waypointsLocations arrayByAddingObject:loc];
    return old;
}
- (NSArray <CLLocation *>*) insertWaypoint:(CLLocation *)loc atIndex:(NSUInteger)idx
{
    NSArray <CLLocation *>*old = _waypointsLocations;
    //[_waypointsLocations insertObject:loc atIndex:idx];
    self.waypointsLocations  = [_waypointsLocations arrayByInsertingObject:loc atIndex:idx];
    return old;
}
- (NSArray <CLLocation *>*) replaceWaypointAtIndex:(NSUInteger)idx by:(CLLocation *)loc
{
    NSArray <CLLocation *>*old = _waypointsLocations;
    if ([old[idx] isKindOfClass:[BPStageEndLocation class]]) loc = [BPStageEndLocation locationFrom:loc];
    //[_waypointsLocations replaceObjectAtIndex:idx withObject:loc];
    self.waypointsLocations  = [_waypointsLocations arrayByReplacingObjectAtIndex:idx withObject:loc];
    return old;
}
- (NSArray <CLLocation *>*) reverseWaypoints
{
    NSArray <CLLocation *>*old = _waypointsLocations;
    self.waypointsLocations  = _waypointsLocations.reverseObjectEnumerator.allObjects;
    return old;
}

#pragma mark - stages (#31)

- (NSArray <CLLocation *>*) setStageEnd:(BOOL)stageEnd atWaypointIndex:(NSUInteger)idx
{
    NSArray <CLLocation *>*old = _waypointsLocations;
    CLLocation *wp = old[idx];
    if (stageEnd == [wp isKindOfClass:[BPStageEndLocation class]]) return old;
    CLLocation *nwp = stageEnd ? [BPStageEndLocation locationFrom:wp] : BPPlainLocation(wp);
    self.waypointsLocations = [old arrayByReplacingObjectAtIndex:idx withObject:nwp];
    return old;
}

- (BOOL) isStageEndAtWaypointIndex:(NSUInteger)idx
{
    return idx > 0 && idx + 1 < _waypointsLocations.count && [_waypointsLocations[idx] isKindOfClass:[BPStageEndLocation class]];
}

+ (NSArray<NSNumber *> *) routeIndexesOfWaypoints:(NSArray<CLLocation *> *)waypoints inRoute:(NSArray<CLLocation *> *)route
{
    NSMutableArray<NSNumber *> *res = [NSMutableArray arrayWithCapacity:waypoints.count];
    NSUInteger from = 0;
    for (CLLocation *wp in waypoints) {
        if (!route.count) break;
        CLLocationDistance best = DBL_MAX;
        NSUInteger n = route.count;
        double *d = malloc(n * sizeof(double));
        for (NSUInteger i = from; i < n; i++) {
            d[i] = [route[i] distanceFromLocation:wp];
            best = MIN(best, d[i]);
        }
        NSUInteger found = from;
        for (NSUInteger i = from; i < n; i++) {
            if (d[i] <= best + 30) { found = i; break; }
        }
        free(d);
        [res addObject:@(found)];
        from = found;
    }
    return res;
}

- (NSArray<NSNumber *> *) stageEndRouteIndexes
{
    NSUInteger n = _routePoints.count;
    if (n < 2) return @[];
    NSArray<NSNumber *> *idx = [BikePlan routeIndexesOfWaypoints:_waypointsLocations inRoute:_routePoints];
    NSMutableArray<NSNumber *> *ends = [NSMutableArray array];
    for (NSUInteger w = 0; w < idx.count; w++) {
        NSUInteger r = idx[w].unsignedIntegerValue;
        if ([self isStageEndAtWaypointIndex:w] && r > 0 && r + 1 < n && r > ends.lastObject.unsignedIntegerValue) {
            [ends addObject:@(r)];
        }
    }
    return ends;
}

- (NSArray<NSArray<CLLocation *> *> *) stagesRoutePoints
{
    NSUInteger n = _routePoints.count;
    if (n < 2) return @[];
    NSMutableArray *stages = [NSMutableArray array];
    NSUInteger from = 0;
    for (NSNumber *e in [self.stageEndRouteIndexes arrayByAddingObject:@(n - 1)]) {
        NSUInteger to = e.unsignedIntegerValue;
        [stages addObject:[_routePoints subarrayWithRange:NSMakeRange(from, to - from + 1)]];
        from = to;
    }
    return stages;
}

- (NSUInteger) stageOfCoordinate:(CLLocationCoordinate2D)coord
{
    NSArray<NSNumber *> *ends = self.stageEndRouteIndexes;
    if (!ends.count) return 0;
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
    CLLocationDistance best = DBL_MAX;
    NSUInteger nearest = 0;
    for (NSUInteger i = 0; i < _routePoints.count; i++) {
        CLLocationDistance d = [_routePoints[i] distanceFromLocation:loc];
        if (d < best) { best = d; nearest = i; }
    }
    NSUInteger stage = 0;
    for (NSNumber *e in ends) if (nearest > e.unsignedIntegerValue) stage++;
    return stage;
}

- (NSDictionary *) routeState
{
    NSDictionary *old = @{ @"waypoints": _waypointsLocations ?: @[],
                           @"route": _routePoints ?: @[],
                           @"kmlen": @(_brouterInfo.kmlen), @"mup": @(_brouterInfo.mup),
                           @"meters": @(_brouterInfo.meters), @"seconds": @(_brouterInfo.seconds),
                           @"roadStats": _brouterInfo.roadStats ?: @{}, @"surfaceStats": _brouterInfo.surfaceStats ?: @{},
                           @"roadRuns": _brouterInfo.roadRuns ?: @[], @"surfaceRuns": _brouterInfo.surfaceRuns ?: @[],
                           @"poiloc": _poiloc ?: @[],
                           @"custom": [_customPoiloc copy] ?: @[] };
    if (_routeGPX) {
        NSMutableDictionary *withGPX = [old mutableCopy];
        withGPX[@"gpx"] = _routeGPX;
        old = withGPX;
    }
    return old;
}

- (NSDictionary *) clearRoute
{
    NSDictionary *old = [self routeState];
    [self undoSetWayPt:@[]];
    self.routePoints = @[];
    self.routeGPX = nil;
    self.brouterInfo.kmlen = 0;
    self.brouterInfo.mup = 0;
    self.brouterInfo.meters = 0;
    self.brouterInfo.seconds = 0;
    self.brouterInfo.roadStats = nil;
    self.brouterInfo.surfaceStats = nil;
    self.brouterInfo.roadRuns = nil;
    self.brouterInfo.surfaceRuns = nil;
    self.poiloc = @[];
    [self restoreCustomPoi:nil];
    return old;
}

- (void) restoreRoute:(NSDictionary *)state
{
    [self undoSetWayPt:state[@"waypoints"]];
    self.routePoints = state[@"route"];
    self.routeGPX = state[@"gpx"];
    self.brouterInfo.kmlen = [state[@"kmlen"] integerValue];
    self.brouterInfo.mup = [state[@"mup"] integerValue];
    self.brouterInfo.meters = [state[@"meters"] integerValue];
    self.brouterInfo.seconds = [state[@"seconds"] integerValue];
    self.brouterInfo.roadStats = [state[@"roadStats"] count] ? state[@"roadStats"] : nil;
    self.brouterInfo.surfaceStats = [state[@"surfaceStats"] count] ? state[@"surfaceStats"] : nil;
    self.brouterInfo.roadRuns = [state[@"roadRuns"] count] ? state[@"roadRuns"] : nil;
    self.brouterInfo.surfaceRuns = [state[@"surfaceRuns"] count] ? state[@"surfaceRuns"] : nil;
    self.poiloc = state[@"poiloc"];
    [self restoreCustomPoi:state[@"custom"]];
}

#pragma mark - import GPX as route (#29)

const CLLocationDistance kBPImportTolerance = 50;
const CLLocationDistance kBPImportMaxSpacing = 3000;
const NSUInteger kBPImportMaxWaypoints = 150;

// Douglas–Peucker on points projected in meters (local equirectangular projection)
static void BPSimplify(const double *x, const double *y, NSUInteger first, NSUInteger last, double tol, BOOL *keep)
{
    NSMutableArray<NSValue *> *stack = [NSMutableArray arrayWithObject:[NSValue valueWithRange:NSMakeRange(first, last - first)]];
    while (stack.count) {
        NSRange r = stack.lastObject.rangeValue;
        [stack removeLastObject];
        NSUInteger a = r.location, b = NSMaxRange(r);
        if (b <= a + 1) continue;
        double dx = x[b] - x[a], dy = y[b] - y[a], len2 = dx * dx + dy * dy;
        double dmax = -1;
        NSUInteger imax = a;
        for (NSUInteger i = a + 1; i < b; i++) {
            double t = len2 > 0 ? ((x[i] - x[a]) * dx + (y[i] - y[a]) * dy) / len2 : 0;
            t = MAX(0, MIN(1, t));
            double ex = x[a] + t * dx - x[i], ey = y[a] + t * dy - y[i];
            double d = sqrt(ex * ex + ey * ey);
            if (d > dmax) { dmax = d; imax = i; }
        }
        if (dmax > tol) {
            keep[imax] = YES;
            [stack addObject:[NSValue valueWithRange:NSMakeRange(a, imax - a)]];
            [stack addObject:[NSValue valueWithRange:NSMakeRange(imax, b - imax)]];
        }
    }
}

+ (NSArray <CLLocation *>*) waypointsForTrace:(NSArray <CLLocation *>*)trace
{
    NSUInteger n = trace.count;
    if (n <= 2) return [trace copy];
    double *x = malloc(n * sizeof(double)), *y = malloc(n * sizeof(double)), *along = malloc(n * sizeof(double));
    BOOL *keep = malloc(n * sizeof(BOOL));
    CLLocationCoordinate2D c0 = trace[0].coordinate;
    double kx = 111320.0 * cos(c0.latitude * M_PI / 180.0), ky = 110540.0;
    for (NSUInteger i = 0; i < n; i++) {
        CLLocationCoordinate2D c = trace[i].coordinate;
        x[i] = (c.longitude - c0.longitude) * kx;
        y[i] = (c.latitude - c0.latitude) * ky;
        along[i] = i ? along[i-1] + [trace[i] distanceFromLocation:trace[i-1]] : 0;
    }
    NSUInteger count;
    for (double tol = kBPImportTolerance; ; tol *= 2) {
        memset(keep, 0, n * sizeof(BOOL));
        keep[0] = keep[n-1] = YES;
        BPSimplify(x, y, 0, n - 1, tol, keep);
        count = 0;
        for (NSUInteger i = 0; i < n; i++) if (keep[i]) count++;
        if (count <= kBPImportMaxWaypoints) break;
    }
    NSMutableArray <CLLocation *>*wps = [NSMutableArray arrayWithObject:trace[0]];
    NSUInteger a = 0;
    for (NSUInteger b = 1; b < n; b++) {
        if (!keep[b]) continue;
        double gap = along[b] - along[a];
        if (gap > kBPImportMaxSpacing) {
            NSUInteger parts = (NSUInteger)ceil(gap / kBPImportMaxSpacing);
            NSUInteger i = a + 1;
            for (NSUInteger j = 1; j < parts; j++) {
                double target = along[a] + j * gap / parts;
                while (i < b && along[i] < target) i++;
                if (i >= b) break;
                [wps addObject:trace[i]];
                i++;
            }
        }
        [wps addObject:trace[b]];
        a = b;
    }
    free(x); free(y); free(along); free(keep);
    return wps;
}

- (void) clearWaypointCache
{
    [self willChangeValueForKey:@"waypointPoly"];
    _waypointPoly = nil;
    [self didChangeValueForKey:@"waypointPoly"];
}

- (void) undoSetWayPt:() wp
{
    [self willChangeValueForKey:@"waypointsLocations"]; \
    _waypointsLocations = wp;
    [self didChangeValueForKey:@"waypointsLocations"]; \
    [self clearWaypointCache]; \
}
- (TaggedPoly *) waypointPoly
{
    if (!_waypointPoly) {
        _waypointPoly = [self buildPolyWith:_waypointsLocations];
        _waypointPoly.tag = 1;
    }
    return _waypointPoly;
}

- (void) refetchPOIWithErr
{
    tpoireq = tpoireq-1;
    [self tryRequestPoi];
}

- (NSTimeInterval) minPOIRequestInterval
{
    return self.poiMinRequestInterval > 0 ? self.poiMinRequestInterval : 2.8;
}
- (void) refetchPOI
{
    dispatch_async(dispatch_get_main_queue(), ^() {
        [self tryRequestPoi];
    });
}
- (void) shouldRequestPOI
{
    NSLog(@"---- shouldRequestPOI ---- ");
    //OSAtomicIncrement32(&poiNeedUpdate);
    tpoineed = [NSDate timeIntervalSinceReferenceDate];
    // a new route: a new series of retries; a pending retry would only duplicate the request
    poiRetryCount = 0;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refetchPOIWithErr) object:nil];
    [self tryRequestPoi];
}

- (void) tryRequestPoiT
{
    // only here for breakpoint or log (tryRequestPoi called by timer)
    [self tryRequestPoi];
}

- (void) setFetchPOI:(BOOL)f
{
    if (f == _fetchPOI) return;
    _fetchPOI = f;
    if (_fetchPOI) {
        [self tryRequestPoi];
    }
}
- (void) tryRequestPoi
{
    if (!_fetchPOI) return;

    if ([_routePoints count] <2) {
        NSLog(@"--- <<< not enought points");
        [poireqretrytimer invalidate];
        poireqretrytimer = nil;
        return;
    }
    //
    if (tpoireq >= tpoineed) {
    //if (!poiNeedUpdate) {
        NSLog(@"--- <<< already fetched");
        [poireqretrytimer invalidate];
        poireqretrytimer = nil;
        return;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    BOOL delay = NO;
    if (poiUpdateOnProgress) {
        NSLog(@"--- ++ delayed (poiUpdateOnProgress)");
        delay = YES;
    } else if (now-lastpoireq<[self minPOIRequestInterval]) {
        NSLog(@"--- ++ delayed (less than %.1f)", [self minPOIRequestInterval]);
        delay = YES;
    }
    if (!delay) {
        tpoireq = tpoineed;
        poiUpdateOnProgress = YES;
        lastpoireq = now;
        [poireqretrytimer invalidate];
        poireqretrytimer = nil;
    } else {
        //NSLog(@"--- ++ delayed");
        if (!poireqretrytimer) {
            NSTimeInterval ti = MIN(2, [self minPOIRequestInterval]);
            poireqretrytimer = [[NSTimer alloc]initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:ti] interval:ti target:self selector:@selector(tryRequestPoiT) userInfo:nil repeats:YES];
            [[NSRunLoop mainRunLoop]addTimer:poireqretrytimer forMode:NSRunLoopCommonModes];
        }
        return;
    }
    [self fetchPOIsNearRoute:_routePoints];
}
// built once per route (the cache tested _waypointPoly, so the poly was rebuilt and the POIs re-requested at each
// access, #6); invalidated by setRoutePoints:
- (TaggedPoly *) routePoly
{
    if (!_routePoly) {
        _routePoly = [self buildPolyWith:_routePoints];
        _routePoly.tag = 0;
        [self shouldRequestPOI];
        //[self fetchPOIsNearRoute:_routePoints];
    }
    return _routePoly;
}

- (void) setRoutePoints:(NSArray<CLLocation *> *)routePoints
{
    _routePoints = routePoints;
    _routePoly = nil;
}

- (void) setExcludedPOIKeys:(NSSet<NSString *> *)keys
{
    _excludedPOIKeys = [keys copy] ?: [NSSet set];
}

- (BOOL) isPOIExcluded:(POILocation *)poi
{
    return [_excludedPOIKeys containsObject:poi.poiKey];
}

- (void) setPOI:(POILocation *)poi excluded:(BOOL)excluded
{
    [self setPOIKey:poi.poiKey excluded:excluded];
}

- (void) setPOIKey:(NSString *)key excluded:(BOOL)excluded
{
    NSMutableSet *keys = [_excludedPOIKeys mutableCopy];
    if (excluded) [keys addObject:key]; else [keys removeObject:key];
    self.excludedPOIKeys = keys;
}

- (nullable NSData *) exportableGPX
{
    if (_routeGPX) return _routeGPX;
    if (_routePoints.count < 2) return nil;
    return [BikePlan gpxDataForPoints:_routePoints name:@"route"];
}

// GPX of the route points (documents saved before #10); the writer is in GPXParser (also used for BRouter, #53)
+ (NSData *) gpxDataForPoints:(NSArray<CLLocation *> *)points name:(NSString *)name
{
    return [GPXParser gpxDataForPoints:points name:name comment:nil];
}
- (TaggedPoly *) buildPolyWith :(NSArray <CLLocation *> *)points
{
    // Build polyline
    NSUInteger n = points.count;
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * n);
    for (NSUInteger i=0;i<n;i++) {
        coords[i] = points[i].coordinate;
    }
    TaggedPoly *poly = [TaggedPoly polylineWithCoordinates:coords count:n];
    free(coords);
    return poly;
}

- (void) setGpxDisplayed:(NSArray<CLLocation *> *)pt
{
    _gpxDisplayedPoly = nil;
    _gpxDisplayed = pt;
}

- (TaggedPoly *) gpxDisplayedPoly
{
    if (!_gpxDisplayedPoly) {
        _gpxDisplayedPoly = [self buildPolyWith:_gpxDisplayed];
        _gpxDisplayedPoly.tag = 2;
    }
    return _gpxDisplayedPoly;
}
#pragma mark - load save

+ (BOOL) supportsSecureCoding
{
    return YES;
}


- (void)encodeWithCoder:(NSCoder *)coder
{
    // plain CLLocations, the stage ends apart (#31): documents stay readable by older versions
    NSMutableArray<CLLocation *> *wps = [NSMutableArray arrayWithCapacity:_waypointsLocations.count];
    NSMutableIndexSet *stageEnds = [NSMutableIndexSet indexSet];
    [_waypointsLocations enumerateObjectsUsingBlock:^(CLLocation *wp, NSUInteger i, BOOL *stop) {
        [wps addObject:BPPlainLocation(wp)];
        if ([wp isKindOfClass:[BPStageEndLocation class]]) [stageEnds addIndex:i];
    }];
    [coder encodeObject:wps forKey:@"waypointsLocations"];
    if (stageEnds.count) [coder encodeObject:stageEnds forKey:@"stageEnds"];
    [coder encodeObject:_routePoints forKey:@"routePoints"];
    [coder encodeObject:_gpxDisplayed forKey:@"gpxDisplayed"];
    [coder encodeObject:_brouterInfo forKey:@"brouterInfo"];
    [coder encodeObject:_poiloc forKey:@"poiloc"];
    [coder encodeObject:_customPoiloc forKey:@"customPoiloc"];
    [coder encodeObject:_profileOverrides forKey:@"profileOverrides"];
    [coder encodeObject:_routeGPX forKey:@"routeGPX"];
    [coder encodeObject:_excludedPOIKeys forKey:@"excludedPOIKeys"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) return self;
    NSArray<CLLocation *> *wps = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [CLLocation class], nil] forKey:@"waypointsLocations"];
    NSIndexSet *stageEnds = [coder decodeObjectOfClass:[NSIndexSet class] forKey:@"stageEnds"];
    if (stageEnds.count && wps.count) {
        NSMutableArray<CLLocation *> *m = [wps mutableCopy];
        [stageEnds enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
            if (i < m.count) m[i] = [BPStageEndLocation locationFrom:m[i]];
        }];
        wps = m;
    }
    self.waypointsLocations = wps;
    self.routePoints = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [CLLocation class], nil] forKey:@"routePoints"];
    self.gpxDisplayed = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [CLLocation class], nil] forKey:@"gpxDisplayed"];
    self.brouterInfo = [coder decodeObjectOfClass:[BrouterInfo class] forKey:@"brouterInfo"];
    if (!_brouterInfo) self.brouterInfo = [[BrouterInfo alloc]init];
    self.poiloc = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [POILocation class], nil]  forKey:@"poiloc"];
    self.customPoiloc = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [POILocation class], nil]  forKey:@"customPoiloc"];
    self.routeGPX = [coder decodeObjectOfClass:[NSData class] forKey:@"routeGPX"];
    self.excludedPOIKeys = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSSet class], [NSString class], nil] forKey:@"excludedPOIKeys"];
    self.profileOverrides = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSDictionary class], [NSString class], nil] forKey:@"profileOverrides"];
    if (!_customPoiloc) {
        self.customPoiloc = [[NSMutableArray alloc]initWithCapacity:5];
    }
    return self;
}

#pragma mark - POI

/*- (NSString *)polyStringFromCoordinates:(NSArray<CLLocation *> *)route
{
    NSMutableString *poly = [NSMutableString string];
    for (CLLocation *loc in route) {
        CLLocationCoordinate2D c = [loc coordinate];
        [poly appendFormat:@"%f %f ", c.latitude, c.longitude];
    }
    return [poly stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}*/

// route points of the query: the first, the last, and points at least 1 km apart (more on long routes, at most
// kPOIMaxSamplePoints); 1.5 km circles 1 km apart still cover ≥ 1.4 km on each side of the route (#12)
+ (NSArray<CLLocation *> *)samplePointsForPOI:(NSArray<CLLocation *> *)points
{
    if (points.count < 2) return points;
    double length = 0;
    for (NSUInteger i = 1; i < points.count; i++) length += [points[i] distanceFromLocation:points[i-1]];
    double spacing = MAX(kPOISampleSpacingMeters, length / (kPOIMaxSamplePoints - 2));
    NSMutableArray<CLLocation *> *sample = [NSMutableArray arrayWithObject:points.firstObject];
    double run = 0;
    for (NSUInteger i = 1; i + 1 < points.count; i++) {
        run += [points[i] distanceFromLocation:points[i-1]];
        if (run >= spacing) {
            [sample addObject:points[i]];
            run = 0;
        }
    }
    [sample addObject:points.lastObject];
    return sample;
}

// 2 "around" clauses per sampled point (was per 10th route point, ~300 m apart, #12). Not one "around" along a
// polyline (around:r,lat1,lon1,lat2,lon2…): overpass-api.de returned no element for it on real routes.
- (NSString *)overpassQueryForTrack:(NSArray<CLLocation *> *)trackPoints
                         withRadius:(NSUInteger)radiusMeters
{
    NSMutableString *query = [NSMutableString stringWithString:@"[out:json][timeout:120];\n(\n"];
    for (CLLocation *loc in [[self class] samplePointsForPOI:trackPoints]) {
        CLLocationCoordinate2D coord = loc.coordinate;
        // amenity: drinking_water, toilets... (nodes)
        [query appendFormat:@"  node(around:%lu,%.6f,%.6f)[\"amenity\"~\"drinking_water|toilets|grave_yard|bicycle_repair_station\"];\n",
             (unsigned long)radiusMeters, coord.latitude, coord.longitude];
        // landuse = cemetery (ways or areas, get center)
        [query appendFormat:@"  way(around:%lu,%.6f,%.6f)[\"landuse\"=\"cemetery\"];\n",
             (unsigned long)radiusMeters, coord.latitude, coord.longitude];
    }
    [query appendString:@");\nout center;"];
    return query;
}

// after an error: retry later, on the main run loop (the NSURLSession completion queue has none, so the retry
// never happened), with exponential backoff or the server's Retry-After, at most poiMaxRetries times (#12)
- (void) refetchPOIAfterError:(NSHTTPURLResponse *)resp
{
    NSUInteger maxRetries = self.poiMaxRetries ?: 5;
    if (poiRetryCount >= maxRetries) {
        NSLog(@"POI: %lu failed requests, waiting for the next route change", (unsigned long)poiRetryCount);
        return;
    }
    NSTimeInterval base = self.poiRetryBaseDelay > 0 ? self.poiRetryBaseDelay : 2;
    NSTimeInterval delay = MIN(base * pow(2, poiRetryCount), kPOIMaxRetryDelay);
    NSString *retryAfter = [resp valueForHTTPHeaderField:@"Retry-After"]; // seconds (an HTTP date is ignored)
    if (retryAfter.length && [retryAfter integerValue] > 0) delay = MIN([retryAfter integerValue], kPOIMaxRetryDelay);
    poiRetryCount++;
    NSLog(@"POI: retry %lu in %.1f s", (unsigned long)poiRetryCount, delay);
    [self performSelector:@selector(refetchPOIWithErr) withObject:nil afterDelay:delay
                  inModes:@[NSRunLoopCommonModes]];
}

- (void) fetchPOIsNearRoute:(NSArray<CLLocation *> *)coords
{
    NSLog(@"--- >>>> fetch");
    NSString *query = [self overpassQueryForTrack:coords withRadius:1500];
    NSData *bodyData = [query dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *url = [BPEnvironment overpassURL]; // https://overpass-api.de/api/interpreter unless overridden
    NSMutableURLRequest *req = [BPEnvironment requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = bodyData;
    
    NSLog(@"----- fetch poi");
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
                                  dataTaskWithRequest:req
                                  completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        // on the main queue: poiUpdateOnProgress and the retry state are main-thread only (#12)
        dispatch_async(dispatch_get_main_queue(), ^{
            self->poiUpdateOnProgress = NO;
            NSHTTPURLResponse *httpResponse = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
            if (err) {
                NSLog(@"Error: %@", err);
                [self refetchPOIAfterError:httpResponse];
                return;
            }
            if (!data) {
                [self refetchPOIAfterError:httpResponse];
                return;
            }
            NSInteger httpcode = [httpResponse statusCode];
            if (httpcode>299) {
                NSLog(@"HTTP status for POI : %d", (int) httpcode);
                [self refetchPOIAfterError:httpResponse];
                return;
            }
            self->poiRetryCount = 0;
            if (coords != self.routePoints && self->tpoineed > self->tpoireq) {
                return; // POIs of a previous route: the request for the current one is pending
            }
            //OSAtomicDecrement32(&poiNeedUpdate);
        
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *elements = json[@"elements"];
            if (![elements count]) {
                //debug
                NSLog(@"no poi1");
                NSString *r = json[@"remark"];
                NSLog(@"no poi1 remark %@", r);
            }
            {
                NSMutableArray *tpoiarray = [[NSMutableArray alloc]initWithCapacity:16];
                for (NSDictionary *el in elements) {
                    NSString *poiid = el[@"id"];
                    NSDictionary *tags = el[@"tags"];
                    NSMutableDictionary *info2 = [tags mutableCopy];
                    [info2 setObject:poiid forKey:@"id"];
                    //NSDictionary *info = el[@"tags"];
                    double lon = 0.;
                    double lat = 0.;
                    NSString *t = el[@"type"];
                    NSString *poitypname = @"";
                    if ((0)) {
                    } else if ([t isEqualToString:@"node"]) {
                        lat = [el[@"lat"] doubleValue];
                        lon = [el[@"lon"] doubleValue];
                        poitypname = tags[@"amenity"];
                    } else if ([t isEqualToString:@"way"]) {
                        NSDictionary *center = el[@"center"];
                        lat = [center[@"lat"] doubleValue];
                        lon = [center[@"lon"] doubleValue];
                        poitypname = tags[@"landuse"];
                    } else {
                        NSLog(@"unknown type");
                        continue;
                    }
                
                    PoiType_t poit = [[POILocation class]poiTypeForAmenity:poitypname];
                    CLLocation *loc = [[POILocation alloc]initWithLatitude:lat longitude:lon ofType:poit info:info2 custom:NO];
                
                    [tpoiarray addObject:loc];
                }
                self.poiloc = tpoiarray;
            
                //[self willChangeValueForKey:@"poiloc"];
                //_poiloc = tpoiarray;
                //[self didChangeValueForKey:@"poiloc"];
                // notify controller
                if (self.poiAvailableCallback) {
                    self.poiAvailableCallback();
                }
            }
        });
    }];
    [task resume];
}

- (void) setPoiloc:(NSArray<POILocation *> * _Nonnull)pl
{
    if (!pl || ![pl count]) {
        // for debug
        NSLog(@"no poi2");
    }
    if (pl != _poiloc) {
        _poiloc = pl;
    }
}

- (void) setCustomPoiloc:(NSMutableArray<POILocation *> * _Nonnull)pl
{
    if (!pl || ![pl count]) {
        // for debug
        NSLog(@"no poi3");
    }
    if (pl != _customPoiloc) {
        _customPoiloc = pl;
    }
}

- (void) addCustomPoiAt:(CLLocationCoordinate2D)coord
{
    (void)[self addCustomPoiAt:coord type:[POILocation defaultCustomPoiType] name:nil];
}

- (POILocation *) customPoiAt:(CLLocationCoordinate2D)coord type:(PoiType_t)type name:(nullable NSString *)name
{
    NSString *n = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [[POILocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude ofType:type
                                            info:(n.length ? @{ @"name": n } : @{}) custom:YES];
}

- (POILocation *) addCustomPoiAt:(CLLocationCoordinate2D)coord type:(PoiType_t)type name:(nullable NSString *)name
{
    POILocation *loc = [self customPoiAt:coord type:type name:name];
    NSAssert([_customPoiloc isKindOfClass:[NSMutableArray class]], @"bad class customPoi");
    [_customPoiloc addObject:loc];
    return loc;
}

// POILocation is immutable: the edited POI replaces the old one (same position, so same poiKey)
- (POILocation *) replaceCustomPoi:(POILocation *)poi type:(PoiType_t)type name:(nullable NSString *)name
{
    POILocation *loc = [self customPoiAt:poi.coordinate type:type name:name];
    NSUInteger i = [_customPoiloc indexOfObjectIdenticalTo:poi];
    if (i == NSNotFound) [_customPoiloc addObject:loc];
    else [_customPoiloc replaceObjectAtIndex:i withObject:loc];
    return loc;
}

- (void) removeCustomPoi:(POILocation *)poi
{
    [_customPoiloc removeObjectIdenticalTo:poi];
}

- (void) restoreCustomPoi:(nullable NSArray<POILocation *> *)pois
{
    self.customPoiloc = pois ? [pois mutableCopy] : [[NSMutableArray alloc]initWithCapacity:5];
}
@end



#pragma mark -

NSString *const BPRoadTypeKindKey = @"kind";
NSString *const BPRoadTypeNameKey = @"name";
NSString *const BPRoadTypeDistanceKey = @"distance";
NSString *const BPRoadTypePercentKey = @"percent";

@implementation BrouterInfo

- (instancetype)init
{
    self = [super init];
    if (self) {
        
    }
    return self;
}


+ (BOOL) supportsSecureCoding
{
    return YES;
}


- (double) averageSpeed
{
    double m = _meters ?: _kmlen * 1000.0;
    if (_seconds <= 0 || m <= 0) return 0;
    return m / 1000.0 / (_seconds / 3600.0);
}

- (NSString *) durationText
{
    if (_seconds <= 0) return @"–";
    NSInteger min = (_seconds + 30) / 60;
    if (min < 60) return [NSString stringWithFormat:NSLocalizedString(@"%ld min", @"riding time < 1 h"), (long)min];
    return [NSString stringWithFormat:NSLocalizedString(@"%ld h %02ld", @"riding time, hours and minutes"), (long)(min / 60), (long)(min % 60)];
}

- (NSString *) averageSpeedText
{
    double v = self.averageSpeed;
    if (v <= 0) return @"–";
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.minimumFractionDigits = f.maximumFractionDigits = 1;
    return [f stringFromNumber:@(v)];
}

+ (NSSet<NSString *> *) keyPathsForValuesAffectingAverageSpeed
{
    return [NSSet setWithObjects:@"meters", @"kmlen", @"seconds", nil];
}

+ (NSSet<NSString *> *) keyPathsForValuesAffectingAverageSpeedText
{
    return [NSSet setWithObject:@"averageSpeed"];
}

+ (NSSet<NSString *> *) keyPathsForValuesAffectingDurationText
{
    return [NSSet setWithObject:@"seconds"];
}

+ (NSString *) displayNameForRoadClass:(NSString *)c
{
    NSDictionary *names = @{ @"cycleway": NSLocalizedString(@"Cycleways", @"road class"),
                             @"path": NSLocalizedString(@"Paths", @"road class"),
                             @"track": NSLocalizedString(@"Tracks", @"road class"),
                             @"small": NSLocalizedString(@"Small roads", @"road class"),
                             @"tertiary": NSLocalizedString(@"Tertiary roads", @"road class"),
                             @"secondary": NSLocalizedString(@"Secondary roads", @"road class"),
                             @"primary": NSLocalizedString(@"Main roads", @"road class"),
                             @"other": NSLocalizedString(@"Other", @"road class") };
    return names[c] ?: c;
}

- (NSArray<NSString *> *) roadTypesClasses
{
    NSArray *classes = [_roadStats keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [b compare:a];
    }] ?: @[];
    return [classes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *c, NSDictionary *b) {
        return self->_roadStats[c].doubleValue > 0;
    }]];
}

+ (NSSet<NSString *> *) keyPathsForValuesAffectingRoadTypesClasses
{
    return [NSSet setWithObject:@"roadStats"];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *) roadTypesRows
{
    NSMutableArray *rows = [NSMutableArray array];
    double total = [[_roadStats.allValues valueForKeyPath:@"@sum.doubleValue"] doubleValue];
    if (total <= 0) return rows;
    NSNumberFormatter *km = [[NSNumberFormatter alloc] init];
    km.numberStyle = NSNumberFormatterDecimalStyle;
    km.minimumFractionDigits = km.maximumFractionDigits = 1;
    void (^add)(NSString *, NSString *, double, double) = ^(NSString *kind, NSString *name, double m, double sum) {
        [rows addObject:@{ BPRoadTypeKindKey: kind, BPRoadTypeNameKey: name,
                           BPRoadTypeDistanceKey: [NSString stringWithFormat:@"%@ km", [km stringFromNumber:@(m / 1000)]],
                           BPRoadTypePercentKey: [NSString stringWithFormat:@"%.0f %%", 100 * m / sum] }];
    };
    for (NSString *c in self.roadTypesClasses) {
        add([@"road:" stringByAppendingString:c], [BrouterInfo displayNameForRoadClass:c], _roadStats[c].doubleValue, total);
    }
    double stotal = [[_surfaceStats.allValues valueForKeyPath:@"@sum.doubleValue"] doubleValue];
    NSDictionary *surfaces = @{ @"paved": NSLocalizedString(@"Paved", @"surface class"),
                                @"unpaved": NSLocalizedString(@"Unpaved", @"surface class"),
                                @"unknown": NSLocalizedString(@"Unknown surface", @"surface class") };
    for (NSString *c in @[@"paved", @"unpaved", @"unknown"]) {
        double m = _surfaceStats[c].doubleValue;
        if (stotal > 0 && m > 0) add([@"surface:" stringByAppendingString:c], surfaces[c], m, stotal);
    }
    return rows;
}

+ (NSSet<NSString *> *) keyPathsForValuesAffectingRoadTypesRows
{
    return [NSSet setWithObjects:@"roadStats", @"surfaceStats", nil];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_kmlen forKey:@"kmlen"];
    [coder encodeInteger:_mup forKey:@"mup"];
    [coder encodeInteger:_meters forKey:@"meters"];
    [coder encodeInteger:_seconds forKey:@"seconds"];
    [coder encodeObject:_roadStats forKey:@"roadStats"];
    [coder encodeObject:_surfaceStats forKey:@"surfaceStats"];
    [coder encodeObject:_roadRuns forKey:@"roadRuns"];
    [coder encodeObject:_surfaceRuns forKey:@"surfaceRuns"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) return self;
    self.kmlen = [coder decodeIntegerForKey:@"kmlen"];
    self.mup = [coder decodeIntegerForKey:@"mup"];
    self.meters = [coder decodeIntegerForKey:@"meters"];
    self.seconds = [coder decodeIntegerForKey:@"seconds"];
    NSSet *classes = [NSSet setWithObjects:[NSDictionary class], [NSString class], [NSNumber class], nil];
    self.roadStats = [coder decodeObjectOfClasses:classes forKey:@"roadStats"];
    self.surfaceStats = [coder decodeObjectOfClasses:classes forKey:@"surfaceStats"];
    NSSet *runClasses = [NSSet setWithObjects:[NSArray class], [NSString class], [NSNumber class], nil];
    self.roadRuns = [coder decodeObjectOfClasses:runClasses forKey:@"roadRuns"];
    self.surfaceRuns = [coder decodeObjectOfClasses:runClasses forKey:@"surfaceRuns"];
    return self;
}
@end


