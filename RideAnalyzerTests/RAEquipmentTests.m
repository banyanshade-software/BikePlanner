//
//  RAEquipmentTests.m
//  RideAnalyzerTests
//
//  Equipment (#82, R13): bikes, parts mounted over time ranges, Crr and CdA defaults, distances, wear; the library
//  (undo, default bike of the rides, saved), the filter by bike, the equipment window.
//

#import <XCTest/XCTest.h>
#import "RAEquipment.h"
#import "RAEquipmentWindowController.h"
#import "RAGarminConnect.h"
#import "RALibraryDocument.h"
#import "RAFilter.h"
#import "RARide.h"
#import "RATestSupport.h"

@interface RAEquipmentTests : XCTestCase
@end

@implementation RAEquipmentTests
{
    NSCalendar *_cal;
}

- (void)setUp
{
    _cal = [NSCalendar currentCalendar];
}

- (NSDate *)day:(NSInteger)year month:(NSInteger)month day:(NSInteger)day
{
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = year; c.month = month; c.day = day; c.hour = 10;
    return [_cal dateFromComponents:c];
}

- (RAMounting *)mountingOn:(NSString *)bike from:(NSDate *)from to:(nullable NSDate *)to
{
    RAMounting *m = [[RAMounting alloc] init];
    m.bikeID = bike;
    m.from = [_cal startOfDayForDate:from];
    m.to = to ? [_cal startOfDayForDate:to] : nil;
    return m;
}

- (RARide *)rideOn:(NSDate *)date km:(double)km bike:(NSString *)bike
{
    RARide *r = [[RARide alloc] initWithTrace:RATrace(@[ @1, @2 ], 0) name:@"r"];
    r.startDate = date;
    r.distance = km * 1000;
    r.bikeID = bike;
    return r;
}

- (void)testDefaults
{
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"Continental Grand Prix 5000" width:28], 0.0032, 1e-6);
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"GP5000" width:0], 0.0032, 1e-6);
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"Schwalbe Marathon Plus" width:40], 0.0075, 1e-6);
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"" width:25], 0.0040, 1e-6, @"by width");
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"" width:50], 0.0070, 1e-6);
    RAPart *chain = [[RAPart alloc] init];
    chain.kind = RAPartChain;
    XCTAssertEqual(chain.effectiveCrr, 0);
    RAPart *tyre = [[RAPart alloc] init];
    tyre.model = @"GP5000";
    XCTAssertEqualWithAccuracy(tyre.effectiveCrr, 0.0032, 1e-6);
    tyre.crr = 0.004;
    XCTAssertEqualWithAccuracy(tyre.effectiveCrr, 0.004, 1e-9, @"corrected by the user");

    RABike *bike = [[RABike alloc] init];
    bike.position = RAPositionDrops;
    XCTAssertEqualWithAccuracy(bike.effectiveCdA, 0.30, 1e-9);
    bike.cdA = 0.33;
    XCTAssertEqualWithAccuracy(bike.effectiveCdA, 0.33, 1e-9);
    XCTAssertEqual(bike.effectiveWeight, 12);
    XCTAssertEqual([RABike defaultPositionForKind:RABikeRoad], RAPositionHoods);
    XCTAssertEqual([[RAEquipment alloc] init].effectiveRiderWeight, 75);
}

