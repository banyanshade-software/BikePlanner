//
//  ElevationProfileView.m
//  BikePlanner
//
//  Created by Daniel on 13/08/2025.
//

#import "ElevationProfileView.h"

static const double kMinElevationRange = 100; // m: small differences must not look steep (#32)
static const double kMinVisibleSpan = 1000;    // m: narrowest zoomed view (#62)
static const CGFloat kOverviewHeight = 14;     // overview strip under the plot when zoomed (#62)

typedef NS_ENUM(NSInteger, BPProfileDrag) {
    BPProfileDragCursor,    // moves the cursor (and the map, Street View)
    BPProfileDragSelect,    // ⌥-drag: range to zoom on
    BPProfileDragOverview,  // moves the visible part in the overview strip
    BPProfileDragNone,
};

@implementation ElevationProfileView {
    double _maxDist;
    double _minElev, _maxElev;
    CGRect _plotRect;
    CGRect _overviewRect;           // empty when not zoomed
    BOOL _zoomed;
    double _visibleFrom, _visibleTo; // when zoomed
    NSButton *_zoomInButton, *_zoomOutButton, *_zoomFitButton;
    BPProfileDrag _drag;
    double _selectFrom, _selectTo;  // ⌥-drag, m
    double _dragOffset;             // overview drag: distance of the pointer from visibleFrom
    NSMutableArray<NSArray<NSValue *> *> *_stageLabels; // drawn stage numbers: rect, range (x: from, y: to)
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) [self setupZoomButtons];
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) [self setupZoomButtons];
    return self;
}

- (NSButton *)zoomButton:(NSString *)symbol action:(SEL)action identifier:(NSString *)identifier tip:(NSString *)tip
{
    NSButton *b = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip]
                                     target:self action:action];
    b.controlSize = NSControlSizeSmall;
    b.toolTip = tip;
    b.accessibilityIdentifier = identifier;
    [self addSubview:b];
    return b;
}

- (void)setupZoomButtons
{
    if (_zoomInButton) return;
    _drag = BPProfileDragNone;
    _zoomOutButton = [self zoomButton:@"minus.magnifyingglass" action:@selector(zoomProfileOut:) identifier:@"profileZoomOut"
                                  tip:NSLocalizedString(@"Zoom out of the elevation profile", @"profile zoom button")];
    _zoomInButton = [self zoomButton:@"plus.magnifyingglass" action:@selector(zoomProfileIn:) identifier:@"profileZoomIn"
                                 tip:NSLocalizedString(@"Zoom in on the elevation profile (also: pinch, ⌘-scroll, ⌥-drag on a range)", @"profile zoom button")];
    _zoomFitButton = [self zoomButton:@"arrow.up.left.and.arrow.down.right" action:@selector(zoomProfileToFit:)
                           identifier:@"profileZoomFit"
                                  tip:NSLocalizedString(@"Show the whole route (also: double-click)", @"profile zoom button")];
    [self placeZoomButtons];
    [self updateZoomButtons];
}

// top right corner, above the plot area
- (void)placeZoomButtons
{
    CGFloat x = NSMaxX(self.bounds) - 4;
    for (NSButton *b in @[_zoomFitButton, _zoomInButton, _zoomOutButton]) {
        NSSize sz = b.fittingSize;
        x -= sz.width;
        b.frame = NSMakeRect(x, NSMaxY(self.bounds) - 3 - sz.height, sz.width, sz.height);
        x -= 2;
    }
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self placeZoomButtons];
}

- (void)updateZoomButtons
{
    double total = self.distances.lastObject.doubleValue;
    _zoomInButton.enabled = total > kMinVisibleSpan && self.visibleTo - self.visibleFrom > kMinVisibleSpan + 1;
    _zoomOutButton.enabled = _zoomed;
    _zoomFitButton.enabled = _zoomed;
}

