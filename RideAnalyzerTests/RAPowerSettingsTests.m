//
//  RAPowerSettingsTests.m
//  RideAnalyzerTests
//
//  The parameters of the estimated power (#82, R11, #94): defaults and bounds, used by the model, the breakdown by
//  force and the sensitivity, the calibration on rides with a power meter, the settings window.
//

#import <XCTest/XCTest.h>
#import "RAPowerSettings.h"
#import "RAPowerSettingsWindowController.h"
#import "RACalibration.h"
#import "RAPower.h"
#import "RAEquipment.h"
#import "RARide.h"
#import "RARideStats.h"
#import "RARideAnalysis.h"
#import "RALibraryDocument.h"
#import "RATestSupport.h"

@interface RAPowerSettingsTests : XCTestCase
@end

@implementation RAPowerSettingsTests

- (void)testDefaultsAndBounds
{
    RAPowerSettings *d = [RAPowerSettings defaultSettings];
    XCTAssertEqualWithAccuracy(d.efficiency, 0.97, 1e-9);
    XCTAssertEqualWithAccuracy(d.wheelInertia, 1.5, 1e-9);
    XCTAssertEqualWithAccuracy(d.rollingScale, 1, 1e-9);
    XCTAssertTrue(d.freewheelingIsZero);
    XCTAssertEqualWithAccuracy([d cdAForPosition:RAPositionDrops], 0.30, 1e-9);
    XCTAssertEqualWithAccuracy([d weightForKind:RABikeElectric], 23, 1e-9);
    RAPowerSettings *s = [RAPowerSettings settingsWithOverrides:@{ RAPowerEfficiency: @0.5, RAPowerWheelInertia: @2 }];
    XCTAssertEqualWithAccuracy(s.efficiency, 0.85, 1e-9, @"bounded");
    XCTAssertEqualWithAccuracy(s.wheelInertia, 2, 1e-9);
    for (NSString *k in [RAPowerSettings allParameters]) {
        XCTAssertGreaterThan([RAPowerSettings nameOfParameter:k].length, 0u, @"%@", k);
        XCTAssertGreaterThan([RAPowerSettings explanationOfParameter:k].length, 0u, @"%@", k);
        XCTAssertLessThanOrEqual([RAPowerSettings minimumOfParameter:k], [RAPowerSettings defaultOfParameter:k], @"%@", k);
        XCTAssertGreaterThanOrEqual([RAPowerSettings maximumOfParameter:k], [RAPowerSettings defaultOfParameter:k], @"%@", k);
    }
}

- (RAEquipment *)equipmentWithBike:(RABike **)outBike
{
    RAEquipment *e = [[RAEquipment alloc] init];
    RABike *bike = [[RABike alloc] init];
    bike.kind = RABikeRoad;
    bike.position = RAPositionHoods;
    e.bikes = @[ bike ];
    e.defaultBikeID = bike.identifier;
    if (outBike) *outBike = bike;
    return e;
}

- (void)testTheModelUsesThem
{
    RAEquipment *e = [self equipmentWithBike:NULL];
    RARide *ride = [[RARide alloc] initWithTrace:RATrace(@[ @1, @2 ], 0) name:@"r"];
    RAPowerModel *before = [RAPowerModel modelForRide:ride equipment:e];
    XCTAssertEqualWithAccuracy(before.mass, 75 + 9, 1e-9, @"rider and typical road bike");
    XCTAssertEqualWithAccuracy(before.cdA, 0.36, 1e-9);
    e.powerParameters = @{ RAPowerRiderWeight: @80, RAPowerWeightRoad: @8, RAPowerCdAHoods: @0.33,
                           RAPowerEfficiency: @0.95, RAPowerWheelInertia: @1, RAPowerRollingScale: @1.2,
                           RAPowerSpeedSmoothing: @9, RAPowerFreewheelingIsZero: @0 };
    RAPowerModel *m = [RAPowerModel modelForRide:ride equipment:e];
    XCTAssertEqualWithAccuracy(m.mass, 88, 1e-9);
    XCTAssertEqualWithAccuracy(m.cdA, 0.33, 1e-9);
    XCTAssertEqualWithAccuracy(m.efficiency, 0.95, 1e-9);
    XCTAssertEqualWithAccuracy(m.wheelInertia, 1, 1e-9);
    XCTAssertEqualWithAccuracy(m.tyreCrr, before.tyreCrr * 1.2, 1e-9, @"the calibration multiplier");
    XCTAssertEqualWithAccuracy(m.speedSmoothing, 9, 1e-9);
    XCTAssertFalse(m.freewheelingIsZero);
    XCTAssertEqualObjects([RAEquipment equipmentWithPropertyList:e.propertyList].powerParameters, e.powerParameters, @"saved");

    // the pressure correction of the tyres
    RAEquipment *t = [self equipmentWithBike:NULL];
    RAPart *tyre = [[RAPart alloc] init];
    tyre.model = @"GP5000";
    tyre.width = 28;
    tyre.pressure = 3;
    RAMounting *on = [[RAMounting alloc] init];
    on.bikeID = t.defaultBikeID;
    on.from = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
    tyre.mountings = @[ on ];
    t.parts = @[ tyre ];
    double crr = [t crrOfBike:t.defaultBikeID atDate:[NSDate date]];
    t.powerParameters = @{ RAPowerPressureExponent: @0 };
    XCTAssertLessThan([t crrOfBike:t.defaultBikeID atDate:[NSDate date]], crr, @"no pressure correction");
}

