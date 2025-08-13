//
//  ElevationProfileView.m
//  BikePlanner
//
//  Created by Daniel on 13/08/2025.
//

#import "ElevationProfileView.h"

@implementation ElevationProfileView

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
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    if (self.distances.count == 0) return;

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    double maxElev = [[self.elevations valueForKeyPath:@"@max.doubleValue"] doubleValue];
    double minElev = [[self.elevations valueForKeyPath:@"@min.doubleValue"] doubleValue];
    double maxDist = [[self.distances lastObject] doubleValue];

    // Margins
    CGFloat leftMargin = 40, bottomMargin = 30;
    CGRect plotRect = NSInsetRect(self.bounds, leftMargin, bottomMargin);

    // Draw axes
    [[NSColor blackColor] setStroke];
    CGContextSetLineWidth(ctx, 1.0);
    CGContextMoveToPoint(ctx, plotRect.origin.x, plotRect.origin.y);
    CGContextAddLineToPoint(ctx, plotRect.origin.x, plotRect.origin.y + plotRect.size.height);
    CGContextAddLineToPoint(ctx, plotRect.origin.x + plotRect.size.width, plotRect.origin.y + plotRect.size.height);
    CGContextStrokePath(ctx);

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
            [[NSColor redColor] setStroke];
        } else if (slope < -0.05) { // < -5% downhill
            [[NSColor blueColor] setStroke];
        } else {
            [[NSColor greenColor] setStroke];
        }

        CGContextSetLineWidth(ctx, 2.0);
        CGContextMoveToPoint(ctx, x1, y1);
        CGContextAddLineToPoint(ctx, x2, y2);
        CGContextStrokePath(ctx);
    }
}




@end
