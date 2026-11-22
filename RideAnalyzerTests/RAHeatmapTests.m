//
//  RAHeatmapTests.m
//  RideAnalyzerTests
//
//  The map of all rides (#82, R10): packed simplified tracks kept in the stats, counting the rides per cell,
//  levels, the Map tab following the selection.
//

#import <XCTest/XCTest.h>
#import "RAHeatmap.h"
#import "RARide.h"
#import "RARideStats.h"
#import "RALibraryDocument.h"
#import "RALibraryWindowController.h"
#import "RARidesMapViewController.h"
#import "RATestSupport.h"

@interface RAHeatmapTests : XCTestCase
@end

@implementation RAHeatmapTests

/// a straight track going north from (lat, lon), one point every ~11 m over `km`
- (NSArray<CLLocation *> *)lineFromLatitude:(double)lat longitude:(double)lon km:(double)km
{
    NSMutableArray<CLLocation *> *t = [NSMutableArray array];
    NSUInteger n = (NSUInteger)(km * 90);
    for (NSUInteger i = 0; i <= n; i++) {
        [t addObject:[[CLLocation alloc] initWithLatitude:lat + i * 0.0001 longitude:lon]];
    }
    return t;
}

- (RARide *)rideOnTrace:(NSArray<CLLocation *> *)trace
{
    RARide *ride = [[RARide alloc] initWithTrace:trace name:@"r"];
    RARideStats *stats = [[RARideStats alloc] init];
    stats.track = [RAHeatmap packedTrackOfTrace:trace tolerance:8];
    ride.stats = stats;
    return ride;
}

- (void)testPackedTrack
{
    NSArray<CLLocation *> *line = [self lineFromLatitude:43.6 longitude:1.44 km:2];
    NSData *packed = [RAHeatmap packedTrackOfTrace:line tolerance:8];
    XCTAssertEqual([RAHeatmap pointCountOfPackedTrack:packed], 2u, @"a straight line: its two ends");
    CLLocationCoordinate2D end = [RAHeatmap coordinateAtIndex:1 ofPackedTrack:packed];
    XCTAssertEqualWithAccuracy(end.latitude, line.lastObject.coordinate.latitude, 1e-5);
    XCTAssertFalse(CLLocationCoordinate2DIsValid([RAHeatmap coordinateAtIndex:2 ofPackedTrack:packed]));

    // a corner is kept
    NSMutableArray<CLLocation *> *corner = [[self lineFromLatitude:43.6 longitude:1.44 km:1] mutableCopy];
    CLLocationCoordinate2D c = corner.lastObject.coordinate;
    for (int i = 1; i <= 90; i++) [corner addObject:[[CLLocation alloc] initWithLatitude:c.latitude longitude:c.longitude + i * 0.0001]];
    XCTAssertEqual([RAHeatmap pointCountOfPackedTrack:[RAHeatmap packedTrackOfTrace:corner tolerance:8]], 3u);
}

- (void)testStatsKeepTheTrack
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:RAFIT(@[ @100, @120, @110, @130 ], 0, 3122, 1) fileName:@"a.fit" error:NULL];
    RARideStats *stats = doc.rides.firstObject.stats;
    XCTAssertGreaterThanOrEqual([RAHeatmap pointCountOfPackedTrack:stats.track], 2u, @"computed at import");
    RARideStats *read = [RARideStats statsWithPropertyList:stats.propertyList];
    XCTAssertEqualObjects(read.track, stats.track, @"saved with the library");
}

- (void)testLevels
{
    XCTAssertEqual([RAHeatmap levelOfCount:1], 0u);
    XCTAssertEqual([RAHeatmap levelOfCount:3], 1u);
    XCTAssertEqual([RAHeatmap levelOfCount:4], 2u);
    XCTAssertEqual([RAHeatmap levelOfCount:25], 3u);
}

- (void)testCountsPerRoad
{
    NSArray<CLLocation *> *road = [self lineFromLatitude:43.6 longitude:1.44 km:3];
    NSArray<CLLocation *> *other = [self lineFromLatitude:43.6 longitude:1.46 km:3];   // ~1.6 km east
    NSMutableArray<RARide *> *rides = [NSMutableArray array];
    for (int i = 0; i < 4; i++) [rides addObject:[self rideOnTrace:road]];
    [rides addObject:[self rideOnTrace:other]];
    [rides addObject:[[RARide alloc] initWithTrace:road name:@"no stats"]];    // left out

    RAHeatmap *map = [[RAHeatmap alloc] initWithRides:rides];
    XCTAssertEqual(map.rideCount, 5u);
    XCTAssertEqual(map.maxCount, 4u);
    XCTAssertEqual([map countAtCoordinate:road[100].coordinate], 4u, @"ridden 4 times");
    XCTAssertEqual([map countAtCoordinate:other[100].coordinate], 1u);
    XCTAssertEqual([map countAtCoordinate:CLLocationCoordinate2DMake(44, 2)], 0u);
    XCTAssertGreaterThan([map polylinesOfLevel:2].count, 0u, @"4 rides: level 4–9");
    XCTAssertGreaterThan([map polylinesOfLevel:0].count, 0u, @"the other road: 1 ride");
    XCTAssertEqual([map polylinesOfLevel:3].count, 0u);
    XCTAssertEqualObjects([map polylinesOfLevel:2].firstObject.title, @"2");
    MKMapRect r = map.boundingRect;
    XCTAssertTrue(MKMapRectContainsPoint(MKMapRectInset(r, -1, -1), MKMapPointForCoordinate(other.lastObject.coordinate)));

    RAHeatmap *empty = [[RAHeatmap alloc] initWithRides:@[]];
    XCTAssertTrue(MKMapRectIsNull(empty.boundingRect));
}

