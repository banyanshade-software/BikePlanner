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
    [plan addCustomPoiAt:CLLocationCoordinate2DMake(44.02, 0.52)];

    BikePlan *r = [self roundTrip:plan];
    XCTAssertEqual(r.waypointsLocations.count, 2u);
    XCTAssertEqualWithAccuracy(r.waypointsLocations[1].coordinate.longitude, 0.6, 1e-9);
    XCTAssertEqual(r.routePoints.count, 3u);
    XCTAssertEqualWithAccuracy(r.routePoints[1].altitude, 150, 1e-9);
    XCTAssertEqual(r.gpxDisplayed.count, 2u);
    XCTAssertEqual(r.brouterInfo.kmlen, 15);
    XCTAssertEqual(r.brouterInfo.mup, 168);
    XCTAssertEqual(r.customPoiloc.count, 1u);
    XCTAssertEqual(r.customPoiloc[0].poiType, POI_warning);
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
