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
