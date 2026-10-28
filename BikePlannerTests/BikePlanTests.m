//
//  BikePlanTests.m
//  BikePlannerTests
//
//  Model: waypoint mutators, cached polylines, NSSecureCoding round trip.
//  POI fetching is disabled (fetchPOI = NO) so that no network request is made.
//

#import <XCTest/XCTest.h>
#import "BikePlan.h"
#import "POILocation.h"
#import "TestFixtures.h"

@interface BikePlanTests : XCTestCase
@end

@implementation BikePlanTests {
    BikePlan *plan;
}

- (void)setUp
{
    plan = [[BikePlan alloc] init];
    plan.fetchPOI = NO;
}

- (BikePlan *)roundTrip:(BikePlan *)p
{
    NSError *err = nil;
    NSData *d = [NSKeyedArchiver archivedDataWithRootObject:p requiringSecureCoding:YES error:&err];
    XCTAssertNotNil(d, @"%@", err);
    BikePlan *r = [NSKeyedUnarchiver unarchivedObjectOfClass:[BikePlan class] fromData:d error:&err];
    XCTAssertNotNil(r, @"%@", err);
    r.fetchPOI = NO;
    return r;
}

#pragma mark - waypoints

- (void)testInitialState
{
    XCTAssertEqual(plan.waypointsLocations.count, 0u);
    XCTAssertNotNil(plan.brouterInfo);
    XCTAssertNotNil(plan.customPoiloc);
}

- (void)testMutatorsReturnPreviousArray
{
    CLLocation *a = BPLoc(44, 0.5), *b = BPLoc(44.1, 0.6), *c = BPLoc(44.05, 0.55), *d = BPLoc(44.2, 0.7);

    NSArray *old = [plan appendWaypoint:a];
    XCTAssertEqual(old.count, 0u);
    old = [plan appendWaypoint:b];
    XCTAssertEqualObjects(old, @[a]);
    XCTAssertEqualObjects(plan.waypointsLocations, (@[a, b]));

    old = [plan insertWaypoint:c atIndex:1];
    XCTAssertEqualObjects(old, (@[a, b]));
    XCTAssertEqualObjects(plan.waypointsLocations, (@[a, c, b]));

    old = [plan replaceWaypointAtIndex:2 by:d];
    XCTAssertEqualObjects(old, (@[a, c, b]));
    XCTAssertEqualObjects(plan.waypointsLocations, (@[a, c, d]));

    old = [plan removeWaypointAtIndex:1];
    XCTAssertEqualObjects(old, (@[a, c, d]));
    XCTAssertEqualObjects(plan.waypointsLocations, (@[a, d]));

    old = [plan removeWaypoints];
    XCTAssertEqualObjects(old, (@[a, d]));
    XCTAssertEqual(plan.waypointsLocations.count, 0u);
}

- (void)testReverseWaypoints
{
    CLLocation *a = BPLoc(44, 0.5), *b = BPLoc(44.05, 0.55), *c = BPLoc(44.1, 0.6);
    (void)[plan appendWaypoint:a]; (void)[plan appendWaypoint:b]; (void)[plan appendWaypoint:c];
    NSArray *old = [plan reverseWaypoints];
    XCTAssertEqualObjects(old, (@[a, b, c]));
    XCTAssertEqualObjects(plan.waypointsLocations, (@[c, b, a]));
}

