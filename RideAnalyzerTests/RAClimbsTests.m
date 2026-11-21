//
//  RAClimbsTests.m
//  RideAnalyzerTests
//
//  Climbs (#82, R7): detection in a ride, figures, the same climb over several rides (passages, best, rank), names
//  kept in the library, the Climbs tab.
//

#import <XCTest/XCTest.h>
#import "RAClimbs.h"
#import "RARideAnalysis.h"
#import "RARideStats.h"
#import "RARide.h"
#import "RALibraryDocument.h"
#import "RALibraryWindowController.h"
#import "RAClimbsViewController.h"
#import "RARideDetailController.h"
#import "ElevationProfileView.h"
#import "RATestSupport.h"

@interface RARideDetailController (Testing)
- (IBAction)compareClimb:(nullable id)sender;
@end

@interface RAClimbsTests : XCTestCase
@end

@implementation RAClimbsTests

/// a ride going north: segments @[ length m, slope %, speed m/s ], a point every 10 m
- (NSArray<CLLocation *> *)traceOf:(NSArray<NSArray<NSNumber *> *> *)segments day:(NSInteger)day
{
    NSMutableArray<CLLocation *> *trace = [NSMutableArray array];
    NSDate *t = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000 + day * 86400];
    double alt = 200, dist = 0;
    [trace addObject:[[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(43.6, 1.44) altitude:alt
                                         horizontalAccuracy:5 verticalAccuracy:5 timestamp:t]];
    for (NSArray<NSNumber *> *s in segments) {
        NSUInteger steps = (NSUInteger)(s[0].doubleValue / 10);
        for (NSUInteger i = 0; i < steps; i++) {
            dist += 10;
            alt += 10 * s[1].doubleValue / 100;
            t = [t dateByAddingTimeInterval:10 / s[2].doubleValue];
            CLLocationCoordinate2D c = CLLocationCoordinate2DMake(43.6 + dist / 111195.0, 1.44);
            [trace addObject:[[CLLocation alloc] initWithCoordinate:c altitude:alt horizontalAccuracy:5 verticalAccuracy:5
                                                          timestamp:t]];
        }
    }
    return trace;
}

- (NSArray<NSArray<NSNumber *> *> *)profileWithClimbSpeed:(double)speed
{
    return @[ @[ @2000, @0, @7 ], @[ @3000, @5, @(speed) ], @[ @1000, @-6, @10 ], @[ @1000, @0, @7 ],
              @[ @200, @5, @5 ], @[ @300, @-3, @8 ],                          // a 10 m bump: not a climb
              @[ @2000, @4, @(speed) ], @[ @500, @0, @7 ] ];
}

- (RARide *)rideWithClimbSpeed:(double)speed day:(NSInteger)day
{
    NSArray<CLLocation *> *trace = [self traceOf:[self profileWithClimbSpeed:speed] day:day];
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:trace metrics:@[] calories:nil hasTimes:YES];
    RARide *ride = [[RARide alloc] initWithTrace:trace name:[NSString stringWithFormat:@"day %ld", (long)day]];
    ride.stats = [RARideStats statsOfAnalysis:a];
    return ride;
}