- (void)updateMetrics {
    _maxDist = [[self.distances lastObject] doubleValue];
    _maxElev = [[self.elevations valueForKeyPath:@"@max.doubleValue"] doubleValue];
    _minElev = [[self.elevations valueForKeyPath:@"@min.doubleValue"] doubleValue];
    _plotRect = NSInsetRect(self.bounds, 40, 30);
    _overviewRect = NSZeroRect;
    if (_zoomed) {
        // the overview at the bottom, the distance labels between it and the plot
        CGFloat extra = kOverviewHeight + 6;
        _plotRect.origin.y += extra;
        _plotRect.size.height -= extra;
        _overviewRect = NSMakeRect(NSMinX(_plotRect), 4, NSWidth(_plotRect), kOverviewHeight);
    }
}

#pragma mark - zoom (#62)

- (double)visibleFrom
{
    return _zoomed ? _visibleFrom : 0;
}

- (double)visibleTo
{
    return _zoomed ? _visibleTo : self.distances.lastObject.doubleValue;
}

- (BOOL)isZoomed
{
    return _zoomed;
}

- (void)showRangeFrom:(double)from to:(double)to notify:(BOOL)notify
{
    double total = self.distances.lastObject.doubleValue;
    double span = fmin(fmax(to - from, kMinVisibleSpan), total);
    if (to - from < span) from = (from + to - span) / 2;
    from = fmax(0, fmin(from, total - span));
    to = from + span;
    _zoomed = total > 0 && (from > 0.5 || to < total - 0.5);
    _visibleFrom = from;
    _visibleTo = to;
    [self updateZoomButtons];
    [self setNeedsDisplay:YES];
    if (notify && [self.delegate respondsToSelector:@selector(elevationProfileView:didShowRangeFrom:to:)]) {
        [self.delegate elevationProfileView:self didShowRangeFrom:self.visibleFrom to:self.visibleTo];
    }
}

- (void)zoomBy:(double)factor around:(double)distance
{
    double from = self.visibleFrom, to = self.visibleTo, span = to - from;
    if (span <= 0 || factor <= 0) return;
    distance = fmax(from, fmin(distance, to));
    double newSpan = span / factor;
    double newFrom = distance - (distance - from) * newSpan / span;
    [self showRangeFrom:newFrom to:newFrom + newSpan notify:YES];
}

// around the cursor when it is in view, else around the middle
- (double)zoomCenter
{
    if (_highlightDistance > 0 && _highlightDistance >= self.visibleFrom && _highlightDistance <= self.visibleTo) {
        return _highlightDistance;
    }
    return (self.visibleFrom + self.visibleTo) / 2;
}

- (IBAction)zoomProfileIn:(id)sender
{
    [self zoomBy:2 around:[self zoomCenter]];
}

- (IBAction)zoomProfileOut:(id)sender
{
    [self zoomBy:0.5 around:[self zoomCenter]];
}

- (IBAction)zoomProfileToFit:(id)sender
{
    [self showRangeFrom:0 to:self.distances.lastObject.doubleValue notify:YES];
}

// x in the plot of a distance, and back
- (CGFloat)xForDistance:(double)d
{
    double span = self.visibleTo - self.visibleFrom;
    return _plotRect.origin.x + (span > 0 ? (d - self.visibleFrom) / span : 0) * _plotRect.size.width;
}

- (double)distanceAtX:(CGFloat)x
{
    return self.visibleFrom + ((x - _plotRect.origin.x) / _plotRect.size.width) * (self.visibleTo - self.visibleFrom);
}

- (double)overviewDistanceAtX:(CGFloat)x
{
    double f = (x - _overviewRect.origin.x) / _overviewRect.size.width;
    return fmax(0, fmin(f, 1)) * _maxDist;
}

// displayed vertical range (#32): the visible part of the route
- (void)displayedElevationLow:(double *)low high:(double *)high
{
    double from = self.visibleFrom, to = self.visibleTo;
    double lo = [self elevationAtDistance:from], hi = lo;
    double e = [self elevationAtDistance:to];
    lo = fmin(lo, e);
    hi = fmax(hi, e);
    for (NSUInteger i = 0; i < self.distances.count; i++) {
        double d = self.distances[i].doubleValue;
        if (d < from) continue;
        if (d > to) break;
        e = self.elevations[i].doubleValue;
        lo = fmin(lo, e);
        hi = fmax(hi, e);
    }
    [[self class] elevationRangeForMin:lo max:hi low:low high:high];
}

#pragma mark - scale

