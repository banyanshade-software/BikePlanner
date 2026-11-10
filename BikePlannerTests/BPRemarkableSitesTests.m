//
//  BPRemarkableSitesTests.m
//  BikePlannerTests
//
//  List of remarkable sites where a new document can start (#65).
//

#import <XCTest/XCTest.h>
#import "BPRemarkableSites.h"
#import "TestFixtures.h"

@interface BPRemarkableSitesTests : XCTestCase
@end

@implementation BPRemarkableSitesTests

- (void)tearDown
{
    BPRestoreDefaults();
}

// RemarkableSites.plist, a resource of the app
- (void)testSitesLoadedFromPlist
{
    XCTAssertNotNil([[NSBundle bundleForClass:[BPRemarkableSites class]] URLForResource:@"RemarkableSites" withExtension:@"plist"]);
    XCTAssertGreaterThanOrEqual([BPRemarkableSites sites].count, 50u);
    for (BPRemarkableSite *s in [BPRemarkableSites sites]) {
        XCTAssertTrue(s.heading >= 0 && s.heading < 360, @"%@: heading %g", s.name, s.heading);
    }
}

// entries: name, latitude, longitude, kind, optional heading; invalid ones are skipped
- (void)testSitesFromPropertyList
{
    NSArray *plist = @[
        @{ @"name": @"A", @"latitude": @45, @"longitude": @6, @"kind": @"climb", @"heading": @135 },
        @{ @"name": @"B", @"latitude": @46, @"longitude": @2, @"kind": @"nature" },
        @{ @"latitude": @45, @"longitude": @6, @"kind": @"climb" },                  // no name
        @{ @"name": @"C", @"latitude": @45, @"longitude": @6, @"kind": @"castle" },  // unknown kind
        @{ @"name": @"D", @"latitude": @100, @"longitude": @6, @"kind": @"climb" },  // invalid coordinate
        @"not a dictionary",
    ];
    NSArray<BPRemarkableSite *> *sites = [BPRemarkableSites sitesFromPropertyList:plist];
    XCTAssertEqual(sites.count, 2u);
    XCTAssertEqualObjects(sites[0].name, @"A");
    XCTAssertEqual(sites[0].kind, BPSiteKindClimb);
    XCTAssertEqual(sites[0].heading, 135);
    XCTAssertEqual(sites[0].coordinate.latitude, 45);
    XCTAssertEqual(sites[1].kind, BPSiteKindNature);
    XCTAssertEqual(sites[1].heading, 0, @"north by default");
    XCTAssertEqual([BPRemarkableSites sitesFromPropertyList:@{}].count, 0u);
    XCTAssertEqual([BPRemarkableSites sitesFromPropertyList:nil].count, 0u);
}

// all in metropolitan France (bounding box), unique names, every kind present
- (void)testSitesInFrance
{
    NSArray<BPRemarkableSite *> *sites = [BPRemarkableSites sites];
    XCTAssertGreaterThanOrEqual(sites.count, 50u);
    NSMutableSet *names = [NSMutableSet set];
    NSMutableSet *kinds = [NSMutableSet set];
    for (BPRemarkableSite *s in sites) {
        XCTAssertTrue([BPRemarkableSites isInMetropolitanFrance:s.coordinate], @"%@", s.name);
        XCTAssertFalse([names containsObject:s.name], @"%@ twice", s.name);
        [names addObject:s.name];
        [kinds addObject:@(s.kind)];
    }
    XCTAssertEqual(kinds.count, 3u);
}

- (void)testDisplayText
{
    BPRemarkableSite *ventoux = [BPRemarkableSites sites].firstObject;
    XCTAssertEqualObjects(ventoux.displayText, @"Mont Ventoux — famous climb");
}

// the test hook chooses the site; otherwise one of the list
- (void)testRandomSite
{
    BPOverrideDefaults(@{ @"BPRemarkableSiteIndex": @3 });
    XCTAssertEqual([BPRemarkableSites randomSite], [BPRemarkableSites sites][3]);
    BPRestoreDefaults();
    for (int i = 0; i < 20; i++) XCTAssertTrue([[BPRemarkableSites sites] containsObject:[BPRemarkableSites randomSite]]);
}

