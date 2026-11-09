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
        XCTAssertTrue(s.coordinate.latitude > 41.3 && s.coordinate.latitude < 51.1, @"%@", s.name);
        XCTAssertTrue(s.coordinate.longitude > -5.2 && s.coordinate.longitude < 9.6, @"%@", s.name);
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

@end