// "nice" tick values (step 1, 2, 2.5 or 5 x 10^n) between low and high, at most maxCount of them
+ (NSArray<NSNumber *> *)ticksFrom:(double)low to:(double)high maxCount:(NSUInteger)maxCount
{
    double step = [self tickStepFrom:low to:high maxCount:maxCount];
    NSMutableArray<NSNumber *> *ticks = [NSMutableArray array];
    if (step <= 0) return ticks;
    for (double k = ceil(low / step - 1e-9); k * step <= high + 1e-9; k++) {
        [ticks addObject:@(round(k * step * 1e6) / 1e6)];
    }
    return ticks;
}

+ (double)tickStepFrom:(double)low to:(double)high maxCount:(NSUInteger)maxCount
{
    double span = high - low;
    if (span <= 0 || maxCount < 2) return 0;
    double raw = span / (maxCount - 1);
    double mag = pow(10, floor(log10(raw)));
    for (NSNumber *m in @[@1, @2, @2.5, @5, @10]) {
        if (m.doubleValue * mag >= raw - 1e-9) return m.doubleValue * mag;
    }
    return 10 * mag;
}

// vertical range: the data, at least kMinElevationRange m (centered), extended to round tick values
+ (void)elevationRangeForMin:(double)minElev max:(double)maxElev low:(double *)low high:(double *)high
{
    double span = fmax(maxElev - minElev, kMinElevationRange);
    double center = (minElev + maxElev) / 2;
    double lo = center - span / 2, hi = center + span / 2;
    if (minElev >= 0 && lo < 0) { hi -= lo; lo = 0; } // no negative altitude for a route above sea level
    double step = [self tickStepFrom:lo to:hi maxCount:5];
    if (step > 0) {
        lo = floor(lo / step) * step;
        hi = ceil(hi / step) * step;
    }
    *low = lo;
    *high = hi;
}

- (void) setStageEndIndexes:(NSArray<NSNumber *> *)stageEndIndexes
{
    _stageEndIndexes = [stageEndIndexes copy] ?: @[];
    [self setNeedsDisplay:YES];
}

- (NSArray<NSNumber *> *) stageEndDistances
{
    NSMutableArray<NSNumber *> *res = [NSMutableArray array];
    for (NSNumber *i in _stageEndIndexes) {
        if (i.unsignedIntegerValue < self.distances.count) [res addObject:self.distances[i.unsignedIntegerValue]];
    }
    return res;
}

- (void) setGpxPoints:(NSArray<CLLocation *> *)trackPoints
{
    NSMutableArray<NSNumber *> *distances = [NSMutableArray array];
    NSMutableArray<NSNumber *> *elevations = [NSMutableArray array];
    NSMutableArray<NSNumber *> *slopes = [NSMutableArray array];

    double totalDist = 0.0;

    for (NSUInteger i = 0; i < trackPoints.count; i++) {
        CLLocation *pt = trackPoints[i];
        [elevations addObject:@(pt.altitude)];
        if (i > 0) {
            double segmentDist = [pt distanceFromLocation:trackPoints[i - 1]];
            totalDist += segmentDist;
            double elevDiff = pt.altitude - trackPoints[i - 1].altitude;
            double slope = (segmentDist > 0) ? elevDiff / segmentDist : 0; // m/m
            [slopes addObject:@(slope)];
        } else {
            [slopes addObject:@(0)];
        }
        [distances addObject:@(totalDist)];
    }
    self.distances = distances;
    self.slopes = slopes;
    self.elevations = elevations;
    _zoomed = NO; // a new route: the whole route (#62)
    [self updateZoomButtons];
    [self setNeedsDisplay:YES];
    //[self setNeedsLayout:YES];
}

#pragma mark - slope at the selected point (#48)

static const double kBPSlopeHalfWindow = 50; // m

- (double) elevationAtDistance:(double)distance
{
    NSUInteger n = self.distances.count;
    if (n == 0) return 0;
    if (distance <= self.distances[0].doubleValue) return self.elevations[0].doubleValue;
    for (NSUInteger i = 1; i < n; i++) {
        double d2 = self.distances[i].doubleValue;
        if (distance <= d2) {
            double d1 = self.distances[i - 1].doubleValue;
            double e1 = self.elevations[i - 1].doubleValue, e2 = self.elevations[i].doubleValue;
            return d2 > d1 ? e1 + (e2 - e1) * (distance - d1) / (d2 - d1) : e2;
        }
    }
    return self.elevations[n - 1].doubleValue;
}

