//
//  RATimeChartView.m
//  RideAnalyzer
//

#import "RATimeChartView.h"
#import "RATrends.h"

@implementation RATimeChartView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _points = @[];
        _color = [NSColor systemBlueColor];
        _emptyMessage = @"";
        _barLabelFormat = @"MMM";
    }
    return self;
}

- (void)setPoints:(NSArray<RATrendPoint *> *)points
{
    _points = [points copy];
    _selectedPoint = nil;
    [self computeRange];
    [self setNeedsDisplay:YES];
}

- (void)setTrendLine:(nullable NSArray<NSNumber *> *)trendLine
{
    _trendLine = [trendLine copy];
    [self setNeedsDisplay:YES];
}

- (void)setStyle:(RATimeChartStyle)style
{
    _style = style;
    [self computeRange];
    [self setNeedsDisplay:YES];
}

- (void)computeRange
{
    double lo = INFINITY, hi = -INFINITY;
    for (RATrendPoint *p in _points) {
        lo = MIN(lo, p.value);
        hi = MAX(hi, p.value);
    }
    if (_points.count == 0) { lo = 0; hi = 1; }
    if (self.style == RATimeChartBars) lo = 0;
    else {
        double pad = (hi - lo) * 0.1;
        if (pad <= 0) pad = MAX(fabs(hi) * 0.1, 1);
        lo -= pad;
        hi += pad;
    }
    if (hi <= lo) hi = lo + 1;
    _lowValue = lo;
    _highValue = hi;
}

- (NSRect)plotRect
{
    return NSMakeRect(48, 22, MAX(1, NSWidth(self.bounds) - 58), MAX(1, NSHeight(self.bounds) - 34));
}

- (CGFloat)xOfIndex:(NSUInteger)i
{
    NSRect plot = [self plotRect];
    if (self.style == RATimeChartBars) {
        CGFloat w = NSWidth(plot) / MAX(_points.count, (NSUInteger)1);
        return NSMinX(plot) + w * (i + 0.5);
    }
    NSTimeInterval t0 = _points.firstObject.date.timeIntervalSinceReferenceDate;
    NSTimeInterval t1 = _points.lastObject.date.timeIntervalSinceReferenceDate;
    if (t1 <= t0) return NSMidX(plot);
    return NSMinX(plot) + (_points[i].date.timeIntervalSinceReferenceDate - t0) / (t1 - t0) * NSWidth(plot);
}

- (CGFloat)yOfValue:(double)v
{
    NSRect plot = [self plotRect];
    return NSMinY(plot) + (v - _lowValue) / (_highValue - _lowValue) * NSHeight(plot);
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSDictionary *small = @{ NSFontAttributeName: [NSFont systemFontOfSize:10],
                             NSForegroundColorAttributeName: [NSColor secondaryLabelColor] };
    NSRect plot = [self plotRect];
    if (_points.count == 0) {
        NSSize size = [self.emptyMessage sizeWithAttributes:small];
        [self.emptyMessage drawAtPoint:NSMakePoint(NSMidX(plot) - size.width / 2, NSMidY(plot)) withAttributes:small];
        return;
    }
    // horizontal grid and values
    [[NSColor separatorColor] setStroke];
    for (int k = 0; k <= 4; k++) {
        double v = _lowValue + (_highValue - _lowValue) * k / 4;
        CGFloat y = [self yOfValue:v];
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(NSMinX(plot), y)];
        [line lineToPoint:NSMakePoint(NSMaxX(plot), y)];
        line.lineWidth = 0.5;
        [line stroke];
        NSString *label = fabs(_highValue - _lowValue) < 10 ? [NSString localizedStringWithFormat:@"%.2f", v]
                                                             : [NSString localizedStringWithFormat:@"%.0f", v];
        NSSize size = [label sizeWithAttributes:small];
        [label drawAtPoint:NSMakePoint(NSMinX(plot) - size.width - 4, y - size.height / 2) withAttributes:small];
    }
    // dates
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    if (self.style == RATimeChartBars) {
        f.dateFormat = self.barLabelFormat;
        NSUInteger step = MAX((NSUInteger)1, (_points.count + 11) / 12);
        for (NSUInteger i = 0; i < _points.count; i += step) {
            NSString *label = [f stringFromDate:_points[i].date];
            NSSize size = [label sizeWithAttributes:small];
            [label drawAtPoint:NSMakePoint([self xOfIndex:i] - size.width / 2, 4) withAttributes:small];
        }
    } else {
        f.dateStyle = NSDateFormatterShortStyle;
        NSUInteger n = _points.count;
        for (NSUInteger k = 0; k < MIN(n, (NSUInteger)5); k++) {
            NSUInteger i = n == 1 ? 0 : k * (n - 1) / MAX(MIN(n, (NSUInteger)5) - 1, (NSUInteger)1);
            NSString *label = [f stringFromDate:_points[i].date];
            NSSize size = [label sizeWithAttributes:small];
            CGFloat x = MIN(MAX([self xOfIndex:i] - size.width / 2, NSMinX(plot)), NSMaxX(plot) - size.width);
            [label drawAtPoint:NSMakePoint(x, 4) withAttributes:small];
        }
    }

    if (self.style == RATimeChartBars) {
        CGFloat w = NSWidth(plot) / _points.count;
        for (NSUInteger i = 0; i < _points.count; i++) {
            CGFloat h = [self yOfValue:_points[i].value] - NSMinY(plot);
            NSRect bar = NSMakeRect([self xOfIndex:i] - w * 0.35, NSMinY(plot), w * 0.7, MAX(0, h));
            [(_points[i] == _selectedPoint ? self.color : [self.color colorWithAlphaComponent:0.55]) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:2 yRadius:2] fill];
        }
    } else {
        for (NSUInteger i = 0; i < _points.count; i++) {
            NSPoint c = NSMakePoint([self xOfIndex:i], [self yOfValue:_points[i].value]);
            CGFloat r = _points[i] == _selectedPoint ? 5 : 3.5;
            [[self.color colorWithAlphaComponent:_points[i] == _selectedPoint ? 1 : 0.6] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - r, c.y - r, 2 * r, 2 * r)] fill];
        }
        if (self.trendLine.count == 2) {
            NSBezierPath *trend = [NSBezierPath bezierPath];
            [trend moveToPoint:NSMakePoint([self xOfIndex:0], [self yOfValue:self.trendLine[0].doubleValue])];
            [trend lineToPoint:NSMakePoint([self xOfIndex:_points.count - 1], [self yOfValue:self.trendLine[1].doubleValue])];
            trend.lineWidth = 2;
            [[NSColor systemOrangeColor] setStroke];
            [trend stroke];
        }
    }
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    RATrendPoint *best = nil;
    CGFloat bestDistance = 20;
    for (NSUInteger i = 0; i < _points.count; i++) {
        CGFloat dx = fabs([self xOfIndex:i] - p.x);
        CGFloat dy = self.style == RATimeChartBars ? 0 : fabs([self yOfValue:_points[i].value] - p.y);
        CGFloat d = self.style == RATimeChartBars ? dx : hypot(dx, dy);
        if (d < bestDistance) { best = _points[i]; bestDistance = d; }
    }
    _selectedPoint = best;
    [self setNeedsDisplay:YES];
    [self.delegate timeChartView:self didSelectPoint:best];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityImageRole;
}

@end
