//
//  BikePlan.h
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "RouteAnnotation.h"

NS_ASSUME_NONNULL_BEGIN

@interface BikePlan : NSObject <NSSecureCoding> {
    NSMutableArray <RouteAnnotation *>*waypointsRouteAnnotations;
    //NSArray<CLLocation *> *routePoints;
    MKPolyline *poly; // route being built
    MKPolyline *gpxpoly; // loaded gpx, just displayed
    MKPointAnnotation *scrubberMarker;
}

@property (strong,nonatomic) NSMutableArray <CLLocation *>*waypointsLocations;
@property (strong,nonatomic) NSArray<CLLocation *> *routePoints;
@property (strong,nonatomic) NSArray<CLLocation *> *gpxDisplayed;



@end

NS_ASSUME_NONNULL_END
