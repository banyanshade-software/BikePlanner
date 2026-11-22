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
#import "RARideDetailController.h"
#import "RATyreDatabase.h"
#import "RATyreDatabaseWindowController.h"
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
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"Continental Grand Prix 5000" width:28], 0.00363, 1e-6);
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"GP5000" width:0], 0.00363, 1e-6);
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"Schwalbe Marathon Plus" width:40], 0.00764, 1e-6);
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"" width:25], 0.0040, 1e-6, @"by width");
    XCTAssertEqualWithAccuracy([RAPart defaultCrrForModel:@"" width:50], 0.0070, 1e-6);
    RAPart *chain = [[RAPart alloc] init];
    chain.kind = RAPartChain;
    XCTAssertEqual(chain.effectiveCrr, 0);
    RAPart *tyre = [[RAPart alloc] init];
    tyre.model = @"GP5000";
    XCTAssertEqualWithAccuracy(tyre.effectiveCrr, 0.00363, 1e-6);
    tyre.crr = 0.004;
    XCTAssertEqualWithAccuracy(tyre.effectiveCrr, 0.004, 1e-9, @"corrected by the user");

    RABike *bike = [[RABike alloc] init];
    bike.position = RAPositionDrops;
    XCTAssertEqualWithAccuracy(bike.effectiveCdA, 0.30, 1e-9);
    bike.cdA = 0.33;
    XCTAssertEqualWithAccuracy(bike.effectiveCdA, 0.33, 1e-9);
    XCTAssertEqual(bike.effectiveWeight, 11, @"typical weight of a hybrid");
    bike.kind = RABikeElectric;
    XCTAssertEqual(bike.effectiveWeight, 23);
    bike.weight = 21.5;
    XCTAssertEqual(bike.effectiveWeight, 21.5);
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

    XCTAssertEqualWithAccuracy([e crrOfBike:giant.identifier atDate:[self day:2026 month:8 day:15]], 0.00764, 1e-6);
    XCTAssertEqualWithAccuracy([e crrOfBike:giant.identifier atDate:[self day:2026 month:11 day:15]],
                               0.4 * 0.00363 + 0.6 * 0.00764, 1e-6);
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
    XCTAssertEqualWithAccuracy(doc.equipment.parts[0].effectiveCrr, 0.00363, 1e-6);

    // moved to another bike: never ridden there (mounted today) → a correction
    [wc addBike:self];
    NSString *second = doc.equipment.bikes[1].identifier;
    [wc setValue:second forColumn:@"bike" ofPartAtRow:0];
    XCTAssertEqual(doc.equipment.parts[0].mountings.count, 1u);
    XCTAssertEqualObjects(doc.equipment.parts[0].mountings[0].bikeID, second);
    [wc setValue:@"" forColumn:@"bike" ofPartAtRow:0];
    XCTAssertNotNil(doc.equipment.parts[0].mountings[0].to, @"unmounted");
    [wc close];
}

// each ride shows its equipment (owner's request): its bike, the parts mounted that day, mass, Crr, CdA
- (void)testEquipmentOfARideInTheDetail
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:RATCX(@[ @1, @2, @3 ], 0, nil, nil) fileName:@"a.tcx" error:NULL];
    RARide *ride = doc.rides.firstObject;
    RABike *giant = [[RABike alloc] init];
    giant.name = @"Giant";
    RABike *road = [[RABike alloc] init];
    road.name = @"Route";
    RAPart *front = [[RAPart alloc] init];
    front.model = @"GP5000";
    front.wheel = RAWheelFront;
    front.mountings = @[ [self mountingOn:giant.identifier from:[self day:2020 month:1 day:1] to:nil] ];
    [doc changeEquipment:^(RAEquipment *e) {
        e.bikes = @[ giant, road ];
        e.defaultBikeID = giant.identifier;
        e.parts = @[ front ];
    } actionName:@"x"];

    RARideDetailController *detail = [[RARideDetailController alloc] init];
    detail.library = doc;
    [detail showRides:@[ ride ]];
    NSPopUpButton *bike = [detail valueForKey:@"_bikePopup"];
    NSTextField *equipment = [detail valueForKey:@"_equipment"];
    XCTAssertEqualObjects(bike.titleOfSelectedItem, @"Giant");
    XCTAssertTrue([equipment.stringValue containsString:@"GP5000"], @"%@", equipment.stringValue);
    XCTAssertTrue([equipment.stringValue containsString:@"86 kg"], @"75 kg rider, 11 kg hybrid bike");

    [bike selectItemWithTitle:@"Route"];
    [bike sendAction:bike.action to:bike.target];
    XCTAssertEqualObjects(ride.bikeID, road.identifier);
    [detail refreshRideInfo];
    XCTAssertFalse([equipment.stringValue containsString:@"GP5000"], @"no tyre known on the other bike");
}