- (nullable NSNumber *) slopeAtDistance:(double)distance
{
    if (self.distances.count < 2) return nil;
    double total = self.distances.lastObject.doubleValue;
    double a = distance - kBPSlopeHalfWindow, b = distance + kBPSlopeHalfWindow;
    // full window at the ends of the route
    if (a < 0) { b -= a; a = 0; }
    if (b > total) { a -= b - total; b = total; }
    a = fmax(0, a);
    if (b - a < 1) return nil;
    return @(100 * ([self elevationAtDistance:b] - [self elevationAtDistance:a]) / (b - a));
}

- (nullable NSString *) highlightText
{
    if (_highlightDistance <= 0 || self.distances.count < 2) return nil;
    static NSNumberFormatter *km, *slope;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        km = [[NSNumberFormatter alloc] init];
        km.numberStyle = NSNumberFormatterDecimalStyle;
        km.minimumFractionDigits = 1;
        km.maximumFractionDigits = 1;
        slope = [km copy];
        slope.positivePrefix = @"+";
    });
    NSString *s = [NSString stringWithFormat:@"%@ km · %.0f m", [km stringFromNumber:@(_highlightDistance / 1000)],
                   [self elevationAtDistance:_highlightDistance]];
    NSNumber *p = [self slopeAtDistance:_highlightDistance];
    if (p != nil) s = [s stringByAppendingFormat:@" · %@ %%", [slope stringFromNumber:p]];
    return s;
}

