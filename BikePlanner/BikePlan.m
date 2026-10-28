//
//  BikePlan.m
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import "BikePlan.h"
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

- (NSDictionary *) clearRoute
{
    NSDictionary *old = @{ @"waypoints": _waypointsLocations ?: @[],
                           @"route": _routePoints ?: @[],
                           @"kmlen": @(_brouterInfo.kmlen), @"mup": @(_brouterInfo.mup),
                           @"meters": @(_brouterInfo.meters), @"seconds": @(_brouterInfo.seconds),
                           @"poiloc": _poiloc ?: @[],
                           @"custom": [_customPoiloc copy] ?: @[] };
    if (_routeGPX) {
        NSMutableDictionary *withGPX = [old mutableCopy];
        withGPX[@"gpx"] = _routeGPX;
        old = withGPX;
    }
    [self undoSetWayPt:@[]];
    self.routePoints = @[];
    self.routeGPX = nil;
    self.brouterInfo.kmlen = 0;
    self.brouterInfo.mup = 0;
    self.brouterInfo.meters = 0;
    self.brouterInfo.seconds = 0;
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
    } else if (now-lastpoireq<2.8) {
        NSLog(@"--- ++ delayed (less than 2.8)");
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
            poireqretrytimer = [[NSTimer alloc]initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:2] interval:2 target:self selector:@selector(tryRequestPoiT) userInfo:nil repeats:YES];
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

static NSString *BPXMLEscaped(NSString *s)
{
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

// minimal GPX 1.1 track with elevations, for documents saved without the BRouter GPX (#10)
+ (NSData *) gpxDataForPoints:(NSArray<CLLocation *> *)points name:(NSString *)name
{
    NSMutableString *xml = [NSMutableString stringWithString:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" creator=\"BikePlanner\" version=\"1.1\">\n"];
    [xml appendFormat:@" <trk>\n  <name>%@</name>\n  <trkseg>\n", BPXMLEscaped(name)];
    for (CLLocation *p in points) {
        [xml appendFormat:@"   <trkpt lat=\"%.6f\" lon=\"%.6f\">", p.coordinate.latitude, p.coordinate.longitude];
        [xml appendFormat:@"<ele>%.2f</ele></trkpt>\n", p.altitude]; // route points from BRouter all have one
    }
    [xml appendString:@"  </trkseg>\n </trk>\n</gpx>\n"];
    return [xml dataUsingEncoding:NSUTF8StringEncoding];
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
    [coder encodeObject:_waypointsLocations forKey:@"waypointsLocations"];
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
    self.waypointsLocations = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [CLLocation class], nil] forKey:@"waypointsLocations"];
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

- (NSString *)overpassQueryForTrack:(NSArray<CLLocation *> *)trackPoints
                        sampleEvery:(NSUInteger)step
                         withRadius:(NSUInteger)radiusMeters
{
    NSMutableString *query = [NSMutableString stringWithString:
        @"[out:json][timeout:120];\n(\n"];

    // Sample points (every Nth point)
    NSUInteger c = [trackPoints count];
    for (NSUInteger i = 0; i < c; i += step) {
        CLLocation *loc = trackPoints[i];
        CLLocationCoordinate2D coord = loc.coordinate;

        // Amenity = drinking_water
        [query appendFormat:@"  node(around:%lu,%.6f,%.6f)[\"amenity\"~\"drinking_water|toilets|grave_yard|bicycle_repair_station\"];\n",
             (unsigned long)radiusMeters, coord.latitude, coord.longitude];


        // Landuse = cemetery (ways or areas, get center)
        [query appendFormat:@"  way(around:%lu,%.6f,%.6f)[\"landuse\"=\"cemetery\"];\n",
             (unsigned long)radiusMeters, coord.latitude, coord.longitude];
    }

    [query appendString:@");\nout center;"];

    return query;
}

- (void) refetchPOIWithAdditionalDelay
{
    NSLog(@"----- refetchPOIWithAdditionalDelay");
    [self performSelector:@selector(refetchPOIWithErr) withObject:nil afterDelay:2.0];
}

- (void) fetchPOIsNearRoute:(NSArray<CLLocation *> *)coords
{
    NSLog(@"--- >>>> fetch");
    NSString *query = [self overpassQueryForTrack:coords sampleEvery:10 withRadius:1500];
    NSData *bodyData = [query dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *url = [BPEnvironment overpassURL]; // https://overpass-api.de/api/interpreter unless overridden
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = bodyData;
    
    NSLog(@"----- fetch poi");
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
                                  dataTaskWithRequest:req
                                  completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        self->poiUpdateOnProgress = NO;
        if (err) {
            NSLog(@"Error: %@", err);
            [self refetchPOIWithAdditionalDelay];
            return;
        }
        if (!data) {
            [self refetchPOIWithAdditionalDelay];
            return;
        }
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) resp;
        NSInteger httpcode = [httpResponse statusCode];
        if (httpcode>299) {
            NSLog(@"HTTP status for POI : %d", (int) httpcode);
            [self refetchPOIWithAdditionalDelay];
            return;
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
        dispatch_async(dispatch_get_main_queue(), ^{
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
    PoiType_t poit = [[POILocation class]poiTypeForAmenity:@"warning"];
    NSDictionary *info2 =[[NSDictionary alloc]init];
    POILocation *loc = [[POILocation alloc] initWithLatitude:coord.latitude
                                                   longitude:coord.longitude
                                                      ofType:poit
                                                        info:info2 custom:YES];
    NSAssert([_customPoiloc isKindOfClass:[NSMutableArray class]], @"bad class customPoi");
    [_customPoiloc addObject:loc];
}

- (void) restoreCustomPoi:(NSArray<POILocation *> *)pois
{
    self.customPoiloc = pois ? [pois mutableCopy] : [[NSMutableArray alloc]initWithCapacity:5];
}
@end



#pragma mark -

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

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_kmlen forKey:@"kmlen"];
    [coder encodeInteger:_mup forKey:@"mup"];
    [coder encodeInteger:_meters forKey:@"meters"];
    [coder encodeInteger:_seconds forKey:@"seconds"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) return self;
    self.kmlen = [coder decodeIntegerForKey:@"kmlen"];
    self.mup = [coder decodeIntegerForKey:@"mup"];
    self.meters = [coder decodeIntegerForKey:@"meters"];
    self.seconds = [coder decodeIntegerForKey:@"seconds"];
    return self;
}
@end


