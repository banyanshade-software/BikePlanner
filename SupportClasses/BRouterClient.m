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
    add(@"format", @"gpx");
    // profile parameter overrides: BRouter reads top-level "profile:<name>" parameters ("extraParams" is ignored)
    for (NSString *name in [overrides.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        add([@"profile:" stringByAppendingString:name], overrides[name]);
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

        
        
        GPXParser *pgpx = [[GPXParser alloc]init];
        NSError *parseError = nil;
        NSArray<CLLocation *> *points = [pgpx parseGPXData:data error:&parseError];

        if (completion) {
            NSDictionary *bi = [pgpx brouterInfo];
            completion(points, data, bi, nil);
        }

    }];
    [task resume];
}





@end

