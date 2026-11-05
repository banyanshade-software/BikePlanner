//
//  SafeOSMTileOverlay.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "SafeOSMTileOverlay.h"
#import "BPEnvironment.h"

@implementation SafeOSMTileOverlay

// tiles are fetched here rather than by MapKit, to send the app's User-Agent (OSM tile usage policy); the
// NSURLSession cache honors the servers' caching headers
- (void)loadTileAtPath:(MKTileOverlayPath)path result:(void (^)(NSData * _Nullable tileData, NSError * _Nullable error))result
{
    NSURL *url = [self URLForTilePath:path];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:[BPEnvironment requestWithURL:url]
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 200;
        if (!error && status != 200) {
            error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse
                                    userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)status] }];
        }
        result(error ? nil : data, error);
    }];
    [task resume];
}
#if 0
- (instancetype)initWithURLTemplate:(NSString *)URLTemplate {
    if (self = [super initWithURLTemplate:URLTemplate]) {
        // Force standard tile size and zoom range that match OSM tile server expectations
        self.tileSize = CGSizeMake(256, 256);
        self.maximumZ = 19;
        self.minimumZ = 0;
        // Mark that we will provide tile data ourselves
        self.canReplaceMapContent = NO;
    }
    return self;
}

// Important: override to fetch tile bytes ourselves and pass them back as NSData.
// Returning NSData avoids MapKit doing its own remote fetch path.
- (void)loadTileAtPath:(MKTileOverlayPath)path result:(void (^)(NSData *tileData, NSError *error))result {
    NSString *urlStr = [self.URLTemplate stringByReplacingOccurrencesOfString:@"{z}" withString:[NSString stringWithFormat:@"%ld", (long)path.z]];
    urlStr = [urlStr stringByReplacingOccurrencesOfString:@"{x}" withString:[NSString stringWithFormat:@"%ld", (long)path.x]];
    urlStr = [urlStr stringByReplacingOccurrencesOfString:@"{y}" withString:[NSString stringWithFormat:@"%ld", (long)path.y]];
    NSURL *url = [NSURL URLWithString:urlStr];

    if (!url) {
        if (result) result(nil, [NSError errorWithDomain:@"SafeOSM" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid tile URL"}]);
        return;
    }

    // Try memory cache first (very small in-memory cache)
    static NSCache *tileCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tileCache = [NSCache new];
    });
    NSString *cacheKey = [NSString stringWithFormat:@"%ld/%ld/%ld", (long)path.z, (long)path.x, (long)path.y];
    NSData *cached = [tileCache objectForKey:cacheKey];
    if (cached) {
        if (result) result(cached, nil);
        return;
    }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (data) [tileCache setObject:data forKey:cacheKey];
        if (result) result(data, error);
    }];
    [task resume];
}
#endif

@end
