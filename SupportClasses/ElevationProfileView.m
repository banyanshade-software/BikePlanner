//
//  ElevationProfileView.m
//  BikePlanner
//
//  Created by Daniel on 13/08/2025.
//

#import "ElevationProfileView.h"

static const double kMinElevationRange = 100; // m: small differences must not look steep (#32)

@implementation ElevationProfileView {
    double _maxDist;
    double _minElev, _maxElev;
    CGRect _plotRect;
}
- (void)updateMetrics {
    _maxDist = [[self.distances lastObject] doubleValue];
    _maxElev = [[self.elevations valueForKeyPath:@"@max.doubleValue"] doubleValue];
    _minElev = [[self.elevations valueForKeyPath:@"@min.doubleValue"] doubleValue];
    _plotRect = NSInsetRect(self.bounds, 40, 30);
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
    [self setNeedsDisplay:YES];
    //[self setNeedsLayout:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    //NSLog(@"[%@] drawRect called", [NSDate date]);
    [super drawRect:dirtyRect];
    [self updateMetrics];

    if (self.distances.count == 0) return;

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    double maxElev, minElev; // displayed range, not the data range (#32)
    [[self class] elevationRangeForMin:_minElev max:_maxElev low:&minElev high:&maxElev];
    double maxDist = [[self.distances lastObject] doubleValue];

    // Margins
    CGFloat leftMargin = 40, bottomMargin = 30;
    CGRect plotRect = NSInsetRect(self.bounds, leftMargin, bottomMargin);

    // Scale: altitude grid + labels (m) on the left, distance labels (km) at the bottom
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
        for (NSNumber *t in [[self class] ticksFrom:0 to:maxDist / 1000 maxCount:6]) {
            CGFloat x = plotRect.origin.x + (t.doubleValue * 1000 / maxDist) * plotRect.size.width;
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

    // Draw profile
    for (NSUInteger i = 1; i < self.distances.count; i++) {
        double d1 = [self.distances[i - 1] doubleValue];
        double e1 = [self.elevations[i - 1] doubleValue];
        double d2 = [self.distances[i] doubleValue];
        double e2 = [self.elevations[i] doubleValue];
        double slope = [self.slopes[i] doubleValue]; // m/m

        // Map to view coords
        CGFloat x1 = plotRect.origin.x + (d1 / maxDist) * plotRect.size.width;
        CGFloat y1 = plotRect.origin.y + ((e1 - minElev) / (maxElev - minElev)) * plotRect.size.height;
        CGFloat x2 = plotRect.origin.x + (d2 / maxDist) * plotRect.size.width;
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
    
    // Draw highlight line
     if (_highlightDistance > 0 && _highlightDistance <= _maxDist) {
         CGFloat hx = _plotRect.origin.x + (_highlightDistance / _maxDist) * _plotRect.size.width;
         [[NSColor labelColor] setStroke];
         CGContextSetLineWidth(ctx, 1.0);
         CGContextMoveToPoint(ctx, hx, _plotRect.origin.y);
         CGContextAddLineToPoint(ctx, hx, _plotRect.origin.y + _plotRect.size.height);
         CGFloat dash[] = {4.0, 2.0};
         CGContextSetLineDash(ctx, 0, dash, 2);
         CGContextStrokePath(ctx);
         CGContextSetLineDash(ctx, 0, NULL, 0);
     }
}



- (void)mouseDown:(NSEvent *)event {
    [self handleMouse:event];
}

- (void)mouseDragged:(NSEvent *)event {
    [self handleMouse:event];
}

- (void)handleMouse:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, _plotRect)) {
        double dist = ((p.x - _plotRect.origin.x) / _plotRect.size.width) * _maxDist;
        [self setHighlightDistance:dist animated:YES];
        if ([self.delegate respondsToSelector:@selector(elevationProfileView:didSelectDistance:)]) {
            [self.delegate elevationProfileView:self didSelectDistance:dist];
        }
        
    }
}



- (void)setHighlightDistance:(double)highlightDistance animated:(BOOL)animated {
    _highlightDistance =  highlightDistance; //fmax(0, fmin(_highlightDistance, [[self.distances lastObject] doubleValue]));
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
