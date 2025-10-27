//
//  BikePlan.m
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import "BikePlan.h"
#import "POILocation.h"

@interface BikePlan ()
@property (strong,nonatomic) NSMutableArray <CLLocation *>*waypointsLocations;
@end


@implementation BikePlan {
    NSMutableArray <CLLocation *>*_waypointsLocations;
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

    return self;
}

#pragma mark -

- (NSArray *) waypointsLocations
{
    return _waypointsLocations;
}
- (void) removeWaypoints
{
    [self willChangeValueForKey:@"waypointsLocations"];
    [_waypointsLocations removeAllObjects];
    [self didChangeValueForKey:@"waypointsLocations"];
    [self clearWaypointCache];
}
- (void) removeWaypointAtIndex:(NSUInteger)idx
{
    [self willChangeValueForKey:@"waypointsLocations"];
    [_waypointsLocations removeObjectAtIndex:idx];
    [self didChangeValueForKey:@"waypointsLocations"];
    [self clearWaypointCache];
}
- (void) appendWaypoint:(CLLocation *)loc
{
    [self willChangeValueForKey:@"waypointsLocations"];
    [_waypointsLocations addObject:loc];
    [self didChangeValueForKey:@"waypointsLocations"];
    [self clearWaypointCache];
}
- (void) insertWaypoint:(CLLocation *)loc atIndex:(NSUInteger)idx
{
    
    [self willChangeValueForKey:@"waypointsLocations"];
    [_waypointsLocations insertObject:loc atIndex:idx];
    [self didChangeValueForKey:@"waypointsLocations"];
    [self clearWaypointCache];
}
- (void) replaceWaypointAtIndex:(NSUInteger)idx by:(CLLocation *)loc
{
    [self willChangeValueForKey:@"waypointsLocations"];
    [_waypointsLocations replaceObjectAtIndex:idx withObject:loc];
    [self didChangeValueForKey:@"waypointsLocations"];
    [self clearWaypointCache];
}
- (void) clearWaypointCache
{
    [self willChangeValueForKey:@"waypointPoly"];
    _waypointPoly = nil;
    [self didChangeValueForKey:@"waypointPoly"];
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
- (TaggedPoly *) routePoly
{
    if (!_waypointPoly) {
        _routePoly = [self buildPolyWith:_routePoints];
        _routePoly.tag = 0;
        [self shouldRequestPOI];
        //[self fetchPOIsNearRoute:_routePoints];
    }
    return _routePoly;
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
        @"[out:json][timeout:25];\n(\n"];

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
    
    NSURL *url = [NSURL URLWithString:@"https://overpass-api.de/api/interpreter"];
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
            NSLog(@"no poi");
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
        NSLog(@"no poi");
    }
    if (pl != _poiloc) {
        _poiloc = pl;
    }
}

- (void) setCustomPoiloc:(NSMutableArray<POILocation *> * _Nonnull)pl
{
    if (!pl || ![pl count]) {
        // for debug
        NSLog(@"no poi");
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


- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_kmlen forKey:@"kmlen"];
    [coder encodeInteger:_mup forKey:@"mup"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) return self;
    self.kmlen = [coder decodeIntegerForKey:@"kmlen"];
    self.mup = [coder decodeIntegerForKey:@"mup"];
    return self;
}
@end