- (void)drawRect:(NSRect)dirtyRect
{
    //NSLog(@"[%@] drawRect called", [NSDate date]);
    [super drawRect:dirtyRect];
    [self updateMetrics];
    [_stageLabels removeAllObjects];

    if (self.distances.count == 0) return;

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    double maxElev, minElev; // displayed range, not the data range (#32), of the visible part (#62)
    [self displayedElevationLow:&minElev high:&maxElev];
    double maxDist = [[self.distances lastObject] doubleValue];
    double from = self.visibleFrom, to = self.visibleTo;
    CGRect plotRect = _plotRect;

    // Scale: altitude grid + labels (m) on the left, distance labels (km from the start) at the bottom
    NSDictionary *labelAttrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:9],
                                  NSForegroundColorAttributeName: [NSColor secondaryLabelColor] };
    for (NSNumber *t in [[self class] ticksFrom:minElev to:maxElev maxCount:5]) {
        CGFloat y = plotRect.origin.y + ((t.doubleValue - minElev) / (maxElev - minElev)) * plotRect.size.height;
        [[NSColor separatorColor] setStroke];
        CGContextSetLineWidth(ctx, 0.5);
        CGContextMoveToPoint(ctx, plotRect.origin.x, y);
        CGContextAddLineToPoint(ctx, NSMaxX(plotRect), y);
        CGContextStrokePath(ctx);
        NSString *s = [NSString stringWithFormat:@"%.0f m", t.doubleValue];
        NSSize sz = [s sizeWithAttributes:labelAttrs];
        [s drawAtPoint:NSMakePoint(plotRect.origin.x - 4 - sz.width, y - sz.height / 2) withAttributes:labelAttrs];
    }
    if (maxDist > 0) {
        for (NSNumber *t in [[self class] ticksFrom:from / 1000 to:to / 1000 maxCount:6]) {
            CGFloat x = [self xForDistance:t.doubleValue * 1000];
            NSString *s = [NSString stringWithFormat:@"%g km", t.doubleValue];
            NSSize sz = [s sizeWithAttributes:labelAttrs];
            [s drawAtPoint:NSMakePoint(x - sz.width / 2, plotRect.origin.y - 4 - sz.height) withAttributes:labelAttrs];
        }
    }

    // Draw axes (left and bottom; the view is not flipped)
    [[NSColor labelColor] setStroke]; // dark in light mode, light in dark mode
    CGContextSetLineWidth(ctx, 1.0);
    CGContextMoveToPoint(ctx, plotRect.origin.x, plotRect.origin.y + plotRect.size.height);
    CGContextAddLineToPoint(ctx, plotRect.origin.x, plotRect.origin.y);
    CGContextAddLineToPoint(ctx, plotRect.origin.x + plotRect.size.width, plotRect.origin.y);
    CGContextStrokePath(ctx);
    if (maxDist <= 0) return; // single point: nothing to draw along the distance

    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, NSInsetRect(plotRect, -2, -2)); // zoomed: segments across the edges

    // Draw profile
    for (NSUInteger i = 1; i < self.distances.count; i++) {
        double d1 = [self.distances[i - 1] doubleValue];
        double e1 = [self.elevations[i - 1] doubleValue];
        double d2 = [self.distances[i] doubleValue];
        double e2 = [self.elevations[i] doubleValue];
        double slope = [self.slopes[i] doubleValue]; // m/m
        if (d2 < from) continue;
        if (d1 > to) break;

        // Map to view coords
        CGFloat x1 = [self xForDistance:d1];
        CGFloat y1 = plotRect.origin.y + ((e1 - minElev) / (maxElev - minElev)) * plotRect.size.height;
        CGFloat x2 = [self xForDistance:d2];
        CGFloat y2 = plotRect.origin.y + ((e2 - minElev) / (maxElev - minElev)) * plotRect.size.height;

        // Color based on slope
        if (slope > 0.05) { // >5% uphill
            [[NSColor systemRedColor] setStroke];
        } else if (slope < -0.05) { // < -5% downhill
            [[NSColor systemBlueColor] setStroke];
        } else {
            [[NSColor systemGreenColor] setStroke];
        }

        CGContextSetLineWidth(ctx, 2.0);
        CGContextMoveToPoint(ctx, x1, y1);
        CGContextAddLineToPoint(ctx, x2, y2);
        CGContextStrokePath(ctx);
    }
    CGContextRestoreGState(ctx);

    // stage ends (#31): a vertical line, the number of the next stage at the top; a click on it zooms on the stage
    if (!_stageLabels) _stageLabels = [NSMutableArray array];
    NSDictionary *stageAttrs = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:10],
                                  NSForegroundColorAttributeName: [NSColor systemPurpleColor] };
    NSArray<NSNumber *> *ends = self.stageEndDistances;
    for (NSUInteger k = 0; k < ends.count; k++) {
        double d = ends[k].doubleValue;
        if (d < from || d > to) continue;
        CGFloat sx = [self xForDistance:d];
        [[NSColor systemPurpleColor] setStroke];
        CGContextSetLineWidth(ctx, 1.5);
        CGContextMoveToPoint(ctx, sx, plotRect.origin.y);
        CGContextAddLineToPoint(ctx, sx, NSMaxY(plotRect));
        CGContextStrokePath(ctx);
        NSString *s = [NSString stringWithFormat:@"%lu", (unsigned long)k + 2];
        NSSize sz = [s sizeWithAttributes:stageAttrs];
        NSPoint at = NSMakePoint(sx + 3, NSMaxY(plotRect) - sz.height);
        [s drawAtPoint:at withAttributes:stageAttrs];
        double stageEnd = k + 1 < ends.count ? ends[k + 1].doubleValue : maxDist;
        [_stageLabels addObject:@[[NSValue valueWithRect:NSInsetRect(NSMakeRect(at.x, at.y, sz.width, sz.height), -3, -2)],
                                  [NSValue valueWithPoint:NSMakePoint(d, stageEnd)]]];
    }

    // ⌥-drag: the range to zoom on
    if (_drag == BPProfileDragSelect) {
        CGFloat xa = [self xForDistance:fmin(_selectFrom, _selectTo)], xb = [self xForDistance:fmax(_selectFrom, _selectTo)];
        [[[NSColor selectedContentBackgroundColor] colorWithAlphaComponent:0.2] setFill];
        NSRectFillUsingOperation(NSMakeRect(xa, plotRect.origin.y, xb - xa, plotRect.size.height), NSCompositingOperationSourceOver);
    }

    if (_zoomed) [self drawOverviewWithMaxDistance:maxDist context:ctx];

    // Draw highlight line
     if (_highlightDistance > 0 && _highlightDistance >= from && _highlightDistance <= to) {
         CGFloat hx = [self xForDistance:_highlightDistance];
         [[NSColor labelColor] setStroke];
         CGContextSetLineWidth(ctx, 1.0);
         CGContextMoveToPoint(ctx, hx, _plotRect.origin.y);
         CGContextAddLineToPoint(ctx, hx, _plotRect.origin.y + _plotRect.size.height);
         CGFloat dash[] = {4.0, 2.0};
         CGContextSetLineDash(ctx, 0, dash, 2);
         CGContextStrokePath(ctx);
         CGContextSetLineDash(ctx, 0, NULL, 0);

         // distance, elevation and slope at the cursor (#48), on the side with room
         NSString *text = self.highlightText;
         if (text) {
             NSDictionary *attrs = @{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium],
                                      NSForegroundColorAttributeName: [NSColor labelColor] };
             NSSize sz = [text sizeWithAttributes:attrs];
             CGFloat tx = hx + 6;
             if (tx + sz.width + 4 > NSMaxX(_plotRect)) tx = hx - 6 - sz.width;
             NSRect box = NSMakeRect(tx - 3, NSMaxY(_plotRect) - sz.height - 4, sz.width + 6, sz.height + 2);
             [[[NSColor windowBackgroundColor] colorWithAlphaComponent:0.85] setFill];
             [[NSBezierPath bezierPathWithRoundedRect:box xRadius:3 yRadius:3] fill];
             [text drawAtPoint:NSMakePoint(tx, NSMinY(box) + 1) withAttributes:attrs];
         }
     }
}

