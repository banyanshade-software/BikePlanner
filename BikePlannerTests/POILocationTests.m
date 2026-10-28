//
//  POILocationTests.m
//  BikePlannerTests
//

#import <XCTest/XCTest.h>
#import "POILocation.h"

@interface POILocationTests : XCTestCase
@end

@implementation POILocationTests

- (void)testTypeForAmenity
{
    XCTAssertEqual([POILocation poiTypeForAmenity:@"drinking_water"], POI_drinking_water);
    XCTAssertEqual([POILocation poiTypeForAmenity:@"toilets"], POI_toilets);
    XCTAssertEqual([POILocation poiTypeForAmenity:@"bicycle_repair_station"], POI_bicycle_repair_station);
    XCTAssertEqual([POILocation poiTypeForAmenity:@"cemetery"], POI_cemetery);
    XCTAssertEqual([POILocation poiTypeForAmenity:@"warning"], POI_warning);
    XCTAssertEqual([POILocation poiTypeForAmenity:@"bench"], POI_unknown);
}

// Overpass returns amenity=grave_yard for nodes (landuse=cemetery for areas) — issue #13.
- (void)testGraveYardIsCemetery
{
    XCTAssertEqual([POILocation poiTypeForAmenity:@"grave_yard"], POI_cemetery);
}

- (void)testGarminTypes
{
    NSDictionary *expected = @{ @(POI_drinking_water): @"WATER",
                                @(POI_toilets): @"TOILET",
                                @(POI_bicycle_repair_station): @"SERVICE",
                                @(POI_cemetery): @"GENERIC",
                                @(POI_warning): @"DANGER" };
    for (NSNumber *t in expected) {
        POILocation *p = [[POILocation alloc] initWithLatitude:1 longitude:2 ofType:t.intValue info:@{} custom:NO];
        XCTAssertEqualObjects(p.gpxType, expected[t]);
    }
}

- (void)testTitles
{
    POILocation *w = [[POILocation alloc] initWithLatitude:1 longitude:2 ofType:POI_drinking_water info:@{} custom:NO];
    XCTAssertEqualObjects(w.title, @"water");
}

- (void)testSecureCodingRoundTrip
{
    NSDictionary *info = @{ @"amenity": @"drinking_water", @"id": @"12345" };
    POILocation *p = [[POILocation alloc] initWithLatitude:44.1 longitude:0.5 ofType:POI_drinking_water info:info custom:NO];
    NSError *err = nil;
    NSData *d = [NSKeyedArchiver archivedDataWithRootObject:p requiringSecureCoding:YES error:&err];
    XCTAssertNotNil(d, @"%@", err);
    POILocation *r = [NSKeyedUnarchiver unarchivedObjectOfClass:[POILocation class] fromData:d error:&err];
    XCTAssertNotNil(r, @"%@", err);
    XCTAssertEqual(r.poiType, POI_drinking_water);
    XCTAssertEqualObjects(r.info, info);
    XCTAssertEqualWithAccuracy(r.coordinate.latitude, 44.1, 1e-9);
}

#pragma mark - custom POI types (#3)

- (void)testCustomTypes
{
    NSArray<NSNumber *> *types = [POILocation customPoiTypes];
    XCTAssertEqual(types.count, 11u);
    XCTAssertEqual(types.firstObject.intValue, POI_warning, @"default type first");
    NSDictionary *garmin = @{ @(POI_warning): @"DANGER", @(POI_drinking_water): @"WATER", @(POI_food): @"FOOD",
                              @(POI_toilets): @"TOILET", @(POI_bicycle_repair_station): @"SERVICE",
                              @(POI_shelter): @"SHELTER", @(POI_viewpoint): @"OVERLOOK", @(POI_campsite): @"CAMPSITE",
                              @(POI_store): @"STORE", @(POI_info): @"INFO", @(POI_generic): @"GENERIC" };
    for (NSNumber *t in types) {
        POILocation *p = [[POILocation alloc] initWithLatitude:1 longitude:2 ofType:t.intValue info:@{} custom:YES];
        XCTAssertEqualObjects(p.gpxType, garmin[t], @"type %@", t);
        XCTAssertGreaterThan([POILocation displayNameForType:t.intValue].length, 0u);
        XCTAssertNotNil(p.title, @"custom POIs always have a title (no <name>(null)</name>)");
    }
    // archived values of the existing types do not change
    XCTAssertEqual(POI_warning, 5);
}

- (void)testCustomPoiNameIsTitle
{
    POILocation *named = [[POILocation alloc] initWithLatitude:1 longitude:2 ofType:POI_drinking_water
                                                          info:@{ @"name": @"Fontaine du village" } custom:YES];
    XCTAssertEqualObjects(named.title, @"Fontaine du village");
    XCTAssertEqualObjects(named.name, @"Fontaine du village");
    POILocation *unnamed = [[POILocation alloc] initWithLatitude:1 longitude:2 ofType:POI_viewpoint info:@{} custom:YES];
    XCTAssertEqualObjects(unnamed.title, [POILocation displayNameForType:POI_viewpoint]);
    XCTAssertNil(unnamed.name);
    // fetched POIs keep their type title
    POILocation *fetched = [[POILocation alloc] initWithLatitude:1 longitude:2 ofType:POI_drinking_water
                                                            info:@{ @"id": @3, @"name": @"OSM name" } custom:NO];
    XCTAssertEqualObjects(fetched.title, @"water");
}

@end
