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
#import "BPEnvironment.h"

// private (#12)
@interface BikePlan (POITesting)
@property (nonatomic) NSTimeInterval poiMinRequestInterval;
@property (nonatomic) NSTimeInterval poiRetryBaseDelay;
@property (nonatomic) NSUInteger poiMaxRetries;
+ (NSArray<CLLocation *> *)samplePointsForPOI:(NSArray<CLLocation *> *)points;
@end

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
    XCTAssertTrue([server startInProcess]);
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
    XCTAssertEqualObjects(r.userAgent, [BPEnvironment userAgent]);
    // route sampled every ≥ 1 km (#12): 25 points ~140 m apart (3.3 km) -> points 0, 8, 16 and the last one
    XCTAssertEqual([r.body componentsSeparatedByString:@"node(around"].count - 1, 4u);
    XCTAssertEqual([r.body componentsSeparatedByString:@"way(around"].count - 1, 4u);
    XCTAssertTrue([r.body containsString:@"node(around:1500,44.000000,0.500000)"]);
    XCTAssertTrue([r.body containsString:@"node(around:1500,44.024000,0.524000)"]);

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
    // a burst of route changes (reading routePoly again without a change asks nothing: cached, #6)
    for (int i = 0; i < 5; i++) {
        plan.routePoints = [self route];
        (void)plan.routePoly;
        (void)plan.routePoly;
    }
    BPSpin(1.0);
    XCTAssertEqual([self overpassRequests].count, 1u, @"burst must give a single request");

    // the coalesced need is served by the retry timer, ~2.8 s after the first request; the answer of the first
    // request is for an older route of the burst: ignored (#12)
    XCTAssertTrue(BPWaitUntil(6, ^{ return (BOOL)(self->callbacks > 0); }));
    XCTAssertEqual([self overpassRequests].count, 2u);
    BPSpin(3.5);
    XCTAssertEqual([self overpassRequests].count, 2u, @"no more requests once served");
    XCTAssertEqual(callbacks, 1, @"POIs of the last route only");
}

// Retry after an HTTP error, on the main run loop (it was scheduled from the NSURLSession completion queue, which
// has no run loop: it never happened, #12)
- (void)testRetryAfterHTTPError
{
    server.failCount = 1;
    plan.routePoints = [self route];
    (void)plan.routePoly;
    BOOL served = BPWaitUntil(8, ^{ return (BOOL)(self->callbacks > 0); });
    XCTAssertTrue(served);
    XCTAssertEqual([self overpassRequests].count, 2u);
}

// exponential backoff: 0.3, 0.6, 1.2 s… between the failed requests (#12)
- (void)testRetryBackoff
{
    plan.poiMinRequestInterval = 0.05;
    plan.poiRetryBaseDelay = 0.3;
    server.failCount = 3;
    plan.routePoints = [self route];
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(8, ^{ return (BOOL)(self->callbacks > 0); }));
    XCTAssertEqual([self overpassRequests].count, 4u);
}

// at most poiMaxRetries retries, then nothing until the next route change, which starts a new series (#12)
- (void)testRetriesAreBounded
{
    plan.poiMinRequestInterval = 0.05;
    plan.poiRetryBaseDelay = 0.05;
    plan.poiMaxRetries = 2;
    server.failCount = 100;
    plan.routePoints = [self route];
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self overpassRequests].count >= 3); }));
    BPSpin(1.5);
    XCTAssertEqual([self overpassRequests].count, 3u, @"1 request + 2 retries");
    server.failCount = 0;
    plan.routePoints = [[self route] subarrayWithRange:NSMakeRange(0, 20)];
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks > 0); }));
    XCTAssertEqual([self overpassRequests].count, 4u);
}

// HTTP 429 with Retry-After: the server's delay, not the backoff (#12)
- (void)testRetryAfterHeader
{
    plan.poiMinRequestInterval = 0.05;
    plan.poiRetryBaseDelay = 60;
    server.failCount = 1;
    server.failStatus = 429;
    server.failRetryAfter = @"1";
    plan.routePoints = [self route];
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks > 0); }), @"retried after 1 s, not 60");
    XCTAssertEqual([self overpassRequests].count, 2u);
}

// route points of the query: first, last, and ~1 km apart; at most 300 on a long route (#12)
- (void)testSamplePoints
{
    NSArray *few = @[BPLoc(44, 0.5), BPLoc(44.001, 0.5)];
    XCTAssertEqualObjects([BikePlan samplePointsForPOI:few], few);

    NSMutableArray<CLLocation *> *route = [NSMutableArray array]; // 1000 points ~111 m apart: ~111 km
    for (int i = 0; i < 1000; i++) [route addObject:BPLoc(44.0 + i * 0.001, 0.5)];
    NSArray<CLLocation *> *s = [BikePlan samplePointsForPOI:route];
    XCTAssertEqual(s.firstObject, route.firstObject);
    XCTAssertEqual(s.lastObject, route.lastObject);
    XCTAssertGreaterThan(s.count, 80u);
    XCTAssertLessThan(s.count, 130u);
    for (NSUInteger i = 1; i + 1 < s.count; i++) XCTAssertGreaterThanOrEqual([s[i] distanceFromLocation:s[i-1]], 999);

    NSMutableArray<CLLocation *> *longRoute = [NSMutableArray array]; // ~1110 km
    for (int i = 0; i < 10000; i++) [longRoute addObject:BPLoc(40.0 + i * 0.001, 0.5)];
    XCTAssertLessThanOrEqual([BikePlan samplePointsForPOI:longRoute].count, 300u);
}

@end
