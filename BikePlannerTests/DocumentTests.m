//
//  DocumentTests.m
//  BikePlannerTests
//
//  Load / save of .bikeplan documents (without window).
//

#import <XCTest/XCTest.h>
#import "Document.h"
#import "BikePlan.h"
#import "TestFixtures.h"

static NSString * const kType = @"fr.free.daniel.braun.bikeplan";

@interface DocumentTests : XCTestCase
@end

@implementation DocumentTests

- (void)testSaveAndLoad
{
    Document *d = [[Document alloc] init];
    d.plan.fetchPOI = NO;
    (void)[d.plan appendWaypoint:BPLoc(44, 0.5)];
    (void)[d.plan appendWaypoint:BPLoc(44.1, 0.6)];
    d.plan.brouterInfo.kmlen = 12;

    NSError *err = nil;
    NSData *data = [d dataOfType:kType error:&err];
    XCTAssertNotNil(data, @"%@", err);

    Document *d2 = [[Document alloc] init];
    XCTAssertTrue([d2 readFromData:data ofType:kType error:&err], @"%@", err);
    XCTAssertEqual(d2.plan.waypointsLocations.count, 2u);
    XCTAssertEqual(d2.plan.brouterInfo.kmlen, 12);
}

- (void)testLoadGarbageFails
{
    Document *d = [[Document alloc] init];
    NSError *err = nil;
    XCTAssertFalse([d readFromData:BPData(@"not a plist") ofType:kType error:&err]);
    XCTAssertNotNil(err);
}

- (void)testSaveWithoutPlanFails
{
    Document *d = [[Document alloc] init];
    d.plan = nil;
    NSError *err = nil;
    XCTAssertNil([d dataOfType:kType error:&err]);
    XCTAssertNotNil(err);
}

- (void)testLoadArchiveOfOtherClassFails
{
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:@[@1, @2] requiringSecureCoding:YES error:NULL];
    Document *d = [[Document alloc] init];
    NSError *err = nil;
    XCTAssertFalse([d readFromData:data ofType:kType error:&err]);
    XCTAssertNotNil(err);
}

- (void)testDocumentSettings
{
    XCTAssertTrue([Document autosavesInPlace]);
    XCTAssertEqualObjects([[Document alloc] init].windowNibName, @"Document");
}

- (void)testLoadEmptyDataFails
{
    Document *d = [[Document alloc] init];
    NSError *err = nil;
    XCTAssertFalse([d readFromData:[NSData data] ofType:kType error:&err]);
    XCTAssertNotNil(err);
}

@end
