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

// Current behavior: waypoints and route points are merged with track points
// into a single list (see doc/02-architecture.md §9, item 14).
- (void)testWaypointsAreMergedWithTrackPoints
{
    NSString *gpx = @"<gpx>"
                    @"<wpt lat=\"10\" lon=\"10\"><name>w</name></wpt>"
                    @"<trk><trkseg><trkpt lat=\"1\" lon=\"1\"/><trkpt lat=\"2\" lon=\"2\"/></trkseg></trk>"
                    @"</gpx>";
    GPXParser *p = [[GPXParser alloc] init];
    NSArray<CLLocation *> *pts = [p parseGPXData:BPData(gpx) error:NULL];
    XCTAssertEqual(pts.count, 3u);
    XCTAssertEqualWithAccuracy(pts[0].coordinate.latitude, 10, 1e-9);
}

@end
