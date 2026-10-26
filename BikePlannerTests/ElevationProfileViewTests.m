//
//  ElevationProfileViewTests.m
//  BikePlannerTests
//

#import <XCTest/XCTest.h>
#import "ElevationProfileView.h"
#import "TestFixtures.h"

@interface ElevationProfileViewTests : XCTestCase <ElevationProfileViewDelegate>
@end

@implementation ElevationProfileViewTests {
    NSMutableArray<NSNumber *> *selected;
}

- (void)elevationProfileView:(id)view didSelectDistance:(double)distance
{
    [selected addObject:@(distance)];
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)p in:(NSWindow *)w
{
    return [NSEvent mouseEventWithType:type location:p modifierFlags:0 timestamp:0
                          windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

// Click / drag in the plot area reports the distance along the route to the delegate.
- (void)testMouseSelectsDistance
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 200) styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    ElevationProfileView *v = [[ElevationProfileView alloc] initWithFrame:NSMakeRect(0, 0, 440, 200)];
    [w.contentView addSubview:v];
    selected = [NSMutableArray array];
    v.delegate = self;
    [v setGpxPoints:@[BPLocAlt(0, 0, 100), BPLocAlt(0, 0.01, 150), BPLocAlt(0, 0.02, 120)]];
    [v displayIfNeeded]; // drawRect computes the plot area
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];

    double total = v.distances.lastObject.doubleValue;
    // plot area is the bounds inset by 40 x 30: x from 40 to 400, middle = 220
    [v mouseDown:[self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(220, 100) in:w]];
    [v mouseDragged:[self mouse:NSEventTypeLeftMouseDragged at:NSMakePoint(130, 100) in:w]];
    // outside the plot area: ignored
    [v mouseDown:[self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(10, 100) in:w]];

    XCTAssertEqual(selected.count, 2u);
    XCTAssertEqualWithAccuracy(selected[0].doubleValue, total / 2, total * 0.01);
    XCTAssertEqualWithAccuracy(selected[1].doubleValue, total / 4, total * 0.01);
    XCTAssertEqualWithAccuracy(v.highlightDistance, total / 4, total * 0.01);

    // highlight cursor drawing
    v.highlightDistance = total / 3;
    XCTAssertNoThrow([v cacheDisplayInRect:v.bounds toBitmapImageRep:rep]);
    [v setHighlightDistance:total / 2 animated:NO];
    XCTAssertEqualWithAccuracy(v.highlightDistance, total / 2, 1e-9);
    [w close];
}

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