// the owner's case: GP5000 at the front since October, Marathon Plus at the rear
- (void)testTyresOverTime
{
    RAEquipment *e = [[RAEquipment alloc] init];
    RABike *giant = [[RABike alloc] init];
    e.bikes = @[ giant ];
    RAPart *oldFront = [[RAPart alloc] init];
    oldFront.model = @"Marathon Plus";
    oldFront.wheel = RAWheelFront;
    oldFront.mountings = @[ [self mountingOn:giant.identifier from:[self day:2025 month:1 day:1] to:[self day:2026 month:9 day:30]] ];
    RAPart *front = [[RAPart alloc] init];
    front.model = @"GP5000";
    front.wheel = RAWheelFront;
    front.mountings = @[ [self mountingOn:giant.identifier from:[self day:2026 month:10 day:1] to:nil] ];
    RAPart *rear = [[RAPart alloc] init];
    rear.model = @"Marathon Plus";
    rear.wheel = RAWheelRear;
    rear.mountings = @[ [self mountingOn:giant.identifier from:[self day:2025 month:1 day:1] to:nil] ];
    e.parts = @[ oldFront, front, rear ];

    XCTAssertEqualWithAccuracy([e crrOfBike:giant.identifier atDate:[self day:2026 month:8 day:15]], 0.0075, 1e-6);
    XCTAssertEqualWithAccuracy([e crrOfBike:giant.identifier atDate:[self day:2026 month:11 day:15]],
                               0.4 * 0.0032 + 0.6 * 0.0075, 1e-6);
    XCTAssertEqualWithAccuracy([e crrOfBike:giant.identifier atDate:[self day:2024 month:6 day:1]], 0.005, 1e-9,
                               @"no tyre known yet");
    XCTAssertEqual([e partsOfBike:giant.identifier atDate:[self day:2026 month:9 day:30]].count, 2u, @"the last day counts");

    NSArray<RARide *> *rides = @[ [self rideOn:[self day:2026 month:9 day:20] km:30 bike:giant.identifier],
                                  [self rideOn:[self day:2026 month:10 day:5] km:40 bike:giant.identifier],
                                  [self rideOn:[self day:2026 month:10 day:6] km:50 bike:@"other"] ];
    XCTAssertEqualWithAccuracy([e distanceOfPart:front rides:rides], 40000, 1, @"only on its bike while mounted");
    XCTAssertEqualWithAccuracy([e distanceOfPart:rear rides:rides], 70000, 1);
    XCTAssertEqualWithAccuracy([e distanceOfBike:giant.identifier rides:rides], 70000, 1);
    rear.wearLimit = 60;
    XCTAssertEqualObjects([e wornPartsWithRides:rides], @[ rear ]);

    RAEquipment *copy = [RAEquipment equipmentWithPropertyList:e.propertyList];
    XCTAssertEqualObjects(copy.propertyList, e.propertyList, @"saved");
}

- (void)testLibrary
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager beginUndoGrouping];
    [doc importData:RATCX(@[ @1, @2 ], 0, nil, nil) fileName:@"a.tcx" error:NULL];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualObjects(doc.rides.firstObject.bikeID, @"", @"no bike yet");

    RABike *bike = [[RABike alloc] init];
    bike.name = @"Giant";
    [doc.undoManager beginUndoGrouping];
    [doc changeEquipment:^(RAEquipment *e) {
        e.bikes = @[ bike ];
        e.defaultBikeID = bike.identifier;
    } actionName:@"Add Bike"];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualObjects(doc.rides.firstObject.bikeID, bike.identifier, @"the rides without bike get the default one");
    [doc.undoManager undo];
    XCTAssertEqual(doc.equipment.bikes.count, 0u);
    XCTAssertEqualObjects(doc.rides.firstObject.bikeID, @"", @"undone with the equipment");
    [doc.undoManager redo];
    XCTAssertEqualObjects(doc.rides.firstObject.bikeID, bike.identifier);

    [doc.undoManager beginUndoGrouping];
    [doc importData:RATCX(@[ @1, @3 ], 86400, nil, nil) fileName:@"b.tcx" error:NULL];
    [doc.undoManager endUndoGrouping];
    RARide *b = [doc.rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"fileName BEGINSWITH 'b'"]].firstObject;
    XCTAssertEqualObjects(b.bikeID, bike.identifier, @"a new ride: the default bike");

    [doc.undoManager beginUndoGrouping];
    [doc setBikeID:@"other" ofRides:@[ b ]];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualObjects(b.bikeID, @"other");
    RAFilter *f = [[RAFilter alloc] init];
    f.bikeIDs = [NSSet setWithObject:bike.identifier];
    XCTAssertEqual([f filteredRides:doc.rides].count, 1u, @"filter by bike");
    XCTAssertEqualObjects([RAFilter filterWithPropertyList:f.propertyList], f);
    XCTAssertTrue([[f summaryWithDeviceLabel:^NSString *(NSString *k) { return k; }
                                   bikeLabel:^NSString *(NSString *i) { return @"Giant"; }] containsString:@"Giant"]);
    [doc.undoManager undo];
    XCTAssertEqualObjects(b.bikeID, bike.identifier);

    NSFileWrapper *package = [doc fileWrapperOfType:RALibraryDocumentType error:NULL];
    RALibraryDocument *reopened = [[RALibraryDocument alloc] init];
    XCTAssertTrue([reopened readFromFileWrapper:package ofType:RALibraryDocumentType error:NULL]);
    XCTAssertEqualObjects(reopened.equipment.propertyList, doc.equipment.propertyList, @"saved with the library");
}

