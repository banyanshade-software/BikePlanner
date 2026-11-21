//
//  RARideAnalysisTests.m
//  RideAnalyzerTests
//
//  The detail of a ride (#82, R4): per-point values, summary, track colors.
//

#import <XCTest/XCTest.h>
#import "RARideAnalysis.h"
#import "RATestSupport.h"

@interface RARideAnalysisTests : XCTestCase
@end

@implementation RARideAnalysisTests

// points every `step` m north, `dt` s apart, at the given altitudes
- (NSArray<CLLocation *> *)traceWithAltitudes:(NSArray<NSNumber *> *)alts step:(double)step dt:(NSArray<NSNumber *> *)dts
{
    NSMutableArray<CLLocation *> *trace = [NSMutableArray array];
    double lat = 45, t = 1795478400;
    for (NSUInteger i = 0; i < alts.count; i++) {
        if (i) {
            lat += step / 111195.0;
            t += dts[i - 1].doubleValue;
        }
        [trace addObject:[[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, 5) altitude:alts[i].doubleValue
            horizontalAccuracy:5 verticalAccuracy:5 timestamp:[NSDate dateWithTimeIntervalSince1970:t]]];
    }
    return trace;
}

- (NSArray *)emptyMetrics:(NSUInteger)n
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++) [a addObject:@{}];
    return a;
}

// points at these distances (m) north of the start and times (s) from the start
- (NSArray<CLLocation *> *)traceAtDistances:(NSArray<NSNumber *> *)distances times:(NSArray<NSNumber *> *)times
{
    NSMutableArray<CLLocation *> *trace = [NSMutableArray array];
    for (NSUInteger i = 0; i < distances.count; i++) {
        [trace addObject:[[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(45 + distances[i].doubleValue / 111195.0, 5)
            altitude:100 horizontalAccuracy:5 verticalAccuracy:5
            timestamp:[NSDate dateWithTimeIntervalSince1970:1795478400 + times[i].doubleValue]]];
    }
    return trace;
}

- (void)testDistanceTimeSpeedAndPauses
{
    // 100 m every 20 s (18 km/h), with a stop of 600 s (1 m) in the middle
    NSArray<CLLocation *> *trace = [self traceAtDistances:@[ @0, @100, @200, @201, @301, @401 ]
                                                    times:@[ @0, @20, @40, @640, @660, @680 ]];
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:trace metrics:[self emptyMetrics:6] calories:@500 hasTimes:YES];
    XCTAssertEqual(a.count, 6u);
    XCTAssertEqualWithAccuracy(a.elapsedTime, 680, 1e-6);
    XCTAssertEqualWithAccuracy(a.movingTime, 80, 1e-6, @"the stop is a pause");
    XCTAssertEqualWithAccuracy(a.pauseTime, 600, 1e-6);
    XCTAssertEqualWithAccuracy(a.distance, 401, 1.5);
    XCTAssertEqualWithAccuracy(a.averageSpeed, a.distance / 80 * 3.6, 1e-6);
    XCTAssertEqualWithAccuracy(a.speeds[1].doubleValue, 18, 0.2, @"from distance / time");
    XCTAssertEqualWithAccuracy(a.maxSpeed, 18, 0.2);
    XCTAssertEqualObjects(a.calories, @500);
    XCTAssertFalse(a.hasHeartRate);
    XCTAssertFalse(RAHasValue(a.averageHeartRate));
    XCTAssertEqual([a indexAtDistance:0], 0u);
    XCTAssertEqual([a indexAtDistance:190], 2u);
    XCTAssertEqual([a indexAtDistance:10000], 5u);
}

- (void)testSlope
{
    // 50 m steps: flat, then +5 m per step (10 %)
    NSArray *alts = @[ @100, @100, @100, @100, @105, @110, @115, @120, @125 ];
    NSMutableArray *dts = [NSMutableArray array];
    for (int i = 0; i < 8; i++) [dts addObject:@10];
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:[self traceWithAltitudes:alts step:50 dt:dts]
                                                      metrics:[self emptyMetrics:9] calories:nil hasTimes:YES];
    XCTAssertEqualWithAccuracy(a.slopes[1].doubleValue, 0, 0.2, @"flat");
    XCTAssertEqualWithAccuracy(a.slopes[6].doubleValue, 10, 0.3, @"10 % over 100 m");
    XCTAssertEqualWithAccuracy(a.ascent, 25, 1e-6);
}

