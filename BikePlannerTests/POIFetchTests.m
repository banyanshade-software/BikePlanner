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
+ (NSArray<CLLocation *> *)samplePointsForPOI:(NSArray<CLLocation *> *)points spacing:(double)spacing;
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
    BPOverrideDefaults(@{ @"BPOverpassURL": server.overpassURL.absoluteString,
                          @"BPPOISearchRadius": @1500, @"BPSightSearchRadius": @1000 }); // not the owner's Preferences (#81)
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
    // cells of 0.02° within 1.5 km of the route (#84; bounding boxes, a cell is complete), from the start
    NSUInteger nodes = [r.body componentsSeparatedByString:@"node("].count - 1;
    XCTAssertEqual(nodes, [r.body componentsSeparatedByString:@"way("].count - 1, @"water… and cemeteries per cell");
    XCTAssertGreaterThanOrEqual(nodes, 4u);
    XCTAssertLessThanOrEqual(nodes, 12u);
    XCTAssertFalse([r.body containsString:@"around"]);
    NSRange first = [r.body rangeOfString:@"node("];
    XCTAssertTrue([[r.body substringFromIndex:first.location] hasPrefix:@"node(44.000000,0.500000,44.020000,0.520000)"], @"the cell of the start first");
    XCTAssertTrue([r.body containsString:@"node(44.020000,0.520000,44.040000,0.540000)"], @"the cell of the end");

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
    // request is for an older route of the burst: ignored (#12). The routes are the same: served from the cells the
    // first answer put in the cache, without a second request (#84)
    XCTAssertTrue(BPWaitUntil(6, ^{ return (BOOL)(self->callbacks > 0); }));
    XCTAssertEqual([self overpassRequests].count, 1u, @"from the cache");
    BPSpin(3.5);
    XCTAssertEqual([self overpassRequests].count, 1u, @"no more requests once served");
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

    // a smaller spacing (search radius under 1 km, #81): points interpolated exactly every 250 m (the route points
    // are ~111 m apart: the next one could be farther than the radius)
    NSArray<CLLocation *> *shortRoute = [route subarrayWithRange:NSMakeRange(0, 200)]; // ~22 km
    NSArray<CLLocation *> *close = [BikePlan samplePointsForPOI:shortRoute spacing:250];
    XCTAssertGreaterThan(close.count, 85u);
    for (NSUInteger i = 1; i + 1 < close.count; i++) XCTAssertEqualWithAccuracy([close[i] distanceFromLocation:close[i-1]], 250, 1.5);
    XCTAssertLessThanOrEqual([BikePlan samplePointsForPOI:longRoute spacing:250].count, 300u, @"still at most 300");
}

#pragma mark - servers in rotation, cache (#84)

- (NSArray<BPStubRequest *> *)requestsTo:(NSString *)path
{
    return [server requestsWithPath:path];
}

- (void)useServers:(NSArray<NSString *> *)specs
{
    BPOverrideDefaults(@{ @"BPOverpassServers": specs, @"BPPOISearchRadius": @1500, @"BPSightSearchRadius": @1000 });
}

// a server that does not answer is demoted, the request goes at once to the next one; the next route skips it
- (void)testFailoverToNextServer
{
    NSString *base = server.baseURL.absoluteString;
    [self useServers:@[ [base stringByAppendingString:@"/s1/api/interpreter"], [base stringByAppendingString:@"/s2/api/interpreter"] ]];
    server.pathFailures = @{ @"/s1/api/interpreter": @-1 };
    plan.routePoints = [self route];
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks > 0); }));
    XCTAssertEqual(plan.poiloc.count, 3u, @"served by s2");
    XCTAssertEqual([self requestsTo:@"/s1/api/interpreter"].count, 1u);
    XCTAssertEqual([self requestsTo:@"/s2/api/interpreter"].count, 1u);
    XCTAssertTrue([[BPOverpassServerPool shared] isDemoted:[BPOverpassServerPool shared].servers[0]]);

    // another route (cells not cached): s1, demoted, is not asked
    plan.poiMinRequestInterval = 0.05;
    NSMutableArray *far = [NSMutableArray array];
    for (int i = 0; i < 25; i++) [far addObject:BPLoc(45.0 + i * 0.001, 1.5 + i * 0.001)];
    plan.routePoints = far;
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks > 1); }));
    XCTAssertEqual([self requestsTo:@"/s1/api/interpreter"].count, 1u, @"demoted: skipped");
    XCTAssertEqual([self requestsTo:@"/s2/api/interpreter"].count, 2u);
}

