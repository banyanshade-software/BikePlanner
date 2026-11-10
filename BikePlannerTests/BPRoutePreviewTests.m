//
//  BPRoutePreviewTests.m
//  BikePlannerTests
//
//  Quick Look preview of documents and GPX files (#70): what is read from the file, the summary, the drawing, and
//  the extension embedded in the app. The Apple Maps snapshot is not tested (network).
//

#import <XCTest/XCTest.h>
#import "BPRoutePreview.h"
#import "BikePlan.h"
#import "GPXParser.h"
#import "TestFixtures.h"

@interface BPRoutePreviewTests : XCTestCase
@end

@implementation BPRoutePreviewTests

// a route of 21 points from (44, 0.5) to (44.2, 0.7), elevations up and down
- (NSArray<CLLocation *> *)route
{
    NSMutableArray *r = [NSMutableArray array];
    for (int i = 0; i <= 20; i++) [r addObject:BPLocAlt(44 + i * 0.01, 0.5 + i * 0.01, 100 + 10 * (i % 5))];
    return r;
}

- (BikePlan *)planInStages
{
    BikePlan *plan = [[BikePlan alloc] init];
    NSArray<CLLocation *> *route = [self route];
    (void)[plan appendWaypoint:route[0]];
    (void)[plan appendWaypoint:route[8]];
    (void)[plan appendWaypoint:route[20]];
    (void)[plan setStageEnd:YES atWaypointIndex:1];
    plan.routePoints = route;
    plan.brouterInfo.meters = 27500;
    plan.brouterInfo.kmlen = 27;
    plan.brouterInfo.mup = 150;
    plan.brouterInfo.seconds = 5400;
    [plan addCustomPoiAt:CLLocationCoordinate2DMake(44.05, 0.56)];
    [plan addCustomPoiAt:CLLocationCoordinate2DMake(44.15, 0.64)];
    [plan setPOI:plan.customPoiloc.lastObject excluded:YES];
    plan.gpxDisplayed = @[BPLoc(44.0, 0.52), BPLoc(44.2, 0.72)];
    return plan;
}

- (NSData *)archive:(BikePlan *)plan
{
    NSError *err = nil;
    NSData *d = [NSKeyedArchiver archivedDataWithRootObject:plan requiringSecureCoding:YES error:&err];
    XCTAssertNotNil(d, @"%@", err);
    return d;
}

// a document: the route cut in stages, BRouter's length, ascent and time, the POIs that are not excluded
- (void)testBikePlanPreview
{
    NSError *err = nil;
    BPRoutePreview *p = [BPRoutePreview previewOfBikePlanData:[self archive:[self planInStages]] name:@"Trip" error:&err];
    XCTAssertNotNil(p, @"%@", err);
    XCTAssertEqualObjects(p.name, @"Trip");
    XCTAssertEqual(p.stages.count, 2u);
    XCTAssertEqual(p.stages[0].count + p.stages[1].count, 22u, @"the stage end in both stages");
    XCTAssertEqual(p.waypoints.count, 0u, @"a route: no waypoints drawn");
    XCTAssertEqual(p.referenceTrace.count, 2u);
    XCTAssertEqual(p.pois.count, 1u, @"the excluded POI is not shown");
    XCTAssertEqual(p.length, 27500);
    XCTAssertEqual(p.ascent, 150);
    XCTAssertEqual(p.duration, 5400);
    NSString *summary = p.summary;
    XCTAssertTrue([summary containsString:@"27"], @"%@", summary);
    XCTAssertTrue([summary containsString:@" km"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"↑ 150 m"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"1 h 30"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"2 stages"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"1 POI"], @"%@", summary);
}

// a document saved before #30: length in kilometers only
- (void)testBikePlanOldLength
{
    BikePlan *plan = [self planInStages];
    plan.brouterInfo.meters = 0;
    BPRoutePreview *p = [BPRoutePreview previewOfBikePlanData:[self archive:plan] name:@"Old" error:NULL];
    XCTAssertEqual(p.length, 27000);
}

