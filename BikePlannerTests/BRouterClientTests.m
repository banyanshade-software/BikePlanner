//
//  BRouterClientTests.m
//  BikePlannerTests
//
//  BRouterClient against the local stub server.
//

#import <XCTest/XCTest.h>
#import "BRouterClient.h"
#import "GPXParser.h"
#import "BPStubServer.h"
#import "TestFixtures.h"

@interface BRouterClientTests : XCTestCase
@end

@implementation BRouterClientTests {
    BPStubServer *server;
    BRouterClient *client;
}

- (void)setUp
{
    server = [[BPStubServer alloc] init];
    XCTAssertTrue([server startInProcess]);
    client = [[BRouterClient alloc] initWithServerURL:server.baseURL];
}

- (void)tearDown
{
    [server stop];
}

- (void)route:(NSArray<CLLocation *> *)wps overrides:(NSDictionary *)overrides
         then:(void (^)(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error))check
{
    XCTestExpectation *done = [self expectationWithDescription:@"route"];
    [client routeWithWaypoints:wps profile:@"trekking" overrides:overrides
                    completion:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        check(points, gpx, info, error);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:10];
}

- (void)testRouteRequestAndResult
{
    [self route:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] overrides:nil
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqual(points.count, 11u);
        XCTAssertNotNil(gpx);
        XCTAssertNotNil(info[@"n-track-length-m"]);
        XCTAssertGreaterThan([info[@"n-track-length-m"] doubleValue], 10000);
        // distance by road / surface class (#53): the stub gives half tertiary/asphalt, half track/gravel
        NSDictionary *roads = info[@"road-stats"];
        XCTAssertGreaterThan([roads[@"tertiary"] doubleValue], 0);
        XCTAssertGreaterThan([roads[@"track"] doubleValue], 0);
        XCTAssertEqualWithAccuracy([[roads.allValues valueForKeyPath:@"@sum.doubleValue"] doubleValue],
                                   [info[@"n-track-length-m"] doubleValue], 1);
        XCTAssertGreaterThan([info[@"surface-stats"][@"unpaved"] doubleValue], 0);
        // GPX for the export, built from the points
        NSArray *gpxPoints = [[[GPXParser alloc] init] parseGPXData:gpx error:NULL];
        XCTAssertEqual(gpxPoints.count, 11u);
    }];
    BPStubRequest *r = [server requestsWithPath:@"/brouter"].firstObject;
    XCTAssertEqualObjects(r.method, @"GET");
    XCTAssertEqualObjects(r.query[@"lonlats"], @"0.500000,44.000000|0.600000,44.100000");
    XCTAssertEqualObjects(r.query[@"profile"], @"trekking");
    XCTAssertEqualObjects(r.query[@"alternativeidx"], @"0");
    XCTAssertEqualObjects(r.query[@"format"], @"geojson", @"way tags for the road types (#53)");
}

- (void)testIntermediateWaypoints
{
    [self route:@[BPLoc(44.0, 0.5), BPLoc(44.05, 0.55), BPLoc(44.1, 0.6)] overrides:nil
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertEqual(points.count, 21u);
    }];
    XCTAssertEqual([[server requestsWithPath:@"/brouter"].firstObject.query[@"lonlats"]
                    componentsSeparatedByString:@"|"].count, 3u);
}

// profile parameter overrides: one top-level "profile:<name>=<value>" parameter each — what BRouter reads
// ("extraParams=…" is ignored by brouter.de) (#15, #35)
- (void)testProfileOverridesAreQueryParameters
{
    [self route:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] overrides:@{ @"uphillcost": @"200", @"avoid_unsafe": @"true" }
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertNil(error);
    }];
    NSDictionary *q = [server requestsWithPath:@"/brouter"].firstObject.query;
    XCTAssertEqualObjects(q[@"profile:uphillcost"], @"200");
    XCTAssertEqualObjects(q[@"profile:avoid_unsafe"], @"1");
    XCTAssertNil(q[@"extraParams"]);
    XCTAssertEqualObjects(q[@"profile"], @"trekking");
}

// booleans are sent as 1/0: brouter.de answers HTTP 500 to profile:<name>=true/false (#38)
- (void)testBooleanOverridesSentAsNumbers
{
    NSURL *u = [BRouterClient routeURLForServer:[NSURL URLWithString:@"https://brouter.de"]
                                      waypoints:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] profile:@"trekking"
                                      overrides:@{ @"a": @"true", @"b": @"false", @"c": @"TRUE", @"d": @"truex" }];
    XCTAssertTrue([u.query hasSuffix:@"&profile:a=1&profile:b=0&profile:c=1&profile:d=truex"], @"%@", u.query);
}

// values are percent-encoded: "&", "=", spaces or "|" can neither split the query nor make the URL invalid
- (void)testOverrideValuesAreEncoded
{
    [self route:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] overrides:@{ @"x": @"a b&c=d|e+f" }
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertNil(error);
    }];
    NSDictionary *q = [server requestsWithPath:@"/brouter"].firstObject.query;
    XCTAssertEqualObjects(q[@"profile:x"], @"a b&c=d|e+f");
    XCTAssertNil(q[@"c"]);
}

- (void)testRouteURL
{
    NSURL *u = [BRouterClient routeURLForServer:[NSURL URLWithString:@"https://brouter.de"]
                                      waypoints:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] profile:@"trekking"
                                      overrides:@{ @"b": @"2", @"a": @"1" }];
    XCTAssertEqualObjects(u.absoluteString, @"https://brouter.de/brouter?lonlats=0.500000,44.000000%7C0.600000,44.100000"
                          @"&profile=trekking&alternativeidx=0&format=geojson&profile:a=1&profile:b=2", @"overrides sorted by name");
}

- (void)testServerUnreachableGivesError
{
    BRouterClient *c = [[BRouterClient alloc] initWithServerURL:[NSURL URLWithString:@"http://127.0.0.1:1"]];
    XCTestExpectation *done = [self expectationWithDescription:@"route"];
    [c routeWithWaypoints:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] profile:@"trekking" overrides:nil
               completion:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertNotNil(error);
        XCTAssertNil(points);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:10];
}

// Known bug (#9): an HTTP error status is not reported as an error.
- (void)testHTTPErrorGivesError
{
    server.failCount = 1;
    [self route:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] overrides:nil
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertEqual(points.count, 0u);
        XCTExpectFailure(@"HTTP status not checked by BRouterClient (#9)");
        XCTAssertNotNil(error);
    }];
}

// Known bug (#9): a BRouter error message (HTTP 400 text) is not reported as an error.
- (void)testSingleWaypointGivesError
{
    [self route:@[BPLoc(44.0, 0.5)] overrides:nil
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertEqual(points.count, 0u);
        XCTExpectFailure(@"HTTP status not checked by BRouterClient (#9)");
        XCTAssertNotNil(error);
    }];
}

@end