- (void)testClearRouteKeepsReferenceTraceAndRestores
{
    CLLocation *a = BPLoc(44, 0.5), *b = BPLoc(44.1, 0.6);
    (void)[plan appendWaypoint:a]; (void)[plan appendWaypoint:b];
    plan.routePoints = @[a, BPLoc(44.05, 0.55), b];
    plan.brouterInfo.kmlen = 12; plan.brouterInfo.mup = 150;
    plan.brouterInfo.meters = 12345; plan.brouterInfo.seconds = 2400;
    [plan addCustomPoiAt:CLLocationCoordinate2DMake(44.05, 0.55)];
    plan.gpxDisplayed = @[a, b];

    NSDictionary *old = [plan clearRoute];
    XCTAssertEqual(plan.waypointsLocations.count, 0u);
    XCTAssertEqual(plan.routePoints.count, 0u);
    XCTAssertEqual(plan.brouterInfo.kmlen, 0);
    XCTAssertEqual(plan.brouterInfo.mup, 0);
    XCTAssertEqual(plan.brouterInfo.seconds, 0);
    XCTAssertEqual(plan.brouterInfo.meters, 0);
    XCTAssertEqual(plan.customPoiloc.count, 0u);
    XCTAssertEqual(plan.gpxDisplayed.count, 2u, @"reference trace kept");

    [plan restoreRoute:old];
    XCTAssertEqualObjects(plan.waypointsLocations, (@[a, b]));
    XCTAssertEqual(plan.routePoints.count, 3u);
    XCTAssertEqual(plan.brouterInfo.kmlen, 12);
    XCTAssertEqual(plan.brouterInfo.mup, 150);
    XCTAssertEqual(plan.brouterInfo.seconds, 2400);
    XCTAssertEqual(plan.brouterInfo.meters, 12345);
    XCTAssertEqual(plan.customPoiloc.count, 1u);
    (void)[plan appendWaypoint:BPLoc(44.2, 0.7)]; // still mutable after restore
    XCTAssertEqual(plan.waypointsLocations.count, 3u);
}

#pragma mark - riding time and average speed (#30)

- (void)testRidingTimeAndAverageSpeed
{
    BrouterInfo *bi = [[BrouterInfo alloc] init];
    XCTAssertEqualObjects(bi.durationText, @"–", @"no route");
    XCTAssertEqualObjects(bi.averageSpeedText, @"–");
    // real brouter.de answer, trekking profile: track-length = 48798 … time=2h 38m 43s
    bi.meters = 48798;
    bi.seconds = 2 * 3600 + 38 * 60 + 43;
    XCTAssertEqualObjects(bi.durationText, @"2 h 39");
    XCTAssertEqualWithAccuracy(bi.averageSpeed, 18.45, 0.01);
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.minimumFractionDigits = f.maximumFractionDigits = 1;
    XCTAssertEqualObjects(bi.averageSpeedText, [f stringFromNumber:@18.4]);
    bi.seconds = 45 * 60 + 20;
    XCTAssertEqualObjects(bi.durationText, @"45 min");
    bi.seconds = 3600 + 5 * 60;
    XCTAssertEqualObjects(bi.durationText, @"1 h 05");
}

// documents saved before #30 have no length in meters: the speed uses the length in km
- (void)testAverageSpeedWithoutMeters
{
    BrouterInfo *bi = [[BrouterInfo alloc] init];
    bi.kmlen = 30;
    bi.seconds = 7200;
    XCTAssertEqualWithAccuracy(bi.averageSpeed, 15, 1e-9);
}

#pragma mark - import GPX as route (#29)

static NSArray<CLLocation *> *BPLine(CLLocationCoordinate2D a, CLLocationCoordinate2D b, NSUInteger n)
{
    NSMutableArray *pts = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++) {
        double t = (double)i / (n - 1);
        [pts addObject:[[CLLocation alloc] initWithLatitude:a.latitude + t * (b.latitude - a.latitude)
                                                  longitude:a.longitude + t * (b.longitude - a.longitude)]];
    }
    return pts;
}

// a straight 10 km track: first and last points, plus points so that no gap exceeds the maximum spacing
- (void)testWaypointsForStraightTrace
{
    NSArray *trace = BPLine(CLLocationCoordinate2DMake(44.0, 0.5), CLLocationCoordinate2DMake(44.0, 0.625), 1001);
    NSArray<CLLocation *> *wps = [BikePlan waypointsForTrace:trace];
    XCTAssertEqualObjects(wps.firstObject, trace.firstObject);
    XCTAssertEqualObjects(wps.lastObject, trace.lastObject);
    XCTAssertGreaterThanOrEqual(wps.count, 5u);
    XCTAssertLessThanOrEqual(wps.count, 6u);
    for (NSUInteger i = 1; i < wps.count; i++) {
        XCTAssertLessThanOrEqual([wps[i] distanceFromLocation:wps[i-1]], kBPImportMaxSpacing + 10);
    }
}

