//
//  BPSightsTests.m
//  BikePlannerTests
//
//  Sights near the route (#81): categories, Overpass clause, classification, inclusion in the track.
//

#import <XCTest/XCTest.h>
#import "BPSights.h"
#import "BikePlan.h"
#import "POILocation.h"
#import "TestFixtures.h"

@interface BikePlan (SightsTesting)
- (NSString *)overpassQueryForTrack:(NSArray<CLLocation *> *)trackPoints withRadius:(NSUInteger)radiusMeters;
- (NSArray<POILocation *> *)poisFromOverpassElements:(NSArray *)elements;
- (void)setPoiloc:(NSArray<POILocation *> *)pl;
@end

@interface BPSightsTests : XCTestCase
@end

@implementation BPSightsTests

- (void)testCategories
{
    NSArray *ids = @[ @"culture", @"viewpoint", @"church", @"nature", @"food", @"accommodation", @"bikeshop" ];
    XCTAssertEqualObjects([BPSights allCategories], ids);
    XCTAssertEqualObjects([BPSights localizedNameOfCategory:@"culture"], @"Culture");
    XCTAssertEqualObjects([BPSights localizedNameOfCategory:@"church"], @"Churches and chapels");
    XCTAssertEqualObjects([BPSights summaryOfCategories:@[]], @"None");
    XCTAssertEqualObjects([BPSights summaryOfCategories:(@[ @"viewpoint", @"culture" ])], @"Culture, Viewpoints",
                          @"in the order of the list");
    XCTAssertEqualObjects([BPSights normalizedCategories:(@[ @"food", @"bogus", @"culture", @"food" ])], (@[ @"culture", @"food" ]));
}

// one clause per sampled point: a key/value regex on the keys and values of the selected categories only
- (void)testOverpassClause
{
    NSString *clause = [BPSights overpassClauseForCategories:@[ @"culture", @"viewpoint" ] radius:1000 latitude:44.5 longitude:0.25];
    XCTAssertTrue([clause hasPrefix:@"  nwr(around:1000,44.500000,0.250000)[~\"^(historic|tourism)$\"~\"^("], @"%@", clause);
    for (NSString *v in @[ @"museum", @"attraction", @"castle", @"ruins", @"archaeological_site", @"monument", @"fort", @"manor", @"viewpoint" ]) {
        XCTAssertTrue([clause containsString:v], @"%@ in %@", v, clause);
    }
    XCTAssertFalse([clause containsString:@"restaurant"]);
    XCTAssertFalse([clause containsString:@"memorial"], @"war memorials are not sights (too many)");
    XCTAssertNil([BPSights overpassClauseForCategories:@[] radius:1000 latitude:0 longitude:0]);
}

- (void)testClassification
{
    NSString *cat = nil;
    XCTAssertEqual([BPSights typeForTags:@{ @"historic": @"castle" } categories:[BPSights allCategories] category:&cat], POI_culture);
    XCTAssertEqualObjects(cat, @"culture");
    XCTAssertEqual([BPSights typeForTags:@{ @"tourism": @"museum" } categories:[BPSights allCategories] category:NULL], POI_culture);
    XCTAssertEqual([BPSights typeForTags:@{ @"tourism": @"viewpoint" } categories:[BPSights allCategories] category:NULL], POI_viewpoint);
    XCTAssertEqual([BPSights typeForTags:@{ @"amenity": @"place_of_worship" } categories:[BPSights allCategories] category:NULL], POI_church);
    XCTAssertEqual([BPSights typeForTags:@{ @"natural": @"waterfall" } categories:[BPSights allCategories] category:NULL], POI_nature);
    XCTAssertEqual([BPSights typeForTags:@{ @"shop": @"bakery" } categories:[BPSights allCategories] category:NULL], POI_food);
    XCTAssertEqual([BPSights typeForTags:@{ @"amenity": @"cafe" } categories:[BPSights allCategories] category:NULL], POI_food);
    XCTAssertEqual([BPSights typeForTags:@{ @"tourism": @"camp_site" } categories:[BPSights allCategories] category:NULL], POI_accommodation);
    XCTAssertEqual([BPSights typeForTags:@{ @"shop": @"bicycle" } categories:[BPSights allCategories] category:NULL], POI_bike_shop);
    // a cross match of the key/value regex (amenity=museum does not exist), or a category not selected
    XCTAssertEqual([BPSights typeForTags:@{ @"amenity": @"museum" } categories:[BPSights allCategories] category:NULL], POI_unknown);
    XCTAssertEqual([BPSights typeForTags:@{ @"amenity": @"cafe" } categories:@[ @"culture" ] category:NULL], POI_unknown);
    XCTAssertEqual([BPSights typeForTags:@{ @"amenity": @"drinking_water" } categories:[BPSights allCategories] category:NULL], POI_unknown);
}

