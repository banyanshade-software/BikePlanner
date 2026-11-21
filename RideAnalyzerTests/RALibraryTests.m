//
//  RALibraryTests.m
//  RideAnalyzerTests
//
//  Ride Analyzer skeleton (#82): ride figures (R3), import with duplicates (R2), library package (R15), undo.
//

#import <XCTest/XCTest.h>
#import <CoreLocation/CoreLocation.h>
#import "RARide.h"
#import "RALibraryDocument.h"
#import "GPXParser.h"
#import "RATestSupport.h"

@interface RALibraryTests : XCTestCase
@end

@implementation RALibraryTests

- (void)testRideFigures
{
    NSArray<CLLocation *> *trace = RATrace(@[ @100, @150, @148, @200, @120 ], 0);
    RARide *ride = [[RARide alloc] initWithTrace:trace name:@"Loop"];
    XCTAssertEqualObjects(ride.name, @"Loop");
    XCTAssertEqualWithAccuracy(ride.distance, 4 * 1112, 20);
    XCTAssertEqualWithAccuracy(ride.ascent, 50 + 52, 0.001, @"the 2 m dip is below the threshold");
    XCTAssertEqualWithAccuracy(ride.duration, 2400, 0.001);
    XCTAssertEqualWithAccuracy(ride.averageSpeed, ride.distance / 2400 * 3.6, 0.001);
    XCTAssertEqualObjects(ride.startDate, trace.firstObject.timestamp);
}

- (void)testAscentIgnoresNoise
{
    NSArray<CLLocation *> *trace = RATrace(@[ @100, @102, @100, @102, @100, @102 ], 0);
    XCTAssertEqual([RARide ascentOfTrace:trace threshold:3], 0);
}

- (void)testPropertyListRoundTrip
{
    RARide *ride = [[RARide alloc] initWithTrace:RATrace(@[ @100, @180 ], 0) name:@"Col"];
    ride.format = @"fit";
    ride.fileName = @"Col.fit";
    ride.contentHash = @"abc";
    ride.notes = @"windy";
    ride.tags = @[ @"montagne" ];
    RARide *copy = [[RARide alloc] initWithPropertyList:ride.propertyList];
    XCTAssertEqualObjects(copy.propertyList, ride.propertyList);
    XCTAssertNil([[RARide alloc] initWithPropertyList:@{ @"name": @"no identifier" }]);
}

- (void)testSameRide
{
    RARide *a = [[RARide alloc] initWithTrace:RATrace(@[ @100, @120, @140 ], 0) name:@"a"];
    RARide *b = [[RARide alloc] initWithTrace:RATrace(@[ @100, @120, @140 ], 30) name:@"b"];
    RARide *later = [[RARide alloc] initWithTrace:RATrace(@[ @100, @120, @140 ], 3600) name:@"c"];
    XCTAssertTrue([a isProbablySameRideAs:b]);
    XCTAssertFalse([a isProbablySameRideAs:later]);
}

- (NSData *)tcxWithAltitudes:(NSArray<NSNumber *> *)altitudes start:(NSTimeInterval)start
{
    return RATCX(altitudes, start, nil, nil);
}

- (void)testImportDuplicatesAndUndo
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    NSData *tcx = [self tcxWithAltitudes:@[ @100, @150, @130 ] start:0];

    [doc.undoManager beginUndoGrouping];
    XCTAssertEqual([doc importData:tcx fileName:@"Morning.tcx" error:NULL], RAImportStatusImported);
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(doc.rides.count, 1u);
    RARide *ride = doc.rides.firstObject;
    XCTAssertEqualObjects(ride.name, @"Morning");
    XCTAssertEqualObjects(ride.format, @"tcx");
    XCTAssertEqualWithAccuracy(ride.duration, 1200, 0.001, @"times read from the file");
    XCTAssertEqualObjects([doc originalDataOfRide:ride], tcx);

    XCTAssertEqual([doc importData:tcx fileName:@"Copy.tcx" error:NULL], RAImportStatusDuplicate, @"same file");
    NSData *sameRide = [self tcxWithAltitudes:@[ @100, @150, @131 ] start:20]; // another file of the same ride
    XCTAssertEqual([doc importData:sameRide fileName:@"Other.tcx" error:NULL], RAImportStatusDuplicate,
                   @"same start and distance");
    NSData *junk = [@"not a track" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqual([doc importData:junk fileName:@"junk.gpx" error:NULL], RAImportStatusUnreadable);
    XCTAssertEqual(doc.rides.count, 1u);

    [doc.undoManager beginUndoGrouping];
    [doc removeRides:@[ ride ]];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(doc.rides.count, 0u);
    XCTAssertNil([doc originalDataOfRide:ride], @"the file goes with the ride");
    [doc.undoManager undo];
    XCTAssertEqual(doc.rides.count, 1u);
    XCTAssertEqualObjects([doc originalDataOfRide:doc.rides.firstObject], tcx, @"and comes back");
    [doc.undoManager undo];
    XCTAssertEqual(doc.rides.count, 0u, @"import undone");
}