// the corner of an L-shaped track is kept, the points on the straight parts are dropped
- (void)testWaypointsForTraceKeepCorner
{
    CLLocationCoordinate2D a = CLLocationCoordinate2DMake(44.0, 0.5), c = CLLocationCoordinate2DMake(44.0, 0.52),
                           b = CLLocationCoordinate2DMake(44.015, 0.52);
    NSMutableArray *trace = [BPLine(a, c, 100) mutableCopy];
    [trace addObjectsFromArray:[BPLine(c, b, 100) subarrayWithRange:NSMakeRange(1, 99)]];
    NSArray<CLLocation *> *wps = [BikePlan waypointsForTrace:trace];
    XCTAssertEqual(wps.count, 3u);
    XCTAssertEqualWithAccuracy(wps[1].coordinate.longitude, 0.52, 1e-9);
    XCTAssertEqualWithAccuracy(wps[1].coordinate.latitude, 44.0, 1e-9);
}

- (void)testWaypointsForShortTrace
{
    XCTAssertEqual([BikePlan waypointsForTrace:@[]].count, 0u);
    NSArray *one = @[ BPLoc(44, 0.5) ];
    XCTAssertEqualObjects([BikePlan waypointsForTrace:one], one);
    NSArray *two = @[ BPLoc(44, 0.5), BPLoc(44.001, 0.5) ];
    XCTAssertEqualObjects([BikePlan waypointsForTrace:two], two);
}

- (void)testPreviousArrayIsNotMutatedLater
{
    // undo relies on the returned array being a snapshot
    (void)[plan appendWaypoint:BPLoc(1, 1)];
    NSArray *snapshot = [plan appendWaypoint:BPLoc(2, 2)];
    (void)[plan appendWaypoint:BPLoc(3, 3)];
    XCTAssertEqual(snapshot.count, 1u);
}

- (void)testUndoSetWaypoints
{
    NSArray *old = [plan appendWaypoint:BPLoc(1, 1)];
    [plan undoSetWayPt:old];
    XCTAssertEqual(plan.waypointsLocations.count, 0u);
}

#pragma mark - polylines

- (void)testPolylineTags
{
    (void)[plan appendWaypoint:BPLoc(1, 1)];
    (void)[plan appendWaypoint:BPLoc(2, 2)];
    plan.routePoints = @[BPLoc(1, 1), BPLoc(1.5, 1.5), BPLoc(2, 2)];
    plan.gpxDisplayed = @[BPLoc(3, 3), BPLoc(4, 4)];
    XCTAssertEqual(plan.routePoly.tag, 0u);
    XCTAssertEqual(plan.routePoly.pointCount, 3u);
    XCTAssertEqual(plan.waypointPoly.tag, 1u);
    XCTAssertEqual(plan.waypointPoly.pointCount, 2u);
    XCTAssertEqual(plan.gpxDisplayedPoly.tag, 2u);
    XCTAssertEqual(plan.gpxDisplayedPoly.pointCount, 2u);
}

// Guard for the routePoly cache fix (doc/02-architecture.md §9 item 1):
// the polyline must follow routePoints changes.
- (void)testRoutePolyFollowsRoutePoints
{
    plan.routePoints = @[BPLoc(1, 1), BPLoc(2, 2)];
    XCTAssertEqual(plan.routePoly.pointCount, 2u);
    plan.routePoints = @[BPLoc(1, 1), BPLoc(2, 2), BPLoc(3, 3), BPLoc(4, 4)];
    XCTAssertEqual(plan.routePoly.pointCount, 4u);
}

- (void)testGpxDisplayedPolyFollowsGpxDisplayed
{
    plan.gpxDisplayed = @[BPLoc(1, 1), BPLoc(2, 2)];
    XCTAssertEqual(plan.gpxDisplayedPoly.pointCount, 2u);
    plan.gpxDisplayed = @[BPLoc(1, 1), BPLoc(2, 2), BPLoc(3, 3)];
    XCTAssertEqual(plan.gpxDisplayedPoly.pointCount, 3u);
}

