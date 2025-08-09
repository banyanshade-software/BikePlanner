//
//  SafeTileRenderer.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "SafeTileRenderer.h"

@implementation SafeTileRenderer


#if 0
// Helper to decode NSData into a CGImageRef (thread-safe with CGImageSource)
- (CGImageRef)cgImageFromData:(NSData *)data {
    if (!data) return NULL;
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return NULL;
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    return img; // retain returned CGImageRef, caller must release
}

- (void)drawMapRect:(MKMapRect)mapRect zoomScale:(MKZoomScale)zoomScale inContext:(CGContextRef)context {
    // Calculate scale and visible tiles; draw each tile directly into Quartz context
    MKTileOverlay *ovlay = (MKTileOverlay *) self.overlay;
    if (![ovlay isKindOfClass:[MKTileOverlay class]]) {
        return;
    }
    double scale = zoomScale / (MKZoomScale)(1.0); // zoomScale already gives pixels per map point
    CGSize tileSize = ovlay.tileSize; // 256x256
    MKMapRect world = MKMapRectWorld;
    // Convert mapRect to tile coordinates (z is not directly available here, derive approximate zoom level)
    // We'll compute z from zoomScale: approximate formula:
    double zf = MAX(0.0, round(log2(zoomScale))); // not exact but acceptable for picking tiles
    NSInteger z = (NSInteger)zf;
    if (z < ovlay.minimumZ) z = ovlay.minimumZ;
    if (z > ovlay.maximumZ) z = ovlay.maximumZ;

    // Determine tile x/y ranges that intersect mapRect
    double tilesPerSide = pow(2.0, z);
    double mapSize = MKMapSizeWorld.width; // world map width in map points
    double tileMapWidth = mapSize / tilesPerSide;

    NSInteger x0 = floor((mapRect.origin.x) / tileMapWidth);
    NSInteger x1 = floor((mapRect.origin.x + mapRect.size.width) / tileMapWidth);
    NSInteger y0 = floor((mapRect.origin.y) / tileMapWidth);
    NSInteger y1 = floor((mapRect.origin.y + mapRect.size.height) / tileMapWidth);

    for (NSInteger tx = x0; tx <= x1; tx++) {
        for (NSInteger ty = y0; ty <= y1; ty++) {
            // Build an MKTileOverlayPath and ask the overlay to load tile data (we implemented loadTileAtPath)
            MKTileOverlayPath path;
            path.x = tx;
            path.y = ty;
            path.z = z;
            path.contentScaleFactor = [NSScreen mainScreen].backingScaleFactor ?: 1.0;

            // Synchronously get tile data using a semaphore (we keep it small and on background thread)
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            __block NSData *tileData = nil;
            __block NSError *err = nil;

            // Call overlay's loadTileAtPath:result: (it does an async URL fetch)
            [((MKTileOverlay *)self.overlay) loadTileAtPath:path result:^(NSData *tileDataReturned, NSError *error) {
                tileData = tileDataReturned;
                err = error;
                dispatch_semaphore_signal(sem);
            }];

            // Wait but don't block main thread long — use short timeout
            dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)); // 1s
            if (dispatch_semaphore_wait(sem, deadline) != 0) {
                // timeout: skip this tile
                continue;
            }
            if (!tileData || err) continue;

            CGImageRef img = [self cgImageFromData:tileData];
            if (!img) continue;

            // Calculate destination rect in context coordinates
            MKMapRect tileMapRect = MKMapRectMake(tx * tileMapWidth, ty * tileMapWidth, tileMapWidth, tileMapWidth);
            CGRect tileRect = [self rectForMapRect:tileMapRect]; // returns rect in view/cg coordinates

            CGContextSaveGState(context);
            // Flip vertically for CG coordinate space
            CGContextTranslateCTM(context, 0, tileRect.origin.y * 2 + tileRect.size.height);
            CGContextScaleCTM(context, 1.0, -1.0);

            // Draw CGImage directly into context (this avoids MapKit's internal texture view path)
            CGContextDrawImage(context, tileRect, img);

            CGContextRestoreGState(context);
            CGImageRelease(img);
        }
    }
}
#endif

/*
- (void)drawMapRect:(MKMapRect)mapRect
         zoomScale:(MKZoomScale)zoomScale
         inContext:(CGContextRef)context {
    @autoreleasepool {
        [super drawMapRect:mapRect zoomScale:zoomScale inContext:context];
    }
}
 */
@end
