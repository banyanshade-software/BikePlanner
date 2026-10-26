//
//  GPXExportTests.m
//  BikePlannerTests
//
//  -[MapController exportGpxDataWithPOI:trackName:] (private, exposed through a test category).
//  Tests wrapped in XCTExpectFailure document known bugs (doc/02-architecture.md §9 item 8):
//  they will start failing once the bug is fixed — then remove the XCTExpectFailure.
//

#import <XCTest/XCTest.h>
#import "MapController.h"
#import "Document.h"
#import "BikePlan.h"
#import "POILocation.h"
#import "GPXParser.h"
#import "TestFixtures.h"

@interface MapController (ExportTesting)
- (NSData *)exportGpxDataWithPOI:(BOOL)inclPOI trackName:(NSString *)trackName;
@end

@interface BikePlan (ExportTesting)
- (void)setPoiloc:(NSArray<POILocation *> *)pl;
@end

@interface GPXExportTests : XCTestCase
@end

@implementation GPXExportTests {
    Document *doc;
    MapController *mc;
}

- (void)setUp
{
    doc = [[Document alloc] init];
    doc.plan.fetchPOI = NO;
    mc = [[MapController alloc] init];
    mc.document = doc;
    mc.gpxData = BPData(kBRouterGPX);
}

- (NSString *)export:(BOOL)poi name:(NSString *)name
{
    NSData *d = [mc exportGpxDataWithPOI:poi trackName:name];
    XCTAssertNotNil(d);
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

- (BOOL)isWellFormedXML:(NSString *)s
{
    NSXMLParser *p = [[NSXMLParser alloc] initWithData:BPData(s)];
    return [p parse];
}

- (void)testTrackIsRenamed
{
    NSString *s = [self export:NO name:@"Tour of Gers"];
    XCTAssertTrue([s containsString:@"<name>Tour of Gers</name>"]);
    XCTAssertFalse([s containsString:@"brouter_trekking_0"]);
    XCTAssertTrue([self isWellFormedXML:s]);
}

- (void)testTrackPointsArePreserved
{
    NSString *s = [self export:NO name:@"t"];
    NSArray *pts = [[[GPXParser alloc] init] parseGPXData:BPData(s) error:NULL];
    XCTAssertEqual(pts.count, 3u);
}

- (void)testPOIsAreExportedAsWaypoints
{
    POILocation *w = [[POILocation alloc] initWithLatitude:44.19 longitude:0.49 ofType:POI_drinking_water info:@{} custom:NO];
    [doc.plan setPoiloc:@[w]];
    NSString *s = [self export:YES name:@"t"];
    XCTAssertTrue([s containsString:@"<wpt lat=\"44.190000\" lon=\"0.490000\">"]);
    XCTAssertTrue([s containsString:@"<type>WATER</type>"]);
    XCTAssertTrue([s hasSuffix:@"</gpx>\n"]);
    XCTAssertTrue([self isWellFormedXML:s]);
}

- (void)testPOIsAreNotExportedWhenNotRequested
{
    POILocation *w = [[POILocation alloc] initWithLatitude:44.19 longitude:0.49 ofType:POI_drinking_water info:@{} custom:NO];
    [doc.plan setPoiloc:@[w]];
    [doc.plan addCustomPoiAt:CLLocationCoordinate2DMake(44.2, 0.5)];
    NSString *s = [self export:NO name:@"t"];
    XCTAssertFalse([s containsString:@"<wpt"]);
}

- (void)testCustomPOIIsExportedAsDanger
{
    [doc.plan addCustomPoiAt:CLLocationCoordinate2DMake(44.2, 0.5)];
    NSString *s = [self export:YES name:@"t"];
    XCTAssertTrue([s containsString:@"<type>DANGER</type>"]);
}

// Known bug: custom POIs have no title, exported as "<name>(null)</name>".
- (void)testCustomPOIHasAName
{
    [doc.plan addCustomPoiAt:CLLocationCoordinate2DMake(44.2, 0.5)];
    NSString *s = [self export:YES name:@"t"];
    XCTExpectFailure(@"custom POI title is nil (doc/02-architecture.md §9 item 8)");
    XCTAssertFalse([s containsString:@"(null)"]);
}

// Known bug: text is not XML-escaped.
- (void)testTrackNameIsXMLEscaped
{
    NSString *s = [self export:NO name:@"Fish & Chips <3"];
    XCTExpectFailure(@"track name not XML-escaped (doc/02-architecture.md §9 item 8)");
    XCTAssertTrue([self isWellFormedXML:s]);
}

@end
