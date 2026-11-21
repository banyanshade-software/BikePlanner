//
//  RATrendsTests.m
//  RideAnalyzerTests
//
//  The progression (#82, R6): stats of a ride per terrain, points per ride / period, trend line, totals, records,
//  the stats of older rides computed later, the trends window.
//

#import <XCTest/XCTest.h>
#import "RARideStats.h"
#import "RARideAnalysis.h"
#import "RATrends.h"
#import "RARide.h"
#import "RALibraryDocument.h"
#import "RATrendsWindowController.h"
#import "RATimeChartView.h"
#import "RATestSupport.h"

@interface RATrendsTests : XCTestCase
@end

@implementation RATrendsTests

// 100 m every 20 s: 10 intervals flat, then 10 intervals climbing 6 m each (6 %), with heart rate and power
- (RARideAnalysis *)flatThenClimb
{
    NSMutableArray<CLLocation *> *trace = [NSMutableArray array];
    NSMutableArray *metrics = [NSMutableArray array];
    for (int i = 0; i <= 20; i++) {
        double alt = i <= 10 ? 100 : 100 + 6 * (i - 10);
        [trace addObject:[[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(45 + i * 100 / 111195.0, 5)
            altitude:alt horizontalAccuracy:5 verticalAccuracy:5
            timestamp:[NSDate dateWithTimeIntervalSince1970:1795478400 + 20 * i]]];
        [metrics addObject:i <= 10 ? @{ @"hr": @120, @"power": @150 } : @{ @"hr": @150, @"power": @300 }];
    }
    return [[RARideAnalysis alloc] initWithTrace:trace metrics:metrics calories:@300 hasTimes:YES];
}

- (void)testRideStatsPerTerrain
{
    RARideStats *s = [RARideStats statsOfAnalysis:[self flatThenClimb]];
    XCTAssertEqualWithAccuracy(s.movingTime, 400, 1e-6);
    RATerrainStats *flat = [s statsForTerrain:RATerrainFlat];
    RATerrainStats *climb = [s statsForTerrain:RATerrainClimb];
    // the interval at the foot of the climb has a mean slope (half flat): it may go to the gentle terrain
    XCTAssertGreaterThanOrEqual(flat.time, 160);
    XCTAssertGreaterThanOrEqual(climb.time, 160);
    XCTAssertEqualWithAccuracy(flat.speed, 18, 0.1);
    XCTAssertEqualWithAccuracy(flat.heartRate, 120, 1e-6);
    XCTAssertEqualWithAccuracy(climb.power, 300, 1e-6);
    XCTAssertEqualWithAccuracy(climb.climbingSpeed, 6.0 / 20 * 3600, 1, @"VAM 1080 m/h");
    XCTAssertEqualWithAccuracy(s.total.time, 400, 1e-6);
    XCTAssertEqualWithAccuracy(s.calories, 300, 1e-9);
    XCTAssertEqualWithAccuracy(s.maxPower, 300, 1e-9);

    RARideStats *copy = [RARideStats statsWithPropertyList:s.propertyList];
    XCTAssertEqualObjects(copy.propertyList, s.propertyList);
    NSMutableDictionary *old = [s.propertyList mutableCopy];
    old[@"version"] = @0;
    XCTAssertNil([RARideStats statsWithPropertyList:old], @"an older version is computed again");
    XCTAssertEqual(RATerrainOfSlope(-3), RATerrainDescent);
    XCTAssertEqual(RATerrainOfSlope(0.5), RATerrainFlat);
    XCTAssertEqual(RATerrainOfSlope(8), RATerrainSteep);
}

- (void)testStatsAtImportAndLater
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:RAFIT(@[ @100, @150, @130 ], 0, 3122, 1) fileName:@"a.fit" error:NULL];
    RARide *ride = doc.rides.firstObject;
    XCTAssertNotNil(ride.stats, @"computed at import");
    XCTAssertEqualWithAccuracy(ride.stats.movingTime, 1200, 1e-6);
    XCTAssertEqual(doc.ridesWithoutStats.count, 0u);

    ride.stats = nil; // a ride imported before the stats existed
    XCTAssertEqual(doc.ridesWithoutStats.count, 1u);
    __block NSInteger computed = -1;
    [doc computeMissingStatsWithCompletion:^(NSUInteger n) { computed = (NSInteger)n; }];
    XCTAssertTrue(RAWaitUntil(10, ^{ return (BOOL)(computed >= 0); }));
    XCTAssertEqual(computed, 1);
    XCTAssertNotNil(ride.stats);
    XCTAssertTrue(doc.documentEdited, @"saved with the library");
}

// a ride on that day with that speed and heart rate on the flat (10 min moving)
- (RARide *)rideOnDay:(NSInteger)day speed:(double)kmh heartRate:(double)hr km:(double)km
{
    RARide *r = [[RARide alloc] init];
    r.name = [NSString stringWithFormat:@"day %ld", (long)day];
    r.startDate = [NSDate dateWithTimeIntervalSince1970:1767225600 + day * 86400 + 9 * 3600]; // 2026-01-01 + day
    r.distance = km * 1000;
    r.ascent = km * 10;
    RARideStats *s = [[RARideStats alloc] init];
    RATerrainStats *flat = [s statsForTerrain:RATerrainFlat];
    flat.time = 600;
    flat.distance = kmh / 3.6 * 600;
    flat.heartRateSum = hr * 600;
    flat.heartRateTime = 600;
    [s.total add:flat];
    s.movingTime = 600;
    r.stats = s;
    return r;
}