// the Map tab: the selected rides when two or more are, else the list
- (void)testMapTab
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    for (int i = 0; i < 3; i++) {
        [doc importData:RAFIT(@[ @100, @150, @130 ], 86400 * 10 * i, 3122, 1)
               fileName:[NSString stringWithFormat:@"%d.fit", i] error:NULL];
    }
    RALibraryWindowController *wc = [[RALibraryWindowController alloc] init];
    wc.document = doc;
    RARidesMapViewController *map = [wc valueForKey:@"_ridesMap"];
    NSTabViewController *tabs = [wc valueForKey:@"_tabs"];
    [wc showRidesMap:self];
    XCTAssertEqual(tabs.selectedTabViewItemIndex, 2);
    [map refresh];
    XCTAssertTrue(RAWaitUntil(5, ^BOOL { return map.heatmap != nil && !map.computing; }));
    XCTAssertEqual(map.heatmap.rideCount, 3u);
    XCTAssertEqual(map.heatmap.maxCount, 3u, @"the same track three times");
    XCTAssertGreaterThan(map.mapView.overlays.count, 0u);

    NSTableView *table = [wc valueForKey:@"_table"];
    [table selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] byExtendingSelection:NO];
    [map refresh];
    XCTAssertTrue(RAWaitUntil(5, ^BOOL { return map.heatmap.rideCount == 2 && !map.computing; }));
    XCTAssertTrue([map.status.stringValue containsString:@"2"]);
    [wc showRidesMap:self];
    XCTAssertEqual(tabs.selectedTabViewItemIndex, 0, @"back to the ride");
    wc.document = nil;
    [wc close];
}

// a long map shows as it goes (owner's request): heatmaps of the first rides, then of twice as many…
- (void)testIntermediateHeatmaps
{
    NSMutableArray<RARide *> *rides = [NSMutableArray array];
    for (int i = 0; i < 5; i++) [rides addObject:[self rideOnTrace:[self lineFromLatitude:43.6 longitude:1.44 + i * 0.01 km:1]]];
    NSTimeInterval delay = RAHeatmap.partialDelay;
    RAHeatmap.partialDelay = 0;
    NSMutableArray<NSNumber *> *counts = [NSMutableArray array];
    RAHeatmap *final = [[RAHeatmap alloc] initWithRides:rides cellSize:40 cancellation:nil
                                                partial:^(RAHeatmap *partial) {
        [counts addObject:@(partial.rideCount)];
        XCTAssertGreaterThan([partial polylinesOfLevel:0].count, 0u, @"drawable");
    }];
    RAHeatmap.partialDelay = delay;
    XCTAssertEqualObjects(counts, (@[ @1, @2, @4 ]), @"each time the number doubles, never the whole");
    XCTAssertEqual(final.rideCount, 5u);
    XCTAssertEqual([[RAHeatmap alloc] initWithRides:rides cellSize:40 cancellation:nil partial:^(RAHeatmap *p) {
        XCTFail(@"too quick for an intermediate heatmap");
    }].rideCount, 5u);
}

// more rides for the map (or more tracks computed): the map shown stays until the new one has more rides
- (void)testMapGrowsWithoutGoingBack
{
    NSMutableArray<RARide *> *rides = [NSMutableArray array];
    for (int i = 0; i < 6; i++) [rides addObject:[self rideOnTrace:[self lineFromLatitude:43.6 longitude:1.44 + i * 0.01 km:1]]];
    NSTimeInterval delay = RAHeatmap.partialDelay;
    RAHeatmap.partialDelay = 0;
    RARidesMapViewController *map = [[RARidesMapViewController alloc] init];
    (void)map.view;
    [map showRides:[rides subarrayWithRange:NSMakeRange(0, 3)] selected:YES];
    [map refresh];
    XCTAssertTrue(RAWaitUntil(5, ^BOOL { return map.heatmap.rideCount == 3 && !map.computing; }));
    [map showRides:rides selected:YES];
    [map refresh];
    __block NSUInteger least = 3;
    XCTAssertTrue(RAWaitUntil(5, ^BOOL {
        least = MIN(least, map.heatmap.rideCount);
        return !map.computing;
    }));
    RAHeatmap.partialDelay = delay;
    XCTAssertEqual(least, 3u, @"never fewer rides than before");
    XCTAssertEqual(map.heatmap.rideCount, 6u);
}

@end
