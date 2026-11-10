//
//  PreviewProvider.m
//  BikePlannerQuickLook
//

#import "PreviewProvider.h"
#import "BPRoutePreview.h"

static const NSSize kPreviewSize = { 680, 480 };
static const NSTimeInterval kMapTimeout = 8;    // s; then the route on a plain background

@implementation PreviewProvider

- (void)providePreviewForFileRequest:(QLFilePreviewRequest *)request
                   completionHandler:(void (^)(QLPreviewReply * _Nullable reply, NSError * _Nullable error))handler
{
    NSError *error = nil;
    BPRoutePreview *preview = [BPRoutePreview previewOfFileAtURL:request.fileURL error:&error];
    if (!preview) {
        handler(nil, error);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [preview takeMapSnapshotForSize:kPreviewSize timeout:kMapTimeout completion:^(NSImage *mapImage) {
            QLPreviewReply *reply = [[QLPreviewReply alloc] initWithContextSize:kPreviewSize isBitmap:YES
                                                                   drawingBlock:^BOOL(CGContextRef context, QLPreviewReply *r, NSError **err) {
                [NSGraphicsContext saveGraphicsState];
                NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
                [preview drawInRect:NSMakeRect(0, 0, kPreviewSize.width, kPreviewSize.height) mapImage:mapImage];
                [NSGraphicsContext restoreGraphicsState];
                return YES;
            }];
            reply.title = preview.name;
            handler(reply, nil);
        }];
    });
}

@end