// waypoints without a computed route: drawn as such, no length
- (void)testBikePlanWithoutRoute
{
    BikePlan *plan = [[BikePlan alloc] init];
    (void)[plan appendWaypoint:BPLoc(44, 0.5)];
    (void)[plan appendWaypoint:BPLoc(44.1, 0.6)];
    BPRoutePreview *p = [BPRoutePreview previewOfBikePlanData:[self archive:plan] name:@"Draft" error:NULL];
    XCTAssertNotNil(p);
    XCTAssertEqual(p.stages.count, 0u);
    XCTAssertEqual(p.waypoints.count, 2u);
    XCTAssertEqual(p.length, 0);
    XCTAssertEqualObjects(p.summary, @"2 waypoints, no route");
}

- (NSData *)gpx:(NSString *)body
{
    NSString *s = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                   "<gpx version=\"1.1\" creator=\"test\" xmlns=\"http://www.topografix.com/GPX/1/1\">%@</gpx>\n", body];
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

// a GPX: its trace, its waypoints as POIs, length and ascent computed (climbs of more than 5 m)
- (void)testGPXPreview
{
    NSData *d = [self gpx:@"<wpt lat=\"44.02\" lon=\"0.51\"><name>Water</name></wpt><trk><name>t</name><trkseg>"
                 "<trkpt lat=\"44.00\" lon=\"0.50\"><ele>100</ele></trkpt>"
                 "<trkpt lat=\"44.01\" lon=\"0.50\"><ele>104</ele></trkpt>"
                 "<trkpt lat=\"44.02\" lon=\"0.50\"><ele>110</ele></trkpt>"
                 "<trkpt lat=\"44.03\" lon=\"0.50\"><ele>108</ele></trkpt>"
                 "<trkpt lat=\"44.04\" lon=\"0.50\"><ele>120</ele></trkpt>"
                 "<trkpt lat=\"44.05\" lon=\"0.50\"><ele>90</ele></trkpt>"
                 "</trkseg></trk>"];
    NSError *err = nil;
    BPRoutePreview *p = [BPRoutePreview previewOfGPXData:d name:@"ride" error:&err];
    XCTAssertNotNil(p, @"%@", err);
    XCTAssertEqual(p.stages.count, 1u);
    XCTAssertEqual(p.stages[0].count, 6u);
    XCTAssertEqual(p.pois.count, 1u);
    XCTAssertEqualWithAccuracy(p.length, 5560, 20, @"0.05° of latitude");
    XCTAssertEqual(p.ascent, 20, @"100 → 110 → 120, the 2 m dip ignored");
    XCTAssertEqual(p.duration, 0);
    XCTAssertTrue([p.summary containsString:@"↑ 20 m"], @"%@", p.summary);
    XCTAssertFalse([p.summary containsString:@"stages"], @"%@", p.summary);
}

// a GPX of BikePlanner or BRouter gives its length, ascent and time in a comment
- (void)testGPXWithBRouterComment
{
    NSData *d = [self gpx:@"<!-- track-length = 12345 filtered ascend = 236 plain-ascend = 27 cost=26496 energy=.1kwh time=57m 15s -->"
                 "<trk><trkseg><trkpt lat=\"44.00\" lon=\"0.50\"><ele>100</ele></trkpt>"
                 "<trkpt lat=\"44.05\" lon=\"0.50\"><ele>100</ele></trkpt></trkseg></trk>"];
    BPRoutePreview *p = [BPRoutePreview previewOfGPXData:d name:@"r" error:NULL];
    XCTAssertEqual(p.length, 12345);
    XCTAssertEqual(p.ascent, 236);
    XCTAssertEqual(p.duration, 57 * 60 + 15);
    XCTAssertTrue([p.summary containsString:@"57 min"], @"%@", p.summary);
}

// without elevations: no ascent; only waypoints: drawn as waypoints
- (void)testGPXWithoutElevationsOrTrack
{
    NSData *d = [self gpx:@"<trk><trkseg><trkpt lat=\"44.00\" lon=\"0.50\"/><trkpt lat=\"44.05\" lon=\"0.50\"/></trkseg></trk>"];
    BPRoutePreview *p = [BPRoutePreview previewOfGPXData:d name:@"flat" error:NULL];
    XCTAssertLessThan(p.ascent, 0);
    XCTAssertFalse([p.summary containsString:@"↑"], @"%@", p.summary);

    d = [self gpx:@"<wpt lat=\"44.0\" lon=\"0.5\"/><wpt lat=\"44.1\" lon=\"0.6\"/>"];
    p = [BPRoutePreview previewOfGPXData:d name:@"points" error:NULL];
    XCTAssertEqual(p.stages.count, 0u);
    XCTAssertEqual(p.waypoints.count, 2u);
    XCTAssertEqual(p.pois.count, 0u);
}