- (void)testWearWarnedOnce
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:RATCX(@[ @1, @2, @3 ], 0, nil, nil) fileName:@"a.tcx" error:NULL];   // ~2.2 km
    RABike *bike = [[RABike alloc] init];
    RAPart *chain = [[RAPart alloc] init];
    chain.kind = RAPartChain;
    chain.wearLimit = 1;
    chain.mountings = @[ [self mountingOn:bike.identifier from:[self day:2020 month:1 day:1] to:nil] ];
    [doc changeEquipment:^(RAEquipment *e) {
        e.bikes = @[ bike ];
        e.defaultBikeID = bike.identifier;
        e.parts = @[ chain ];
    } actionName:@"x"];
    XCTAssertEqual([doc takeNewlyWornParts].count, 1u);
    XCTAssertEqual([doc takeNewlyWornParts].count, 0u, @"once");
}

- (void)testWindow
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:RATCX(@[ @1, @2, @3 ], 0, nil, nil) fileName:@"a.tcx" error:NULL];
    RAEquipmentWindowController *wc = [[RAEquipmentWindowController alloc] initWithLibrary:doc];
    (void)wc.window;
    [wc addBike:self];
    XCTAssertEqual(doc.equipment.bikes.count, 1u);
    XCTAssertEqualObjects(doc.equipment.defaultBikeID, doc.equipment.bikes[0].identifier, @"the first bike: default");
    XCTAssertEqual(wc.bikesTable.numberOfRows, 1);
    [wc setValue:@"11,5" forColumn:@"weight" ofBikeAtRow:0];
    [wc setValue:@"Giant Rapid" forColumn:@"name" ofBikeAtRow:0];
    [wc setValue:@(RABikeRoad) forColumn:@"kind" ofBikeAtRow:0];
    RABike *bike = doc.equipment.bikes[0];
    XCTAssertTrue(bike.weight == 11.5 || bike.weight == 115, @"decimal comma or point, as the locale reads it");
    XCTAssertEqualObjects(bike.name, @"Giant Rapid");
    XCTAssertEqual(bike.position, RAPositionHoods, @"the position follows the kind");

    [wc.bikesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [wc addPart:self];
    XCTAssertEqual(doc.equipment.parts.count, 1u);
    RAPart *part = doc.equipment.parts[0];
    XCTAssertEqualObjects(part.mountings.firstObject.bikeID, bike.identifier, @"mounted on the selected bike");
    [wc setValue:@"GP5000" forColumn:@"model" ofPartAtRow:0];
    XCTAssertEqualWithAccuracy(doc.equipment.parts[0].effectiveCrr, 0.0032, 1e-6);

    // moved to another bike: never ridden there (mounted today) → a correction
    [wc addBike:self];
    NSString *second = doc.equipment.bikes[1].identifier;
    [wc setValue:second forColumn:@"bike" ofPartAtRow:0];
    XCTAssertEqual(doc.equipment.parts[0].mountings.count, 1u);
    XCTAssertEqualObjects(doc.equipment.parts[0].mountings[0].bikeID, second);
    [wc setValue:@"" forColumn:@"bike" ofPartAtRow:0];
    XCTAssertNotNil(doc.equipment.parts[0].mountings[0].to, @"unmounted");

    RAGarminGear *g = [[RAGarminGear alloc] init];
    g.gearID = @"g1";
    g.name = @"Garmin bike";
    g.typeName = @"Bike";
    XCTAssertEqual([wc importGear:@[ g ]], 1u);
    XCTAssertEqual([wc importGear:@[ g ]], 0u, @"already there");
    XCTAssertEqualObjects(doc.equipment.bikes.lastObject.garminGearID, @"g1");
    [wc close];
}

@end
