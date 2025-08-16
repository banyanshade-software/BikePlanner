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
}

- (instancetype)init
{
    self = [super init];
    if (!self) return self;
    
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
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) return self;
    self.waypointsLocations = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [CLLocation class], nil] forKey:@"waypointsLocations"];
    self.routePoints = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [CLLocation class], nil] forKey:@"routePoints"];
    self.gpxDisplayed = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [CLLocation class], nil] forKey:@"gpxDisplayed"];
    return self;
}
@end
