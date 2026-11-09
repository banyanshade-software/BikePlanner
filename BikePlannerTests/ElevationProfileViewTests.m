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
- (void)displayedElevationLow:(double *)low high:(double *)high;
@end

@interface ElevationProfileViewTests : XCTestCase <ElevationProfileViewDelegate>
@end

@implementation ElevationProfileViewTests {
    NSMutableArray<NSNumber *> *selected;
    NSMutableArray<NSArray<NSNumber *> *> *shown; // ranges reported by elevationProfileView:didShowRangeFrom:to:
}

- (void)elevationProfileView:(id)view didSelectDistance:(double)distance
{
    [selected addObject:@(distance)];
}

- (void)elevationProfileView:(id)view didShowRangeFrom:(double)from to:(double)to
{
    [shown addObject:@[@(from), @(to)]];
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)p in:(NSWindow *)w
{
    return [self mouse:type at:p in:w flags:0 clicks:1];
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)p in:(NSWindow *)w flags:(NSEventModifierFlags)flags clicks:(NSInteger)n
{
    return [NSEvent mouseEventWithType:type location:p modifierFlags:flags timestamp:0
                          windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:n pressure:1];
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

#pragma mark - slope at the selected point (#48)

// points every 10 m going north, elevation from f(distance in m)
- (ElevationProfileView *)profileOver:(double)length elevation:(double (^)(double d))f
{
    NSMutableArray<CLLocation *> *pts = [NSMutableArray array];
    for (double d = 0; d <= length + 0.1; d += 10) pts[pts.count] = BPLocAlt(44.0 + d / 111195.0, 0.5, f(d));
    ElevationProfileView *v = [[ElevationProfileView alloc] initWithFrame:NSMakeRect(0, 0, 400, 150)];
    [v setGpxPoints:pts];
    return v;
}

- (void)testSlopeAtDistance
{
    ElevationProfileView *flat = [self profileOver:2000 elevation:^double(double d) { return 100; }];
    XCTAssertEqualWithAccuracy([flat slopeAtDistance:1000].doubleValue, 0, 0.05);
    ElevationProfileView *up = [self profileOver:2000 elevation:^double(double d) { return 100 + 0.05 * d; }];
    XCTAssertEqualWithAccuracy([up slopeAtDistance:1000].doubleValue, 5.0, 0.1, @"5 %%");
    XCTAssertEqualWithAccuracy([up slopeAtDistance:0].doubleValue, 5.0, 0.1, @"at the start");
    XCTAssertEqualWithAccuracy([up slopeAtDistance:2000].doubleValue, 5.0, 0.1, @"at the end");
    ElevationProfileView *down = [self profileOver:2000 elevation:^double(double d) { return 300 - 0.08 * d; }];
    XCTAssertEqualWithAccuracy([down slopeAtDistance:500].doubleValue, -8.0, 0.1, @"downhill, in the route direction");
    // noisy elevations (±2 m every 10 m): the slope over ±50 m stays readable (a point-to-point slope would be ±40 %)
    ElevationProfileView *noisy = [self profileOver:2000 elevation:^double(double d) {
        return 100 + 0.03 * d + ((int)(d / 10) % 2 ? 2 : -2); }];
    XCTAssertEqualWithAccuracy([noisy slopeAtDistance:1005].doubleValue, 3.0, 4.1);
    // no route
    ElevationProfileView *empty = [[ElevationProfileView alloc] initWithFrame:NSMakeRect(0, 0, 400, 150)];
    XCTAssertNil([empty slopeAtDistance:10]);
}

- (void)testHighlightTextShowsDistanceElevationSlope
{
    ElevationProfileView *up = [self profileOver:2000 elevation:^double(double d) { return 100 + 0.065 * d; }];
    XCTAssertNil(up.highlightText, @"no point selected");
    up.highlightDistance = 1200;
    NSString *t = up.highlightText;
    XCTAssertTrue([t containsString:@"+6"] && [t containsString:@"%"], @"%@", t);
    XCTAssertTrue([t containsString:@"km"], @"%@", t);
    XCTAssertTrue([t containsString:@"178 m"], @"elevation at 1.2 km: %@", t);
}

#pragma mark - zoom (#62)

// a 440 x 200 profile in a window (plot area: x from 40 to 400) over a route going east along the equator, one
// point every ~111 m; elevations from f(index)
- (ElevationProfileView *)zoomableProfile:(NSUInteger)n elevation:(double (^)(NSUInteger i))f window:(NSWindow **)pw
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 200) styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    ElevationProfileView *v = [[ElevationProfileView alloc] initWithFrame:NSMakeRect(0, 0, 440, 200)];
    [w.contentView addSubview:v];
    NSMutableArray<CLLocation *> *pts = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++) pts[i] = BPLocAlt(0, i * 0.001, f(i));
    [v setGpxPoints:pts];
    selected = [NSMutableArray array];
    shown = [NSMutableArray array];
    v.delegate = self;
    [self render:v];
    *pw = w;
    return v;
}

