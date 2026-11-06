//
//  BRouterClient.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>
#import "BRouterClient.h"
#import "BPEnvironment.h"
#import "GPXParser.h"
#import "BRouterGeoJSON.h"

@implementation BRouterClient {
    NSURLSession *_session; // one per client (was one per request, never invalidated, #9)
}

- (instancetype)initWithServerURL:(NSURL *)url {
    if (self = [super init]) {
        self.serverURL = url;
    }
    return self;
}

- (void)dealloc
{
    [_session finishTasksAndInvalidate];
}

// created at the first request (in tests, after the stub server is installed)
- (NSURLSession *)session
{
    if (!_session) _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]]; // avoid setting Accept-Encoding here
    return _session;
}

// BRouter answers errors as plain text (e.g. HTTP 400 "lonlats must contain at least 2 points"): first line, short
static NSError *BRouterError(NSInteger code, NSData *data, NSString *fallback)
{
    NSString *text = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding];
    text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]].firstObject
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (text.length > 200) text = [[text substringToIndex:200] stringByAppendingString:@"…"];
    if (!text.length || [text hasPrefix:@"<"]) text = fallback; // empty or an HTML error page
    return [NSError errorWithDomain:@"BRouterClient" code:code userInfo:@{ NSLocalizedDescriptionKey: text }];
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

- (nullable NSURLSessionDataTask *)routeWithWaypoints:(NSArray <CLLocation *>*)waypoints
          profile:(NSString *)profile
        overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides
       completion:(void(^)(NSArray<CLLocation *> * _Nullable points, NSData * _Nullable gpx, NSDictionary * _Nullable brouterInfo, NSError * _Nullable error))completion
{
    NSURL *url = [[self class] routeURLForServer:self.serverURL waypoints:waypoints profile:profile overrides:overrides];
    if (!url) {
        if (completion) completion(nil, nil, nil, [NSError errorWithDomain:@"BRouterClient" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Invalid URL"}]);
        return nil;
    }
    
    if ((0)) {
        NSString *urlString = @"https://brouter.de/brouter?lonlats=11.5754,48.1372|11.5650,48.1550&profile=trekking&alternativeidx=0&format=gpx";
        NSString *encodedString = [urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        url = [NSURL URLWithString:encodedString];
    }
    NSLog(@"URL: %@", url);
    // NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *task = [[self session] dataTaskWithRequest:[BPEnvironment requestWithURL:url] completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            if (completion) completion(nil, nil, nil, err);
            return;
        }
        if (!data) { if (completion) completion(nil, nil, nil, [NSError errorWithDomain:@"BRouterClient" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"No data"}]); return; }

        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 200;
        if (status < 200 || status > 299) {
            NSString *fallback = [NSString stringWithFormat:NSLocalizedString(@"HTTP error %ld", @"BRouter error"), (long)status];
            if (completion) completion(nil, nil, nil, BRouterError(status, data, fallback));
            return;
        }
        // GeoJSON (#53). Not a route (BRouter error text, no point): an error (#9)
        BRouterGeoJSON *route = [BRouterGeoJSON routeWithData:data error:NULL];
        if (!route || !route.points.count) {
            if (completion) completion(nil, nil, nil, BRouterError(-3, data, NSLocalizedString(@"No route found", @"BRouter error")));
            return;
        }
        NSMutableDictionary *bi = [route.info mutableCopy];
        bi[@"road-stats"] = route.roadStats;
        bi[@"surface-stats"] = route.surfaceStats;
        bi[@"road-runs"] = route.roadRuns;
        bi[@"surface-runs"] = route.surfaceRuns;
        // GPX for the export, with BRouter's statistics as comment (as in BRouter's own GPX)
        NSString *comment = [NSString stringWithFormat:@"track-length = %@ filtered ascend = %@ time=%@s (BRouter, %@)",
                             route.info[@"n-track-length-m"] ?: @"?", route.info[@"filtered-ascend"] ?: @"?",
                             route.info[@"n-time-seconds"] ?: @"?", profile];
        NSData *gpx = [GPXParser gpxDataForPoints:route.points name:[@"brouter_" stringByAppendingString:profile] comment:comment];
        if (completion) completion(route.points, gpx, bi, nil);

    }];
    [task resume];
    return task;
}





@end