// the whole route, small, with the visible part framed (#62)
- (void)drawOverviewWithMaxDistance:(double)maxDist context:(CGContextRef)ctx
{
    NSRect r = _overviewRect;
    [[[NSColor tertiaryLabelColor] colorWithAlphaComponent:0.15] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:r xRadius:2 yRadius:2] fill];
    double lo, hi;
    [[self class] elevationRangeForMin:_minElev max:_maxElev low:&lo high:&hi];
    NSBezierPath *area = [NSBezierPath bezierPath];
    [area moveToPoint:NSMakePoint(NSMinX(r), NSMinY(r))];
    for (NSUInteger i = 0; i < self.distances.count; i++) {
        CGFloat x = NSMinX(r) + self.distances[i].doubleValue / maxDist * NSWidth(r);
        CGFloat y = NSMinY(r) + (self.elevations[i].doubleValue - lo) / (hi - lo) * NSHeight(r);
        [area lineToPoint:NSMakePoint(x, y)];
    }
    [area lineToPoint:NSMakePoint(NSMaxX(r), NSMinY(r))];
    [area closePath];
    [[NSColor secondaryLabelColor] setFill];
    [area fill];
    CGFloat xa = NSMinX(r) + self.visibleFrom / maxDist * NSWidth(r);
    CGFloat xb = NSMinX(r) + self.visibleTo / maxDist * NSWidth(r);
    NSRect vis = NSMakeRect(xa, NSMinY(r) - 1, fmax(xb - xa, 3), NSHeight(r) + 2);
    NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:vis xRadius:2 yRadius:2];
    [[[NSColor controlAccentColor] colorWithAlphaComponent:0.25] setFill];
    [frame fill];
    [[NSColor controlAccentColor] setStroke];
    frame.lineWidth = 1.5;
    [frame stroke];
}



- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    _drag = BPProfileDragNone;
    if (self.distances.count < 2) return;
    if (_zoomed && NSPointInRect(p, NSInsetRect(_overviewRect, 0, -3))) {
        double d = [self overviewDistanceAtX:p.x];
        double span = self.visibleTo - self.visibleFrom;
        if (d < self.visibleFrom || d > self.visibleTo) {
            [self showRangeFrom:d - span / 2 to:d + span / 2 notify:YES]; // centered on the click
        }
        _dragOffset = d - self.visibleFrom;
        _drag = BPProfileDragOverview;
        return;
    }
    for (NSArray<NSValue *> *label in _stageLabels) {
        if (NSPointInRect(p, label[0].rectValue)) {
            NSPoint range = label[1].pointValue;
            [self showRangeFrom:range.x to:range.y notify:YES];
            return;
        }
    }
    if (event.clickCount == 2) {
        [self zoomProfileToFit:self];
        return;
    }
    if ((event.modifierFlags & NSEventModifierFlagOption) && NSPointInRect(p, _plotRect)) {
        _selectFrom = _selectTo = [self distanceAtX:p.x];
        _drag = BPProfileDragSelect;
        [self setNeedsDisplay:YES];
        return;
    }
    _drag = BPProfileDragCursor;
    [self handleMouse:event];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    switch (_drag) {
        case BPProfileDragCursor:
            [self handleMouse:event];
            break;
        case BPProfileDragSelect:
            _selectTo = [self distanceAtX:fmax(NSMinX(_plotRect), fmin(p.x, NSMaxX(_plotRect)))];
            [self setNeedsDisplay:YES];
            break;
        case BPProfileDragOverview: {
            double from = [self overviewDistanceAtX:p.x] - _dragOffset;
            [self showRangeFrom:from to:from + self.visibleTo - self.visibleFrom notify:YES];
            break;
        }
        case BPProfileDragNone:
            break;
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (_drag == BPProfileDragSelect) {
        _drag = BPProfileDragNone;
        CGFloat xa = [self xForDistance:_selectFrom], xb = [self xForDistance:_selectTo];
        if (fabs(xb - xa) >= 4) { // not a ⌥-click
            [self showRangeFrom:fmin(_selectFrom, _selectTo) to:fmax(_selectFrom, _selectTo) notify:YES];
        }
        [self setNeedsDisplay:YES];
    }
    _drag = BPProfileDragNone;
}

- (void)handleMouse:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, _plotRect)) {
        double dist = [self distanceAtX:p.x];
        [self setHighlightDistance:dist animated:YES];
        if ([self.delegate respondsToSelector:@selector(elevationProfileView:didSelectDistance:)]) {
            [self.delegate elevationProfileView:self didSelectDistance:dist];
        }
        
    }
}

// horizontal scroll (or ⇧-scroll with a mouse) moves a zoomed profile; ⌘-scroll zooms around the pointer
- (void)scrollWheel:(NSEvent *)event
{
    if (self.distances.count < 2) {
        [super scrollWheel:event];
        return;
    }
    CGFloat scale = event.hasPreciseScrollingDeltas ? 1 : 10; // lines → points
    CGFloat dx = event.scrollingDeltaX * scale, dy = event.scrollingDeltaY * scale;
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        if (dy != 0) {
            NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
            [self zoomBy:exp(dy / 100) around:[self distanceAtX:p.x]];
        }
        return;
    }
    if (_zoomed && dx != 0 && fabs(dx) >= fabs(dy)) {
        double shift = -dx * (self.visibleTo - self.visibleFrom) / _plotRect.size.width;
        [self showRangeFrom:self.visibleFrom + shift to:self.visibleTo + shift notify:YES];
        return;
    }
    [super scrollWheel:event];
}

// trackpad pinch
- (void)magnifyWithEvent:(NSEvent *)event
{
    if (self.distances.count < 2) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    [self zoomBy:1 + event.magnification around:[self distanceAtX:p.x]];
}

- (void)setHighlightDistance:(double)highlightDistance
{
    [self setHighlightDistance:highlightDistance animated:NO];
}

- (void)setHighlightDistance:(double)highlightDistance animated:(BOOL)animated {
    _highlightDistance =  highlightDistance; //fmax(0, fmin(_highlightDistance, [[self.distances lastObject] doubleValue]));
    if (_zoomed && highlightDistance > 0 && (highlightDistance < _visibleFrom || highlightDistance > _visibleTo)) {
        // set from the map: the profile moves to show it (the map is where it is)
        double span = _visibleTo - _visibleFrom;
        [self showRangeFrom:highlightDistance - span / 2 to:highlightDistance + span / 2 notify:NO];
    }
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.1;
            [self.animator setNeedsDisplay:YES];
        } completionHandler:nil];
    } else {
        [self setNeedsDisplay:YES];
    }
}


- (void)setNeedsDisplay:(BOOL)flag
{
    //NSLog(@"[%@] setNeedsDisplay called", [NSDate date]);
    [super setNeedsDisplay:flag];
}



@end
