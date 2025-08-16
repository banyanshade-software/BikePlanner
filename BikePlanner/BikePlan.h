//
//  BikePlan.h
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "RouteAnnotation.h"
#import "TaggedPoly.h"

NS_ASSUME_NONNULL_BEGIN


@interface BikePlan : NSObject <NSSecureCoding> {
    //NSMutableArray <RouteAnnotation *>*waypointsRouteAnnotations;
    //NSArray<CLLocation *> *routePoints;
    //MKPolyline *gpxpoly; // loaded gpx, just displayed
    //MKPointAnnotation *scrubberMarker;
}

@property (readonly,nonatomic) NSArray <CLLocation *>*waypointsLocations;
@property (strong,nonatomic) NSArray<CLLocation *> *routePoints;
@property (strong,nonatomic) NSArray<CLLocation *> *gpxDisplayed;

- (void) removeWaypoints;
- (void) appendWaypoint:(CLLocation *)loc;
- (void) insertWaypoint:(CLLocation *)loc atIndex:(NSUInteger)idx;
- (void) replaceWaypointAtIndex:(NSUInteger)idx by:(CLLocation *)loc;

@property (readonly,nonatomic) TaggedPoly *routePoly;    // MKPolyLine with a tag, 0
@property (readonly,nonatomic) TaggedPoly *waypointPoly; // MKPolyLine with a tag, 1


@end

NS_ASSUME_NONNULL_END
