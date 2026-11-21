//
//  RAChartView.m
//  RideAnalyzer
//

#import "RAChartView.h"

@implementation RAChartView
{
    NSArray<NSNumber *> *_values;
    NSArray<NSNumber *> *_distances;
    double _from, _to;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _title = @"";
        _color = [NSColor systemOrangeColor];
        _values = @[];
        _distances = @[];
        _cursorDistance = NAN;
        _minimum = NAN;
        _maximum = NAN;
    }
    return self;
}

- (BOOL)isFlipped
{
    return NO;
}

- (void)setValues:(NSArray<NSNumber *> *)values distances:(NSArray<NSNumber *> *)distances
{
    _values = [values copy];
    _distances = [distances copy];
    double lo = NAN, hi = NAN;
    for (NSNumber *v in values) {
        double d = v.doubleValue;
        if (isnan(d)) continue;
        lo = isnan(lo) ? d : MIN(lo, d);
        hi = isnan(hi) ? d : MAX(hi, d);
    }
    _minimum = lo;
    _maximum = hi;
    _from = 0;
    _to = distances.lastObject.doubleValue;
    [self setNeedsDisplay:YES];
}

- (void)setVisibleFrom:(double)from to:(double)to
{
    if (to <= from) return;
    _from = from;
    _to = to;
    [self setNeedsDisplay:YES];
}

- (void)setCursorDistance:(double)cursorDistance
{
    _cursorDistance = cursorDistance;
    [self setNeedsDisplay:YES];
}

- (NSRect)plotRect
{
    return NSMakeRect(44, 6, MAX(1, NSWidth(self.bounds) - 52), MAX(1, NSHeight(self.bounds) - 24));
}

- (double)xForDistance:(double)d
{
    NSRect r = [self plotRect];
    return NSMinX(r) + (d - _from) / MAX(_to - _from, 1) * NSWidth(r);
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSDictionary *labelAttrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize],
                                  NSForegroundColorAttributeName: [NSColor secondaryLabelColor] };
    [self.title drawAtPoint:NSMakePoint(4, NSHeight(self.bounds) - 15) withAttributes:labelAttrs];
    NSRect plot = [self plotRect];
    [[NSColor separatorColor] setStroke];
    NSBezierPath *frame = [NSBezierPath bezierPathWithRect:NSInsetRect(plot, -0.5, -0.5)];
    frame.lineWidth = 0.5;
    [frame stroke];
    if (isnan(_minimum) || _distances.count != _values.count) {
        NSString *none = NSLocalizedString(@"No data", @"chart");
        [none drawAtPoint:NSMakePoint(NSMidX(plot) - 20, NSMidY(plot) - 6) withAttributes:labelAttrs];
        return;
    }
    double lo = _minimum, hi = _maximum;
    if (hi - lo < 1e-9) { lo -= 1; hi += 1; }
    NSDictionary *small = @{ NSFontAttributeName: [NSFont systemFontOfSize:9],
                             NSForegroundColorAttributeName: [NSColor secondaryLabelColor] };
    [[NSString localizedStringWithFormat:@"%.0f", hi] drawAtPoint:NSMakePoint(4, NSMaxY(plot) - 10) withAttributes:small];
    [[NSString localizedStringWithFormat:@"%.0f", lo] drawAtPoint:NSMakePoint(4, NSMinY(plot)) withAttributes:small];

    [NSGraphicsContext saveGraphicsState];
    NSRectClip(plot);
    NSBezierPath *path = [NSBezierPath bezierPath];
    BOOL pen = NO;
    for (NSUInteger i = 0; i < _values.count; i++) {
        double v = _values[i].doubleValue;
        if (isnan(v)) { pen = NO; continue; }
        NSPoint p = NSMakePoint([self xForDistance:_distances[i].doubleValue],
                                NSMinY(plot) + (v - lo) / (hi - lo) * NSHeight(plot));
        if (pen) [path lineToPoint:p];
        else [path moveToPoint:p];
        pen = YES;
    }
    path.lineWidth = 1.4;
    path.lineJoinStyle = NSLineJoinStyleRound;
    if (self.dashed) {
        CGFloat dash[2] = { 5, 3 };
        [path setLineDash:dash count:2 phase:0];
    }
    [self.color setStroke];
    [path stroke];
    if (!isnan(_cursorDistance)) {
        CGFloat x = [self xForDistance:_cursorDistance];
        NSBezierPath *cursor = [NSBezierPath bezierPath];
        [cursor moveToPoint:NSMakePoint(x, NSMinY(plot))];
        [cursor lineToPoint:NSMakePoint(x, NSMaxY(plot))];
        CGFloat dash[2] = { 3, 3 };
        [cursor setLineDash:dash count:2 phase:0];
        [[NSColor controlAccentColor] setStroke];
        [cursor stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)selectAtPoint:(NSPoint)windowPoint
{
    NSRect plot = [self plotRect];
    NSPoint p = [self convertPoint:windowPoint fromView:nil];
    if (NSWidth(plot) <= 0 || _distances.count == 0) return;
    double d = _from + (p.x - NSMinX(plot)) / NSWidth(plot) * (_to - _from);
    d = MAX(_from, MIN(_to, d));
    self.cursorDistance = d;
    [self.delegate chartView:self didSelectDistance:d];
}

- (void)mouseDown:(NSEvent *)event
{
    [self selectAtPoint:event.locationInWindow];
}

- (void)mouseDragged:(NSEvent *)event
{
    [self selectAtPoint:event.locationInWindow];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityImageRole;
}

- (nullable NSString *)accessibilityLabel
{
    if (isnan(_minimum)) return self.title;
    return [NSString localizedStringWithFormat:NSLocalizedString(@"%@, from %.0f to %.0f", @"chart accessibility"),
            self.title, _minimum, _maximum];
}

@end
