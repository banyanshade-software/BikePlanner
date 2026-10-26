//
//  ElevationProfileViewTests.m
//  BikePlannerTests
//

#import <XCTest/XCTest.h>
#import "ElevationProfileView.h"
#import "TestFixtures.h"

@interface ElevationProfileViewTests : XCTestCase
@end

@implementation ElevationProfileViewTests

- (void)testDistancesElevationsSlopes
{
    ElevationProfileView *v = [[ElevationProfileView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    CLLocation *a = BPLocAlt(0, 0, 100), *b = BPLocAlt(0, 0.01, 150), *c = BPLocAlt(0, 0.02, 100);
    [v setGpxPoints:@[a, b, c]];

    double d1 = [b distanceFromLocation:a];
    XCTAssertEqual(v.distances.count, 3u);
    XCTAssertEqualWithAccuracy(v.distances[0].doubleValue, 0, 1e-9);
    XCTAssertEqualWithAccuracy(v.distances[1].doubleValue, d1, 1e-6);
    XCTAssertEqualWithAccuracy(v.distances[2].doubleValue, d1 + [c distanceFromLocation:b], 1e-6);

    XCTAssertEqualObjects(v.elevations, (@[@100, @150, @100]));

    XCTAssertEqualWithAccuracy(v.slopes[0].doubleValue, 0, 1e-9);
    XCTAssertEqualWithAccuracy(v.slopes[1].doubleValue, 50 / d1, 1e-9);
    XCTAssertLessThan(v.slopes[2].doubleValue, 0);
}

- (void)testEmptyRoute
{
    ElevationProfileView *v = [[ElevationProfileView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    [v setGpxPoints:@[]];
    XCTAssertEqual(v.distances.count, 0u);
}

// Drawing must not crash, even on a flat route (min == max elevation).
- (void)testDrawingFlatRouteDoesNotCrash
{
    ElevationProfileView *v = [[ElevationProfileView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    [v setGpxPoints:@[BPLocAlt(0, 0, 100), BPLocAlt(0, 0.01, 100)]];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    XCTAssertNoThrow([v cacheDisplayInRect:v.bounds toBitmapImageRep:rep]);
}

@end
