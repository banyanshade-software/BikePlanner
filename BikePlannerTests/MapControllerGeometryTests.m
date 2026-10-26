//
//  MapControllerGeometryTests.m
//  BikePlannerTests
//
//  Pure geometry helpers of MapController (private methods, exposed through a test category).
//  They do not need a map view, only document.plan.routePoints for the route-based ones.
//

#import <XCTest/XCTest.h>
#import "MapController.h"
#import "Document.h"
#import "BikePlan.h"
#import "TestFixtures.h"

@interface MapController (GeometryTesting)
- (double)bearingFrom:(CLLocationCoordinate2D)p1 to:(CLLocationCoordinate2D)p2;
- (double)projectedDistanceAlongPolyline:(MKPolyline *)polyline forCoordinate:(CLLocationCoordinate2D)coord;
- (NSUInteger)insertionIndexForCoordinate:(CLLocationCoordinate2D)coord
                                 polyline:(MKPolyline *)polyline
                                waypoints:(NSArray<CLLocation *> *)waypoints;
- (CLLocationCoordinate2D)coordinateAtDistance:(double)targetDist;
- (double)bearingAtDistance:(double)distanceAlongRoute;
- (CLLocationDistance)distanceAtCoordinate:(CLLocationCoordinate2D)coord segstart:(NSUInteger *)psegstart;
@end

static MKPolyline *BPPoly(NSArray<CLLocation *> *pts)
{
    CLLocationCoordinate2D c[pts.count];
    for (NSUInteger i = 0; i < pts.count; i++) c[i] = pts[i].coordinate;
    return [MKPolyline polylineWithCoordinates:c count:pts.count];
}

@interface MapControllerGeometryTests : XCTestCase
@end

@implementation MapControllerGeometryTests {
    Document *doc;      // strong: MapController.document is weak
    MapController *mc;
}

- (void)setUp
{
    doc = [[Document alloc] init];
    doc.plan.fetchPOI = NO;
    mc = [[MapController alloc] init];
    mc.document = doc;
}

#pragma mark - bearing

- (void)testBearingCardinalDirections
{
    CLLocationCoordinate2D o = CLLocationCoordinate2DMake(0, 0);
    XCTAssertEqualWithAccuracy([mc bearingFrom:o to:CLLocationCoordinate2DMake(1, 0)], 0, 1e-6);
    XCTAssertEqualWithAccuracy([mc bearingFrom:o to:CLLocationCoordinate2DMake(0, 1)], 90, 1e-6);
    XCTAssertEqualWithAccuracy([mc bearingFrom:o to:CLLocationCoordinate2DMake(-1, 0)], 180, 1e-6);
    XCTAssertEqualWithAccuracy([mc bearingFrom:o to:CLLocationCoordinate2DMake(0, -1)], 270, 1e-6);
}

#pragma mark - projection on polyline

- (void)testProjectedDistanceAlongPolyline
{
    MKPolyline *poly = BPPoly(@[BPLoc(0, 0), BPLoc(0, 0.1)]);
    double d = [mc projectedDistanceAlongPolyline:poly forCoordinate:CLLocationCoordinate2DMake(0.001, 0.05)];
    double expected = [BPLoc(0, 0) distanceFromLocation:BPLoc(0, 0.05)];
    XCTAssertEqualWithAccuracy(d, expected, expected * 0.01);
}

- (void)testInsertionIndex
{
    NSArray *wps = @[BPLoc(0, 0), BPLoc(0, 0.1), BPLoc(0, 0.2)];
    MKPolyline *poly = BPPoly(wps);
    XCTAssertEqual([mc insertionIndexForCoordinate:CLLocationCoordinate2DMake(0, 0.05) polyline:poly waypoints:wps], 1u);
    XCTAssertEqual([mc insertionIndexForCoordinate:CLLocationCoordinate2DMake(0, 0.15) polyline:poly waypoints:wps], 2u);
    // start and end stay first / last
    XCTAssertEqual([mc insertionIndexForCoordinate:CLLocationCoordinate2DMake(0, -0.05) polyline:poly waypoints:wps], 1u);
    XCTAssertEqual([mc insertionIndexForCoordinate:CLLocationCoordinate2DMake(0, 0.25) polyline:poly waypoints:wps], 2u);
}

