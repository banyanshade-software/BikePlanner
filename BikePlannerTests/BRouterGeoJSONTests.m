//
//  BRouterGeoJSONTests.m
//  BikePlannerTests
//
//  Route in BRouter GeoJSON (format=geojson): points, statistics, distance by road / surface class (#53).
//

#import <XCTest/XCTest.h>
#import "BRouterGeoJSON.h"
#import "TestFixtures.h"

// same structure as a brouter.de answer (values are strings, coordinates [lon, lat, ele])
static NSString *const kBRouterGeoJSON =
    @"{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{"
    @"\"creator\":\"BRouter-1.7.11-beta\",\"name\":\"brouter_trekking_0\",\"track-length\":\"3658\","
    @"\"filtered ascend\":\"62\",\"plain-ascend\":\"-5\",\"total-time\":\"889\",\"total-energy\":\"85380\",\"cost\":\"18291\","
    @"\"messages\":["
    @"[\"Longitude\",\"Latitude\",\"Elevation\",\"Distance\",\"CostPerKm\",\"ElevCost\",\"TurnCost\",\"NodeCost\",\"InitialCost\",\"WayTags\",\"NodeTags\",\"Time\",\"Energy\"],"
    @"[\"500770\",\"43999594\",\"178\",\"140\",\"5050\",\"0\",\"17\",\"0\",\"0\",\"reversedirection=yes highway=path\",\"\",\"29\",\"2903\"],"
    @"[\"501000\",\"44000000\",\"180\",\"1500\",\"1000\",\"0\",\"0\",\"0\",\"0\",\"highway=tertiary surface=asphalt\",\"\",\"300\",\"2903\"],"
    @"[\"502000\",\"44005000\",\"185\",\"1000\",\"1000\",\"0\",\"0\",\"0\",\"0\",\"highway=track tracktype=grade2 surface=gravel\",\"\",\"300\",\"2903\"],"
    @"[\"503000\",\"44009000\",\"190\",\"1018\",\"1000\",\"0\",\"0\",\"0\",\"0\",\"highway=unclassified\",\"\",\"260\",\"2903\"]],"
    @"\"times\":[0,29,329,629,889]},"
    @"\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[0.501237,44.000691,172.0],[0.501136,43.999777,172.75],"
    @"[0.501,44.0,180.0],[0.502,44.005,185.0],[0.503,44.009,190.0]]}}]}";

@interface BRouterGeoJSONTests : XCTestCase
@end

@implementation BRouterGeoJSONTests

- (void)testParseRoute
{
    NSError *err = nil;
    BRouterGeoJSON *r = [BRouterGeoJSON routeWithData:BPData(kBRouterGeoJSON) error:&err];
    XCTAssertNotNil(r, @"%@", err);
    XCTAssertEqual(r.points.count, 5u);
    XCTAssertEqualWithAccuracy(r.points[1].coordinate.latitude, 43.999777, 1e-9);
    XCTAssertEqualWithAccuracy(r.points[1].coordinate.longitude, 0.501136, 1e-9);
    XCTAssertEqualWithAccuracy(r.points[1].altitude, 172.75, 1e-9);
    // same keys as the GPX comment parser
    XCTAssertEqualObjects(r.info[@"n-track-length-m"], @"3658");
    XCTAssertEqualObjects(r.info[@"filtered-ascend"], @"62");
    XCTAssertEqualObjects(r.info[@"n-time-seconds"], @"889");
}

- (void)testDistanceByRoadAndSurface
{
    BRouterGeoJSON *r = [BRouterGeoJSON routeWithData:BPData(kBRouterGeoJSON) error:NULL];
    XCTAssertEqualObjects(r.roadStats, (@{ BPRoadPath: @140, BPRoadTertiary: @1500, BPRoadTrack: @1000, BPRoadSmall: @1018 }));
    XCTAssertEqualObjects(r.surfaceStats, (@{ BPSurfaceUnknown: @1158, BPSurfacePaved: @1500, BPSurfaceUnpaved: @1000 }));
    double total = [[r.roadStats.allValues valueForKeyPath:@"@sum.doubleValue"] doubleValue];
    XCTAssertEqual(total, 3658, @"= track length");
}

- (void)testClasses
{
    NSDictionary *cases = @{ @"cycleway": BPRoadCycleway, @"footway": BPRoadPath, @"steps": BPRoadPath,
                             @"track": BPRoadTrack, @"residential": BPRoadSmall, @"service": BPRoadSmall,
                             @"tertiary_link": BPRoadTertiary, @"secondary": BPRoadSecondary,
                             @"primary": BPRoadPrimary, @"trunk": BPRoadPrimary, @"motorway": BPRoadOther };
    for (NSString *h in cases) {
        XCTAssertEqualObjects([BRouterGeoJSON roadClassForTags:@{ @"highway": h }], cases[h], @"%@", h);
    }
    XCTAssertEqualObjects([BRouterGeoJSON roadClassForTags:@{ @"route": @"ferry" }], BPRoadOther);
    XCTAssertEqualObjects([BRouterGeoJSON surfaceClassForTags:@{ @"surface": @"asphalt" }], BPSurfacePaved);
    XCTAssertEqualObjects([BRouterGeoJSON surfaceClassForTags:@{ @"surface": @"concrete:plates" }], BPSurfacePaved);
    XCTAssertEqualObjects([BRouterGeoJSON surfaceClassForTags:@{ @"surface": @"fine_gravel" }], BPSurfaceUnpaved);
    XCTAssertEqualObjects([BRouterGeoJSON surfaceClassForTags:@{}], BPSurfaceUnknown);
}

- (void)testNotARoute
{
    NSError *err = nil;
    XCTAssertNil([BRouterGeoJSON routeWithData:BPData(@"{\"type\":\"FeatureCollection\",\"features\":[]}") error:&err]);
    XCTAssertNotNil(err);
    err = nil;
    XCTAssertNil([BRouterGeoJSON routeWithData:BPData(@"lonlats must contain at least 2 points") error:&err]);
    XCTAssertNotNil(err);
}

@end