- (void)testInvalidFiles
{
    NSError *err = nil;
    XCTAssertNil([BPRoutePreview previewOfBikePlanData:[@"not an archive" dataUsingEncoding:NSUTF8StringEncoding] name:@"x" error:&err]);
    XCTAssertNotNil(err);
    err = nil;
    XCTAssertNil([BPRoutePreview previewOfGPXData:[NSData data] name:@"x" error:&err]);
    XCTAssertNotNil(err);
    err = nil;
    XCTAssertNil([BPRoutePreview previewOfGPXData:[self gpx:@""] name:@"x" error:&err]);
    XCTAssertNotNil(err, @"no point");
    err = nil;
    XCTAssertNil([BPRoutePreview previewOfGPXData:[@"<gpx><trk>" dataUsingEncoding:NSUTF8StringEncoding] name:@"x" error:&err]);
    XCTAssertNotNil(err, @"broken XML");
}

// the kind of file comes from its extension, the name from the file name
- (void)testPreviewOfFileAtURL
{
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-preview"] isDirectory:YES];
    [[NSFileManager defaultManager] removeItemAtURL:dir error:NULL];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:nil error:NULL]);
    NSURL *plan = [dir URLByAppendingPathComponent:@"Tour de France.bikeplan"];
    XCTAssertTrue([[self archive:[self planInStages]] writeToURL:plan atomically:YES]);
    NSURL *gpx = [dir URLByAppendingPathComponent:@"ride.GPX"];
    XCTAssertTrue([[GPXParser gpxDataForPoints:[self route] name:@"ride" comment:nil] writeToURL:gpx atomically:YES]);

    BPRoutePreview *p = [BPRoutePreview previewOfFileAtURL:plan error:NULL];
    XCTAssertEqualObjects(p.name, @"Tour de France");
    XCTAssertEqual(p.stages.count, 2u);
    p = [BPRoutePreview previewOfFileAtURL:gpx error:NULL];
    XCTAssertEqualObjects(p.name, @"ride");
    XCTAssertEqual(p.stages.count, 1u);
    XCTAssertEqual(p.stages[0].count, 21u);
    NSError *err = nil;
    XCTAssertNil([BPRoutePreview previewOfFileAtURL:[dir URLByAppendingPathComponent:@"missing.gpx"] error:&err]);
    XCTAssertNotNil(err);
}

// the map shows all the points in the aspect ratio of its area, below the summary band
- (void)testGeometry
{
    BPRoutePreview *p = [BPRoutePreview previewOfBikePlanData:[self archive:[self planInStages]] name:@"Trip" error:NULL];
    NSSize size = NSMakeSize(600, 400);
    NSRect area = [p mapAreaForSize:size];
    XCTAssertEqual(NSMinY(area), 0);
    XCTAssertLessThan(NSMaxY(area), size.height, @"room for the summary");
    MKMapRect r = [p mapRectForArea:area.size];
    XCTAssertEqualWithAccuracy(r.size.width / r.size.height, NSWidth(area) / NSHeight(area), 1e-9);
    for (CLLocation *l in [p.stages.firstObject arrayByAddingObjectsFromArray:p.referenceTrace]) {
        XCTAssertTrue(MKMapRectContainsPoint(r, MKMapPointForCoordinate(l.coordinate)));
        XCTAssertTrue(NSPointInRect([p pointForCoordinate:l.coordinate inMapArea:area], area));
    }
    NSPoint south = [p pointForCoordinate:CLLocationCoordinate2DMake(44.0, 0.6) inMapArea:area];
    NSPoint north = [p pointForCoordinate:CLLocationCoordinate2DMake(44.2, 0.6) inMapArea:area];
    XCTAssertGreaterThan(north.y, south.y, @"north up");
    XCTAssertTrue(MKMapRectIsNull([[BPRoutePreview alloc] mapRectForArea:area.size]), @"no point");
}