- (void)render:(ElevationProfileView *)v
{
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
}

- (NSButton *)button:(NSString *)identifier in:(NSView *)v
{
    for (NSView *s in v.subviews) {
        if ([s.accessibilityIdentifier isEqualToString:identifier]) return (NSButton *)s;
    }
    return nil;
}

- (void)testShowRangeIsClampedWithMinimumSpan
{
    NSWindow *w;
    ElevationProfileView *v = [self zoomableProfile:21 elevation:^double(NSUInteger i) { return 100; } window:&w];
    double total = v.distances.lastObject.doubleValue; // ~2.2 km
    XCTAssertFalse(v.zoomed);
    XCTAssertEqual(v.visibleFrom, 0);
    XCTAssertEqualWithAccuracy(v.visibleTo, total, 1e-6);

    [v showRangeFrom:600 to:900 notify:NO]; // 300 m: widened to 1 km around its middle
    XCTAssertTrue(v.zoomed);
    XCTAssertEqualWithAccuracy(v.visibleFrom, 250, 1e-6);
    XCTAssertEqualWithAccuracy(v.visibleTo, 1250, 1e-6);
    XCTAssertEqual(shown.count, 0u, @"not notified");

    [v showRangeFrom:-500 to:400 notify:YES]; // before the start: moved, keeps its span
    XCTAssertEqualWithAccuracy(v.visibleFrom, 0, 1e-6);
    XCTAssertEqualWithAccuracy(v.visibleTo, 1000, 1e-6);
    XCTAssertEqual(shown.count, 1u);

    [v showRangeFrom:-100 to:total + 100 notify:NO]; // the whole route
    XCTAssertFalse(v.zoomed);
    XCTAssertEqualWithAccuracy(v.visibleTo, total, 1e-6);
    [w close];
}

- (void)testZoomButtons
{
    NSWindow *w;
    ElevationProfileView *v = [self zoomableProfile:41 elevation:^double(NSUInteger i) { return 100; } window:&w];
    double total = v.distances.lastObject.doubleValue; // ~4.4 km
    NSButton *zin = [self button:@"profileZoomIn" in:v], *zout = [self button:@"profileZoomOut" in:v];
    NSButton *fit = [self button:@"profileZoomFit" in:v];
    XCTAssertNotNil(zin);
    XCTAssertNotNil(zout);
    XCTAssertNotNil(fit);
    XCTAssertTrue(zin.enabled);
    XCTAssertFalse(zout.enabled, @"nothing to zoom out");
    XCTAssertFalse(fit.enabled, @"the whole route is shown");
    // in the top right corner, above the plot area
    XCTAssertGreaterThan(NSMinX(zin.frame), 300);
    XCTAssertGreaterThanOrEqual(NSMinY(zin.frame), 170);

    [zin performClick:self]; // no cursor: around the middle
    XCTAssertTrue(v.zoomed);
    XCTAssertEqualWithAccuracy(v.visibleFrom, total / 4, 1);
    XCTAssertEqualWithAccuracy(v.visibleTo, total * 3 / 4, 1);
    XCTAssertTrue(zout.enabled);
    XCTAssertTrue(fit.enabled);
    XCTAssertEqual(shown.count, 1u, @"the delegate is told (the map follows)");

    v.highlightDistance = total * 0.3; // with a cursor in view: around the cursor
    [zin performClick:self];
    XCTAssertEqualWithAccuracy(v.visibleTo - v.visibleFrom, total / 4, 1);
    XCTAssertTrue(v.visibleFrom < total * 0.3 && total * 0.3 < v.visibleTo);
    XCTAssertTrue(zin.enabled);
    [zin performClick:self];
    XCTAssertEqualWithAccuracy(v.visibleTo - v.visibleFrom, 1000, 1, @"at most 1 km");
    XCTAssertFalse(zin.enabled, @"at the minimum span");

    [zout performClick:self];
    XCTAssertEqualWithAccuracy(v.visibleTo - v.visibleFrom, 2000, 1);

    [fit performClick:self];
    XCTAssertFalse(v.zoomed);
    XCTAssertEqualWithAccuracy(shown.lastObject[0].doubleValue, 0, 1e-6);
    XCTAssertEqualWithAccuracy(shown.lastObject[1].doubleValue, total, 1e-6);
    XCTAssertFalse(fit.enabled);
    [w close];
}

