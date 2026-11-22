//
//  RARoadsTests.m
//  RideAnalyzerTests
//
//  Road types and surfaces (#82, R8): rolling factors of OSM tags, matching a track to ways, the Overpass request
//  and its cache (a stub: never the real service), the roads kept with the ride and used by the estimated power.
//

#import <XCTest/XCTest.h>
#import "RARoads.h"
#import "RASurfaceFactors.h"
#import "RASurfaceFactorsWindowController.h"
#import "RAEquipment.h"
#import "RARide.h"
#import "RARideStats.h"
#import "RARideAnalysis.h"
#import "RAPower.h"
#import "RALibraryDocument.h"
#import "RATestSupport.h"

@interface RARoadsTests : XCTestCase
@end

typedef struct { float lat, lon; } RATestWayPoint;

@implementation RARoadsTests
{
    NSURL *_cache;
    NSUInteger _overpassRequests;
}

- (void)setUp
{
    _cache = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:_cache.path forKey:@"RAWaysCacheDirectory"];
    [ud setObject:@[ @"https://overpass.stub/api/interpreter" ] forKey:@"RAOverpassServers"];
    [RAStubURLProtocol reset];
    _overpassRequests = 0;
    __weak RARoadsTests *weakSelf = self;
    RAStubURLProtocol.handler = ^RAStubResponse *(NSURLRequest *r) { return [weakSelf answer:r]; };
    RARoadMatcher.session = [RAStubURLProtocol session];
}

- (void)tearDown
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud removeObjectForKey:@"RAWaysCacheDirectory"];
    [ud removeObjectForKey:@"RAOverpassServers"];
    RARoadMatcher.session = nil;
    [RAStubURLProtocol reset];
    [[NSFileManager defaultManager] removeItemAtURL:_cache error:NULL];
}

/// along longitude 5.0 (RATrace): an asphalt cycleway from 45.00 to 45.025, a gravel track from 45.025 to 45.05
- (nullable RAStubResponse *)answer:(NSURLRequest *)r
{
    if (![r.URL.path isEqualToString:@"/api/interpreter"]) return nil;
    _overpassRequests++;
    NSMutableArray *a = [NSMutableArray array], *b = [NSMutableArray array];
    for (int i = 0; i <= 25; i++) [a addObject:@{ @"lat": @(45.0 + i * 0.001), @"lon": @5.0 }];
    for (int i = 25; i <= 50; i++) [b addObject:@{ @"lat": @(45.0 + i * 0.001), @"lon": @5.0 }];
    return [RAStubResponse json:@{ @"elements": @[
        @{ @"type": @"way", @"id": @1, @"tags": @{ @"highway": @"cycleway", @"surface": @"asphalt" }, @"geometry": a },
        @{ @"type": @"way", @"id": @2, @"tags": @{ @"highway": @"track", @"surface": @"gravel" }, @"geometry": b },
        // a road crossing at 45.01: the track does not jump to it
        @{ @"type": @"way", @"id": @3, @"tags": @{ @"highway": @"residential" },
           @"geometry": @[ @{ @"lat": @45.01, @"lon": @4.99 }, @{ @"lat": @45.01, @"lon": @5.01 } ] } ] }];
}

- (NSData *)packed:(NSArray<NSArray<NSNumber *> *> *)latLons
{
    NSMutableData *d = [NSMutableData data];
    for (NSArray<NSNumber *> *p in latLons) {
        RATestWayPoint w = { p[0].floatValue, p[1].floatValue };
        [d appendBytes:&w length:sizeof w];
    }
    return d;
}

