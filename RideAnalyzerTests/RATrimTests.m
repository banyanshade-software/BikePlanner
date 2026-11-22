//
//  RATrimTests.m
//  RideAnalyzerTests
//
//  Trimming a ride (#82, owner's case: the computer left running in the car, 277 km of which 3 by bike): the part
//  of the file kept, the figures and stats computed again, undo, the suggestion of the detail when a long stretch
//  goes at car speed.
//

#import <XCTest/XCTest.h>
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RARideAnalysis.h"
#import "RARideStats.h"
#import "RARideDetailController.h"
#import "RATestSupport.h"

@interface RATrimTests : XCTestCase
@end

@implementation RATrimTests

/// a GPX going north: segments @[ length m, speed m/s ], a point every 100 m
- (NSData *)gpxOf:(NSArray<NSArray<NSNumber *> *> *)segments
{
    NSMutableString *gpx = [NSMutableString stringWithString:@"<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"t\"><trk><trkseg>"];
    NSISO8601DateFormatter *f = [[NSISO8601DateFormatter alloc] init];
    NSDate *t = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
    double dist = 0;
    [gpx appendFormat:@"<trkpt lat=\"43.6\" lon=\"1.44\"><ele>150</ele><time>%@</time></trkpt>", [f stringFromDate:t]];
    for (NSArray<NSNumber *> *s in segments) {
        NSUInteger steps = (NSUInteger)(s[0].doubleValue / 100);
        for (NSUInteger i = 0; i < steps; i++) {
            dist += 100;
            t = [t dateByAddingTimeInterval:100 / s[1].doubleValue];
            [gpx appendFormat:@"<trkpt lat=\"%.7f\" lon=\"1.44\"><ele>150</ele><time>%@</time></trkpt>",
             43.6 + dist / 111195.0, [f stringFromDate:t]];
        }
    }
    [gpx appendString:@"</trkseg></trk></gpx>"];
    return [gpx dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)testTrimRide
{
    NSData *data = [self gpxOf:@[ @[ @3000, @5 ], @[ @50000, @25 ] ]];    // 3 km at 18 km/h, 50 km at 90 km/h
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager beginUndoGrouping];
    XCTAssertEqual([doc importData:data fileName:@"car.gpx" error:NULL], RAImportStatusImported);
    [doc.undoManager endUndoGrouping];
    RARide *ride = doc.rides.firstObject;
    XCTAssertEqualWithAccuracy(ride.distance, 53000, 200);

    [doc.undoManager beginUndoGrouping];
    [doc trimRide:ride start:0 end:600];       // the 3 km at 5 m/s: 600 s
    [doc.undoManager endUndoGrouping];
    XCTAssertTrue(ride.trimmed);
    XCTAssertEqualWithAccuracy(ride.distance, 3000, 150);
    XCTAssertEqualWithAccuracy(ride.duration, 600, 25);
    XCTAssertEqualWithAccuracy(ride.stats.total.distance, 3000, 150, @"the stats too");
    RARide *read = [[RARide alloc] initWithPropertyList:ride.propertyList];
    XCTAssertEqual(read.trimEnd, 600, @"saved");
    RARideAnalysis *a = [RARideAnalysis analysisOfData:data trimStart:ride.trimStart trimEnd:ride.trimEnd];
    XCTAssertEqualWithAccuracy(a.distance, 3000, 150);

    [doc.undoManager undo];
    XCTAssertFalse(ride.trimmed);
    XCTAssertEqualWithAccuracy(ride.distance, 53000, 200);

    NSRange all = [RARideAnalysis rangeOfTrace:@[] trimStart:10 trimEnd:20];
    XCTAssertEqual(all.length, 0u);
}

// the detail sees the stretch at car speed and proposes to end the ride where it starts
- (void)testCarSpeedSuggestion
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:[self gpxOf:@[ @[ @3000, @5 ], @[ @50000, @25 ] ]] fileName:@"car.gpx" error:NULL];
    RARide *ride = doc.rides.firstObject;
    RARideDetailController *detail = [[RARideDetailController alloc] init];
    detail.library = doc;
    [detail showRides:@[ ride ]];
    XCTAssertTrue(RAWaitUntil(10, ^BOOL { return detail.analysis != nil; }));
    NSButton *suggestion = [detail valueForKey:@"_trimSuggestion"];
    XCTAssertFalse(suggestion.hidden);
    XCTAssertTrue([suggestion.title containsString:@"3"], @"%@", suggestion.title);
    [suggestion performClick:self];
    XCTAssertTrue(ride.trimmed);
    XCTAssertEqualWithAccuracy(ride.distance, 3000, 300);

    // an ordinary ride: no suggestion
    RALibraryDocument *doc2 = [[RALibraryDocument alloc] init];
    [doc2 importData:[self gpxOf:@[ @[ @20000, @7 ] ]] fileName:@"bike.gpx" error:NULL];
    RARideDetailController *d2 = [[RARideDetailController alloc] init];
    d2.library = doc2;
    [d2 showRides:@[ doc2.rides.firstObject ]];
    XCTAssertTrue(RAWaitUntil(10, ^BOOL { return d2.analysis != nil; }));
    XCTAssertTrue(((NSButton *)[d2 valueForKey:@"_trimSuggestion"]).hidden);
}

// the elevation gain: the device's for the whole recording (it filters with data the file does not keep), the one
// computed from the points for a trimmed ride (Garmin Connect does the same: forum thread of #91)
- (void)testDeviceAscent
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager beginUndoGrouping];
    [doc importData:RAFITWithAscent(@[ @100, @150, @130, @180 ], 0, 3122, 1, 77) fileName:@"a.fit" error:NULL];
    [doc.undoManager endUndoGrouping];
    RARide *ride = doc.rides.firstObject;
    XCTAssertEqualWithAccuracy(ride.ascent, 77, 1e-9, @"the device's gain");
    [doc.undoManager beginUndoGrouping];
    [doc trimRide:ride start:0 end:1200];          // the first three points: +50 m
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualWithAccuracy(ride.ascent, 50, 5, @"computed from the points kept");
    [doc.undoManager undo];
    XCTAssertEqualWithAccuracy(ride.ascent, 77, 1e-9, @"the whole recording again");
}

@end
