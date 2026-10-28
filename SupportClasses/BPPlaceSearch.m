//
//  BPPlaceSearch.m
//  BikePlanner
//

#import "BPPlaceSearch.h"

static BPPlaceSearchHandler testHandler;

@implementation BPPlaceSearch

+ (void)setSearchHandlerForTesting:(nullable BPPlaceSearchHandler)handler
{
    testHandler = [handler copy];
}

+ (void)search:(NSString *)query near:(MKCoordinateRegion)region completion:(BPPlaceSearchCompletion)completion
{
    void (^done)(NSArray<MKMapItem *> *, NSError *) = ^(NSArray<MKMapItem *> *items, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(items ?: @[], error); });
    };
    if (testHandler) {
        testHandler(query, region, done);
        return;
    }
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;
    request.region = region; // results near the current map first
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse * _Nullable response, NSError * _Nullable error) {
        // "no result" is reported by MapKit as an error: give an empty list instead
        if (error && [error.domain isEqualToString:MKErrorDomain] && error.code == MKErrorPlacemarkNotFound) error = nil;
        done(response.mapItems, error);
    }];
}

+ (NSString *)subtitleForItem:(MKMapItem *)item
{
    MKPlacemark *p = item.placemark;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *s in @[ p.thoroughfare ?: @"", p.locality ?: @"", p.administrativeArea ?: @"", p.country ?: @"" ]) {
        if (s.length && ![parts containsObject:s] && ![s isEqualToString:item.name]) [parts addObject:s];
    }
    return [parts componentsJoinedByString:@", "];
}

+ (NSString *)titleForItem:(MKMapItem *)item
{
    NSString *name = item.name ?: @"?";
    NSString *sub = [self subtitleForItem:item];
    return sub.length ? [NSString stringWithFormat:@"%@ — %@", name, sub] : name;
}

+ (MKCoordinateRegion)regionForItem:(MKMapItem *)item
{
    MKPlacemark *p = item.placemark;
    CLLocationDistance d = (p.thoroughfare.length || p.subThoroughfare.length) ? 2000 : 20000;
    return MKCoordinateRegionMakeWithDistance(p.coordinate, d, d);
}

@end
