//
//  BRouterClient.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>
#import "BRouterClient.h"
#import "GPXParser.h"
#import "BRouterGeoJSON.h"

@implementation BRouterClient

- (instancetype)initWithServerURL:(NSURL *)url {
    if (self = [super init]) {
        self.serverURL = url;
    }
    return self;
}


// query value or name: percent-encode everything but the unreserved characters and ",:" (so "&", "=", "+", "|",
// spaces… can neither split the query nor make the URL invalid)
static NSString *BPQueryEncoded(NSString *s)
{
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~,:"];
    });
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

+ (nullable NSURL *)routeURLForServer:(NSURL *)server
                            waypoints:(NSArray <CLLocation *>*)waypoints
                              profile:(nullable NSString *)profile
                            overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides
{
    // BRouter expects lon,lat pairs separated by "|"
    NSString *lonlats = @"";
    BOOL first = YES;
    for (CLLocation *loc in waypoints) {
        lonlats = [lonlats stringByAppendingFormat:@"%s%f,%f",
                   first ? "" : "|",
                   loc.coordinate.longitude,
                   loc.coordinate.latitude];
        first = NO;
    }
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    void (^add)(NSString *, NSString *) = ^(NSString *name, NSString *value) {
        [items addObject:[NSURLQueryItem queryItemWithName:BPQueryEncoded(name) value:BPQueryEncoded(value)]];
    };
    add(@"lonlats", lonlats);
    add(@"profile", profile ?: @"fastbike");
    add(@"alternativeidx", @"0");
    add(@"format", @"geojson"); // way tags for the distance by road type (#53); the GPX for export is built from the points
    // profile parameter overrides: BRouter reads top-level "profile:<name>" parameters ("extraParams" is ignored);
    // booleans must be 1/0: "true"/"false" make brouter.de fail with HTTP 500 (#38)
    for (NSString *name in [overrides.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *value = overrides[name];
        if ([value caseInsensitiveCompare:@"true"] == NSOrderedSame) value = @"1";
        else if ([value caseInsensitiveCompare:@"false"] == NSOrderedSame) value = @"0";
        add([@"profile:" stringByAppendingString:name], value);
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:server resolvingAgainstBaseURL:NO];
    components.path = @"/brouter";
    components.percentEncodedQueryItems = items;
    return components.URL;
}

- (void)routeWithWaypoints:(NSArray <CLLocation *>*)waypoints
          profile:(NSString *)profile
        overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides
       completion:(void(^)(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *brouterInfo, NSError *error))completion
{
    NSURL *url = [[self class] routeURLForServer:self.serverURL waypoints:waypoints profile:profile overrides:overrides];
    if (!url) {
        if (completion) completion(nil, nil, nil, [NSError errorWithDomain:@"BRouterClient" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Invalid URL"}]);
        return;
    }
    
    if ((0)) {
        NSString *urlString = @"https://brouter.de/brouter?lonlats=11.5754,48.1372|11.5650,48.1550&profile=trekking&alternativeidx=0&format=gpx";
        NSString *encodedString = [urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        url = [NSURL URLWithString:encodedString];
    }
    NSLog(@"URL: %@", url);
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPAdditionalHeaders = @{ @"User-Agent" : @"BikePlaner/1.0" }; // avoid setting Accept-Encoding here
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    // NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            if (completion) completion(nil, nil, nil, err);
            return;
        }
        if (!data) { if (completion) completion(nil, nil, nil, [NSError errorWithDomain:@"BRouterClient" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"No data"}]); return; }

        
        
        // GeoJSON (#53). Not a route (BRouter error text): no points and no error, as before (#9)
        BRouterGeoJSON *route = [BRouterGeoJSON routeWithData:data error:NULL];
        if (!route) {
            if (completion) completion(@[], nil, nil, nil);
            return;
        }
        NSMutableDictionary *bi = [route.info mutableCopy];
        bi[@"road-stats"] = route.roadStats;
        bi[@"surface-stats"] = route.surfaceStats;
        // GPX for the export, with BRouter's statistics as comment (as in BRouter's own GPX)
        NSString *comment = [NSString stringWithFormat:@"track-length = %@ filtered ascend = %@ time=%@s (BRouter, %@)",
                             route.info[@"n-track-length-m"] ?: @"?", route.info[@"filtered-ascend"] ?: @"?",
                             route.info[@"n-time-seconds"] ?: @"?", profile];
        NSData *gpx = [GPXParser gpxDataForPoints:route.points name:[@"brouter_" stringByAppendingString:profile] comment:comment];
        if (completion) completion(route.points, gpx, bi, nil);

    }];
    [task resume];
}





@end

