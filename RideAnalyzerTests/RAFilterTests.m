//
//  RAFilterTests.m
//  RideAnalyzerTests
//
//  Search and filters of the rides (#82, R3): criteria, saved filters, notes and tags.
//

#import <XCTest/XCTest.h>
#import "RAFilter.h"
#import "RARide.h"
#import "RALibraryDocument.h"
#import "RATestSupport.h"

@interface RAFilterTests : XCTestCase
@end

@implementation RAFilterTests
{
    NSCalendar *_cal;
}

- (void)setUp
{
    _cal = [NSCalendar currentCalendar];
}

- (NSDate *)day:(NSInteger)year month:(NSInteger)month day:(NSInteger)day hour:(NSInteger)hour
{
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = year; c.month = month; c.day = day; c.hour = hour;
    return [_cal dateFromComponents:c];
}

- (RARide *)ride:(NSString *)name date:(nullable NSDate *)date km:(double)km ascent:(double)ascent device:(NSString *)device
{
    RARide *r = [[RARide alloc] init];
    r.name = name;
    r.startDate = date;
    r.distance = km * 1000;
    r.ascent = ascent;
    r.deviceKey = device;
    return r;
}

- (void)testEmptyFilterKeepsEverything
{
    RAFilter *f = [[RAFilter alloc] init];
    XCTAssertTrue(f.empty);
    RARide *r = [self ride:@"x" date:nil km:1 ascent:0 device:@""];
    XCTAssertTrue([f matchesRide:r]);
    f.text = @"   ";
    XCTAssertTrue(f.empty, @"blanks only");
}

- (void)testTextSearch
{
    RARide *r = [self ride:@"Boucle des Côteaux" date:nil km:60 ascent:700 device:@""];
    r.notes = @"vent du sud-ouest";
    r.tags = @[ @"entraînement" ];
    RAFilter *f = [[RAFilter alloc] init];
    for (NSString *t in @[ @"boucle", @"COTEAUX", @"coteaux boucle", @"vent", @"entrainement" ]) {
        f.text = t;
        XCTAssertTrue([f matchesRide:r], @"%@", t);
    }
    f.text = @"boucle lac";
    XCTAssertFalse([f matchesRide:r], @"every word must be found");
}

- (void)testPeriod
{
    RARide *morning = [self ride:@"a" date:[self day:2026 month:11 day:16 hour:8] km:10 ascent:0 device:@""];
    RARide *evening = [self ride:@"b" date:[self day:2026 month:11 day:16 hour:23] km:10 ascent:0 device:@""];
    RARide *undated = [self ride:@"c" date:nil km:10 ascent:0 device:@""];
    RAFilter *f = [[RAFilter alloc] init];
    f.fromDay = [self day:2026 month:11 day:16 hour:12]; // the whole day counts
    f.toDay = [self day:2026 month:11 day:16 hour:12];
    XCTAssertTrue([f matchesRide:morning]);
    XCTAssertTrue([f matchesRide:evening]);
    XCTAssertFalse([f matchesRide:undated], @"no date: not in a period");
    f.toDay = [self day:2026 month:11 day:15 hour:12];
    f.fromDay = nil;
    XCTAssertFalse([f matchesRide:morning]);
}

- (void)testDeviceDistanceAscentTags
{
    RARide *edge = [self ride:@"a" date:nil km:85 ascent:900 device:@"p1-s1"];
    edge.tags = @[ @"club" ];
    RARide *watch = [self ride:@"b" date:nil km:12 ascent:50 device:@"p2-s2"];
    NSArray *rides = @[ edge, watch ];
    RAFilter *f = [[RAFilter alloc] init];
    f.deviceKeys = [NSSet setWithObject:@"p1-s1"];
    XCTAssertEqualObjects([f filteredRides:rides], @[ edge ], @"the Edge only (no estimated power on the watch)");
    f = [[RAFilter alloc] init];
    f.minDistance = 30000;
    XCTAssertEqualObjects([f filteredRides:rides], @[ edge ], @"> 30 km");
    f = [[RAFilter alloc] init];
    f.maxDistance = 30000;
    XCTAssertEqualObjects([f filteredRides:rides], @[ watch ]);
    f = [[RAFilter alloc] init];
    f.minAscent = 500;
    XCTAssertEqualObjects([f filteredRides:rides], @[ edge ]);
    f = [[RAFilter alloc] init];
    f.tags = [NSSet setWithObjects:@"club", @"gravel", nil];
    XCTAssertEqualObjects([f filteredRides:rides], @[ edge ], @"any of the tags");
    // combined
    f.deviceKeys = [NSSet setWithObject:@"p2-s2"];
    XCTAssertEqual([f filteredRides:rides].count, 0u);
}

