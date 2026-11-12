//
//  BPColorSchemeTests.m
//  BikePlannerTests
//
//  Colors of the route on the map (#71).
//

#import <XCTest/XCTest.h>
#import "BPColorScheme.h"
#import "TestFixtures.h"

@interface BPColorSchemeTests : XCTestCase
@end

@implementation BPColorSchemeTests

- (void)tearDown
{
    BPRestoreDefaults();
}

- (void)testSchemes
{
    NSArray<BPColorScheme *> *all = [BPColorScheme allSchemes];
    NSArray *ids = [all valueForKey:@"identifier"];
    XCTAssertEqualObjects(ids, (@[ @"classic", @"vivid", @"dark", @"satellite", @"compare" ]));
    for (BPColorScheme *s in all) {
        XCTAssertGreaterThan(s.localizedName.length, 0u);
        XCTAssertGreaterThanOrEqual(s.stageColors.count, 2u, @"%@: stages alternate", s.identifier);
        XCTAssertGreaterThan(s.routeAlpha, 0);
        XCTAssertLessThanOrEqual(s.routeAlpha, 1);
        // the trace and the highlight stay distinct from the stage colors (owner's decision on #71)
        for (NSColor *c in s.stageColors) {
            XCTAssertNotEqualObjects(c, s.referenceTraceColor, @"%@", s.identifier);
            XCTAssertNotEqualObjects(c, s.highlightColor, @"%@", s.identifier);
        }
        XCTAssertNotEqualObjects(s.referenceTraceColor, s.highlightColor, @"%@", s.identifier);
        XCTAssertNotEqualObjects(s.stageColors[0], s.stageColors[1], @"%@", s.identifier);
        NSImage *swatch = [s swatchImage];
        XCTAssertGreaterThan(swatch.size.width, 0);
    }
}

// Classic: the colors before #71
- (void)testClassicIsTheDefault
{
    BPColorScheme *c = [BPColorScheme defaultScheme];
    XCTAssertEqualObjects(c.identifier, @"classic");
    XCTAssertEqualObjects(c.stageColors, (@[ [NSColor blueColor], [NSColor systemPurpleColor] ]));
    XCTAssertEqual(c.routeAlpha, 0.5);
    XCTAssertEqualObjects(c.stageEndColor, [NSColor systemPurpleColor]);
    XCTAssertEqualObjects(c.referenceTraceColor, [NSColor orangeColor]);
    XCTAssertEqualObjects(c.highlightColor, [NSColor systemPinkColor]);
    XCTAssertEqual(c.routeWidth, 8.0);
    XCTAssertEqual(c.traceAlpha, 0.5);
    XCTAssertEqual(c.traceWidth, 6.0);
}

// to compare the real track with the planned route (owner's choice after trying): the trace red and opaque, the
// route opaque and drawn over it, narrower, so that where they coincide the trace shows on both sides of the route
- (void)testCompareScheme
{
    BPColorScheme *c = [BPColorScheme schemeWithIdentifier:@"compare"];
    XCTAssertEqual(c.traceAlpha, 1.0);
    XCTAssertEqual(c.routeAlpha, 1.0);
    XCTAssertGreaterThanOrEqual(c.traceWidth - c.routeWidth, 4.0, @"at least 2 pt of trace on each side of the route");
}

- (void)testLookup
{
    XCTAssertEqualObjects([BPColorScheme schemeWithIdentifier:@"dark"].identifier, @"dark");
    XCTAssertEqualObjects([BPColorScheme schemeWithIdentifier:@"nope"].identifier, @"classic", @"unknown: the default");
    XCTAssertEqualObjects([BPColorScheme schemeWithIdentifier:nil].identifier, @"classic");
    BPColorScheme *v = [BPColorScheme schemeWithIdentifier:@"vivid"];
    XCTAssertEqualObjects([v colorForStage:0], v.stageColors[0]);
    XCTAssertEqualObjects([v colorForStage:1], v.stageColors[1]);
    XCTAssertEqualObjects([v colorForStage:2], v.stageColors[0], @"alternating");
}

- (void)testCurrentSchemeFromDefaults
{
    XCTAssertEqualObjects(BPColorSchemeKey, @"BPColorScheme");
    BPOverrideDefaults(@{ @"BPColorScheme": @"satellite" });
    XCTAssertEqualObjects([BPColorScheme currentScheme].identifier, @"satellite");
    BPOverrideDefaults(@{ @"BPColorScheme": @"bogus" });
    XCTAssertEqualObjects([BPColorScheme currentScheme].identifier, @"classic");
}

@end
