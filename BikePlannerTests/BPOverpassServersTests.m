//
//  BPOverpassServersTests.m
//  BikePlannerTests
//
//  Overpass servers in rotation, demotion of failing or slow ones, regional zones (#84).
//

#import <XCTest/XCTest.h>
#import "BPOverpassServers.h"
#import "BPEnvironment.h"
#import "TestFixtures.h"

@interface BPOverpassServersTests : XCTestCase
@end

@implementation BPOverpassServersTests {
    NSDate *now;
    BPOverpassServerPool *pool;
    BPOverpassServer *a, *b, *europe;
}

static const BPGeoBox kParis = { 48.80, 2.25, 48.90, 2.40 };
static const BPGeoBox kMorocco = { 33.5, -7.7, 33.6, -7.5 };

- (void)setUp
{
    a = [BPOverpassServer serverWithSpec:@"https://a.test/api/interpreter"];
    b = [BPOverpassServer serverWithSpec:@"https://b.test/api/interpreter"];
    europe = [BPOverpassServer serverWithSpec:@"https://eu.test/api/interpreter 37.5,-10,71,30;36,-9.5,37.5,-2"];
    pool = [[BPOverpassServerPool alloc] initWithServers:@[ a, b, europe ]];
    now = [NSDate dateWithTimeIntervalSince1970:1000000];
    __weak BPOverpassServersTests *weakSelf = self;
    pool.clock = ^{
        BPOverpassServersTests *strongSelf = weakSelf;
        return strongSelf ? strongSelf->now : [NSDate date];
    };
}

- (void)tearDown
{
    BPRestoreDefaults();
}

- (void)testSpecsAndZones
{
    XCTAssertTrue(a.worldwide);
    XCTAssertTrue([a covers:kMorocco]);
    XCTAssertFalse(europe.worldwide);
    XCTAssertEqual(europe.zones.count, 2u);
    XCTAssertTrue([europe covers:kParis]);
    XCTAssertTrue([europe covers:BPGeoBoxMake(36.5, -6.0, 37.0, -5.0)], @"Andalusia (zone 2)");
    XCTAssertFalse([europe covers:kMorocco]);
    XCTAssertFalse([europe covers:BPGeoBoxMake(37.0, -6.0, 38.0, -5.0)], @"across two zones: the box must fit in one");
    XCTAssertNil([BPOverpassServer serverWithSpec:@"not a url"]);
    XCTAssertNil([BPOverpassServer serverWithSpec:@"https://x.test/i 1,2,3"], @"a zone needs 4 values");
    XCTAssertNil([BPOverpassServer serverWithSpec:@"https://x.test/i 50,2,40,3"], @"south > north");
}

// round robin among the candidates: the regional server only for a route inside its zones
- (void)testRoundRobin
{
    NSMutableArray *hosts = [NSMutableArray array];
    for (int i = 0; i < 6; i++) [hosts addObject:[pool nextServerFor:kParis excluding:[NSSet set]].url.host];
    XCTAssertEqualObjects(hosts, (@[ @"a.test", @"b.test", @"eu.test", @"a.test", @"b.test", @"eu.test" ]));
    [hosts removeAllObjects];
    for (int i = 0; i < 4; i++) [hosts addObject:[pool nextServerFor:kMorocco excluding:[NSSet set]].url.host];
    XCTAssertEqualObjects([NSSet setWithArray:hosts], ([NSSet setWithObjects:@"a.test", @"b.test", nil]), @"no regional server outside its zones");
}

- (void)testExcludingTried
{
    NSSet *tried = [NSSet setWithObjects:a.url, b.url, nil];
    XCTAssertEqualObjects([pool nextServerFor:kParis excluding:tried], europe);
    XCTAssertNil([pool nextServerFor:kMorocco excluding:tried], @"every candidate tried");
}

// a failing server leaves the rotation for 10 min, then 20, 40… at most 2 h; a success brings it back
- (void)testDemotion
{
    [pool serverFailed:a retryAfter:0];
    XCTAssertTrue([pool isDemoted:a]);
    for (int i = 0; i < 4; i++) XCTAssertNotEqualObjects([pool nextServerFor:kMorocco excluding:[NSSet set]], a);
    now = [now dateByAddingTimeInterval:601];
    XCTAssertFalse([pool isDemoted:a], @"back after 10 min");
    [pool serverFailed:a retryAfter:0];
    now = [now dateByAddingTimeInterval:601];
    XCTAssertTrue([pool isDemoted:a], @"second failure: 20 min");
    now = [now dateByAddingTimeInterval:600];
    XCTAssertFalse([pool isDemoted:a]);
    for (int i = 0; i < 10; i++) [pool serverFailed:a retryAfter:0];
    now = [now dateByAddingTimeInterval:7199];
    XCTAssertTrue([pool isDemoted:a]);
    now = [now dateByAddingTimeInterval:2];
    XCTAssertFalse([pool isDemoted:a], @"at most 2 h");
    [pool server:a answeredAfter:3];
    [pool serverFailed:a retryAfter:0];
    now = [now dateByAddingTimeInterval:601];
    XCTAssertFalse([pool isDemoted:a], @"a success resets the doubling");
}