// the tyre database (owner's request): published Crr per tyre, the default Crr of a tyre part
- (void)testTyreDatabase
{
    RATyreDatabase *db = [RATyreDatabase shared];
    XCTAssertGreaterThanOrEqual(db.tyres.count, 20u, @"RATyres.plist in the app's resources");
    XCTAssertTrue(db.note.length > 0);
    XCTAssertEqualObjects([db tyreMatchingModel:@"GP5000" width:25].name, @"Continental Grand Prix 5000");
    XCTAssertEqualObjects([db tyreMatchingModel:@"Continental GP 5000 TL" width:25].model, @"Grand Prix 5000 TL");
    XCTAssertEqualObjects([db tyreMatchingModel:@"Marathon Plus 40-622" width:40].model, @"Marathon Plus", @"the most specific name");
    XCTAssertEqualObjects([db tyreMatchingModel:@"Schwalbe Marathon" width:37].model, @"Marathon");
    XCTAssertEqual([db tyreMatchingModel:@"GravelKing" width:35].width, 35, @"the nearest width");
    XCTAssertEqual([db tyreMatchingModel:@"GravelKing" width:42].width, 40);
    XCTAssertNil([db tyreMatchingModel:@"Unknown Tyre" width:30]);
    XCTAssertNil([db tyreMatchingModel:@"" width:30]);
    XCTAssertGreaterThan([db tyresMatchingText:@"gravel"].count, 5u);
    XCTAssertEqual([db tyresMatchingText:@"marathon plus"].count, 2u, @"Plus and E-Plus");

    RATyreDatabase *custom = [[RATyreDatabase alloc] initWithPropertyList:@{ @"tyres": @[
        @{ @"brand": @"B", @"model": @"M", @"width": @30, @"crr": @0.004 }, @{ @"model": @"no crr" } ] }];
    XCTAssertEqual(custom.tyres.count, 1u, @"rows without Crr ignored");
}

- (void)testTyreDatabaseWindowGivesTheTyreToThePart
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    RAEquipmentWindowController *wc = [[RAEquipmentWindowController alloc] initWithLibrary:doc];
    (void)wc.window;
    [wc addBike:self];
    RATyre *gp = [[RATyreDatabase shared] tyreMatchingModel:@"GP5000" width:25];
    [wc useTyre:gp];     // no part selected: a new tyre
    XCTAssertEqual(doc.equipment.parts.count, 1u);
    RAPart *p = doc.equipment.parts[0];
    XCTAssertEqualObjects(p.model, @"Continental Grand Prix 5000");
    XCTAssertEqual(p.width, 25);
    XCTAssertEqual(p.crr, 0, @"the default: from the database");
    XCTAssertEqualWithAccuracy(p.effectiveCrr, gp.crr, 1e-9);
    XCTAssertEqualObjects(p.name, @"Grand Prix 5000");

    RATyreDatabaseWindowController *db = [[RATyreDatabaseWindowController alloc] initWithDatabase:[RATyreDatabase shared]];
    __block RATyre *used = nil;
    db.useHandler = ^(RATyre *t) { used = t; };
    db.search.stringValue = @"energizer";
    [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:db.search];
    XCTAssertEqual(db.shownTyres.count, 1u);
    [db.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [db useSelectedTyre:self];
    XCTAssertEqualObjects(used.model, @"Energizer Plus");
    [wc close];
}

