//
//  BikePlan.m
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import "BikePlan.h"

@interface BikePlan ()
@property (strong,nonatomic) NSMutableArray <CLLocation *>*waypointsLocations;
@end


@implementation BikePlan {
    NSMutableArray <CLLocation *>*_waypointsLocations;
    TaggedPoly *_waypointPoly;
    TaggedPoly *_routePoly;
    TaggedPoly *_gpxDisplayedPoly;
    NSMutableArray <LocationWithString *> *poiloc;
}

- (instancetype)init
{
    self = [super init];
    if (!self) return self;
    self.brouterInfo = [[BrouterInfo alloc]init];
    self.waypointsLocations = [[NSMutableArray alloc]initWithCapacity:32];
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

- (TaggedPoly *) routePoly
{
    if (!_waypointPoly) {
        _routePoly = [self buildPolyWith:_routePoints];
        _routePoly.tag = 0;
        [self fetchPOIsNearRoute:_routePoints];
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
    self.poiloc = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [LocationWithString class], nil]  forKey:@"poiloc"];
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

- (void)fetchPOIsNearRoute:(NSArray<CLLocation *> *)coords
{
    NSString *query = [self overpassQueryForTrack:coords sampleEvery:10 withRadius:1500];
    NSData *bodyData = [query dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *url = [NSURL URLWithString:@"https://overpass-api.de/api/interpreter"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = bodyData;
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err) { NSLog(@"Error: %@", err); return; }
            if (!data) { return; }
            
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *elements = json[@"elements"];
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableArray *tpoiarray = [[NSMutableArray alloc]initWithCapacity:16];
                for (NSDictionary *el in elements) {
                    NSString *poiid = el[@"id"];
                    NSDictionary *tags = el[@"tags"];
                    NSMutableDictionary *info2 = [tags mutableCopy];
                    [info2 setObject:poiid forKey:@"id"];
                    NSDictionary *info = el[@"tags"];
                    double lon = 0.;
                    double lat = 0.;
                    NSString *t = el[@"type"];
                    NSString *poitype = @"";
                    if ((0)) {
                    } else if ([t isEqualToString:@"node"]) {
                        lat = [el[@"lat"] doubleValue];
                        lon = [el[@"lon"] doubleValue];
                        poitype = tags[@"amenity"];
                    } else if ([t isEqualToString:@"way"]) {
                        NSDictionary *center = el[@"center"];
                        lat = [center[@"lat"] doubleValue];
                        lon = [center[@"lon"] doubleValue];
                        poitype = tags[@"landuse"];
                    } else {
                        NSLog(@"unknown type");
                        continue;
                    }
                   
                   //title = el[@"tags"]
                    CLLocation *loc = [[LocationWithString alloc]initWithLatitude:lat longitude:lon title:poitype info:info2];
                    
                    [tpoiarray addObject:loc];
                    /*
                    MKPointAnnotation *ann = [[MKPointAnnotation alloc] init];
                    ann.title = @"Drinking Water";
                    ann.coordinate = CLLocationCoordinate2DMake(lat, lon);
                    //[self.mapView addAnnotation:ann];
                     */
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

- (void) setPoiloc:(NSArray<LocationWithString *> * _Nonnull)pl
{
    if (pl != _poiloc) {
        _poiloc = pl;
    }
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


@implementation LocationWithString

- (instancetype) initWithLatitude:(CLLocationDegrees)latitude longitude:(CLLocationDegrees)longitude title:(NSString *)_title info:(NSDictionary *)dic
{
    self = [super initWithLatitude:latitude longitude:longitude];
    if (self) {
        title = _title;
        info = dic;
    }
    return self;
}

- (NSString *) title
{
    return title;
}
- (NSDictionary *) info
{
    return info;
}


+ (BOOL) supportsSecureCoding
{
    return YES;
}


- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:title forKey:@"title"];
    [coder encodeObject:info forKey:@"info"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) return self;
    title = [coder decodeObjectOfClass:[NSString class] forKey:@"title"];
    info = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"info"];
    return self;
}

@end