- (void)testSightTypes
{
    POILocation *castle = [[POILocation alloc] initWithLatitude:44 longitude:0.5 ofType:POI_culture info:@{ @"name": @"Bonaguil" } custom:NO];
    XCTAssertTrue(castle.isSight);
    XCTAssertEqualObjects(castle.title, @"Bonaguil", @"the OSM name");
    POILocation *unnamed = [[POILocation alloc] initWithLatitude:44 longitude:0.5 ofType:POI_viewpoint info:@{} custom:NO];
    XCTAssertEqualObjects(unnamed.title, @"Viewpoint", @"the type when no name");
    XCTAssertEqualObjects(unnamed.gpxType, @"OVERLOOK");
    POILocation *water = [[POILocation alloc] initWithLatitude:44 longitude:0.5 ofType:POI_drinking_water info:@{} custom:NO];
    XCTAssertFalse(water.isSight);
    POILocation *custom = [[POILocation alloc] initWithLatitude:44 longitude:0.5 ofType:POI_viewpoint info:@{} custom:YES];
    XCTAssertFalse(custom.isSight, @"custom POIs are not sights");
    for (NSNumber *t in @[ @(POI_culture), @(POI_church), @(POI_nature), @(POI_accommodation), @(POI_bike_shop) ]) {
        XCTAssertGreaterThan([POILocation displayNameForType:t.intValue].length, 0u);
    }
}

#pragma mark - plan

// a route going east along latitude 44.0, from 0.50 to 0.60
- (BikePlan *)planWithRoute
{
    BikePlan *plan = [[BikePlan alloc] init];
    plan.fetchPOI = NO;
    NSMutableArray *pts = [NSMutableArray array];
    for (int i = 0; i <= 100; i++) [pts addObject:[[CLLocation alloc] initWithLatitude:44.0 longitude:0.50 + i * 0.001]];
    plan.routePoints = pts;
    return plan;
}

- (POILocation *)sightAtLatitudeOffsetMeters:(double)meters longitude:(double)lon id:(int)osmid type:(PoiType_t)type
{
    return [[POILocation alloc] initWithLatitude:44.0 + meters / 111195.0 longitude:lon ofType:type
                                            info:@{ @"id": @(osmid), @"name": [NSString stringWithFormat:@"S%d", osmid] } custom:NO];
}

- (void)testQueryContainsSightsOfTheSelectedCategories
{
    BikePlan *plan = [self planWithRoute];
    plan.sightCategories = @[];
    NSString *q = [plan overpassQueryForTrack:plan.routePoints withRadius:1500];
    XCTAssertFalse([q containsString:@"nwr("], @"no category: utilities only");
    plan.sightCategories = @[ @"viewpoint" ];
    q = [plan overpassQueryForTrack:plan.routePoints withRadius:1500];
    XCTAssertTrue([q containsString:@"nwr(around:1000,"], @"sights within 1 km");
    XCTAssertTrue([q containsString:@"drinking_water"], @"utilities still there");
}

- (void)testParsingKeepsSightsOfSelectedCategories
{
    BikePlan *plan = [self planWithRoute];
    plan.sightCategories = @[ @"culture" ];
    NSArray *elements = @[
        @{ @"type": @"node", @"id": @1, @"lat": @44.01, @"lon": @0.5, @"tags": @{ @"amenity": @"drinking_water" } },
        @{ @"type": @"way", @"id": @2, @"center": @{ @"lat": @44.001, @"lon": @0.52 }, @"tags": @{ @"historic": @"castle", @"name": @"Castle" } },
        @{ @"type": @"relation", @"id": @3, @"center": @{ @"lat": @44.002, @"lon": @0.53 }, @"tags": @{ @"tourism": @"museum" } },
        @{ @"type": @"node", @"id": @4, @"lat": @44.003, @"lon": @0.54, @"tags": @{ @"amenity": @"cafe" } },
        @{ @"type": @"way", @"id": @5, @"center": @{ @"lat": @44.004, @"lon": @0.55 }, @"tags": @{ @"landuse": @"cemetery" } },
    ];
    NSArray<POILocation *> *pois = [plan poisFromOverpassElements:elements];
    NSArray *types = [pois valueForKey:@"poiType"];
    XCTAssertEqualObjects(types, (@[ @(POI_drinking_water), @(POI_culture), @(POI_culture), @(POI_cemetery) ]),
                          @"the cafe is not in the selected categories");
    XCTAssertEqualWithAccuracy(pois[1].coordinate.latitude, 44.001, 1e-9, @"center of the way");
}