- (void)testPointsTrendLineTotalsRecords
{
    NSArray<RARide *> *rides = @[ [self rideOnDay:40 speed:26 heartRate:130 km:60],  // February
                                  [self rideOnDay:0 speed:24 heartRate:140 km:30],   // January
                                  [self rideOnDay:5 speed:25 heartRate:140 km:80],   // January
                                  [self rideOnDay:70 speed:27 heartRate:120 km:45] ]; // March
    RARide *undated = [self rideOnDay:1 speed:30 heartRate:100 km:200];
    undated.startDate = nil;

    NSArray<RATrendPoint *> *perRide = [RATrends pointsForRides:[rides arrayByAddingObject:undated] measure:RATrendSpeed
                                                        terrain:RATerrainFlat grouping:RATrendPerRide];
    XCTAssertEqual(perRide.count, 4u, @"undated left out");
    XCTAssertEqualWithAccuracy(perRide.firstObject.value, 24, 1e-6, @"oldest first");
    XCTAssertEqualObjects(perRide.firstObject.ride, rides[1]);

    NSArray<RATrendPoint *> *climbs = [RATrends pointsForRides:rides measure:RATrendSpeed terrain:RATerrainClimb
                                                      grouping:RATrendPerRide];
    XCTAssertEqual(climbs.count, 0u, @"no time on this terrain");

    NSArray<RATrendPoint *> *perMonth = [RATrends pointsForRides:rides measure:RATrendSpeed terrain:RATerrainFlat
                                                        grouping:RATrendPerMonth];
    XCTAssertEqual(perMonth.count, 3u);
    XCTAssertEqualWithAccuracy(perMonth[0].value, 24.5, 1e-6, @"January: time-weighted");
    XCTAssertEqual(perMonth[0].rides, 2u);

    NSArray<RATrendPoint *> *efficiency = [RATrends pointsForRides:rides measure:RATrendSpeedPerBeat
                                                           terrain:RATerrainFlat grouping:RATrendPerRide];
    XCTAssertEqualWithAccuracy(efficiency.lastObject.value, 27.0 / 120 * 100, 1e-6);

    NSArray<NSNumber *> *line = [RATrends trendLineOfPoints:perRide];
    XCTAssertNotNil(line);
    XCTAssertGreaterThan(line[1].doubleValue, line[0].doubleValue, @"getting faster");
    XCTAssertNil([RATrends trendLineOfPoints:@[ perRide.firstObject ]]);

    NSArray<RATrendPoint *> *months = [RATrends totalsForRides:rides measure:RATotalDistance period:RAPeriodMonth];
    XCTAssertEqual(months.count, 3u, @"January to March");
    XCTAssertEqualWithAccuracy(months[0].value, 110, 1e-6);
    XCTAssertEqual(months[0].rides, 2u);
    NSArray<RATrendPoint *> *weeks = [RATrends totalsForRides:rides measure:RATotalRides period:RAPeriodWeek];
    XCTAssertGreaterThan(weeks.count, 9u, @"empty weeks included");
    double total = 0;
    for (RATrendPoint *p in weeks) total += p.value;
    XCTAssertEqualWithAccuracy(total, 4, 1e-9);

    NSArray<RARecord *> *records = [RATrends recordsForRides:rides];
    RARecord *longest = records.firstObject;
    XCTAssertEqualObjects(longest.ride, rides[2], @"80 km");
    RARecord *fastest = [records filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"title CONTAINS '50 km'"]].firstObject;
    XCTAssertEqualObjects(fastest.ride, rides[0], @"26 km/h over 60 km; the 27 km/h ride is 45 km");
}

- (void)testTrendsWindow
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:RAFIT(@[ @100, @150, @130 ], 0, 3122, 1) fileName:@"a.fit" error:NULL];
    [doc importData:RAFIT(@[ @100, @110, @130 ], 86400 * 40, 3122, 1) fileName:@"b.fit" error:NULL];
    RATrendsWindowController *trends = [[RATrendsWindowController alloc] initWithLibrary:doc];
    trends.measure = RATrendSpeed;
    trends.terrain = RATerrainAll;
    trends.grouping = RATrendPerRide;
    [trends refresh];
    XCTAssertEqual(trends.trendChart.points.count, 2u);
    XCTAssertEqual(trends.totalsChart.points.count, 2u, @"two months");
    XCTAssertGreaterThan(trends.records.count, 0u);
    trends.filterIndex = 5; // no such saved filter: all rides
    [trends refresh];
    XCTAssertEqual(trends.filterIndex, 0);
}

- (void)testTimeChartRange
{
    RATimeChartView *chart = [[RATimeChartView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    RATrendPoint *a = [[RATrendPoint alloc] init];
    a.date = [NSDate dateWithTimeIntervalSince1970:0];
    a.value = 10;
    RATrendPoint *b = [[RATrendPoint alloc] init];
    b.date = [NSDate dateWithTimeIntervalSince1970:86400];
    b.value = 20;
    chart.points = @[ a, b ];
    XCTAssertLessThan(chart.lowValue, 10);
    XCTAssertGreaterThan(chart.highValue, 20);
    chart.style = RATimeChartBars;
    XCTAssertEqual(chart.lowValue, 0, @"bars start at 0");
    [chart display];
}

@end
