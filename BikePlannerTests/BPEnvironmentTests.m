//
//  BPEnvironmentTests.m
//  BikePlannerTests
//

#import <XCTest/XCTest.h>
#import "BPEnvironment.h"
#import "TestFixtures.h"

@interface BPEnvironmentTests : XCTestCase
@end

@implementation BPEnvironmentTests

- (void)tearDown
{
    BPRestoreDefaults();
}

- (void)testProductionDefaults
{
    XCTAssertEqualObjects([BPEnvironment brouterServerURL].absoluteString, @"https://brouter.de");
    XCTAssertEqualObjects([BPEnvironment brouterProfileURLForName:@"trekking"].absoluteString,
                          @"https://brouter.de/brouter/profiles2/trekking.brf");
    XCTAssertEqualObjects([BPEnvironment overpassURL].absoluteString, @"https://overpass-api.de/api/interpreter");
    XCTAssertFalse([BPEnvironment streetViewDisabled]);
    XCTAssertFalse([BPEnvironment tilesDisabled]);
}

- (void)testOverrides
{
    BPOverrideDefaults(@{ @"BPBRouterServer": @"http://127.0.0.1:1234",
                          @"BPOverpassURL": @"http://127.0.0.1:1234/api/interpreter",
                          @"BPDisableStreetView": @YES,
                          @"BPDisableTiles": @YES });
    XCTAssertEqualObjects([BPEnvironment brouterServerURL].absoluteString, @"http://127.0.0.1:1234");
    XCTAssertEqualObjects([BPEnvironment brouterProfileURLForName:@"fastbike"].absoluteString,
                          @"http://127.0.0.1:1234/brouter/profiles2/fastbike.brf");
    XCTAssertEqualObjects([BPEnvironment overpassURL].absoluteString, @"http://127.0.0.1:1234/api/interpreter");
    XCTAssertTrue([BPEnvironment streetViewDisabled]);
    XCTAssertTrue([BPEnvironment tilesDisabled]);
}

- (void)testEmptyOverrideFallsBackToDefault
{
    BPOverrideDefaults(@{ @"BPBRouterServer": @"" });
    XCTAssertEqualObjects([BPEnvironment brouterServerURL].absoluteString, @"https://brouter.de");
}

- (void)testInitialRegion
{
    XCTAssertFalse([BPEnvironment getInitialRegion:NULL]);
    BPOverrideDefaults(@{ @"BPInitialRegion": @"44.05,0.55,0.2" });
    MKCoordinateRegion r;
    XCTAssertTrue([BPEnvironment getInitialRegion:&r]);
    XCTAssertEqualWithAccuracy(r.center.latitude, 44.05, 1e-9);
    XCTAssertEqualWithAccuracy(r.center.longitude, 0.55, 1e-9);
    XCTAssertEqualWithAccuracy(r.span.latitudeDelta, 0.2, 1e-9);
    BPOverrideDefaults(@{ @"BPInitialRegion": @"44.05,0.55" });
    XCTAssertFalse([BPEnvironment getInitialRegion:&r]);
    BPOverrideDefaults(@{ @"BPInitialRegion": @"44.05,0.55,0" });
    XCTAssertFalse([BPEnvironment getInitialRegion:&r]);
}

- (void)testIsUnitTestHost
{
    XCTAssertTrue([BPEnvironment isUnitTestHost]);
}

// #26: default position and radius of the initial map region
- (void)testDefaultPositionAndRadius
{
    BPOverrideDefaults(@{ @"BPDefaultPosition": @"45.5,1.25", @"BPInitialRadiusKm": @"50" });
    CLLocationCoordinate2D p = [BPEnvironment defaultPosition];
    XCTAssertEqualWithAccuracy(p.latitude, 45.5, 1e-9);
    XCTAssertEqualWithAccuracy(p.longitude, 1.25, 1e-9);
    XCTAssertEqualWithAccuracy([BPEnvironment initialRadiusKm], 50, 1e-9);

    BPOverrideDefaults(@{ @"BPDefaultPosition": @"garbage", @"BPInitialRadiusKm": @"0" });
    p = [BPEnvironment defaultPosition];
    XCTAssertTrue(CLLocationCoordinate2DIsValid(p), @"fallback position");
    XCTAssertEqualWithAccuracy([BPEnvironment initialRadiusKm], 80, 1e-9, @"default radius");
    BPOverrideDefaults(@{ @"BPDefaultPosition": @"95,0" });
    XCTAssertNotEqual([BPEnvironment defaultPosition].latitude, 95, @"invalid latitude ignored");
}

@end
