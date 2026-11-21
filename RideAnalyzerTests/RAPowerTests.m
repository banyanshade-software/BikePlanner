//
//  RAPowerTests.m
//  RideAnalyzerTests
//
//  Estimated power (#82, R11): the model (gravity, rolling resistance, air drag, acceleration, wind), the model of
//  a ride from the equipment, per point and from the work sums of the stats, in the detail and the trends.
//

#import <XCTest/XCTest.h>
#import "RAPower.h"
#import "RAEquipment.h"
#import "RARide.h"
#import "RARideAnalysis.h"
#import "RARideStats.h"
#import "RATrends.h"
#import "RATestSupport.h"

@interface RAPowerTests : XCTestCase
@end

@implementation RAPowerTests

/// a straight climb north: a point every 10 m, `slope` %, at `speed` m/s
- (RARideAnalysis *)climbOf:(double)km slope:(double)slope speed:(double)speed
{
    NSMutableArray<CLLocation *> *trace = [NSMutableArray array];
    NSDate *t0 = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
    NSUInteger n = (NSUInteger)(km * 100);
    for (NSUInteger i = 0; i <= n; i++) {
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake(43.6 + i * 10 / 111195.0, 1.44);
        [trace addObject:[[CLLocation alloc] initWithCoordinate:c altitude:100 + i * 10 * slope / 100 horizontalAccuracy:5
                                               verticalAccuracy:5 timestamp:[t0 dateByAddingTimeInterval:i * 10 / speed]]];
    }
    return [[RARideAnalysis alloc] initWithTrace:trace metrics:@[] calories:nil hasTimes:YES];
}

- (RAPowerModel *)model
{
    RAPowerModel *m = [[RAPowerModel alloc] init];
    m.mass = 87;
    m.crr = 0.005;
    m.cdA = 0.45;
    return m;
}

- (void)testPowerOnTheFlat
{
    RAPowerModel *m = [self model];
    double v = 25 / 3.6;
    // rolling 87 × 9.81 × 0.005 = 4.27 N, air ½ × 1.225 × 0.45 × v² = 13.29 N, × v / 0.97
    XCTAssertEqualWithAccuracy([m powerAtSpeed:v slope:0 acceleration:0 headwind:0 airDensity:1.225], 125.7, 1);
    XCTAssertGreaterThan([m powerAtSpeed:v slope:0 acceleration:0 headwind:5 airDensity:1.225], 200, @"headwind");
    XCTAssertLessThan([m powerAtSpeed:v slope:0 acceleration:0 headwind:-5 airDensity:1.225], 80, @"tailwind");
    XCTAssertEqual([m powerAtSpeed:v slope:-8 acceleration:0 headwind:0 airDensity:1.225], 0, @"coasting downhill: 0, not negative");
    XCTAssertEqual([m powerAtSpeed:0 slope:5 acceleration:0 headwind:0 airDensity:1.225], 0);
    // climbing 6 % at 12 km/h: gravity dominates
    XCTAssertEqualWithAccuracy([m powerAtSpeed:12 / 3.6 slope:6 acceleration:0 headwind:0 airDensity:1.225], 201, 3);
}

- (void)testWindAndAir
{
    RAWind *north = [RAWind windWithSpeed:5 fromDirection:0];
    XCTAssertEqualWithAccuracy([north headwindForHeading:0], 5, 1e-9, @"riding north into a north wind");
    XCTAssertEqualWithAccuracy([north headwindForHeading:180], -5, 1e-9);
    XCTAssertEqualWithAccuracy([north headwindForHeading:90], 0, 1e-9);
    XCTAssertEqualWithAccuracy([RAPowerModel airDensityAtAltitude:0 temperature:15], 1.225, 1e-3);
    XCTAssertLessThan([RAPowerModel airDensityAtAltitude:1500 temperature:15], 1.06);
    XCTAssertEqualWithAccuracy([RAPowerModel airDensityAtAltitude:NAN temperature:NAN], 1.225, 1e-3);
    XCTAssertEqualWithAccuracy([RAPowerModel headingFromLatitude:43 longitude:1 toLatitude:44 longitude:1], 0, 1e-6);
    XCTAssertEqualWithAccuracy([RAPowerModel headingFromLatitude:43 longitude:1 toLatitude:43 longitude:1.1], 90, 0.1);
}