- (void)testFreewheelingRule
{
    NSMutableArray *trace = [NSMutableArray array], *metrics = [NSMutableArray array];
    for (int i = 0; i < 60; i++) {
        [trace addObject:[[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(43.6 + i * 8 / 111195.0, 1.44)
            altitude:100 horizontalAccuracy:5 verticalAccuracy:5 timestamp:[NSDate dateWithTimeIntervalSince1970:1e9 + i]]];
        [metrics addObject:@{ @"cadence": @0 }];
    }
    RARideAnalysis *a = [[RARideAnalysis alloc] initWithTrace:trace metrics:metrics calories:nil hasTimes:YES];
    RAPowerModel *m = [[RAPowerModel alloc] init];
    XCTAssertEqual([m powersOfAnalysis:a wind:nil][30].doubleValue, 0);
    m.freewheelingIsZero = NO;
    XCTAssertGreaterThan([m powersOfAnalysis:a wind:nil][30].doubleValue, 50, @"28.8 km/h on the flat");
    XCTAssertEqual([RARideStats statsOfAnalysis:a].total.airWork, 0, @"no work while freewheeling");
    a.freewheelingIsZero = NO;
    RARideStats *s = [RARideStats statsOfAnalysis:a];
    XCTAssertGreaterThan(s.total.airWork, 0);
    XCTAssertFalse(s.freewheelingIsZero);
    XCTAssertFalse([RARideStats statsWithPropertyList:s.propertyList].freewheelingIsZero, @"saved");
}

- (void)testBreakdownAndSensitivity
{
    RATerrainStats *t = [[RATerrainStats alloc] init];
    t.time = 1000;
    t.gravityWork = 9.81 * 0.05 * 5000;   // 5 km at 5 %
    t.rollingWork = 9.81 * 5000;
    t.airWork = 0.5 * 1.2 * 25 * 5000;    // 5 m/s
    RAPowerModel *m = [[RAPowerModel alloc] init];
    NSDictionary<NSString *, NSNumber *> *b = [m breakdownOfStats:t];
    double wheel = b[RAPowerGravity].doubleValue + b[RAPowerRolling].doubleValue + b[RAPowerAir].doubleValue
                 + b[RAPowerInertia].doubleValue;
    XCTAssertEqualWithAccuracy(wheel + b[RAPowerLosses].doubleValue, b[RAPowerTotal].doubleValue, 1e-6);
    XCTAssertEqualWithAccuracy(b[RAPowerTotal].doubleValue, [m averagePowerOfStats:t], 1e-9);
    XCTAssertGreaterThan(b[RAPowerGravity].doubleValue, b[RAPowerAir].doubleValue, @"a climb: gravity first");
    NSArray<NSArray *> *s = [m sensitivityOfStats:t];
    XCTAssertEqual(s.count, 4u);
    for (NSArray *row in s) XCTAssertGreaterThan([row[2] doubleValue], 0, @"%@", row[0]);
    XCTAssertNil([m breakdownOfStats:[[RATerrainStats alloc] init]]);
}

/// a ride with a power meter on the flat at that speed, its power that of the given rolling and air (true values)
- (RARide *)meteredRideAtSpeed:(double)v day:(int)day crr:(double)crr cdA:(double)cdA mass:(double)mass
{
    RARide *r = [[RARide alloc] initWithTrace:RATrace(@[ @1, @2 ], day * 86400) name:@"metered"];
    RARideStats *stats = [[RARideStats alloc] init];
    RATerrainStats *flat = [stats statsForTerrain:RATerrainFlat];
    flat.time = 1800;
    flat.distance = v * 1800;
    flat.rollingWork = 9.81 * flat.distance;
    flat.airWork = 0.5 * 1.225 * v * v * flat.distance;
    double power = (mass * crr * flat.rollingWork + cdA * flat.airWork) / 0.97 / flat.time;
    flat.powerSum = power * flat.time;
    flat.powerTime = flat.time;
    [stats.total add:flat];
    r.stats = stats;
    return r;
}

- (void)testCalibration
{
    RABike *bike = nil;
    RAEquipment *e = [self equipmentWithBike:&bike];
    RARide *probe = [[RARide alloc] initWithTrace:RATrace(@[ @1, @2 ], 0) name:@"p"];
    RAPowerModel *m = [RAPowerModel modelForRide:probe equipment:e];
    NSMutableArray<RARide *> *rides = [NSMutableArray array];
    int day = 0;
    for (NSNumber *v in @[ @5, @7, @9, @11, @13 ]) {
        [rides addObject:[self meteredRideAtSpeed:v.doubleValue day:day++ crr:m.crr * 1.4 cdA:0.31 mass:m.mass]];
    }
    NSArray<RACalibrationResult *> *results = [RACalibration calibrateRides:rides equipment:e];
    XCTAssertEqual(results.count, 1u);
    RACalibrationResult *r = results.firstObject;
    XCTAssertTrue(r.valid, @"%@", r.note);
    XCTAssertEqual(r.rideCount, 5u);
    XCTAssertEqualWithAccuracy(r.rollingFactor, 1.4, 0.01);
    XCTAssertEqualWithAccuracy(r.cdA, 0.31, 0.005);
    XCTAssertLessThan(r.errorAfter, 0.5);
    XCTAssertGreaterThan(r.errorBefore, r.errorAfter);

    // one speed only: rolling and air cannot be told apart
    NSArray *same = @[ [self meteredRideAtSpeed:8 day:1 crr:0.006 cdA:0.3 mass:m.mass],
                       [self meteredRideAtSpeed:8 day:2 crr:0.006 cdA:0.3 mass:m.mass],
                       [self meteredRideAtSpeed:8 day:3 crr:0.006 cdA:0.3 mass:m.mass] ];
    XCTAssertFalse([RACalibration calibrateRides:same equipment:e].firstObject.valid);
    XCTAssertEqual([RACalibration calibrateRides:@[] equipment:e].count, 0u);
}

- (void)testWindow
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager beginUndoGrouping];
    RABike *bike = [[RABike alloc] init];
    [doc changeEquipment:^(RAEquipment *e) { e.bikes = @[ bike ]; e.defaultBikeID = bike.identifier; } actionName:@"x"];
    RAPowerSettingsWindowController *wc = [[RAPowerSettingsWindowController alloc] initWithLibrary:doc];
    (void)wc.window;
    XCTAssertEqual(wc.controls.count, [RAPowerSettings allParameters].count);
    [wc setValue:@0.95 ofParameter:RAPowerEfficiency];
    XCTAssertEqual(doc.equipment.powerParameters[RAPowerEfficiency].doubleValue, 0.95);
    [wc setValue:@99 ofParameter:RAPowerWheelInertia];
    XCTAssertEqual(doc.equipment.powerParameters[RAPowerWheelInertia].doubleValue, 5, @"bounded");
    [wc setValue:nil ofParameter:RAPowerWheelInertia];
    XCTAssertNil(doc.equipment.powerParameters[RAPowerWheelInertia]);
    [doc.undoManager endUndoGrouping];

    [wc calibrate:self];
    XCTAssertEqual(wc.calibrationResults.count, 0u, @"no power meter");
    RACalibrationResult *r = [[RACalibrationResult alloc] init];
    r.bikeID = bike.identifier;
    r.bikeName = @"b";
    r.valid = YES;
    r.rollingFactor = 1.25;
    r.cdA = 0.4;
    [doc.undoManager beginUndoGrouping];
    [wc applyCalibration:r];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualWithAccuracy(doc.equipment.powerSettings.rollingScale, 1.25, 1e-9);
    XCTAssertEqualWithAccuracy([doc.equipment bikeWithID:bike.identifier].cdA, 0.4, 1e-9);
    [doc.undoManager undo];
    XCTAssertEqualWithAccuracy(doc.equipment.powerSettings.rollingScale, 1, 1e-9, @"undoable");
    [doc.undoManager beginUndoGrouping];
    [wc restoreDefaults:self];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(doc.equipment.powerParameters.count, 0u);
    [wc close];
}

@end