// tyre pressure and road surface (owner's request: better power estimate, tyres and their Crr first)
- (void)testPressureAndSurface
{
    RATyre *gp = [[RATyreDatabase shared] tyreMatchingModel:@"GP5000" width:28];
    XCTAssertGreaterThan(gp.pressureBar, 3, @"the test pressure is parsed from the database");
    RAPart *tyre = [[RAPart alloc] init];
    tyre.model = @"GP5000";
    tyre.width = 28;
    double base = tyre.effectiveCrr;
    tyre.pressure = gp.pressureBar;
    XCTAssertEqualWithAccuracy(tyre.effectiveCrr, base, 1e-9, @"at the test pressure");
    tyre.pressure = gp.pressureBar - 1.5;
    XCTAssertGreaterThan(tyre.effectiveCrr, base * 1.1, @"softer: more rolling resistance");
    tyre.pressure = 1;
    XCTAssertLessThanOrEqual(tyre.effectiveCrr, base * 1.5 + 1e-9, @"bounded");
    RAPart *read = [RAPart partWithPropertyList:tyre.propertyList];
    XCTAssertEqual(read.pressure, 1);

    XCTAssertEqualWithAccuracy([RABike rollingFactorOfSurface:RASurfaceAsphalt], 1.3, 1e-9);
    XCTAssertGreaterThan([RABike rollingFactorOfSurface:RASurfaceGravel], [RABike rollingFactorOfSurface:RASurfaceRoughAsphalt]);
    RABike *bike = [[RABike alloc] init];
    XCTAssertEqual(bike.surface, RASurfaceAsphalt);
    bike.surface = RASurfaceGravel;
    bike.model = @"Giant Rapid 4";
    RABike *b2 = [RABike bikeWithPropertyList:bike.propertyList];
    XCTAssertEqual(b2.surface, RASurfaceGravel);
    XCTAssertEqualObjects(b2.model, @"Giant Rapid 4");
    XCTAssertEqual([RABike bikeWithPropertyList:@{ @"identifier": @"x" }].surface, RASurfaceAsphalt, @"older libraries");
}

// the tyres of a bike as its sheet shows them: changing a tyre keeps the old one in the history (owner's request)
- (void)testChangingATyre
{
    RAEquipment *e = [[RAEquipment alloc] init];
    RABike *bike = [[RABike alloc] init];
    e.bikes = @[ bike ];
    NSString *b = bike.identifier;
    RAPart *pair = [e mountTyreOnBike:b wheel:RAWheelBoth fromDate:nil];
    pair.model = @"Marathon Plus";
    XCTAssertEqualObjects([e tyreOfBike:b wheel:RAWheelFront atDate:[self day:2024 month:5 day:1]], pair, @"since always");
    XCTAssertEqualObjects([e tyreOfBike:b wheel:RAWheelRear atDate:[NSDate date]], pair);

    // October 1st: a GP5000 at the front; the rear keeps the Marathon Plus
    RAPart *front = [e mountTyreOnBike:b wheel:RAWheelFront fromDate:[self day:2026 month:10 day:1]];
    front.model = @"GP5000";
    XCTAssertEqualObjects([e tyreOfBike:b wheel:RAWheelFront atDate:[self day:2026 month:9 day:30]].model, @"Marathon Plus");
    XCTAssertEqualObjects([e tyreOfBike:b wheel:RAWheelFront atDate:[self day:2026 month:10 day:2]], front);
    RAPart *rear = [e tyreOfBike:b wheel:RAWheelRear atDate:[self day:2026 month:10 day:2]];
    XCTAssertEqualObjects(rear.model, @"Marathon Plus");
    XCTAssertEqual(rear.wheel, RAWheelRear, @"the other tyre of the pair goes on");
    XCTAssertNotNil(pair.mountings.lastObject.to, @"the pair taken off the day before");
    XCTAssertEqual([e tyreHistoryOfBike:b].count, 3u);
    XCTAssertEqualObjects([e tyreHistoryOfBike:b].lastObject, pair, @"the oldest last");

    // the same day again: a correction, not a new history entry
    RAPart *fixed = [e mountTyreOnBike:b wheel:RAWheelFront fromDate:[self day:2026 month:10 day:1]];
    fixed.model = @"GP5000 S TR";
    XCTAssertFalse([e.parts containsObject:front], @"mounted only that day: replaced");
    XCTAssertEqual([e tyreHistoryOfBike:b].count, 3u);
    XCTAssertEqualWithAccuracy([e crrOfBike:b atDate:[self day:2026 month:10 day:2]],
                               0.4 * fixed.effectiveCrr + 0.6 * rear.effectiveCrr, 1e-9);
}