// every server fails: a message for the map, the usual retries later
- (void)testAllServersFail
{
    NSString *base = server.baseURL.absoluteString;
    [self useServers:@[ [base stringByAppendingString:@"/s1/api/interpreter"], [base stringByAppendingString:@"/s2/api/interpreter"] ]];
    server.pathFailures = @{ @"/s1/api/interpreter": @502, @"/s2/api/interpreter": @-1 };
    __block NSString *message = nil;
    plan.poiErrorCallback = ^(NSString *m) { message = m; };
    plan.poiMinRequestInterval = 0.05;
    plan.poiRetryBaseDelay = 0.3;
    plan.routePoints = [self route];
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(3, ^{ return (BOOL)(message != nil); }));
    XCTAssertTrue([message containsString:@"Overpass"], @"%@", message);
    XCTAssertEqual(callbacks, 0);
    server.pathFailures = nil;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks > 0); }), @"retried later");
    XCTAssertEqual(plan.poiloc.count, 3u);
}

// the cache: the same route again makes no request; a longer route asks only for its new cells (#84)
- (void)testCacheAvoidsRequests
{
    plan.poiMinRequestInterval = 0.05;
    plan.routePoints = [self route];
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks == 1); }));
    NSString *firstBody = [self overpassRequests].firstObject.body;

    plan.routePoints = [[self route] copy]; // the same points
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks == 2); }));
    XCTAssertEqual([self overpassRequests].count, 1u, @"from the cache");
    XCTAssertEqual(plan.poiloc.count, 3u);

    NSMutableArray *longer = [[self route] mutableCopy];
    for (int i = 25; i < 80; i++) [longer addObject:BPLoc(44.0 + i * 0.001, 0.5 + i * 0.001)];
    plan.routePoints = longer;
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks == 3); }));
    XCTAssertEqual([self overpassRequests].count, 2u);
    NSString *body = [self overpassRequests].lastObject.body;
    XCTAssertTrue([firstBody containsString:@"node(44.000000,0.500000,44.020000,0.520000)"]);
    XCTAssertFalse([body containsString:@"node(44.000000,0.500000,44.020000,0.520000)"], @"a cached cell is not asked again");
    XCTAssertTrue([body containsString:@"node(44.060000,0.560000,44.080000,0.580000)"], @"a new cell is");
}

// Refresh Points of Interest: every cell again, ignoring the cache
- (void)testRefreshIgnoresTheCache
{
    plan.poiMinRequestInterval = 0.05;
    plan.routePoints = [self route];
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks == 1); }));
    NSString *firstBody = [self overpassRequests].firstObject.body;
    [plan refreshPOIs];
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks == 2); }));
    XCTAssertEqual([self overpassRequests].count, 2u);
    XCTAssertEqualObjects([self overpassRequests].lastObject.body, firstBody);
    // then the cache again
    [plan refetchPOIs];
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks == 3); }));
    XCTAssertEqual([self overpassRequests].count, 2u);
}

