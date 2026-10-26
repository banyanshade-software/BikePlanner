//
//  UndoTests.m
//  BikePlannerTests
//
//  Custom POIs and reference trace are undoable and mark the document as edited (issue #8).
//  MapController runs without a map view (messages to nil mapView are no-ops).
//

#import <XCTest/XCTest.h>
#import "MapController.h"
#import "Document.h"
#import "BikePlan.h"
#import "TestFixtures.h"

@interface MapController (UndoTesting)
- (void)addCustomPoiAt:(CLLocationCoordinate2D)coord;
- (void)loadGPXFromURL:(NSURL *)url;
@end

@interface UndoTests : XCTestCase
@end

@implementation UndoTests {
    Document *doc;
    MapController *mc;
    NSUndoManager *um;
}

- (void)setUp
{
    doc = [[Document alloc] init];
    doc.plan.fetchPOI = NO;
    mc = [[MapController alloc] init];
    mc.document = doc;
    um = doc.undoManager;
    um.groupsByEvent = NO;
}

- (void)inGroup:(void (^)(void))block
{
    [um beginUndoGrouping];
    block();
    [um endUndoGrouping];
    // NSDocument updates its edited state asynchronously
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

- (void)testAddCustomPoiIsUndoable
{
    XCTAssertFalse(doc.isDocumentEdited);
    [self inGroup:^{ [self->mc addCustomPoiAt:CLLocationCoordinate2DMake(44, 0.5)]; }];
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);
    XCTAssertTrue(doc.isDocumentEdited);
    XCTAssertEqualObjects(um.undoActionName, @"add POI");

    [um undo];
    XCTAssertEqual(doc.plan.customPoiloc.count, 0u);
    [um redo];
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);

    // still mutable after undo/redo
    [self inGroup:^{ [self->mc addCustomPoiAt:CLLocationCoordinate2DMake(44.1, 0.6)]; }];
    XCTAssertEqual(doc.plan.customPoiloc.count, 2u);
    [um undo];
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);
}

- (void)testImportReferenceTraceIsUndoable
{
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                         [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"gpx"]]];
    XCTAssertTrue([BPData(kBRouterGPX) writeToURL:url atomically:YES]);

    XCTAssertFalse(doc.isDocumentEdited);
    [self inGroup:^{ [self->mc loadGPXFromURL:url]; }];
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 3u);
    XCTAssertTrue(doc.isDocumentEdited);
    XCTAssertEqualObjects(um.undoActionName, @"import trace");

    [um undo];
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 0u);
    [um redo];
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 3u);

    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

@end
