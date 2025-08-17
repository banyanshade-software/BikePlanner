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

@interface BrouterInfo : NSObject <NSSecureCoding> {
}

@property NSInteger kmlen;
@property NSInteger mup;

@end

@interface LocationWithString : CLLocation <NSSecureCoding> {
    NSString *title;
    NSDictionary *info;
}
@property (nonatomic,readonly) NSString *title;
@property (nonatomic,readonly) NSDictionary *info;

- (instancetype) initWithLatitude:(CLLocationDegrees)latitude longitude:(CLLocationDegrees)longitude title:(NSString *)title info:(NSDictionary *)info;
@end

#pragma mark -


@interface BikePlan : NSObject <NSSecureCoding> {
 
}

@property (readonly,nonatomic) NSArray <CLLocation *>*waypointsLocations;
@property (strong,nonatomic) NSArray<CLLocation *> *routePoints;
@property (strong,nonatomic) NSArray<CLLocation *> *gpxDisplayed;
@property (strong,nonatomic) BrouterInfo *brouterInfo;

@property (nonatomic, copy) void (^poiAvailableCallback)(void);

- (void) removeWaypoints;
- (void) removeWaypointAtIndex:(NSUInteger)idx;
- (void) appendWaypoint:(CLLocation *)loc;
- (void) insertWaypoint:(CLLocation *)loc atIndex:(NSUInteger)idx;
- (void) replaceWaypointAtIndex:(NSUInteger)idx by:(CLLocation *)loc;

@property (readonly,nonatomic) TaggedPoly *routePoly;    // MKPolyLine with a tag, 0
@property (readonly,nonatomic) TaggedPoly *waypointPoly; // MKPolyLine with a tag, 1
@property (readonly,nonatomic) TaggedPoly *gpxDisplayedPoly; // MKPolyLine with a tag, 2


@end

NS_ASSUME_NONNULL_END