#pragma mark - writing the list (start sites editor, #67)

// the bundled list written again gives the same sites and keeps the header comment
- (void)testPropertyListRoundTrip
{
    NSData *data = [BPRemarkableSites bundledPropertyListData];
    XCTAssertNotNil(data);
    NSString *header = [BPRemarkableSites headerCommentOfPropertyListData:data];
    XCTAssertTrue([header containsString:@"Keep Mont Ventoux first"], @"%@", header);
    NSArray *entries = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    NSData *out = [BPRemarkableSites propertyListDataForEntries:entries headerComment:header];
    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    XCTAssertTrue([text containsString:@"<!--"], @"comment kept");
    XCTAssertLessThan([text rangeOfString:@"<!DOCTYPE"].location, [text rangeOfString:@"<!--"].location);
    XCTAssertLessThan([text rangeOfString:@"<!--"].location, [text rangeOfString:@"<plist"].location);
    XCTAssertEqualObjects([BPRemarkableSites headerCommentOfPropertyListData:out], header);
    NSArray *back = [NSPropertyListSerialization propertyListWithData:out options:0 format:NULL error:NULL];
    XCTAssertEqualObjects(back, entries);
    XCTAssertEqualObjects(text, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding],
                          @"same layout as the file: an export without change gives no diff");
    NSArray<BPRemarkableSite *> *sites = [BPRemarkableSites sitesFromPropertyList:back];
    XCTAssertEqual(sites.count, [BPRemarkableSites sites].count);
    XCTAssertEqualObjects(sites.firstObject.name, @"Mont Ventoux");
}

// whole headings are written as integers, others as reals; no comment: a plain property list
- (void)testPropertyListHeadings
{
    NSArray *entries = @[ @{ @"name": @"A", @"latitude": @45.5, @"longitude": @6, @"kind": @"climb", @"heading": @90.0 },
                          @{ @"name": @"B", @"latitude": @45, @"longitude": @6, @"kind": @"nature", @"heading": @12.5 } ];
    NSData *out = [BPRemarkableSites propertyListDataForEntries:entries headerComment:nil];
    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    XCTAssertTrue([text containsString:@"<integer>90</integer>"], @"%@", text);
    XCTAssertTrue([text containsString:@"<real>12.5</real>"], @"%@", text);
    XCTAssertTrue([text containsString:@"<real>45.5</real>"], @"%@", text);
    XCTAssertLessThan([text rangeOfString:@"<key>name</key>"].location, [text rangeOfString:@"<key>latitude</key>"].location,
                      @"keys in the order of the header comment");
    XCTAssertLessThan([text rangeOfString:@"<key>kind</key>"].location, [text rangeOfString:@"<key>heading</key>"].location);
    XCTAssertFalse([text containsString:@"<!--"]);
    XCTAssertNil([BPRemarkableSites headerCommentOfPropertyListData:out]);
    NSArray<BPRemarkableSite *> *sites = [BPRemarkableSites sitesFromPropertyList:
        [NSPropertyListSerialization propertyListWithData:out options:0 format:NULL error:NULL]];
    XCTAssertEqual(sites[0].heading, 90);
    XCTAssertEqual(sites[1].heading, 12.5);
}

- (void)testMetropolitanFrance
{
    XCTAssertTrue([BPRemarkableSites isInMetropolitanFrance:CLLocationCoordinate2DMake(44.17, 5.28)]);   // Ventoux
    XCTAssertTrue([BPRemarkableSites isInMetropolitanFrance:CLLocationCoordinate2DMake(42.0, 9.0)]);     // Corsica
    XCTAssertFalse([BPRemarkableSites isInMetropolitanFrance:CLLocationCoordinate2DMake(46.5, 10.0)]);   // Switzerland
    XCTAssertFalse([BPRemarkableSites isInMetropolitanFrance:CLLocationCoordinate2DMake(16.2, -61.5)]);  // Guadeloupe
}

@end