- (void)testRollingFactors
{
    XCTAssertEqualWithAccuracy(RARollingFactorOfTags(@{ @"highway": @"tertiary", @"surface": @"asphalt" }), 1.3, 1e-9);
    XCTAssertEqualWithAccuracy(RARollingFactorOfTags(@{ @"surface": @"asphalt", @"smoothness": @"excellent" }), 1.15, 1e-9);
    XCTAssertEqualWithAccuracy(RARollingFactorOfTags(@{ @"surface": @"gravel" }), 2.5, 1e-9);
    XCTAssertEqualWithAccuracy(RARollingFactorOfTags(@{ @"surface": @"sett" }), 2.2, 1e-9);
    XCTAssertEqualWithAccuracy(RARollingFactorOfTags(@{ @"highway": @"track", @"tracktype": @"grade1" }), 1.4, 1e-9);
    XCTAssertEqualWithAccuracy(RARollingFactorOfTags(@{ @"highway": @"track" }), 2.5, 1e-9);
    XCTAssertEqualWithAccuracy(RARollingFactorOfTags(@{ @"highway": @"residential" }), 1.3, 1e-9, @"a road: asphalt");
    XCTAssertEqualObjects([RASurfaceFactors categoryOfTags:@{ @"surface": @"fine_gravel" }], RASurfaceKeyFineGravel);
    XCTAssertEqualObjects([RASurfaceFactors categoryOfTags:@{ @"surface": @"asphalt", @"smoothness": @"bad" }], RASurfaceKeyBadAsphalt);
    XCTAssertEqualObjects([RASurfaceFactors categoryOfTags:@{ @"highway": @"track", @"tracktype": @"grade5" }], RASurfaceKeyTrackGrade45);
    XCTAssertEqualObjects([RASurfaceFactors categoryOfTags:@{ @"highway": @"cycleway" }], RASurfaceKeyRoad);
    for (NSString *c in [RASurfaceFactors categories]) {
        XCTAssertGreaterThan([RASurfaceFactors nameOfCategory:c].length, 0u);
        XCTAssertGreaterThan([RASurfaceFactors defaultFactorOfCategory:c], 1.0);
    }
    XCTAssertEqual([RASurfaceFactors factorsWithOverrides:@{ RASurfaceKeyGravel: @4, @"nonsense": @9 }][RASurfaceKeyGravel].doubleValue, 4);
    XCTAssertNil([RASurfaceFactors factorsWithOverrides:@{ @"nonsense": @9 }][@"nonsense"]);
    XCTAssertGreaterThan([RASurfaceFactors sources].count, 3u, @"the defaults have sources");
}

- (void)testMatchingAndRuns
{
    // a track north along 2.0 E, then 8 m east of a parallel road; a crossing road; the end far from any way
    NSMutableArray<CLLocation *> *trace = [NSMutableArray array];
    for (int i = 0; i <= 200; i++) [trace addObject:[[CLLocation alloc] initWithLatitude:44.0 + i * 0.0001 longitude:2.0]];
    for (int i = 1; i <= 20; i++) [trace addObject:[[CLLocation alloc] initWithLatitude:44.02 + i * 0.0001 longitude:2.01]];
    NSArray *ways = @[
        @[ @{ @"highway": @"cycleway", @"surface": @"asphalt" }, [self packed:@[ @[ @44.0, @2.0 ], @[ @44.01, @2.0 ] ]] ],
        @[ @{ @"highway": @"track", @"surface": @"gravel" }, [self packed:@[ @[ @44.01, @2.0 ], @[ @44.02, @2.0 ] ]] ],
        @[ @{ @"highway": @"primary" }, [self packed:@[ @[ @44.005, @1.99 ], @[ @44.005, @2.01 ] ]] ] ];
    RARoadMatch *m = [RARoadMatcher matchTrace:trace toWays:ways];
    XCTAssertEqual(m.pointCount, trace.count);
    XCTAssertEqualObjects([m roadClassAtIndex:20], @"cycleway");
    XCTAssertEqualObjects([m roadClassAtIndex:50], @"cycleway", @"at the crossing: still the cycleway (same direction)");
    XCTAssertEqualObjects([m roadClassAtIndex:150], @"track");
    XCTAssertEqualObjects([m surfaceClassAtIndex:150], RASurfaceClassUnpaved);
    XCTAssertEqualObjects([m roadClassAtIndex:210], RARoadNone, @"far from any way");
    XCTAssertEqual(m.runs.count, 3u, @"cycleway, track, none");
    NSArray<NSString *> *f = [m surfaceCategoriesFrom:95 count:10];
    XCTAssertEqualObjects(f.firstObject, RASurfaceKeyAsphalt);
    XCTAssertEqualObjects(f.lastObject, RASurfaceKeyGravel);
    XCTAssertEqualObjects([m surfaceCategoriesFrom:215 count:1].firstObject, @"", @"no way");
    XCTAssertEqualWithAccuracy(m.matchedFraction, 201.0 / 221, 0.01);
    RARoadMatch *read = [RARoadMatch matchWithPropertyList:m.propertyList];
    XCTAssertEqualObjects(read.runs, m.runs);
    XCTAssertNil([RARoadMatch matchWithPropertyList:@{ @"runs": @[ @[ @1 ] ] }]);
    XCTAssertNil([RARoadMatch matchWithPropertyList:@{ @"runs": @[ @[ @"cycleway", @"paved", @1.3, @3 ] ] }],
                 @"version 1 (factors): matched again");

    // rows over an analysis of the trace (distance per class and surface)
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:trace metrics:@[] calories:nil hasTimes:NO];
    NSArray<RARoadRow *> *rows = [m rowsForAnalysis:a];
    RARoadRow *cycleway = [rows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind == 'road:cycleway'"]].firstObject;
    XCTAssertEqualWithAccuracy(cycleway.distance, 1100, 30);
    XCTAssertTrue([[rows valueForKey:@"kind"] containsObject:@"surface:unpaved"]);
}