- (void)testDetection
{
    NSArray<CLLocation *> *trace = [self traceOf:[self profileWithClimbSpeed:4] day:0];
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:trace metrics:@[] calories:nil hasTimes:YES];
    NSArray<RAClimb *> *climbs = [RAClimbDetector climbsOfAnalysis:a wind:nil];
    XCTAssertEqual(climbs.count, 2u, @"the 3 km at 5 % and the 2 km at 4 %, not the bump");
    RAClimb *first = climbs.firstObject;
    XCTAssertEqualWithAccuracy(first.startDistance, 2000, 60);
    XCTAssertEqualWithAccuracy(first.length, 3000, 100);
    XCTAssertEqualWithAccuracy(first.gain, 150, 8);
    XCTAssertEqualWithAccuracy(first.averageGradient, 5, 0.3);
    XCTAssertEqualWithAccuracy(first.maxGradient, 5, 0.5);
    XCTAssertEqualWithAccuracy(first.time, 750, 40, @"3 km at 4 m/s");
    XCTAssertEqualWithAccuracy(first.climbingSpeed, 720, 40);
    XCTAssertEqualWithAccuracy(climbs[1].gain, 80, 8);

    // a short dip in a climb does not split it
    NSArray<CLLocation *> *dip = [self traceOf:@[ @[ @1000, @0, @7 ], @[ @1500, @6, @4 ], @[ @100, @-4, @6 ],
                                                  @[ @1500, @6, @4 ], @[ @500, @0, @7 ] ] day:0];
    RARideAnalysis *b = [[RARideAnalysis alloc] initWithTrace:dip metrics:@[] calories:nil hasTimes:YES];
    NSArray<RAClimb *> *one = [RAClimbDetector climbsOfAnalysis:b wind:nil];
    XCTAssertEqual(one.count, 1u);
    XCTAssertEqualWithAccuracy(one.firstObject.length, 3100, 120);

    RAClimb *read = [RAClimb climbWithPropertyList:first.propertyList];
    XCTAssertEqualObjects(read.propertyList, first.propertyList, @"saved with the stats");
    RARideStats *stats = [RARideStats statsOfAnalysis:a];
    XCTAssertEqual([RARideStats statsWithPropertyList:stats.propertyList].climbs.count, 2u);
}

- (void)testSameClimbOverSeveralRides
{
    RARide *slow = [self rideWithClimbSpeed:3 day:0];
    RARide *fast = [self rideWithClimbSpeed:5 day:10];
    RARide *mid = [self rideWithClimbSpeed:4 day:20];
    NSArray<RAClimbGroup *> *groups = [RAClimbGroup groupsOfRides:@[ mid, slow, fast ]];
    XCTAssertEqual(groups.count, 2u);
    RAClimbGroup *g = groups.firstObject;
    XCTAssertEqual(g.passages.count, 3u);
    XCTAssertEqual(g.passages.firstObject.ride, slow, @"oldest first");
    XCTAssertEqual(g.best.ride, fast);
    XCTAssertEqual([g rankOfPassage:g.passages[1]], 1u, @"the fast one, 10 days later");
    XCTAssertEqual([g rankOfPassage:g.passages[0]], 3u);
    XCTAssertGreaterThan(g.reference.gain, groups[1].reference.gain, @"same number of passages: the biggest first");

    RAClimb *elsewhere = [[RAClimb alloc] init];
    elsewhere.start = CLLocationCoordinate2DMake(44, 2);
    elsewhere.end = CLLocationCoordinate2DMake(44.03, 2);
    elsewhere.length = 3000;
    XCTAssertFalse([g.reference isSameClimbAs:elsewhere]);
}

