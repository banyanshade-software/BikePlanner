//
//  BRouterClientTests.m
//  BikePlannerTests
//
//  BRouterClient against the local stub server.
//

#import <XCTest/XCTest.h>
#import "BRouterClient.h"
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

- (void)route:(NSArray<CLLocation *> *)wps extra:(NSString *)extra
         then:(void (^)(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error))check
{
    XCTestExpectation *done = [self expectationWithDescription:@"route"];
    [client routeWithWaypoints:wps profile:@"trekking" extraUrl:extra
                    completion:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        check(points, gpx, info, error);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:10];
}

- (void)testRouteRequestAndResult
{
    [self route:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] extra:nil
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqual(points.count, 11u);
        XCTAssertNotNil(gpx);
        XCTAssertNotNil(info[@"n-track-length-m"]);
        XCTAssertGreaterThan([info[@"n-track-length-m"] doubleValue], 10000);
    }];
    BPStubRequest *r = [server requestsWithPath:@"/brouter"].firstObject;
    XCTAssertEqualObjects(r.method, @"GET");
    XCTAssertEqualObjects(r.query[@"lonlats"], @"0.500000,44.000000|0.600000,44.100000");
    XCTAssertEqualObjects(r.query[@"profile"], @"trekking");
    XCTAssertEqualObjects(r.query[@"alternativeidx"], @"0");
    XCTAssertEqualObjects(r.query[@"format"], @"gpx");
}

- (void)testIntermediateWaypoints
{
    [self route:@[BPLoc(44.0, 0.5), BPLoc(44.05, 0.55), BPLoc(44.1, 0.6)] extra:nil
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertEqual(points.count, 21u);
    }];
    XCTAssertEqual([[server requestsWithPath:@"/brouter"].firstObject.query[@"lonlats"]
                    componentsSeparatedByString:@"|"].count, 3u);
}

- (void)testExtraParamsAreAppended
{
    [self route:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] extra:@"extraParams=profile:uphillcost%3D200"
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertNil(error);
    }];
    XCTAssertEqualObjects([server requestsWithPath:@"/brouter"].firstObject.query[@"extraParams"],
                          @"profile:uphillcost=200");
}

- (void)testServerUnreachableGivesError
{
    BRouterClient *c = [[BRouterClient alloc] initWithServerURL:[NSURL URLWithString:@"http://127.0.0.1:1"]];
    XCTestExpectation *done = [self expectationWithDescription:@"route"];
    [c routeWithWaypoints:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] profile:@"trekking" extraUrl:nil
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
    [self route:@[BPLoc(44.0, 0.5), BPLoc(44.1, 0.6)] extra:nil
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertEqual(points.count, 0u);
        XCTExpectFailure(@"HTTP status not checked by BRouterClient (#9)");
        XCTAssertNotNil(error);
    }];
}

// Known bug (#9): a BRouter error message (HTTP 400 text) is not reported as an error.
- (void)testSingleWaypointGivesError
{
    [self route:@[BPLoc(44.0, 0.5)] extra:nil
           then:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error) {
        XCTAssertEqual(points.count, 0u);
        XCTExpectFailure(@"HTTP status not checked by BRouterClient (#9)");
        XCTAssertNotNil(error);
    }];
}

@end