- (void)testOverpassAndCache
{
    XCTAssertTrue([[RARoadMatcher queryForCells:@[ @"4500_500" ]] containsString:@"way[\"highway\"](45.00,5.00,45.01,5.01);"]);
    NSArray<CLLocation *> *trace = RATrace(@[ @1, @2, @3, @4, @5, @6 ], 0);   // 45.00 → 45.05 along 5.0 E
    NSError *error = nil;
    RARoadMatch *m = [RARoadMatcher matchTrace:trace cancellation:nil error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(m);
    XCTAssertEqualObjects([m roadClassAtIndex:1], @"cycleway");
    XCTAssertEqualObjects([m roadClassAtIndex:4], @"track");
    XCTAssertEqual(_overpassRequests, 1u, @"20 cells per request");
    NSURLRequest *r = RAStubURLProtocol.requests.lastObject;
    XCTAssertEqualObjects(r.HTTPMethod, @"POST");
    XCTAssertTrue([[r valueForHTTPHeaderField:@"User-Agent"] hasPrefix:@"RideAnalyzer/"]);
    // again: from the cache
    XCTAssertNotNil([RARoadMatcher matchTrace:trace cancellation:nil error:&error]);
    XCTAssertEqual(_overpassRequests, 1u, @"the cells are cached");

    // Overpass unreachable: an error, nothing matched
    [[NSFileManager defaultManager] removeItemAtURL:_cache error:NULL];
    RAStubURLProtocol.handler = ^RAStubResponse *(NSURLRequest *req) { return [RAStubResponse status:504 body:nil]; };
    error = nil;
    XCTAssertNil([RARoadMatcher matchTrace:trace cancellation:nil error:&error]);
    XCTAssertNotNil(error);
}

// the library finds the roads of rides, keeps them, computes the stats again with the surfaces
- (void)testRoadsOfALibrary
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:RATCX(@[ @100, @100, @100, @100, @100, @100 ], 0, nil, nil) fileName:@"flat.tcx" error:NULL];
    RARide *ride = doc.rides.firstObject;
    XCTAssertFalse(ride.stats.usesRoads);
    RATerrainStats *before = ride.stats.total;
    XCTAssertEqual([doc ridesWithoutRoads:doc.rides].count, 1u);

    __block NSInteger found = -1;
    NSProgress *p = [doc findRoadsOfRides:doc.rides completion:^(NSUInteger n, NSError *e) { found = (NSInteger)n; }];
    XCTAssertNotNil(p);
    XCTAssertTrue(doc.findingRoads);
    XCTAssertTrue(RAWaitUntil(10, ^BOOL { return found >= 0 && ride.stats.usesRoads; }));
    XCTAssertEqual(found, 1);
    XCTAssertNotNil(ride.roads);
    XCTAssertEqual([doc ridesWithoutRoads:doc.rides].count, 0u);
    XCTAssertTrue(doc.documentEdited);
    RATerrainStats *after = ride.stats.total;
    XCTAssertGreaterThan(after.surfaceWorks[RASurfaceKeyGravel].doubleValue, 0);
    XCTAssertGreaterThan(after.surfaceWorks[RASurfaceKeyAsphalt].doubleValue, 0);
    XCTAssertLessThan(after.rollingWork, before.rollingWork, @"the known part moved to surfaceWorks");
    // half on gravel (2.5), half on asphalt (1.3): more rolling resistance than the bike's ordinary asphalt (1.3)
    RAPowerModel *m = [RAPowerModel modelForRide:ride equipment:nil];
    XCTAssertGreaterThan([m averagePowerOfStats:after], [m averagePowerOfStats:before]);
    // saved
    RARide *copy = [[RARide alloc] initWithPropertyList:ride.propertyList];
    XCTAssertEqualObjects(copy.roads.runs, ride.roads.runs);
}

