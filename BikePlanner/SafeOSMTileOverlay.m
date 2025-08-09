//
//  SafeOSMTileOverlay.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "SafeOSMTileOverlay.h"

@implementation SafeOSMTileOverlay

- (void)loadTileAtPath:(MKTileOverlayPath)path
         result:(void (^)(NSData *tileData, NSError *error))result
{
    NSString *urlStr = [NSString stringWithFormat:
        @"https://tile.openstreetmap.org/%ld/%ld/%ld.png",
        (long)path.z, (long)path.x, (long)path.y];
    NSURL *url = [NSURL URLWithString:urlStr];
    [[[NSURLSession sharedSession] dataTaskWithURL:url
                                 completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (result) result(data, err);
    }] resume];
}

@end