// ⌥-drag selects a range and zooms on it; the cursor does not move. Double-click: the whole route.
- (void)testOptionDragZoomsOnRangeAndDoubleClickResets
{
    NSWindow *w;
    ElevationProfileView *v = [self zoomableProfile:41 elevation:^double(NSUInteger i) { return 100; } window:&w];
    double total = v.distances.lastObject.doubleValue;
    NSEventModifierFlags opt = NSEventModifierFlagOption;
    [v mouseDown:[self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(130, 100) in:w flags:opt clicks:1]];
    [v mouseDragged:[self mouse:NSEventTypeLeftMouseDragged at:NSMakePoint(250, 100) in:w flags:opt clicks:1]];
    [self render:v]; // the selection is drawn
    [v mouseDragged:[self mouse:NSEventTypeLeftMouseDragged at:NSMakePoint(310, 100) in:w flags:opt clicks:1]];
    [v mouseUp:[self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(310, 100) in:w flags:opt clicks:1]];
    XCTAssertEqual(selected.count, 0u, @"the cursor does not move");
    XCTAssertEqualWithAccuracy(v.visibleFrom, total / 4, total * 0.01);
    XCTAssertEqualWithAccuracy(v.visibleTo, total * 3 / 4, total * 0.01);
    XCTAssertEqual(shown.count, 1u);

    // a click in the zoomed profile: the distance in the visible part
    [self render:v];
    [v mouseDown:[self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(220, 120) in:w]];
    XCTAssertEqual(selected.count, 1u);
    XCTAssertEqualWithAccuracy(selected[0].doubleValue, total / 2, total * 0.01);

    // ⌥-click without dragging: nothing
    [v mouseDown:[self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(200, 120) in:w flags:opt clicks:1]];
    [v mouseUp:[self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(201, 120) in:w flags:opt clicks:1]];
    XCTAssertEqualWithAccuracy(v.visibleFrom, total / 4, total * 0.01);

    [v mouseDown:[self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(220, 120) in:w flags:0 clicks:2]];
    XCTAssertFalse(v.zoomed);
    [w close];
}

- (NSEvent *)scrollX:(int32_t)dx y:(int32_t)dy flags:(CGEventFlags)flags at:(NSPoint)p in:(NSWindow *)w
{
    CGEventRef cg = CGEventCreateScrollWheelEvent2(NULL, kCGScrollEventUnitPixel, 2, dy, dx, 0);
    CGEventSetFlags(cg, flags);
    NSPoint sp = [w convertPointToScreen:p];
    CGEventSetLocation(cg, CGPointMake(sp.x, NSMaxY(NSScreen.screens.firstObject.frame) - sp.y));
    NSEvent *e = [NSEvent eventWithCGEvent:cg];
    CFRelease(cg);
    return e;
}

// horizontal scrolling moves a zoomed profile; ⌘-scroll zooms
- (void)testScrollMovesZoomedProfile
{
    NSWindow *w;
    ElevationProfileView *v = [self zoomableProfile:41 elevation:^double(NSUInteger i) { return 100; } window:&w];
    double total = v.distances.lastObject.doubleValue;
    [v scrollWheel:[self scrollX:-50 y:0 flags:0 at:NSMakePoint(220, 100) in:w]];
    XCTAssertFalse(v.zoomed, @"not zoomed: nothing to scroll");

    [v showRangeFrom:total / 4 to:total * 3 / 4 notify:NO];
    double from = v.visibleFrom;
    [v scrollWheel:[self scrollX:-36 y:0 flags:0 at:NSMakePoint(220, 100) in:w]];
    // content moved to the left: further along the route
    XCTAssertGreaterThan(v.visibleFrom, from + 1);
    XCTAssertLessThan(v.visibleFrom, from + total / 4);
    XCTAssertEqual(shown.count, 1u);

    double span = v.visibleTo - v.visibleFrom;
    [v scrollWheel:[self scrollX:0 y:30 flags:kCGEventFlagMaskCommand at:NSMakePoint(220, 100) in:w]];
    XCTAssertNotEqualWithAccuracy(v.visibleTo - v.visibleFrom, span, 1, @"⌘-scroll zooms");
    [w close];
}

- (void)testMagnifyZoomsAroundPointer
{
    NSWindow *w;
    ElevationProfileView *v = [self zoomableProfile:41 elevation:^double(NSUInteger i) { return 100; } window:&w];
    double total = v.distances.lastObject.doubleValue;
    [v zoomBy:2 around:total / 4];
    XCTAssertEqualWithAccuracy(v.visibleFrom, total / 8, 1, @"the distance stays at the same place");
    XCTAssertEqualWithAccuracy(v.visibleTo, total * 5 / 8, 1);
    XCTAssertEqual(shown.count, 1u);
    [w close];
}