- (void)testRetryAfterAndSlowAnswers
{
    [pool serverFailed:b retryAfter:1800];
    now = [now dateByAddingTimeInterval:1000];
    XCTAssertTrue([pool isDemoted:b], @"Retry-After longer than 10 min is respected");
    [pool server:a answeredAfter:25];
    XCTAssertTrue([pool isDemoted:a], @"a slow answer demotes the server");
}

// all demoted: the one available first, rather than nothing
- (void)testAllDemoted
{
    [pool serverFailed:a retryAfter:0];
    [pool serverFailed:b retryAfter:0];
    [pool serverFailed:b retryAfter:0];
    XCTAssertEqualObjects([pool nextServerFor:kMorocco excluding:[NSSet set]], a, @"a back in 10 min, b in 20");
}

// all demoted: the one that answered last (even with an error: it is reachable), rather than a silent one whose
// demotion ends first (owner's choice, 2026-11-17: overpass-api.de silent, dresel answering)
- (void)testAllDemotedPrefersTheLastOneThatAnswered
{
    [pool serverFailed:a retryAfter:0];                 // silent: no answer
    now = [now dateByAddingTimeInterval:30];
    [pool serverResponded:b];                           // answered, with an error
    [pool serverFailed:b retryAfter:0];
    XCTAssertEqualObjects([pool nextServerFor:kMorocco excluding:[NSSet set]], b, @"b answered, a never did");
    now = [now dateByAddingTimeInterval:30];
    [pool serverResponded:a];
    [pool serverFailed:a retryAfter:0];
    XCTAssertEqualObjects([pool nextServerFor:kMorocco excluding:[NSSet set]], a, @"a answered more recently");
}

// the demotions are kept from one launch to the next (user defaults; owner's request 2026-11-17: 60 s lost at each
// launch on the two silent servers)
- (void)testDemotionsPersist
{
    NSString *suite = [@"bp-tests-overpass-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:suite];
    BPOverpassServerPool *first = [[BPOverpassServerPool alloc] initWithServers:@[ a, b ] defaults:ud];
    first.clock = pool.clock;
    [first serverFailed:a retryAfter:0];
    [first serverFailed:a retryAfter:0];
    [first serverResponded:b];
    [first serverFailed:b retryAfter:0];

    BPOverpassServerPool *next = [[BPOverpassServerPool alloc] initWithServers:@[ a, b ] defaults:ud];
    next.clock = pool.clock;
    XCTAssertTrue([next isDemoted:a], @"still demoted after a relaunch");
    XCTAssertTrue([next isDemoted:b]);
    XCTAssertEqualObjects([next nextServerFor:kMorocco excluding:[NSSet set]], b, @"b answered last");
    now = [now dateByAddingTimeInterval:1201];
    XCTAssertFalse([next isDemoted:a], @"until the end of its period (20 min after 2 failures)");
    [next serverFailed:a retryAfter:0];
    now = [now dateByAddingTimeInterval:1201];
    XCTAssertTrue([next isDemoted:a], @"the count of failures is kept too: 40 min");
    [next server:a answeredAfter:2];
    BPOverpassServerPool *third = [[BPOverpassServerPool alloc] initWithServers:@[ a, b ] defaults:ud];
    third.clock = pool.clock;
    XCTAssertFalse([third isDemoted:a], @"a success is kept");
    [ud removePersistentDomainForName:suite];
}

// the servers: the defaults (FOSSGIS, private.coffee, dresel Europe; not the Russian instance, owner's decision;
// not openstreetmap.fr, which answers 403 to non white-listed users); BPOverpassURL (tests) or BPOverpassServers
- (void)testServersFromEnvironment
{
    BPOverrideDefaults(@{ @"BPOverpassURL": @"", @"BPOverpassServers": @[] });
    NSArray<NSString *> *specs = [BPEnvironment overpassServerSpecs];
    XCTAssertEqual(specs.count, 3u);
    XCTAssertTrue([specs[0] hasPrefix:@"https://overpass-api.de/api/interpreter"]);
    XCTAssertTrue([specs[1] hasPrefix:@"https://overpass.private.coffee/api/interpreter"]);
    XCTAssertTrue([specs[2] hasPrefix:@"https://ovp.dresel.systems/api/interpreter "]);
    for (NSString *s in specs) {
        XCTAssertFalse([s containsString:@"mail.ru"]);
        XCTAssertFalse([s containsString:@"openstreetmap.fr"]);
    }
    BPOverpassServer *eu = [BPOverpassServer serverWithSpec:specs[2]];
    XCTAssertTrue([eu covers:kParis]);
    XCTAssertFalse([eu covers:kMorocco]);

    BPOverrideDefaults(@{ @"BPOverpassURL": @"http://bpstub.test/api/interpreter" });
    XCTAssertEqualObjects([BPEnvironment overpassServerSpecs], @[ @"http://bpstub.test/api/interpreter" ]);
    XCTAssertEqual([BPOverpassServerPool shared].servers.count, 1u);
    BPOverrideDefaults(@{ @"BPOverpassServers": @[ @"http://bpstub.test/s1/api/interpreter", @"http://bpstub.test/s2/api/interpreter 40,-5,52,9" ] });
    XCTAssertEqual([BPOverpassServerPool shared].servers.count, 2u);
    XCTAssertFalse([BPOverpassServerPool shared].servers[1].worldwide);
}

@end