// a sight is included when the route passes within the distance (0: none), unless the user chose otherwise
- (void)testSightInclusionRule
{
    BikePlan *plan = [self planWithRoute];
    POILocation *near = [self sightAtLatitudeOffsetMeters:60 longitude:0.55 id:10 type:POI_culture];
    POILocation *far = [self sightAtLatitudeOffsetMeters:400 longitude:0.56 id:11 type:POI_viewpoint];
    POILocation *water = [self sightAtLatitudeOffsetMeters:900 longitude:0.57 id:12 type:POI_drinking_water];
    [plan setPoiloc:@[ near, far, water ]];

    double along = 0, off = 0;
    XCTAssertTrue([plan routePositionOfPOI:near along:&along off:&off]);
    XCTAssertEqualWithAccuracy(off, 60, 2);
    XCTAssertEqualWithAccuracy(along, 0.05 * 111195 * cos(44 * M_PI / 180), 30, @"km along the route (≈ 4 km)");

    plan.sightIncludeDistance = 100;
    XCTAssertFalse([plan isPOIExcluded:near], @"60 m ≤ 100 m");
    XCTAssertTrue([plan isPOIExcluded:far], @"400 m > 100 m");
    XCTAssertFalse([plan isPOIExcluded:water], @"utilities are always included");
    plan.sightIncludeDistance = 50;
    XCTAssertTrue([plan isPOIExcluded:near]);
    plan.sightIncludeDistance = 0;
    XCTAssertTrue([plan isPOIExcluded:near], @"0: none automatically");

    // the user's choice wins
    [plan setPOIKey:far.poiKey excluded:NO];
    XCTAssertFalse([plan isPOIExcluded:far]);
    XCTAssertTrue([plan.includedPOIKeys containsObject:far.poiKey]);
    plan.sightIncludeDistance = 250;
    [plan setPOIKey:near.poiKey excluded:YES];
    XCTAssertTrue([plan isPOIExcluded:near]);
    [plan setPOIKey:near.poiKey excluded:NO];
    XCTAssertFalse([plan isPOIExcluded:near]);
    XCTAssertFalse([plan.excludedPOIKeys containsObject:near.poiKey]);
    [plan setPOIKey:water.poiKey excluded:YES];
    XCTAssertTrue([plan isPOIExcluded:water]);
    XCTAssertFalse([plan.includedPOIKeys containsObject:water.poiKey]);

    // the sights along the route, by km
    NSArray<POILocation *> *sights = [plan sightsAlongRoute];
    XCTAssertEqualObjects([sights valueForKey:@"poiKey"], (@[ near.poiKey, far.poiKey ]));
}

- (void)testSightSettingsAreSaved
{
    BikePlan *plan = [self planWithRoute];
    plan.sightCategories = @[ @"nature", @"culture" ];
    plan.sightIncludeDistance = 250;
    POILocation *far = [self sightAtLatitudeOffsetMeters:400 longitude:0.56 id:11 type:POI_viewpoint];
    [plan setPoiloc:@[ far ]];
    [plan setPOIKey:far.poiKey excluded:NO];
    NSData *d = [NSKeyedArchiver archivedDataWithRootObject:plan requiringSecureCoding:YES error:NULL];
    BikePlan *copy = [NSKeyedUnarchiver unarchivedObjectOfClass:[BikePlan class] fromData:d error:NULL];
    XCTAssertEqualObjects(copy.sightCategories, (@[ @"culture", @"nature" ]));
    XCTAssertEqual(copy.sightIncludeDistance, 250);
    XCTAssertTrue([copy.includedPOIKeys containsObject:far.poiKey]);

    // a new plan, or a document saved before #81: no sights, none included automatically (the owner checks them;
    // on a city route almost every café is within 100 m)
    BikePlan *fresh = [[BikePlan alloc] init];
    XCTAssertEqualObjects(fresh.sightCategories, @[]);
    XCTAssertEqual(fresh.sightIncludeDistance, 0);
}

@end
