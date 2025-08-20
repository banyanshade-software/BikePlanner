//
//  POIAnnotationView.m
//  BikePlanner
//
//  Created by Daniel Braun on 20/08/2025.
//

#import "POIAnnotationView.h"

@implementation POIAnnotationView


/*
- (BOOL)pointInside:(NSPoint)point withEvent:(NSEvent *)event {
    // Enlarge the hit area around the annotation
    CGRect bounds = self.bounds;
    CGFloat padding = 10.0; // extra clickable margin around pin
    CGRect hitRect = NSInsetRect(bounds, -padding, -padding);
    return NSPointInRect(point, hitRect);
}

- (NSView *)hitTest:(NSPoint)point
{
    // pass-through events that don't hit one of the visible subviews
    CGRect bounds = self.bounds;
    CGFloat padding = 10.0; // extra clickable margin around pin
    CGRect hitRect = NSInsetRect(bounds, -padding, -padding);
    if (NSPointInRect(point, hitRect)) return self;
    return nil;
}
 */
@end
