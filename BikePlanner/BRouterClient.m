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

@implementation NSURL (Additions)
// https://stackoverflow.com/questions/6309698/objective-c-how-to-add-query-parameter-to-nsurl
- (NSURL *)URLByAppendingQueryString:(NSString *)queryString {
    if (![queryString length]) {
        return self;
    }

    NSString *URLString = [[NSString alloc] initWithFormat:@"%@%@%@", [self absoluteString],
                           [self query] ? @"&" : @"?", queryString];
    NSURL *theURL = [NSURL URLWithString:URLString];
    //[URLString release];
    return theURL;
}

@end



@implementation BRouterClient

- (instancetype)initWithServerURL:(NSURL *)url {
    if (self = [super init]) {
        self.serverURL = url;
    }
    return self;
}


- (void)routeWithWaypoints:(NSArray <CLLocation *>*)waypoints
          profile:(NSString *)profile
         extraUrl:(NSString *)extraUrl
       completion:(void(^)(NSArray<CLLocation *> *points, NSData *gpx, NSError *error))completion
{
    // Build lonlats parameter. BRouter expects lon,lat pairs. 
    // Use pipe or semicolon separator depending on server.
    // We'll use the common format: lon,lat;lon,lat
    
    NSString *lonlats = @"";
    BOOL first = YES;
    for (CLLocation *loc in waypoints) {
        lonlats = [lonlats stringByAppendingFormat:@"%s%f,%f",
                   first ? "" : "|",
                   loc.coordinate.longitude,
                   loc.coordinate.latitude];
        first = NO;
    }
    // Request GPX output
    NSURLComponents *components = [NSURLComponents componentsWithURL:self.serverURL resolvingAgainstBaseURL:NO];
    components.path = @"/brouter";
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"lonlats" value:lonlats],
        [NSURLQueryItem queryItemWithName:@"profile" value:profile ?: @"fastbike"],
        [NSURLQueryItem queryItemWithName:@"alternativeidx" value:@"0"],
        [NSURLQueryItem queryItemWithName:@"format" value:@"gpx"] //,
        //[NSURLQueryItem queryItemWithName:extraUrl value:nil]
    ];
    NSURL *url = components.URL;
    if ([extraUrl length]) {
        url = [url URLByAppendingQueryString:extraUrl];
    }
    if (!url) {
        if (completion) completion(nil, nil, [NSError errorWithDomain:@"BRouterClient" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Invalid URL"}]);
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
            if (completion) completion(nil, nil, err);
            return;
        }
        if (!data) { if (completion) completion(nil, nil, [NSError errorWithDomain:@"BRouterClient" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"No data"}]); return; }

        // Parse GPX: look for <trkpt lat="..." lon="..."> tags. Simple parser using NSXMLParser would be more proper.
        // Here we'll do a quick string-based parse that's tolerant for this demo.
        /*
        NSString *gpx = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!gpx) { if (completion) completion(nil, [NSError errorWithDomain:@"BRouterClient" code:-3 userInfo:@{NSLocalizedDescriptionKey:@"Unable to decode GPX"}]); return; }

        NSMutableArray<CLLocation *> *points = [NSMutableArray array];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<trkpt[^>]*lat=\"([0-9.-]+)\"[^>]*lon=\"([0-9.-]+)\"" options:0 error:nil];
        [re enumerateMatchesInString:gpx options:0 range:NSMakeRange(0, gpx.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
            if (result.numberOfRanges >= 3) {
                NSString *latS = [gpx substringWithRange:[result rangeAtIndex:1]];
                NSString *lonS = [gpx substringWithRange:[result rangeAtIndex:2]];
                CLLocationDegrees lat = [latS doubleValue];
                CLLocationDegrees lon = [lonS doubleValue];
                CLLocation *loc = [[CLLocation alloc] initWithLatitude:lat longitude:lon];
                [points addObject:loc];
            }
         }];
         if (completion) completion([points copy], nil);
         */
        
        GPXParser *pgpx = [[GPXParser alloc]init];
        NSError *parseError = nil;
        NSArray<CLLocation *> *points = [pgpx parseGPXData:data error:&parseError];

        if (completion) completion(points, data, nil);

    }];
    [task resume];
}





@end