- (void)testNamesAndTab
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    NSMutableArray<RARide *> *rides = [NSMutableArray array];
    for (NSInteger d = 0; d < 3; d++) {
        NSArray<CLLocation *> *trace = [self traceOf:[self profileWithClimbSpeed:3 + d] day:d * 7];
        NSMutableString *gpx = [NSMutableString stringWithString:@"<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"t\"><trk><trkseg>"];
        NSISO8601DateFormatter *f = [[NSISO8601DateFormatter alloc] init];
        for (CLLocation *l in trace) {
            [gpx appendFormat:@"<trkpt lat=\"%.7f\" lon=\"%.7f\"><ele>%.1f</ele><time>%@</time></trkpt>",
             l.coordinate.latitude, l.coordinate.longitude, l.altitude, [f stringFromDate:l.timestamp]];
        }
        [gpx appendString:@"</trkseg></trk></gpx>"];
        NSString *name = [NSString stringWithFormat:@"r%ld.gpx", (long)d];
        XCTAssertEqual([doc importData:[gpx dataUsingEncoding:NSUTF8StringEncoding] fileName:name error:NULL], RAImportStatusImported);
    }
    for (RARide *r in doc.rides) [rides addObject:r];
    XCTAssertEqual(rides.firstObject.stats.climbs.count, 2u, @"computed at import");

    RAClimb *c0 = rides[0].stats.climbs.firstObject, *c2 = rides[2].stats.climbs.firstObject;
    [doc setName:@"Col de test" ofClimb:c0];
    XCTAssertEqualObjects([doc nameOfClimb:c2], @"Col de test", @"the same climb, another ride");
    XCTAssertEqualObjects([doc nameOfClimb:rides[0].stats.climbs[1]], @"");
    NSFileWrapper *package = [doc fileWrapperOfType:RALibraryDocumentType error:NULL];
    RALibraryDocument *reopened = [[RALibraryDocument alloc] init];
    XCTAssertTrue([reopened readFromFileWrapper:package ofType:RALibraryDocumentType error:NULL]);
    XCTAssertEqualObjects([reopened nameOfClimb:c2], @"Col de test", @"saved");

    RALibraryWindowController *wc = [[RALibraryWindowController alloc] init];
    wc.document = doc;
    RAClimbsViewController *tab = [wc valueForKey:@"_climbs"];
    [wc showClimbs:self];
    [tab refresh];
    XCTAssertEqual(tab.groups.count, 2u, @"nothing selected: the climbs of the list");
    XCTAssertEqual(tab.groups.firstObject.passages.count, 3u);
    XCTAssertEqualObjects(tab.groups.firstObject.name, @"Col de test");
    XCTAssertEqual(tab.passagesTable.numberOfRows, 3);
    XCTAssertEqual(tab.timeChart.points.count, 3u);

    NSTableView *table = [wc valueForKey:@"_table"];
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [tab refresh];
    XCTAssertEqual(tab.groups.count, 2u, @"one ride selected: still the climbs of the list (its own are in its detail)");
    XCTAssertTrue([tab.climbsTable tableColumnWithIdentifier:@"mine"].hidden);
    [tab renameClimbAtRow:1 to:@"Côte"];
    XCTAssertEqualObjects([doc nameOfClimb:rides[0].stats.climbs[1]], @"Côte");

    // the detail of the selected ride: its climbs, shaded on the profile; a double-click compares (Climbs tab)
    RARideDetailController *detail = [wc valueForKey:@"_detail"];
    NSTableView *climbsOfRide = [detail valueForKey:@"_climbsTable"];
    XCTAssertEqual(climbsOfRide.numberOfRows, 2);
    ElevationProfileView *profile = [detail valueForKey:@"_profile"];
    XCTAssertEqual(profile.shadedRanges.count, 2u);
    NSTextField *rank = (NSTextField *)[climbsOfRide viewAtColumn:[climbsOfRide columnWithIdentifier:@"rank"] row:0 makeIfNecessary:YES];
    XCTAssertTrue([rank.stringValue containsString:@"3"], @"%@", rank.stringValue);
    NSTextField *name = (NSTextField *)[climbsOfRide viewAtColumn:[climbsOfRide columnWithIdentifier:@"name"] row:0 makeIfNecessary:YES];
    XCTAssertEqualObjects(name.stringValue, @"Col de test");
    [wc showClimbs:self];   // back to the Ride tab
    NSTabViewController *tabs = [wc valueForKey:@"_tabs"];
    XCTAssertEqual(tabs.selectedTabViewItemIndex, 0);
    [climbsOfRide selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    XCTAssertEqual(profile.emphasizedRange, 1u);
    [detail compareClimb:self];
    XCTAssertEqual(tabs.selectedTabViewItemIndex, 3, @"the Climbs tab");
    XCTAssertEqualObjects(tab.groups[(NSUInteger)tab.climbsTable.selectedRow].name, @"Côte", @"on that climb");
    wc.document = nil;
    [wc close];
}

@end
