//
//  BPRemarkableSites.m
//  BikePlanner
//

#import "BPRemarkableSites.h"
#import "BPEnvironment.h"

@interface BPRemarkableSite ()
@property (readwrite) NSString *name;
@property (readwrite) CLLocationCoordinate2D coordinate;
@property (readwrite) BPSiteKind kind;
@property (readwrite) double heading;
@end

@implementation BPRemarkableSite

- (NSString *) displayText
{
    NSString *kind = nil;
    switch (self.kind) {
        case BPSiteKindClimb:    kind = NSLocalizedString(@"famous climb", @"remarkable site kind"); break;
        case BPSiteKindMonument: kind = NSLocalizedString(@"monument", @"remarkable site kind"); break;
        case BPSiteKindNature:   kind = NSLocalizedString(@"natural site", @"remarkable site kind"); break;
    }
    return [NSString stringWithFormat:@"%@ — %@", self.name, kind];
}

@end

@implementation BPRemarkableSites

// RemarkableSites.plist (resource): array of { name, latitude, longitude, kind ("climb", "monument", "nature"),
// heading (degrees, 0 = north, optional) }; invalid entries are skipped
+ (NSArray<BPRemarkableSite *> *) sitesFromPropertyList:(id)plist
{
    NSDictionary<NSString *, NSNumber *> *kinds = @{ @"climb": @(BPSiteKindClimb), @"monument": @(BPSiteKindMonument),
                                                     @"nature": @(BPSiteKindNature) };
    NSMutableArray<BPRemarkableSite *> *a = [NSMutableArray array];
    if (![plist isKindOfClass:[NSArray class]]) return a;
    for (NSDictionary *d in plist) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = d[@"name"];
        NSNumber *lat = d[@"latitude"], *lon = d[@"longitude"], *heading = d[@"heading"];
        NSNumber *kind = [d[@"kind"] isKindOfClass:[NSString class]] ? kinds[d[@"kind"]] : nil;
        if (![name isKindOfClass:[NSString class]] || !name.length || ![lat isKindOfClass:[NSNumber class]]
            || ![lon isKindOfClass:[NSNumber class]] || kind == nil) continue;
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat.doubleValue, lon.doubleValue);
        if (!CLLocationCoordinate2DIsValid(c)) continue;
        BPRemarkableSite *s = [[BPRemarkableSite alloc] init];
        s.name = name;
        s.coordinate = c;
        s.kind = kind.integerValue;
        s.heading = [heading isKindOfClass:[NSNumber class]] ? heading.doubleValue : 0;
        [a addObject:s];
    }
    return a;
}

+ (NSArray<BPRemarkableSite *> *) sites
{
    static NSArray<BPRemarkableSite *> *sites;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [[NSBundle bundleForClass:self] URLForResource:@"RemarkableSites" withExtension:@"plist"];
        NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
        id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
        sites = [self sitesFromPropertyList:plist];
        if (!sites.count) NSLog(@"RemarkableSites.plist: no site");
    });
    return sites;
}

+ (nullable BPRemarkableSite *) randomSite
{
    NSArray<BPRemarkableSite *> *sites = [self sites];
    if (!sites.count) return nil;
    NSInteger forced = [BPEnvironment remarkableSiteIndex];
    if (forced >= 0 && forced < (NSInteger)sites.count) return sites[forced];
    return sites[arc4random_uniform((uint32_t)sites.count)];
}

@end