- (void)testRecordedMetrics
{
    NSArray *alts = @[ @100, @100, @100, @100 ];
    NSArray *metrics = @[ @{ @"hr": @120, @"power": @100, @"cadence": @80, @"speed": @5, @"temperature": @10 },
                          @{ @"hr": @140, @"power": @200, @"cadence": @0, @"speed": @6, @"temperature": @12 },
                          @{ @"hr": @160, @"power": @300, @"cadence": @90, @"speed": @7 },
                          @{} ];
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:[self traceWithAltitudes:alts step:100 dt:@[ @20, @20, @20 ]]
                                                      metrics:metrics calories:nil hasTimes:YES];
    XCTAssertTrue(a.hasHeartRate && a.hasPower && a.hasCadence && a.hasTemperature);
    XCTAssertEqualWithAccuracy(a.averageHeartRate, 140, 1e-9);
    XCTAssertEqualWithAccuracy(a.maxHeartRate, 160, 1e-9);
    XCTAssertEqualWithAccuracy(a.averagePower, 250, 1e-9, @"while moving: the first point starts the ride");
    XCTAssertEqualWithAccuracy(a.maxPower, 300, 1e-9);
    XCTAssertEqualWithAccuracy(a.averageCadence, 85, 1e-9, @"0 rpm (coasting) left out");
    XCTAssertEqualWithAccuracy(a.averageTemperature, 11, 1e-9);
    XCTAssertEqualWithAccuracy(a.speeds[0].doubleValue, 18, 1e-9, @"recorded speed, m/s → km/h");
    XCTAssertEqualWithAccuracy(a.maxSpeed, 25.2, 1e-9);
    XCTAssertTrue(RAHasValue(a.speeds[3].doubleValue), @"a point without recorded speed gets a computed one");
    XCTAssertFalse(RAHasValue(a.heartRates[3].doubleValue));
}

- (void)testUntimedTrace
{
    NSArray *alts = @[ @100, @110 ];
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:[self traceWithAltitudes:alts step:100 dt:@[ @20 ]]
                                                      metrics:[self emptyMetrics:2] calories:nil hasTimes:NO];
    XCTAssertEqual(a.movingTime, 0);
    XCTAssertEqual(a.elapsedTime, 0);
    XCTAssertFalse(RAHasValue(a.speeds[0].doubleValue));
    XCTAssertFalse([RATrackColoring analysis:a supportsMode:RAColorBySpeed]);
    XCTAssertTrue([RATrackColoring analysis:a supportsMode:RAColorBySlope]);
}

- (void)testAnalysisOfAFile
{
    RARideAnalysis *a = [RARideAnalysis analysisOfData:RAFIT(@[ @100, @150, @130 ], 0, 3122, 1)];
    XCTAssertNotNil(a);
    XCTAssertEqual(a.count, 3u);
    XCTAssertTrue(a.hasTimes);
    XCTAssertEqualWithAccuracy(a.elapsedTime, 1200, 1e-6);
    XCTAssertNil([RARideAnalysis analysisOfData:[@"junk" dataUsingEncoding:NSUTF8StringEncoding]]);
}

- (void)testColoring
{
    NSArray *alts = @[ @100, @100, @100, @100, @100 ];
    NSArray *metrics = @[ @{ @"speed": @(10 / 3.6), @"hr": @100, @"power": @50 },
                          @{ @"speed": @(20 / 3.6), @"hr": @130, @"power": @150 },
                          @{ @"speed": @(26 / 3.6), @"hr": @150, @"power": @250 },
                          @{ @"speed": @(35 / 3.6), @"hr": @200, @"power": @400 },
                          @{ @"speed": @(35 / 3.6) } ];
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:[self traceWithAltitudes:alts step:100 dt:@[ @20, @20, @20, @20 ]]
                                                      metrics:metrics calories:nil hasTimes:YES];
    XCTAssertEqualObjects([RATrackColoring classesOfAnalysis:a mode:RAColorBySpeed], (@[ @0, @1, @2, @3, @3 ]));
    // heart rate relative to the max of the ride (200): 50 %, 65 %, 75 %, 100 %, none
    XCTAssertEqualObjects([RATrackColoring classesOfAnalysis:a mode:RAColorByHeartRate], (@[ @0, @1, @2, @4, @(-1) ]));
    XCTAssertEqualObjects([RATrackColoring classesOfAnalysis:a mode:RAColorBySlope], (@[ @2, @2, @2, @2, @2 ]), @"flat");
    NSArray<NSString *> *legend = [RATrackColoring legendForMode:RAColorBySpeed analysis:a];
    XCTAssertEqual(legend.count, 4u);
    XCTAssertTrue([legend.firstObject hasPrefix:@"< 18"], @"%@", legend.firstObject);
    XCTAssertTrue([legend.lastObject hasPrefix:@"> 30"], @"%@", legend.lastObject);
    XCTAssertTrue([RATrackColoring analysis:a supportsMode:RAColorByPower]);
    XCTAssertEqual([RATrackColoring legendForMode:RAColorBySlope analysis:a].count, 6u);
}

@end
