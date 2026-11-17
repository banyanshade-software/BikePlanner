//
//  BPPOICacheTests.m
//  BikePlannerTests
//
//  Cache of the Overpass answers per area (#84): cells of 0.02° along the route, one layer per kind of POI
//  (utilities, each sight category), kept 7 days, on disk with a size limit.
//

#import <XCTest/XCTest.h>
#import "BPPOICache.h"
#import "TestFixtures.h"

@interface BPPOICacheTests : XCTestCase
@end

@implementation BPPOICacheTests {
    NSURL *dir;
    NSDate *now;
}

- (BPPOICache *)cacheWithDirectory:(nullable NSURL *)d
{
    BPPOICache *c = [[BPPOICache alloc] initWithDirectory:d];
    __weak BPPOICacheTests *weakSelf = self;
    c.clock = ^{
        BPPOICacheTests *strongSelf = weakSelf;
        return strongSelf ? strongSelf->now : [NSDate date];
    };
    return c;
}

- (void)setUp
{
    dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"bp-poi-cache-" stringByAppendingString:NSUUID.UUID.UUIDString]]];
    now = [NSDate dateWithTimeIntervalSince1970:2000000000];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:dir error:NULL];
}

- (void)testCells
{
    BPPOICell c = [BPPOICache cellOfLatitude:44.031 longitude:0.539];
    XCTAssertEqual(c.lat, 2201);
    XCTAssertEqual(c.lon, 26);
    BPPOICell neg = [BPPOICache cellOfLatitude:-0.001 longitude:-0.001];
    XCTAssertEqual(neg.lat, -1, @"floor, not truncation");
    BPGeoBox b = [BPPOICache boxOfCell:c];
    XCTAssertEqualWithAccuracy(b.south, 44.02, 1e-9);
    XCTAssertEqualWithAccuracy(b.north, 44.04, 1e-9);
    XCTAssertEqualWithAccuracy(b.west, 0.52, 1e-9);
    XCTAssertEqualWithAccuracy(b.east, 0.54, 1e-9);
}

// the cells within the radius of the route: none missing along it, from the start
- (void)testCellsAlongRoute
{
    NSMutableArray *route = [NSMutableArray array];
    for (int i = 0; i <= 100; i++) [route addObject:BPLoc(44.0, 0.50 + i * 0.001)]; // ~8 km east
    NSArray<NSValue *> *cells = [BPPOICache cellsAlongRoute:route radius:1000];
    BPPOICell first;
    [cells.firstObject getValue:&first size:sizeof(first)];
    XCTAssertEqual(first.lat, 2200, @"the cell of the start first");
    XCTAssertEqual(first.lon, 25);
    NSMutableSet *keys = [NSMutableSet set];
    for (NSValue *v in cells) {
        BPPOICell c;
        [v getValue:&c size:sizeof(c)];
        [keys addObject:[NSString stringWithFormat:@"%ld_%ld", (long)c.lat, (long)c.lon]];
    }
    XCTAssertEqual(keys.count, cells.count, @"no duplicate");
    // the route is on latitude 44.0 (a cell border), 1 km = 0.009°: cells 2199 and 2200 in latitude, 0.49 → 0.61 in longitude
    for (NSInteger lon = 24; lon <= 30; lon++) {
        for (NSInteger lat = 2199; lat <= 2200; lat++) {
            NSString *k = [NSString stringWithFormat:@"%ld_%ld", (long)lat, (long)lon];
            XCTAssertTrue([keys containsObject:k], @"%@", k);
        }
    }
    XCTAssertFalse([keys containsObject:@"2201_26"], @"not beyond the radius");
}

- (void)testStoreExpireAndLayers
{
    BPPOICache *cache = [self cacheWithDirectory:dir];
    BPPOICell c = { 2201, 26 };
    NSArray *els = @[ @{ @"type": @"node", @"id": @1, @"lat": @44.03, @"lon": @0.53, @"tags": @{ @"amenity": @"toilets" } } ];
    XCTAssertNil([cache elementsForCell:c layer:@"utilities"]);
    [cache setElements:els forCell:c layer:@"utilities"];
    [cache setElements:@[] forCell:c layer:@"culture"];
    XCTAssertEqualObjects([cache elementsForCell:c layer:@"utilities"], els);
    XCTAssertEqualObjects([cache elementsForCell:c layer:@"culture"], @[], @"an empty cell is cached too");
    XCTAssertNil([cache elementsForCell:c layer:@"food"], @"another layer is not");

    // on disk: another instance reads it
    BPPOICache *other = [self cacheWithDirectory:dir];
    XCTAssertEqualObjects([other elementsForCell:c layer:@"utilities"], els);

    // 7 days
    now = [now dateByAddingTimeInterval:7 * 86400 - 10];
    XCTAssertNotNil([cache elementsForCell:c layer:@"utilities"]);
    now = [now dateByAddingTimeInterval:20];
    XCTAssertNil([cache elementsForCell:c layer:@"utilities"], @"expired");
    XCTAssertNil([other elementsForCell:c layer:@"utilities"]);

    [cache setElements:els forCell:c layer:@"utilities"];
    [cache removeAll];
    XCTAssertNil([cache elementsForCell:c layer:@"utilities"]);
    XCTAssertNil([[self cacheWithDirectory:dir] elementsForCell:c layer:@"utilities"]);
}

// above the size limit, the oldest cells go first
- (void)testSizeLimit
{
    BPPOICache *cache = [self cacheWithDirectory:dir];
    cache.maxBytes = 20000;
    NSMutableArray *big = [NSMutableArray array];
    for (int i = 0; i < 60; i++) [big addObject:@{ @"type": @"node", @"id": @(i), @"lat": @44.03, @"lon": @0.53, @"tags": @{ @"name": @"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" } }];
    for (NSInteger k = 0; k < 10; k++) {
        now = [now dateByAddingTimeInterval:60];
        [cache setElements:big forCell:(BPPOICell){ 2201, k } layer:@"utilities"];
    }
    BPPOICache *fresh = [self cacheWithDirectory:dir];
    BPPOICell oldest = { 2201, 0 }, newest = { 2201, 9 };
    NSArray *oldestElements = [fresh elementsForCell:oldest layer:@"utilities"];
    NSArray *newestElements = [fresh elementsForCell:newest layer:@"utilities"];
    XCTAssertNil(oldestElements, @"the oldest evicted");
    XCTAssertNotNil(newestElements, @"the newest kept");
    XCTAssertLessThanOrEqual([cache diskSize], 20000u + 8000u);
}

// memory only (no directory)
- (void)testMemoryOnly
{
    BPPOICache *cache = [self cacheWithDirectory:nil];
    BPPOICell c = { 1, 2 };
    [cache setElements:@[] forCell:c layer:@"utilities"];
    NSArray *els = [cache elementsForCell:c layer:@"utilities"];
    XCTAssertEqualObjects(els, @[]);
}

@end
