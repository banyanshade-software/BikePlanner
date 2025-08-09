//
//  SafeTileRenderer.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "SafeTileRenderer.h"

@implementation SafeTileRenderer
- (void)drawMapRect:(MKMapRect)mapRect
         zoomScale:(MKZoomScale)zoomScale
         inContext:(CGContextRef)context {
    @autoreleasepool {
        [super drawMapRect:mapRect zoomScale:zoomScale inContext:context];
    }
}
@end
