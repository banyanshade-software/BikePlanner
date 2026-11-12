//
//  BPPOIDescriptionTests.m
//  BikePlannerTests
//
//  What the POI callout shows (#72).
//

#import <XCTest/XCTest.h>
#import "BPPOIDescription.h"

@interface BPPOIDescriptionTests : XCTestCase
@end

@implementation BPPOIDescriptionTests

- (void)testFetchedWaterPOI
{
    NSDictionary *info = @{ @"id": @123456, @"amenity": @"drinking_water", @"name": @"Fontaine du village",
                            @"drinking_water": @"yes", @"seasonal": @"no", @"opening_hours": @"Mo-Su 08:00-20:00",
                            @"fee": @"no", @"source": @"survey" };
    BPPOIDescription *d = [[BPPOIDescription alloc] initWithType:POI_drinking_water info:info custom:NO];
    XCTAssertFalse(d.custom);
    XCTAssertEqualObjects(d.name, @"Fontaine du village");
    XCTAssertEqualObjects(d.typeName, @"Water");
    NSArray *expected = @[ @[@"Drinking water", @"yes"], @[@"Seasonal", @"no"],
                           @[@"Opening hours", @"Mo-Su 08:00-20:00"], @[@"Fee", @"no"] ];
    XCTAssertEqualObjects(d.rows, expected, @"known tags translated, in display order; unknown tags not in rows");
    NSMutableArray *keys = [NSMutableArray array];
    for (NSArray *t in d.allTags) [keys addObject:t[0]];
    NSArray *expectedKeys = @[ @"amenity", @"drinking_water", @"fee", @"name", @"opening_hours", @"seasonal", @"source" ];
    XCTAssertEqualObjects(keys, expectedKeys, @"every tag sorted by key, without the id added by the app");
    XCTAssertEqualObjects(d.osmURL.absoluteString, @"https://www.openstreetmap.org/node/123456");
}

- (void)testYesNoValuesAndOtherValues
{
    NSDictionary *info = @{ @"id": @1, @"amenity": @"toilets", @"wheelchair": @"limited", @"seasonal": @"summer",
                            @"unisex": @"yes" };
    BPPOIDescription *d = [[BPPOIDescription alloc] initWithType:POI_toilets info:info custom:NO];
    NSArray *expected = @[ @[@"Seasonal", @"summer"], @[@"Unisex", @"yes"], @[@"Wheelchair", @"limited"] ];
    XCTAssertEqualObjects(d.rows, expected);
    XCTAssertNil(d.name);
}

// a value that is a URL is a link (#72), e.g. the website of a repair station (node 8894672388)
- (void)testURLValues
{
    NSDictionary *info = @{ @"id": @8894672388, @"amenity": @"bicycle_repair_station", @"name": @"CycloStand",
                            @"service:bicycle:pump": @"no", @"website": @"https://www.cyclostand.fr/" };
    BPPOIDescription *d = [[BPPOIDescription alloc] initWithType:POI_bicycle_repair_station info:info custom:NO];
    XCTAssertTrue([d.rows containsObject:(@[@"Website", @"https://www.cyclostand.fr/"])], @"%@", d.rows);
    XCTAssertEqualObjects([BPPOIDescription linkURLForValue:@"https://www.cyclostand.fr/"].absoluteString, @"https://www.cyclostand.fr/");
    XCTAssertEqualObjects([BPPOIDescription linkURLForValue:@"http://example.org/a?b=c"].absoluteString, @"http://example.org/a?b=c");
    XCTAssertEqualObjects([BPPOIDescription linkURLForValue:@"www.example.org"].absoluteString, @"https://www.example.org");
    XCTAssertNil([BPPOIDescription linkURLForValue:@"yes"]);
    XCTAssertNil([BPPOIDescription linkURLForValue:@"Mo-Su 08:00-20:00"]);
    XCTAssertNil([BPPOIDescription linkURLForValue:@"ftp://example.org"]);
    // other website tags
    d = [[BPPOIDescription alloc] initWithType:POI_toilets info:@{ @"id": @1, @"contact:website": @"https://a.fr" } custom:NO];
    XCTAssertTrue([d.rows containsObject:(@[@"Website", @"https://a.fr"])], @"%@", d.rows);
}

- (void)testCemeteryAreaIsAWay
{
    NSDictionary *info = @{ @"id": @987, @"landuse": @"cemetery" };
    BPPOIDescription *d = [[BPPOIDescription alloc] initWithType:POI_cemetery info:info custom:NO];
    XCTAssertEqualObjects(d.osmURL.absoluteString, @"https://www.openstreetmap.org/way/987");
    XCTAssertEqual(d.rows.count, 0u);
    d = [[BPPOIDescription alloc] initWithType:POI_cemetery info:@{ @"id": @988, @"amenity": @"grave_yard" } custom:NO];
    XCTAssertEqualObjects(d.osmURL.absoluteString, @"https://www.openstreetmap.org/node/988");
}

- (void)testCustomPOI
{
    BPPOIDescription *d = [[BPPOIDescription alloc] initWithType:POI_shelter info:@{ @"name": @"Abri" } custom:YES];
    XCTAssertTrue(d.custom);
    XCTAssertEqualObjects(d.name, @"Abri");
    XCTAssertEqualObjects(d.typeName, @"Shelter");
    XCTAssertEqual(d.rows.count, 0u);
    XCTAssertEqual(d.allTags.count, 0u);
    XCTAssertNil(d.osmURL);
    d = [[BPPOIDescription alloc] initWithType:POI_info info:@{} custom:YES];
    XCTAssertNil(d.name);
}

// distances use the decimal separator of the user's locale (like the elevation profile)
static NSString *BPLocalDecimal(NSString *s)
{
    return [s stringByReplacingOccurrencesOfString:@"." withString:[NSLocale currentLocale].decimalSeparator];
}

- (void)testPositionString
{
    XCTAssertEqualObjects([BPPOIDescription positionStringForDistance:12430 offset:183 stage:-1],
                          BPLocalDecimal(@"km 12.4 · 180 m off route"));
    XCTAssertEqualObjects([BPPOIDescription positionStringForDistance:12430 offset:5 stage:1],
                          BPLocalDecimal(@"km 12.4 (stage 2) · on the route"));
    XCTAssertEqualObjects([BPPOIDescription positionStringForDistance:0 offset:1450 stage:0],
                          BPLocalDecimal(@"km 0.0 (stage 1) · 1.4 km off route"));
}

- (void)testCoordinateString
{
    XCTAssertEqualObjects([BPPOIDescription coordinateString:CLLocationCoordinate2DMake(44.1234567, -0.5)], @"44.123457, -0.500000");
}

@end
