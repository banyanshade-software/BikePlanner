//
//  POIFetchTests.m
//  BikePlannerTests
//
//  BikePlan POI fetching (Overpass) against the local stub server: query, parsing, throttling, retry.
//

#import <XCTest/XCTest.h>
#import "BikePlan.h"
#import "POILocation.h"
#import "BPStubServer.h"
#import "TestFixtures.h"

@interface POIFetchTests : XCTestCase
@end

@implementation POIFetchTests {
    BPStubServer *server;
    BikePlan *plan;
    NSInteger callbacks;
}

- (void)setUp
{
    server = [[BPStubServer alloc] init];
    XCTAssertTrue([server start]);
    BPOverrideDefaults(@{ @"BPOverpassURL": server.overpassURL.absoluteString });
    plan = [[BikePlan alloc] init];
    callbacks = 0;
    __weak POIFetchTests *weakSelf = self;
    plan.poiAvailableCallback = ^{
        POIFetchTests *s = weakSelf;
        if (s) s->callbacks++;
    };
}

- (void)tearDown
{
    plan.fetchPOI = NO;
    BPSpin(0.1);
    [server stop];
    BPRestoreDefaults();
}

- (NSArray<CLLocation *> *)route
{
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < 25; i++) [a addObject:BPLoc(44.0 + i * 0.001, 0.5 + i * 0.001)];
    return a;
}

- (NSArray<BPStubRequest *> *)overpassRequests
{
    return [server requestsWithPath:@"/api/interpreter"];
}

- (void)testFetchAndParse
{
    plan.routePoints = [self route];
    (void)plan.routePoly; // triggers the request
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks > 0); }));

    BPStubRequest *r = [self overpassRequests].firstObject;
    XCTAssertEqualObjects(r.method, @"POST");
    XCTAssertTrue([r.body hasPrefix:@"[out:json]"]);
    XCTAssertTrue([r.body containsString:@"around:1500,44.000000,0.500000"]);
    // one point out of 10 is sampled: 25 points -> 0, 10, 20
    XCTAssertEqual([r.body componentsSeparatedByString:@"node(around"].count - 1, 3u);
    XCTAssertEqual([r.body componentsSeparatedByString:@"way(around"].count - 1, 3u);

    XCTAssertEqual(plan.poiloc.count, 3u);
    NSArray *types = [plan.poiloc valueForKey:@"poiType"];
    XCTAssertTrue([types containsObject:@(POI_drinking_water)]);
    XCTAssertTrue([types containsObject:@(POI_toilets)]);
    XCTAssertTrue([types containsObject:@(POI_cemetery)]);
    POILocation *water = [plan.poiloc filteredArrayUsingPredicate:
                          [NSPredicate predicateWithFormat:@"poiType == %d", POI_drinking_water]].firstObject;
    XCTAssertEqualObjects(water.info[@"amenity"], @"drinking_water");
    XCTAssertEqualObjects(water.info[@"id"], @1001);
}

- (void)testNoFetchWhenDisabled
{
    plan.fetchPOI = NO;
    plan.routePoints = [self route];
    (void)plan.routePoly;
    BPSpin(1.0);
    XCTAssertEqual([self overpassRequests].count, 0u);
    XCTAssertEqual(callbacks, 0);
}

- (void)testEnablingFetchTriggersRequest
{
    plan.fetchPOI = NO;
    plan.routePoints = [self route];
    (void)plan.routePoly;
    plan.fetchPOI = YES;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks > 0); }));
    XCTAssertEqual([self overpassRequests].count, 1u);
}

- (void)testNoFetchWithLessThanTwoPoints
{
    plan.routePoints = @[BPLoc(44, 0.5)];
    (void)plan.routePoly;
    BPSpin(1.0);
    XCTAssertEqual([self overpassRequests].count, 0u);
}

// tryRequestPoi: at most one request every ~2.8 s, later needs are coalesced by a timer
- (void)testThrottling
{
    plan.routePoints = [self route];
    for (int i = 0; i < 5; i++) (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks > 0); }));
    BPSpin(1.0);
    XCTAssertEqual([self overpassRequests].count, 1u, @"burst must give a single request");

    // the coalesced need is served by the retry timer, ~2.8 s after the first request
    XCTAssertTrue(BPWaitUntil(6, ^{ return (BOOL)([self overpassRequests].count >= 2); }));
    BPSpin(3.5);
    XCTAssertEqual([self overpassRequests].count, 2u, @"no more requests once served");
}

// Retry after an HTTP error. The retry is scheduled with performSelector:afterDelay: from the
// NSURLSession completion queue, which has no run loop — check whether it really happens.
- (void)testRetryAfterHTTPError
{
    server.failCount = 1;
    plan.routePoints = [self route];
    (void)plan.routePoly;
    BOOL served = BPWaitUntil(8, ^{ return (BOOL)(self->callbacks > 0); });
    XCTExpectFailure(@"retry is scheduled on a thread without run loop (#12)");
    XCTAssertTrue(served);
    XCTAssertEqual([self overpassRequests].count, 2u);
}

@end
