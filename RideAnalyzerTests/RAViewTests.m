//
//  RAViewTests.m
//  RideAnalyzerTests
//
//  The views of Ride Analyzer that have logic (#82): the filter sheet (R3), the curves and the ride detail (R4).
//

#import <XCTest/XCTest.h>
#import "RAFilter.h"
#import "RAFilterSheet.h"
#import "RAChartView.h"
#import "RARideDetailController.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RATestSupport.h"

@interface RAViewTests : XCTestCase
@end

@implementation RAViewTests

- (void)testFilterSheetRoundTrip
{
    RAFilter *f = [[RAFilter alloc] init];
    NSCalendar *cal = [NSCalendar currentCalendar];
    f.fromDay = [cal startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:1767225600]]; // 2026-01-01
    f.minDistance = 30000;
    f.minAscent = 500;
    f.deviceKeys = [NSSet setWithObject:@"p1-s1"];
    f.tags = [NSSet setWithObject:@"club"];
    RAFilterSheet *sheet = [[RAFilterSheet alloc] initWithFilter:f
        devices:@[ @[ @"p1-s1", @"Edge" ], @[ @"p2-s2", @"Montre" ] ] tags:@[ @"club", @"gravel" ]];
    (void)sheet.window;
    XCTAssertEqual(sheet.deviceCheckboxes.count, 2u);
    XCTAssertEqualObjects(sheet.deviceCheckboxes[0].title, @"Edge");
    XCTAssertEqual(sheet.toCheckbox.state, NSControlStateValueOff);
    XCTAssertEqualObjects([sheet editedFilter], f, @"unchanged: the same filter");

    // edited: the watch too, a maximum distance, no tag
    sheet.deviceCheckboxes[1].state = NSControlStateValueOn;
    sheet.maxDistanceField.stringValue = @"100";
    sheet.tagsField.objectValue = @[];
    RAFilter *edited = [sheet editedFilter];
    XCTAssertEqualObjects(edited.deviceKeys, ([NSSet setWithObjects:@"p1-s1", @"p2-s2", nil]));
    XCTAssertEqualWithAccuracy(edited.maxDistance, 100000, 1e-6);
    XCTAssertEqual(edited.tags.count, 0u);
}

- (void)testChartView
{
    RAChartView *chart = [[RAChartView alloc] initWithFrame:NSMakeRect(0, 0, 300, 80)];
    [chart setValues:@[ @10, @(NAN), @30, @20 ] distances:@[ @0, @100, @200, @300 ]];
    XCTAssertEqualWithAccuracy(chart.minimum, 10, 1e-9);
    XCTAssertEqualWithAccuracy(chart.maximum, 30, 1e-9, @"no value: left out");
    XCTAssertTrue(isnan(chart.cursorDistance));
    [chart setValues:@[ @(NAN) ] distances:@[ @0 ]];
    XCTAssertTrue(isnan(chart.minimum));
    [chart display]; // draws "No data" without failing
}

- (void)testRideDetail
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:RAFIT(@[ @100, @150, @130, @180 ], 0, 3122, 1) fileName:@"ride.fit" error:NULL];
    RARide *ride = doc.rides.firstObject;
    RARideDetailController *detail = [[RARideDetailController alloc] init];
    detail.library = doc;
    detail.colorMode = RAColorByHeartRate;
    [detail showRides:@[ ride ]];
    XCTAssertTrue(RAWaitUntil(10, ^{ return (BOOL)(detail.analysis != nil); }), @"analysed in the background");
    XCTAssertEqual(detail.ride, ride);
    XCTAssertEqual(detail.analysis.count, 4u);
    XCTAssertEqual(detail.colorMode, RAColorBySlope, @"no heart rate in the file: colored by slope");
    XCTAssertEqual(detail.cursorIndex, (NSUInteger)NSNotFound);
    [detail moveCursorToDistance:detail.analysis.distances[2].doubleValue + 10];
    XCTAssertEqual(detail.cursorIndex, 2u);

    // several rides: no detail; back to the ride: analysed again
    [detail showRides:@[ ride, ride ]];
    XCTAssertNil(detail.ride);
    XCTAssertNil(detail.analysis);
    [detail showRides:@[ ride ]];
    XCTAssertTrue(RAWaitUntil(10, ^{ return (BOOL)(detail.analysis != nil); }));

    // a ride whose original file is missing: no analysis, no crash
    [doc importData:RATCX(@[ @1, @2 ], 86400, nil, nil) fileName:@"other.tcx" error:NULL];
    RARide *other = [doc.rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"format == 'tcx'"]].firstObject;
    other.fileName = @"missing.tcx";
    [detail showRides:@[ other ]];
    RAWaitUntil(2, ^{ return NO; }); // let the background read finish
    XCTAssertNil(detail.analysis);
}

@end