- (void)testPropertyListAndSummary
{
    RAFilter *f = [[RAFilter alloc] init];
    f.text = @"col";
    f.fromDay = [self day:2026 month:1 day:1 hour:0];
    f.deviceKeys = [NSSet setWithObject:@"p1-s1"];
    f.minDistance = 30000;
    f.tags = [NSSet setWithObject:@"montagne"];
    RAFilter *copy = [RAFilter filterWithPropertyList:f.propertyList];
    XCTAssertEqualObjects(copy, f);
    XCTAssertEqualObjects([f copy], f);
    XCTAssertTrue([[RAFilter filterWithPropertyList:nil] isEmpty]);
    NSString *summary = [f summaryWithDeviceLabel:^NSString *(NSString *key) { return @"Edge"; }];
    XCTAssertTrue([summary containsString:@"Edge"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"> 30 km"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"#montagne"], @"%@", summary);
    XCTAssertEqualObjects([f filterWithText:@"lac"].text, @"lac");
    XCTAssertEqualObjects(f.text, @"col", @"a copy");
}

- (void)testSavedFiltersNotesAndTagsInTheLibrary
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager beginUndoGrouping];
    [doc importData:RATCX(@[ @1, @2 ], 0, nil, nil) fileName:@"a.tcx" error:NULL];
    [doc.undoManager endUndoGrouping];
    RARide *ride = doc.rides.firstObject;

    [doc.undoManager beginUndoGrouping];
    [doc setTags:@[ @" #club ", @"gravel", @"club", @"" ] ofRide:ride];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualObjects(ride.tags, (@[ @"club", @"gravel" ]), @"trimmed, # and duplicates dropped");
    XCTAssertEqualObjects(doc.allTags, (@[ @"club", @"gravel" ]));
    [doc.undoManager beginUndoGrouping];
    [doc setNotes:@"crevaison" ofRide:ride];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualObjects(ride.notes, @"crevaison");
    [doc.undoManager undo];
    XCTAssertEqualObjects(ride.notes, @"");
    [doc.undoManager undo];
    XCTAssertEqual(ride.tags.count, 0u);

    RAFilter *f = [[RAFilter alloc] init];
    f.minDistance = 30000;
    [doc.undoManager beginUndoGrouping];
    RASavedFilter *saved = [doc saveFilter:f name:@"Plus de 30 km"];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(doc.savedFilters.count, 1u);
    f.minDistance = 1; // the saved filter is a copy
    XCTAssertEqualWithAccuracy(saved.filter.minDistance, 30000, 1e-9);
    [doc.undoManager beginUndoGrouping];
    [doc renameSavedFilter:saved to:@"> 30 km"];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualObjects(saved.name, @"> 30 km");
    [doc.undoManager beginUndoGrouping];
    [doc removeSavedFilter:saved];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(doc.savedFilters.count, 0u);
    [doc.undoManager undo];
    XCTAssertEqual(doc.savedFilters.count, 1u);

    // saved with the library
    NSFileWrapper *package = [doc fileWrapperOfType:RALibraryDocumentType error:NULL];
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:
                  [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"ridelib"]];
    XCTAssertTrue([package writeToURL:url options:0 originalContentsURL:nil error:NULL]);
    RALibraryDocument *reopened = [[RALibraryDocument alloc] init];
    XCTAssertTrue([reopened readFromFileWrapper:[[NSFileWrapper alloc] initWithURL:url options:NSFileWrapperReadingImmediate error:NULL]
                                         ofType:RALibraryDocumentType error:NULL]);
    XCTAssertEqualObjects(reopened.savedFilters.firstObject.name, @"> 30 km");
    XCTAssertEqualObjects(reopened.savedFilters.firstObject.filter, saved.filter);
    XCTAssertEqualObjects(reopened.savedFilters.firstObject.identifier, saved.identifier);
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

@end