// a GPX without <time> (e.g. a planned route): no date rather than the import date
- (void)testUntimedGPX
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    NSData *untimed = [GPXParser gpxDataForPoints:RATrace(@[ @10, @20 ], 0) name:@"plan" comment:nil];
    XCTAssertEqual([doc importData:untimed fileName:@"plan.gpx" error:NULL], RAImportStatusImported);
    RARide *ride = doc.rides.firstObject;
    XCTAssertEqualObjects(ride.format, @"gpx");
    XCTAssertNil(ride.startDate);
    XCTAssertEqual(ride.duration, 0);
    NSData *other = [GPXParser gpxDataForPoints:RATrace(@[ @10, @25 ], 0) name:@"plan 2" comment:nil];
    XCTAssertEqual([doc importData:other fileName:@"plan2.gpx" error:NULL], RAImportStatusImported,
                   @"no date: never taken for the same ride");
}

- (void)testRename
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager beginUndoGrouping];
    [doc importData:[self tcxWithAltitudes:@[ @100, @110 ] start:0] fileName:@"a.tcx" error:NULL];
    [doc.undoManager endUndoGrouping];
    RARide *ride = doc.rides.firstObject;
    [doc.undoManager beginUndoGrouping];
    [doc renameRide:ride to:@"Coteaux"];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualObjects(ride.name, @"Coteaux");
    [doc.undoManager undo];
    XCTAssertEqualObjects(ride.name, @"a");
}

- (void)testPackageRoundTrip
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    NSData *tcx1 = [self tcxWithAltitudes:@[ @100, @150 ] start:0];
    NSData *tcx2 = [self tcxWithAltitudes:@[ @200, @260, @240 ] start:86400];
    [doc importData:tcx1 fileName:@"ride.tcx" error:NULL];
    [doc importData:tcx2 fileName:@"ride.tcx" error:NULL];
    XCTAssertEqual(doc.rides.count, 2u);
    XCTAssertNotEqualObjects(doc.rides[0].fileName, doc.rides[1].fileName, @"same name, two files");

    NSError *error = nil;
    NSFileWrapper *package = [doc fileWrapperOfType:RALibraryDocumentType error:&error];
    XCTAssertNotNil(package, @"%@", error);
    XCTAssertNotNil(package.fileWrappers[@"Library.plist"]);
    XCTAssertEqual(package.fileWrappers[@"Rides"].fileWrappers.count, 2u);

    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                  URLByAppendingPathComponent:[NSUUID UUID].UUIDString isDirectory:YES];
    url = [url URLByAppendingPathExtension:@"ridelib"];
    XCTAssertTrue([package writeToURL:url options:0 originalContentsURL:nil error:&error], @"%@", error);
    NSFileWrapper *read = [[NSFileWrapper alloc] initWithURL:url options:NSFileWrapperReadingImmediate error:&error];
    RALibraryDocument *reopened = [[RALibraryDocument alloc] init];
    XCTAssertTrue([reopened readFromFileWrapper:read ofType:RALibraryDocumentType error:&error], @"%@", error);
    XCTAssertEqual(reopened.rides.count, 2u);
    XCTAssertEqualObjects(reopened.libraryID, doc.libraryID, @"the Keychain key goes with the library");
    NSArray *before = [doc.rides valueForKey:@"propertyList"];
    NSArray *after = [reopened.rides valueForKey:@"propertyList"];
    XCTAssertEqualObjects(after, before);
    for (RARide *r in reopened.rides) XCTAssertNotNil([reopened originalDataOfRide:r]);
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

- (void)testUnreadablePackage
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    NSFileWrapper *empty = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
    NSError *error = nil;
    XCTAssertFalse([doc readFromFileWrapper:empty ofType:RALibraryDocumentType error:&error]);
    XCTAssertNotNil(error);
}

@end