#pragma mark - custom POI

- (void)testAddCustomPoi
{
    [plan addCustomPoiAt:CLLocationCoordinate2DMake(44, 0.5)];
    XCTAssertEqual(plan.customPoiloc.count, 1u);
    POILocation *p = plan.customPoiloc[0];
    XCTAssertEqual(p.poiType, POI_warning);
    XCTAssertEqualWithAccuracy(p.coordinate.latitude, 44, 1e-9);
}

#pragma mark - archiving

- (void)testArchiveRoundTrip
{
    (void)[plan appendWaypoint:BPLoc(44, 0.5)];
    (void)[plan appendWaypoint:BPLoc(44.1, 0.6)];
    plan.routePoints = @[BPLocAlt(44, 0.5, 100), BPLocAlt(44.05, 0.55, 150), BPLocAlt(44.1, 0.6, 120)];
    plan.gpxDisplayed = @[BPLoc(45, 1), BPLoc(45.1, 1.1)];
    plan.brouterInfo.kmlen = 15;
    plan.brouterInfo.mup = 168;
    plan.brouterInfo.meters = 14994;
    plan.brouterInfo.seconds = 3435;
    [plan addCustomPoiAt:CLLocationCoordinate2DMake(44.02, 0.52)];

    BikePlan *r = [self roundTrip:plan];
    XCTAssertEqual(r.waypointsLocations.count, 2u);
    XCTAssertEqualWithAccuracy(r.waypointsLocations[1].coordinate.longitude, 0.6, 1e-9);
    XCTAssertEqual(r.routePoints.count, 3u);
    XCTAssertEqualWithAccuracy(r.routePoints[1].altitude, 150, 1e-9);
    XCTAssertEqual(r.gpxDisplayed.count, 2u);
    XCTAssertEqual(r.brouterInfo.kmlen, 15);
    XCTAssertEqual(r.brouterInfo.mup, 168);
    XCTAssertEqual(r.brouterInfo.meters, 14994);
    XCTAssertEqual(r.brouterInfo.seconds, 3435);
    XCTAssertEqual(r.customPoiloc.count, 1u);
    XCTAssertEqual(r.customPoiloc[0].poiType, POI_warning);
}

// BRouter parameters are saved with the document (#44); none = the profile defaults
- (void)testProfileOverridesArchived
{
    XCTAssertEqualObjects(plan.profileOverrides, @{});
    XCTAssertEqualObjects(plan.profileName, @"trekking");
    XCTAssertEqualObjects([self roundTrip:plan].profileOverrides, @{}, @"none saved (documents before #44)");
    plan.profileOverrides = @{ @"bikerPower": @"80", @"avoid_unsafe": @"1" };
    XCTAssertEqualObjects([self roundTrip:plan].profileOverrides, (@{ @"bikerPower": @"80", @"avoid_unsafe": @"1" }));
    plan.profileOverrides = nil;
    XCTAssertEqualObjects(plan.profileOverrides, @{});
}

- (void)testCustomPoiCanBeAddedAfterLoad
{
    [plan addCustomPoiAt:CLLocationCoordinate2DMake(44, 0.5)];
    BikePlan *r = [self roundTrip:plan];
    [r addCustomPoiAt:CLLocationCoordinate2DMake(44.1, 0.6)];
    XCTAssertEqual(r.customPoiloc.count, 2u);
}

- (void)testEmptyPlanRoundTrip
{
    BikePlan *r = [self roundTrip:plan];
    XCTAssertEqual(r.waypointsLocations.count, 0u);
    XCTAssertNotNil(r.brouterInfo);
    XCTAssertNotNil(r.customPoiloc);
    [r addCustomPoiAt:CLLocationCoordinate2DMake(44.1, 0.6)];
    XCTAssertEqual(r.customPoiloc.count, 1u);
}

@end