// the estimated power along the ride takes the surface of each point
- (void)testPowerWithSurfaces
{
    NSArray<CLLocation *> *trace = RATrace(@[ @100, @100, @100, @100 ], 0);
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:trace metrics:@[] calories:nil hasTimes:YES];
    RAPowerModel *m = [[RAPowerModel alloc] init];
    m.tyreCrr = 0.004;
    m.crr = 0.004 * 1.3;
    double plain = [[m powersOfAnalysis:a wind:nil][2] doubleValue];
    a.surfaceCategories = @[ RASurfaceKeyGravel, RASurfaceKeyGravel, RASurfaceKeyGravel, RASurfaceKeyGravel ];
    double gravel = [[m powersOfAnalysis:a wind:nil][2] doubleValue];
    XCTAssertGreaterThan(gravel, plain, @"gravel rolls harder");
    m.surfaceFactors = [RASurfaceFactors factorsWithOverrides:@{ RASurfaceKeyGravel: @4 }];
    XCTAssertGreaterThan([[m powersOfAnalysis:a wind:nil][2] doubleValue], gravel, @"a factor changed by the user");
    a.surfaceCategories = @[ @"", @"", @"", @"" ];
    XCTAssertEqualWithAccuracy([[m powersOfAnalysis:a wind:nil][2] doubleValue], plain, 1e-9, @"unknown: the bike's usual roads");
}

// the factors are settings of the library (owner's request): a change applies at once, undoable, without new stats
- (void)testConfigurableFactors
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager beginUndoGrouping];
    [doc importData:RATCX(@[ @100, @100, @100, @100, @100, @100 ], 0, nil, nil) fileName:@"flat.tcx" error:NULL];
    [doc.undoManager endUndoGrouping];
    RARide *ride = doc.rides.firstObject;
    __block NSInteger found = -1;
    [doc findRoadsOfRides:doc.rides completion:^(NSUInteger n, NSError *e) { found = (NSInteger)n; }];
    XCTAssertTrue(RAWaitUntil(10, ^BOOL { return found >= 0 && ride.stats.usesRoads; }));
    RARideStats *stats = ride.stats;
    double before = [[RAPowerModel modelForRide:ride equipment:doc.equipment] averagePowerOfStats:stats.total];

    RASurfaceFactorsWindowController *wc = [[RASurfaceFactorsWindowController alloc] initWithLibrary:doc];
    (void)wc.window;
    XCTAssertEqual(wc.tableView.numberOfRows, (NSInteger)[RASurfaceFactors categories].count);
    [doc.undoManager beginUndoGrouping];
    [wc setFactor:@4 ofCategory:RASurfaceKeyGravel];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(doc.equipment.surfaceFactors[RASurfaceKeyGravel].doubleValue, 4);
    XCTAssertEqual(ride.stats, stats, @"no new stats");
    double after = [[RAPowerModel modelForRide:ride equipment:doc.equipment] averagePowerOfStats:stats.total];
    XCTAssertGreaterThan(after, before, @"gravel harder: more watts at once");

    [doc.undoManager beginUndoGrouping];
    [wc setFactor:@100 ofCategory:RASurfaceKeyDirt];
    XCTAssertEqual(doc.equipment.surfaceFactors[RASurfaceKeyDirt].doubleValue, [RASurfaceFactors maximumFactor], @"bounded");
    [wc setFactor:nil ofCategory:RASurfaceKeyDirt];
    XCTAssertNil(doc.equipment.surfaceFactors[RASurfaceKeyDirt], @"back to the default");
    // the bike's usual roads use the same factors
    [wc setFactor:@1.6 ofCategory:RASurfaceKeyAsphalt];
    XCTAssertEqualWithAccuracy([doc.equipment factorOfBikeSurface:RASurfaceAsphalt], 1.6, 1e-9);
    XCTAssertEqualObjects([RAEquipment equipmentWithPropertyList:doc.equipment.propertyList].surfaceFactors,
                          doc.equipment.surfaceFactors, @"saved");
    [doc.undoManager endUndoGrouping];
    [doc.undoManager beginUndoGrouping];
    [wc restoreDefaults:self];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(doc.equipment.surfaceFactors.count, 0u);
    [doc.undoManager undo];
    XCTAssertEqual(doc.equipment.surfaceFactors[RASurfaceKeyAsphalt].doubleValue, 1.6, @"undoable");
    [wc close];
}

@end