// a regional server is asked only for a route inside its zones; round robin with the worldwide one
- (void)testRegionalServer
{
    NSString *base = server.baseURL.absoluteString;
    [self useServers:@[ [base stringByAppendingString:@"/world/api/interpreter"],
                        [base stringByAppendingString:@"/europe/api/interpreter 43,-1,50,6"] ]];
    plan.poiMinRequestInterval = 0.05;
    NSArray *routes = @[ @[ BPLoc(44.0, 0.5), BPLoc(44.02, 0.52) ], @[ BPLoc(45.0, 1.5), BPLoc(45.02, 1.52) ],
                         @[ BPLoc(46.0, 2.5), BPLoc(46.02, 2.52) ] ];
    for (NSUInteger i = 0; i < routes.count; i++) {
        plan.routePoints = routes[i];
        (void)plan.routePoly;
        XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks == (NSInteger)i + 1); }));
    }
    XCTAssertEqual([self requestsTo:@"/world/api/interpreter"].count, 2u, @"round robin");
    XCTAssertEqual([self requestsTo:@"/europe/api/interpreter"].count, 1u);
    // outside the zone (Morocco): never the regional server
    for (int k = 0; k < 2; k++) {
        plan.routePoints = @[ BPLoc(33.5 + k, -7.6), BPLoc(33.52 + k, -7.58) ];
        (void)plan.routePoly;
        XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->callbacks == 4 + k); }));
    }
    XCTAssertEqual([self requestsTo:@"/europe/api/interpreter"].count, 1u);
    XCTAssertEqual([self requestsTo:@"/world/api/interpreter"].count, 4u);
}

// a long route: the missing cells in batches of at most 20, one request after the other, each cached and shown as
// it arrives (one query for every cell of a long route timed out on the server, 2026-11-17)
- (void)testBatches
{
    plan.poiMinRequestInterval = 0.05;
    NSMutableArray *longRoute = [NSMutableArray array];
    for (int i = 0; i < 300; i++) [longRoute addObject:BPLoc(44.0 + i * 0.001, 0.5 + i * 0.001)]; // ~40 km
    plan.routePoints = longRoute;
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)([self overpassRequests].count >= 3); }));
    BPSpin(1.0);
    NSArray<BPStubRequest *> *requests = [self overpassRequests];
    XCTAssertGreaterThanOrEqual(requests.count, 3u, @"several batches");
    NSMutableSet *cells = [NSMutableSet set];
    for (BPStubRequest *r in requests) {
        NSUInteger n = [r.body componentsSeparatedByString:@"node("].count - 1;
        XCTAssertLessThanOrEqual(n, 20u, @"at most 20 cells per request");
        XCTAssertGreaterThan(n, 0u);
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"node\\(([^)]*)\\)" options:0 error:NULL];
        for (NSTextCheckingResult *m in [re matchesInString:r.body options:0 range:NSMakeRange(0, r.body.length)]) {
            NSString *bbox = [r.body substringWithRange:[m rangeAtIndex:1]];
            XCTAssertFalse([cells containsObject:bbox], @"a cell asked once");
            [cells addObject:bbox];
        }
    }
    XCTAssertGreaterThanOrEqual(callbacks, (NSInteger)requests.count, @"the POIs shown after each batch");
    // all cached: the same route again makes no request
    NSUInteger before = requests.count;
    plan.routePoints = [longRoute copy];
    (void)plan.routePoly;
    BPSpin(1.0);
    XCTAssertEqual([self overpassRequests].count, before);
}

// a batch that fails moves to the next server; the batches already received stay cached
- (void)testBatchFailover
{
    NSString *base = server.baseURL.absoluteString;
    [self useServers:@[ [base stringByAppendingString:@"/s1/api/interpreter"], [base stringByAppendingString:@"/s2/api/interpreter"] ]];
    plan.poiMinRequestInterval = 0.05;
    server.pathFailures = @{ @"/s2/api/interpreter": @502 };
    NSMutableArray *longRoute = [NSMutableArray array];
    for (int i = 0; i < 300; i++) [longRoute addObject:BPLoc(44.0 + i * 0.001, 0.5 + i * 0.001)];
    plan.routePoints = longRoute;
    (void)plan.routePoly;
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)([self requestsTo:@"/s1/api/interpreter"].count >= 3); }));
    BPSpin(1.0);
    XCTAssertEqual([self requestsTo:@"/s2/api/interpreter"].count, 1u, @"s2 failed once, then demoted");
    XCTAssertGreaterThanOrEqual([self requestsTo:@"/s1/api/interpreter"].count, 3u, @"every batch served by s1");
}

@end
