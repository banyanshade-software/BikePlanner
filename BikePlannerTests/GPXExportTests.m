//
//  GPXExportTests.m
//  BikePlannerTests
//
//  -[MapController exportGpxDataWithPOI:trackName:] (private, exposed through a test category).
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

// custom POIs have no title: they must not be exported as "<name>(null)</name>" (#11)
- (void)testCustomPOIHasAName
{
    [doc.plan addCustomPoiAt:CLLocationCoordinate2DMake(44.2, 0.5)];
    NSString *s = [self export:YES name:@"t"];
    XCTAssertFalse([s containsString:@"(null)"]);
    XCTAssertTrue([s containsString:@"<name>DANGER</name>"]);
}

// text is XML-escaped (#11)
- (void)testTrackNameIsXMLEscaped
{
    NSString *s = [self export:NO name:@"Fish & Chips <3"];
    XCTAssertTrue([self isWellFormedXML:s]);
    XCTAssertTrue([s containsString:@"<name>Fish &amp; Chips &lt;3</name>"]);
}

// A GPX exported with POIs can be imported back as a reference trace: same points as the route,
// the POIs are waypoints, not trace points (#28)
- (void)testExportWithPOIsCanBeImportedAsTrace
{
    POILocation *w = [[POILocation alloc] initWithLatitude:44.19 longitude:0.49 ofType:POI_drinking_water info:@{} custom:NO];
    [doc.plan setPoiloc:@[w]];
    [doc.plan addCustomPoiAt:CLLocationCoordinate2DMake(44.2, 0.5)];
    NSString *s = [self export:YES name:@"Tour & detours"];

    GPXParser *exported = [[GPXParser alloc] init];
    NSArray<CLLocation *> *pts = [exported parseGPXData:BPData(s) error:NULL];
    NSArray<CLLocation *> *route = [[[GPXParser alloc] init] parseGPXData:mc.gpxData error:NULL];
    XCTAssertEqual(pts.count, route.count);
    for (NSUInteger i = 0; i < MIN(pts.count, route.count); i++) {
        XCTAssertEqualWithAccuracy(pts[i].coordinate.latitude, route[i].coordinate.latitude, 1e-9);
        XCTAssertEqualWithAccuracy(pts[i].coordinate.longitude, route[i].coordinate.longitude, 1e-9);
    }
    XCTAssertEqual(exported.waypoints.count, 2u);
}

// excluded POIs are not exported (#5)
- (void)testExcludedPOIsAreNotExported
{
    [doc.plan addCustomPoiAt:CLLocationCoordinate2DMake(44.19, 0.49)];
    [doc.plan addCustomPoiAt:CLLocationCoordinate2DMake(44.20, 0.50)];
    POILocation *water = [[POILocation alloc] initWithLatitude:44.1 longitude:0.51 ofType:POI_drinking_water
                                                          info:@{ @"id": @7 } custom:NO];
    POILocation *wc = [[POILocation alloc] initWithLatitude:44.3 longitude:0.61 ofType:POI_toilets
                                                       info:@{ @"id": @8 } custom:NO];
    [doc.plan setPoiloc:@[water, wc]];
    [doc.plan setPOI:doc.plan.customPoiloc[0] excluded:YES];
    [doc.plan setPOI:water excluded:YES];
    NSString *s = [self export:YES name:@"t"];
    XCTAssertFalse([s containsString:@"lat=\"44.100000\""], @"excluded fetched POI");
    XCTAssertTrue([s containsString:@"lat=\"44.300000\""]);
    XCTAssertFalse([s containsString:@"lat=\"44.190000\""], @"excluded custom POI");
    XCTAssertTrue([s containsString:@"lat=\"44.200000\""]);
}

@end