- (void)testInsertionIndexWithTwoWaypoints
{
    NSArray *wps = @[BPLoc(0, 0), BPLoc(0, 0.2)];
    MKPolyline *poly = BPPoly(@[BPLoc(0, 0), BPLoc(0, 0.1), BPLoc(0, 0.2)]);
    XCTAssertEqual([mc insertionIndexForCoordinate:CLLocationCoordinate2DMake(0, 0.1) polyline:poly waypoints:wps], 1u);
}

#pragma mark - route-based helpers

// Works on the first segment (no ambiguity).
- (void)testDistanceAtCoordinateOnFirstSegment
{
    [self setEastThenNorthRoute];
    NSUInteger seg = 99;
    double d = [mc distanceAtCoordinate:CLLocationCoordinate2DMake(0, 0.05) segstart:&seg];
    XCTAssertEqualWithAccuracy(d, [BPLoc(0, 0) distanceFromLocation:BPLoc(0, 0.05)], 1.0);
    XCTAssertEqual(seg, 0u);
}

- (void)setEastThenNorthRoute
{
    // east along the equator, then north
    doc.plan.routePoints = @[BPLoc(0, 0), BPLoc(0, 0.1), BPLoc(0.1, 0.1)];
}

- (void)testCoordinateAtDistance
{
    [self setEastThenNorthRoute];
    double seg1 = [BPLoc(0, 0) distanceFromLocation:BPLoc(0, 0.1)];
    CLLocationCoordinate2D c = [mc coordinateAtDistance:seg1 / 2];
    XCTAssertEqualWithAccuracy(c.latitude, 0, 1e-6);
    XCTAssertEqualWithAccuracy(c.longitude, 0.05, 1e-4);
    // beyond the end: last point
    c = [mc coordinateAtDistance:1e9];
    XCTAssertEqualWithAccuracy(c.latitude, 0.1, 1e-9);
    XCTAssertEqualWithAccuracy(c.longitude, 0.1, 1e-9);
}

- (void)testBearingAtDistance
{
    [self setEastThenNorthRoute];
    double seg1 = [BPLoc(0, 0) distanceFromLocation:BPLoc(0, 0.1)];
    XCTAssertEqualWithAccuracy([mc bearingAtDistance:seg1 / 2], 90, 0.1);
    XCTAssertEqualWithAccuracy([mc bearingAtDistance:seg1 + 100], 0, 0.1);
    XCTAssertEqualWithAccuracy([mc bearingAtDistance:1e9], 0, 0.1);
}

// Known bug: distanceAtCoordinate:segstart: picks the FIRST segment on which the point projects
// (0 <= t <= 1) instead of the NEAREST segment, so a point on segment 2 is reported at the end of segment 1.
- (void)testDistanceAtCoordinate
{
    XCTExpectFailure(@"distanceAtCoordinate picks first projecting segment, not nearest (MapController.m)");
    [self setEastThenNorthRoute];
    double seg1 = [BPLoc(0, 0) distanceFromLocation:BPLoc(0, 0.1)];
    double half2 = [BPLoc(0, 0.1) distanceFromLocation:BPLoc(0.05, 0.1)];
    NSUInteger seg = 99;
    double d = [mc distanceAtCoordinate:CLLocationCoordinate2DMake(0.05, 0.1) segstart:&seg];
    XCTAssertEqualWithAccuracy(d, seg1 + half2, 1.0);
    XCTAssertEqual(seg, 1u);
}

- (void)testDistanceAndCoordinateAreInverse
{
    XCTExpectFailure(@"distanceAtCoordinate picks first projecting segment, not nearest (MapController.m)");
    [self setEastThenNorthRoute];
    for (double target = 500; target < 20000; target += 2500) {
        CLLocationCoordinate2D c = [mc coordinateAtDistance:target];
        NSUInteger seg = 0;
        XCTAssertEqualWithAccuracy([mc distanceAtCoordinate:c segstart:&seg], target, 5.0, @"target %g", target);
    }
}

@end
