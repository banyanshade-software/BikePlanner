//
//  GPXParserTests.m
//  BikePlannerTests
//

#import <XCTest/XCTest.h>
#import "GPXParser.h"
#import "TestFixtures.h"

@interface GPXParserTests : XCTestCase
@end

@implementation GPXParserTests

- (void)testParsesTrackPointsWithElevation
{
    GPXParser *p = [[GPXParser alloc] init];
    NSError *err = nil;
    NSArray<CLLocation *> *pts = [p parseGPXData:BPData(kBRouterGPX) error:&err];
    XCTAssertNil(err);
    XCTAssertEqual(pts.count, 3u);
    XCTAssertEqualWithAccuracy(pts[0].coordinate.latitude, 44.193329, 1e-9);
    XCTAssertEqualWithAccuracy(pts[0].coordinate.longitude, 0.491229, 1e-9);
    XCTAssertEqualWithAccuracy(pts[0].altitude, 140.25, 1e-9);
    XCTAssertEqualWithAccuracy(pts[1].altitude, 145.5, 1e-9);
    XCTAssertEqualWithAccuracy(pts[2].altitude, 143.0, 1e-9);
}

- (void)testParsesBRouterStatisticsComment
{
    GPXParser *p = [[GPXParser alloc] init];
    [p parseGPXData:BPData(kBRouterGPX) error:NULL];
    NSDictionary *bi = [p brouterInfo];
    XCTAssertEqualObjects(bi[@"track-length"], @"14994");
    XCTAssertEqualObjects(bi[@"filtered-ascend"], @"168");
    XCTAssertEqualObjects(bi[@"plain-ascend"], @"27");
    XCTAssertEqualObjects(bi[@"cost"], @"26496");
    // normalized values
    XCTAssertEqualObjects(bi[@"n-track-length-m"], @"14994");
    XCTAssertEqualObjects(bi[@"n-time-seconds"], @"3435"); // 57m 15s
    XCTAssertEqualObjects(bi[@"n-energy-wh"], @"100");      // .1 kWh
}

- (void)testTimeWithHours
{
    NSString *gpx = [kBRouterGPX stringByReplacingOccurrencesOfString:@"time=57m 15s"
                                                           withString:@"time=6h 10m 11s"];
    GPXParser *p = [[GPXParser alloc] init];
    [p parseGPXData:BPData(gpx) error:NULL];
    XCTAssertEqualObjects([p brouterInfo][@"n-time-seconds"], @"22211");
}

- (void)testNoCommentGivesNoBRouterInfo
{
    NSString *gpx = @"<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"/></trkseg></trk></gpx>";
    GPXParser *p = [[GPXParser alloc] init];
    NSArray *pts = [p parseGPXData:BPData(gpx) error:NULL];
    XCTAssertEqual(pts.count, 1u);
    XCTAssertNil([p brouterInfo]);
}

- (void)testEmptyDataIsAnError
{
    GPXParser *p = [[GPXParser alloc] init];
    NSError *err = nil;
    XCTAssertNil([p parseGPXData:[NSData data] error:&err]);
    XCTAssertNotNil(err);
}

- (void)testMalformedXMLIsAnError
{
    GPXParser *p = [[GPXParser alloc] init];
    NSError *err = nil;
    XCTAssertNil([p parseGPXData:BPData(@"<gpx><trk>") error:&err]);
    XCTAssertNotNil(err);
}

// The trace is the track; waypoints (e.g. POIs exported by BikePlanner) are kept apart (#28).
- (void)testWaypointsAreKeptOutOfTheTrack
{
    NSString *gpx = @"<gpx>"
                    @"<trk><trkseg><trkpt lat=\"1\" lon=\"1\"/><trkpt lat=\"2\" lon=\"2\"/></trkseg></trk>"
                    @"<wpt lat=\"10\" lon=\"10\"><name>w</name></wpt>"
                    @"</gpx>";
    GPXParser *p = [[GPXParser alloc] init];
    NSArray<CLLocation *> *pts = [p parseGPXData:BPData(gpx) error:NULL];
    XCTAssertEqual(pts.count, 2u);
    XCTAssertEqualWithAccuracy(pts[0].coordinate.latitude, 1, 1e-9);
    XCTAssertEqualWithAccuracy(pts[1].coordinate.latitude, 2, 1e-9);
    XCTAssertEqual(p.waypoints.count, 1u);
    XCTAssertEqualWithAccuracy(p.waypoints[0].coordinate.latitude, 10, 1e-9);
}

// without a track: the route points, then the waypoints, are the trace
- (void)testRouteOrWaypointsWhenNoTrack
{
    NSString *rte = @"<gpx><wpt lat=\"10\" lon=\"10\"/>"
                    @"<rte><rtept lat=\"1\" lon=\"1\"/><rtept lat=\"2\" lon=\"2\"/><rtept lat=\"3\" lon=\"3\"/></rte></gpx>";
    XCTAssertEqual([[[GPXParser alloc] init] parseGPXData:BPData(rte) error:NULL].count, 3u);
    NSString *wpt = @"<gpx><wpt lat=\"1\" lon=\"1\"/><wpt lat=\"2\" lon=\"2\"/></gpx>";
    XCTAssertEqual([[[GPXParser alloc] init] parseGPXData:BPData(wpt) error:NULL].count, 2u);
}

@end