- (void)testModelOfARide
{
    RAEquipment *e = [[RAEquipment alloc] init];
    e.riderWeight = 75;
    RABike *bike = [[RABike alloc] init];
    bike.weight = 13;
    bike.position = RAPositionFlatBar;
    RAPart *tyre = [[RAPart alloc] init];
    tyre.model = @"GP5000";
    RAMounting *m = [[RAMounting alloc] init];
    m.bikeID = bike.identifier;
    m.from = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
    tyre.mountings = @[ m ];
    e.bikes = @[ bike ];
    e.parts = @[ tyre ];
    e.defaultBikeID = bike.identifier;
    RARide *ride = [[RARide alloc] initWithTrace:RATrace(@[ @1, @2 ], 0) name:@"r"];
    RAPowerModel *model = [RAPowerModel modelForRide:ride equipment:e];
    XCTAssertEqualWithAccuracy(model.mass, 88, 1e-9);
    XCTAssertEqualWithAccuracy(model.crr, 0.0032, 1e-6);
    XCTAssertEqualWithAccuracy(model.cdA, 0.45, 1e-9);
    RAPowerModel *none = [RAPowerModel modelForRide:ride equipment:nil];
    XCTAssertEqualWithAccuracy(none.mass, 87, 1e-9, @"75 kg rider, 12 kg bike");
}

- (void)testPerPointAndFromStats
{
    RARideAnalysis *a = [self climbOf:2 slope:5 speed:4];   // 14.4 km/h at 5 %
    RAPowerModel *m = [self model];
    NSArray<NSNumber *> *powers = [m powersOfAnalysis:a wind:nil];
    XCTAssertEqual(powers.count, a.count);
    double expected = [m powerAtSpeed:4 slope:5 acceleration:0 headwind:0
                           airDensity:[RAPowerModel airDensityAtAltitude:150 temperature:15]];
    XCTAssertEqualWithAccuracy(powers[a.count / 2].doubleValue, expected, expected * 0.05);

    RARideStats *stats = [RARideStats statsOfAnalysis:a];
    RATerrainStats *climb = [stats statsForTerrain:RATerrainClimb];
    XCTAssertGreaterThan(climb.time, 300);
    XCTAssertEqualWithAccuracy([m averagePowerOfStats:climb], expected, expected * 0.05, @"the same from the work sums");
    XCTAssertTrue(isnan([m averagePowerOfStats:[[RATerrainStats alloc] init]]));

    RARideStats *windy = [RARideStats statsOfAnalysis:a wind:^RAWind *(NSUInteger i) { return [RAWind windWithSpeed:6 fromDirection:0]; }];
    XCTAssertGreaterThan([m averagePowerOfStats:[windy statsForTerrain:RATerrainClimb]], expected + 20, @"against the wind");
    RARideStats *read = [RARideStats statsWithPropertyList:stats.propertyList];
    XCTAssertEqualWithAccuracy([m averagePowerOfStats:[read statsForTerrain:RATerrainClimb]], [m averagePowerOfStats:climb], 1e-6);
}

- (void)testEstimatedPowersInTheAnalysis
{
    RARideAnalysis *a = [self climbOf:1 slope:5 speed:4];
    XCTAssertFalse(a.hasPower);
    [a useEstimatedPowers:[[self model] powersOfAnalysis:a wind:nil]];
    XCTAssertTrue(a.hasPower);
    XCTAssertTrue(a.powerIsEstimated);
    XCTAssertGreaterThan(a.averagePower, 100);

    NSMutableArray *metrics = [NSMutableArray array];
    for (NSUInteger i = 0; i < a.count; i++) [metrics addObject:@{ @"power": @250 }];
    RARideAnalysis *measured = [[RARideAnalysis alloc] initWithTrace:a.trace metrics:metrics calories:nil hasTimes:YES];
    [measured useEstimatedPowers:[[self model] powersOfAnalysis:measured wind:nil]];
    XCTAssertFalse(measured.powerIsEstimated, @"measured power kept");
    XCTAssertEqualWithAccuracy(measured.averagePower, 250, 1e-9);
}

- (void)testTrends
{
    RARideAnalysis *a = [self climbOf:3 slope:5 speed:4];
    RARide *ride = [[RARide alloc] initWithTrace:a.trace name:@"climb"];
    ride.stats = [RARideStats statsOfAnalysis:a];
    RAEquipment *light = [[RAEquipment alloc] init];
    light.riderWeight = 60;
    RAEquipment *heavy = [[RAEquipment alloc] init];
    heavy.riderWeight = 90;
    NSArray<RATrendPoint *> *p1 = [RATrends pointsForRides:@[ ride ] measure:RATrendEstimatedPower terrain:RATerrainClimb
                                                  grouping:RATrendPerRide equipment:light];
    NSArray<RATrendPoint *> *p2 = [RATrends pointsForRides:@[ ride ] measure:RATrendEstimatedPower terrain:RATerrainClimb
                                                  grouping:RATrendPerMonth equipment:heavy];
    XCTAssertEqual(p1.count, 1u);
    XCTAssertEqual(p2.count, 1u);
    XCTAssertGreaterThan(p2[0].value, p1[0].value, @"the same climb is harder for a heavier rider");
    XCTAssertEqual([RATrends pointsForRides:@[ ride ] measure:RATrendEstimatedPowerPerBeat terrain:RATerrainClimb
                                   grouping:RATrendPerRide equipment:light].count, 0u, @"no heart rate");
    XCTAssertTrue([[RATrends nameOfMeasure:RATrendEstimatedPower] containsString:@"stimated"]);
}

@end
