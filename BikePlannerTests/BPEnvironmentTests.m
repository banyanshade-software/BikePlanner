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

- (void)testIsUnitTestHost
{
    XCTAssertTrue([BPEnvironment isUnitTestHost]);
}

@end