- (void)testBikeSheet
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager beginUndoGrouping];
    [doc importData:RATCX(@[ @1, @2, @3 ], 0, nil, nil) fileName:@"a.tcx" error:NULL];
    RAEquipmentWindowController *wc = [[RAEquipmentWindowController alloc] initWithLibrary:doc];
    (void)wc.window;
    [wc addBike:self];
    XCTAssertEqual(wc.bikesTable.selectedRow, 0, @"the sheet shows the first bike");
    [wc setValue:@"Giant" forBikeField:@"name"];
    [wc setValue:@"Giant Rapid 4" forBikeField:@"model"];
    [wc setValue:@(RASurfaceRoughAsphalt) forBikeField:@"surface"];
    RABike *bike = doc.equipment.bikes[0];
    XCTAssertEqualObjects(bike.model, @"Giant Rapid 4");
    XCTAssertEqual(bike.surface, RASurfaceRoughAsphalt);
    XCTAssertEqualObjects(wc.sheetControls[@"bikeName"].stringValue, @"Giant");
    XCTAssertEqualObjects(((NSTextField *)wc.sheetControls[@"bikeWeight"]).placeholderString, @"11", @"typical weight");

    // tyres: chosen from the database, the first ones count since always
    RATyre *gp = [[RATyreDatabase shared] tyreMatchingModel:@"GP5000" width:28];
    [wc setValue:gp.displayName forTyreField:@"model" wheel:RAWheelFront];
    [wc setValue:@"Marathon Plus" forTyreField:@"model" wheel:RAWheelRear];
    [wc setValue:@"4" forTyreField:@"pressure" wheel:RAWheelRear];
    RAEquipment *e = doc.equipment;
    RAPart *front = [e tyreOfBike:bike.identifier wheel:RAWheelFront atDate:[NSDate date]];
    RAPart *rear = [e tyreOfBike:bike.identifier wheel:RAWheelRear atDate:[NSDate date]];
    XCTAssertEqual(front.wheel, RAWheelFront);
    XCTAssertEqual(front.width, gp.width);
    XCTAssertEqual(rear.pressure, 4);
    XCTAssertNotNil([e tyreOfBike:bike.identifier wheel:RAWheelRear atDate:[self day:2020 month:1 day:1]]);
    XCTAssertTrue([wc.sheetControls[@"frontTyreModel"].stringValue containsString:@"5000"]);
    XCTAssertTrue([wc.sheetFigures.stringValue containsString:@"86 kg"], @"%@", wc.sheetFigures.stringValue);
    XCTAssertEqual(wc.tyreHistoryTable.numberOfRows, 2);

    [doc.undoManager endUndoGrouping];

    // Change Tyre…: a new rear tyre from today, the old one in the history
    [doc.undoManager beginUndoGrouping];
    [wc changeTyreOnWheel:RAWheelRear model:@"Marathon Racer" width:37 date:[NSDate date]];
    [doc.undoManager endUndoGrouping];
    e = doc.equipment;
    RAPart *newRear = [e tyreOfBike:bike.identifier wheel:RAWheelRear atDate:[NSDate date]];
    XCTAssertEqualObjects(newRear.model, @"Marathon Racer");
    XCTAssertEqual(newRear.pressure, 4, @"the pressure of the previous tyre");
    XCTAssertEqualObjects([e tyreOfBike:bike.identifier wheel:RAWheelRear atDate:[self day:2020 month:1 day:1]].model,
                          @"Marathon Plus", @"older rides keep the old tyre");
    XCTAssertEqual(wc.tyreHistoryTable.numberOfRows, 3);
    [doc.undoManager undo];
    XCTAssertEqualObjects([doc.equipment tyreOfBike:bike.identifier wheel:RAWheelRear atDate:[NSDate date]].model,
                          @"Marathon Plus", @"undoable");
    [wc close];
}

@end
