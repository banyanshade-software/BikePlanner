//
//  ElevationProfileViewTests.m
//  BikePlannerTests
//

#import <XCTest/XCTest.h>
#import "ElevationProfileView.h"
#import "TestFixtures.h"

@interface ElevationProfileView (ScaleTesting)
+ (void)elevationRangeForMin:(double)minElev max:(double)maxElev low:(double *)low high:(double *)high;
+ (NSArray<NSNumber *> *)ticksFrom:(double)low to:(double)high maxCount:(NSUInteger)maxCount;
@end

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

#pragma mark - scale (#32, #17)

// the vertical range is at least 100 m, so small differences stay small; flat route: no division by zero
- (void)testElevationRangeHasMinimumSpan
{
    double lo, hi;
    [ElevationProfileView elevationRangeForMin:150 max:150 low:&lo high:&hi];
    XCTAssertGreaterThanOrEqual(hi - lo, 100);
    XCTAssertLessThanOrEqual(lo, 150);
    XCTAssertGreaterThanOrEqual(hi, 150);
    XCTAssertEqualWithAccuracy((lo + hi) / 2, 150, 25, @"centered on the route");

    [ElevationProfileView elevationRangeForMin:140 max:152 low:&lo high:&hi];
    XCTAssertGreaterThanOrEqual(hi - lo, 100, @"12 m of difference does not fill the plot");
}

- (void)testElevationRangeContainsTheDataOnRoundValues
{
    double lo, hi;
    [ElevationProfileView elevationRangeForMin:123 max:987 low:&lo high:&hi];
    XCTAssertLessThanOrEqual(lo, 123);
    XCTAssertGreaterThanOrEqual(hi, 987);
    XCTAssertEqual(fmod(lo, 50), 0);
    XCTAssertEqual(fmod(hi, 50), 0);
    XCTAssertLessThan(hi - lo, 1300, @"not much wider than the data");
}

- (void)testTicksAreRoundAndInRange
{
    for (NSArray *r in @[@[@0, @1000], @[@100, @200], @[@50, @1850], @[@0, @37.5]]) {
        double lo = [r[0] doubleValue], hi = [r[1] doubleValue];
        NSArray<NSNumber *> *t = [ElevationProfileView ticksFrom:lo to:hi maxCount:5];
        XCTAssertGreaterThanOrEqual(t.count, 2u, @"%@", r);
        XCTAssertLessThanOrEqual(t.count, 5u, @"%@", r);
        double step = t[1].doubleValue - t[0].doubleValue;
        double mant = step / pow(10, floor(log10(step)));
        XCTAssertTrue(fabs(mant - 1) < 1e-9 || fabs(mant - 2) < 1e-9 || fabs(mant - 2.5) < 1e-9 || fabs(mant - 5) < 1e-9,
                      @"round step %g for %@", step, r);
        for (NSNumber *v in t) {
            XCTAssertTrue(v.doubleValue >= lo - 1e-9 && v.doubleValue <= hi + 1e-9, @"%@ in %@", v, r);
            XCTAssertEqualWithAccuracy(fmod(v.doubleValue, step), 0, 1e-9, @"%@ multiple of %g", v, step);
        }
    }
}

// renders the view, returns the fraction of non-transparent pixels in a rect (view coordinates, origin bottom-left)
- (double)inkIn:(NSRect)r of:(ElevationProfileView *)v
{
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    CGFloat s = rep.pixelsWide / v.bounds.size.width;
    NSUInteger ink = 0, n = 0;
    for (NSInteger x = (NSInteger)(r.origin.x * s); x < (NSInteger)(NSMaxX(r) * s); x++) {
        for (NSInteger y = (NSInteger)(r.origin.y * s); y < (NSInteger)(NSMaxY(r) * s); y++) {
            NSInteger py = rep.pixelsHigh - 1 - y; // bitmap rows go top-down
            if ([rep colorAtX:x y:py].alphaComponent > 0.1) ink++; // labels are secondaryLabelColor (~50 % alpha)
            n++;
        }
    }
    return n ? (double)ink / n : 0;
}

- (void)testFlatRouteIsDrawnMidHeightWithLabels
{
    ElevationProfileView *v = [[ElevationProfileView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    v.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [v setGpxPoints:@[BPLocAlt(0, 0, 100), BPLocAlt(0, 0.01, 100), BPLocAlt(0, 0.02, 100)]];
    // plot area is the bounds inset by 40 x 30: a flat route is a line near mid-height, not at the bottom
    XCTAssertGreaterThan([self inkIn:NSMakeRect(100, 85, 200, 30) of:v], 0.01, @"profile line near mid-height");
    XCTAssertGreaterThan([self inkIn:NSMakeRect(0, 30, 38, 140) of:v], 0.005, @"altitude labels in the left margin");
    XCTAssertGreaterThan([self inkIn:NSMakeRect(40, 0, 320, 28) of:v], 0.005, @"distance labels in the bottom margin");
}

@end
