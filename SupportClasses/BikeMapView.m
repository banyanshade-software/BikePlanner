//
//  BikeMapView.m
//  BikePlanner
//
//  Created by Daniel Braun on 17/08/2025.
//

#import "BikeMapView.h"

@implementation BikeMapView

- (nullable NSMenu *)menuForEvent:(NSEvent *)event
{
    NSMenu *menu = [self.menuProvider contextMenuForMapPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    return menu ?: [super menuForEvent:event];
}

/*- (NSView *)hitTest:(NSPoint)point
{
    NSView *hit = [super hitTest:point];
    if (hit == self) {
        return nil; // pass clicks through to underlying map buttons
    }
    return hit;
}
*/
@end