// zoomed: an overview of the whole route under the plot; a click there moves the view, a drag moves it along
- (void)testOverviewStrip
{
    NSWindow *w;
    ElevationProfileView *v = [self zoomableProfile:41 elevation:^double(NSUInteger i) { return 100 + i; } window:&w];
    double total = v.distances.lastObject.doubleValue;
    double inkBefore = [self inkIn:NSMakeRect(40, 3, 360, 14) of:v];
    [v showRangeFrom:0 to:total / 4 notify:NO];
    XCTAssertGreaterThan([self inkIn:NSMakeRect(40, 3, 360, 14) of:v], inkBefore + 0.1, @"overview drawn");

    // overview: x from 40 to 400 for the whole route
    [v mouseDown:[self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(220, 10) in:w]];
    XCTAssertEqualWithAccuracy((v.visibleFrom + v.visibleTo) / 2, total / 2, total * 0.01, @"centered on the click");
    [v mouseDragged:[self mouse:NSEventTypeLeftMouseDragged at:NSMakePoint(310, 10) in:w]];
    XCTAssertEqualWithAccuracy((v.visibleFrom + v.visibleTo) / 2, total * 3 / 4, total * 0.01);
    [v mouseUp:[self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(310, 10) in:w]];
    XCTAssertEqual(selected.count, 0u, @"the cursor does not move");
    XCTAssertEqual(shown.count, 2u);
    XCTAssertEqualWithAccuracy(v.visibleTo - v.visibleFrom, total / 4, 1, @"same span");
    [w close];
}

// the vertical axis fits the visible part
- (void)testVerticalAxisFitsVisiblePart
{
    NSWindow *w;
    // climbs 1000 m over the first half, then flat
    ElevationProfileView *v = [self zoomableProfile:41 elevation:^double(NSUInteger i) {
        return i <= 20 ? 100 + 50 * i : 1100; } window:&w];
    double total = v.distances.lastObject.doubleValue;
    double lo, hi;
    [v displayedElevationLow:&lo high:&hi];
    XCTAssertLessThanOrEqual(lo, 100);
    XCTAssertGreaterThanOrEqual(hi, 1100);
    [v showRangeFrom:total * 0.6 to:total notify:NO];
    [v displayedElevationLow:&lo high:&hi];
    XCTAssertGreaterThanOrEqual(lo, 1000);
    XCTAssertLessThanOrEqual(hi, 1200);
    [w close];
}

// a cursor set from the map outside the visible part moves the profile (not the map)
- (void)testCursorOutsideVisiblePartMovesProfile
{
    NSWindow *w;
    ElevationProfileView *v = [self zoomableProfile:41 elevation:^double(NSUInteger i) { return 100; } window:&w];
    double total = v.distances.lastObject.doubleValue;
    [v showRangeFrom:0 to:total / 4 notify:NO];
    v.highlightDistance = total * 0.8;
    XCTAssertTrue(v.visibleFrom < total * 0.8 && total * 0.8 < v.visibleTo);
    XCTAssertEqualWithAccuracy(v.visibleTo - v.visibleFrom, total / 4, 1);
    XCTAssertEqual(shown.count, 0u);
    v.highlightDistance = 0; // no cursor: unchanged
    XCTAssertTrue(v.zoomed);
    [w close];
}

// a click on a stage number zooms on that stage; a new route shows the whole route
- (void)testStageNumberZoomsOnStageAndNewRouteResets
{
    NSWindow *w;
    ElevationProfileView *v = [self zoomableProfile:41 elevation:^double(NSUInteger i) { return 100; } window:&w];
    double total = v.distances.lastObject.doubleValue;
    v.stageEndIndexes = @[@10, @30];
    [self render:v];
    // stage 2 starts at 1/4 of the route: its number is drawn right of the line, at the top of the plot (y 170)
    [v mouseDown:[self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(40 + 90 + 6, 165) in:w]];
    XCTAssertEqualWithAccuracy(v.visibleFrom, total / 4, 1);
    XCTAssertEqualWithAccuracy(v.visibleTo, total * 3 / 4, 1);
    XCTAssertEqual(selected.count, 0u);
    XCTAssertEqual(shown.count, 1u);

    [v setGpxPoints:@[BPLocAlt(0, 0, 100), BPLocAlt(0, 0.05, 100)]];
    XCTAssertFalse(v.zoomed);
    [w close];
}

@end