- (NSColor *)colorOf:(NSBitmapImageRep *)rep at:(NSPoint)p
{
    return [[rep colorAtX:(NSInteger)round(p.x) y:(NSInteger)round(rep.pixelsHigh - p.y)] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
}

// drawn without a map: the route in blue then purple (stages), the start in green, no POI
- (void)testDrawing
{
    BPRoutePreview *p = [BPRoutePreview previewOfBikePlanData:[self archive:[self planInStages]] name:@"Trip" error:NULL];
    NSSize size = NSMakeSize(600, 400);
    NSBitmapImageRep *rep = [p bitmapOfSize:size mapImage:nil];
    XCTAssertEqual(rep.pixelsWide, 600);
    NSRect area = [p mapAreaForSize:size];
    CLLocationCoordinate2D first = p.stages[0][4].coordinate, second = p.stages[1][6].coordinate;
    NSColor *c1 = [self colorOf:rep at:[p pointForCoordinate:first inMapArea:area]];
    NSColor *c2 = [self colorOf:rep at:[p pointForCoordinate:second inMapArea:area]];
    NSColor *start = [self colorOf:rep at:[p pointForCoordinate:p.stages[0][0].coordinate inMapArea:area]];
    XCTAssertGreaterThan(c1.blueComponent, 0.8, @"%@", c1);
    XCTAssertLessThan(c1.redComponent, 0.2, @"%@", c1);
    XCTAssertGreaterThan(c2.redComponent, 0.4, @"purple: %@", c2);
    XCTAssertGreaterThan(c2.blueComponent, 0.7, @"purple: %@", c2);
    XCTAssertGreaterThan(start.greenComponent, start.redComponent, @"%@", start);
    NSColor *poi = [self colorOf:rep at:[p pointForCoordinate:CLLocationCoordinate2DMake(44.05, 0.56) inMapArea:area]];
    XCTAssertEqualWithAccuracy(poi.greenComponent, 0.93, 0.02, @"POIs are not drawn: plain background %@", poi);
    NSColor *band = [self colorOf:rep at:NSMakePoint(590, 395)];
    XCTAssertGreaterThan(band.redComponent, 0.9, @"light summary band: %@", band);

    XCTestExpectation *e = [self expectationWithDescription:@"no map without points"];
    [[[BPRoutePreview alloc] init] takeMapSnapshotForSize:size timeout:1 completion:^(NSImage *image) {
        XCTAssertNil(image);
        [e fulfill];
    }];
    [self waitForExpectations:@[e] timeout:2];
}

// the extension is in the app, for both kinds of files, with the version of the app
- (void)testQuickLookExtensionEmbedded
{
    NSURL *appex = [[NSBundle mainBundle].builtInPlugInsURL URLByAppendingPathComponent:@"BikePlannerQuickLook.appex"];
    NSBundle *ext = [NSBundle bundleWithURL:appex];
    XCTAssertNotNil(ext, @"%@", appex.path);
    NSDictionary *info = ext.infoDictionary;
    NSDictionary *app = [NSBundle mainBundle].infoDictionary;
    XCTAssertEqualObjects(info[@"CFBundleShortVersionString"], app[@"CFBundleShortVersionString"]);
    XCTAssertEqualObjects(info[@"CFBundleVersion"], app[@"CFBundleVersion"]);
    XCTAssertEqualObjects(info[@"NSExtension"][@"NSExtensionPointIdentifier"], @"com.apple.quicklook.preview");
    XCTAssertEqualObjects(info[@"NSExtension"][@"NSExtensionPrincipalClass"], @"PreviewProvider");
    NSArray *types = info[@"NSExtension"][@"NSExtensionAttributes"][@"QLSupportedContentTypes"];
    XCTAssertEqualObjects(types, (@[@"fr.free.daniel.braun.bikeplan", @"com.topografix.gpx"]));
    XCTAssertEqualObjects(info[@"NSExtension"][@"NSExtensionAttributes"][@"QLIsDataBasedPreview"], @YES);
}

@end
