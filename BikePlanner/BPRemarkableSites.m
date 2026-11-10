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
        NSData *data = [self bundledPropertyListData];
        id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
        sites = [self sitesFromPropertyList:plist];
        if (!sites.count) NSLog(@"RemarkableSites.plist: no site");
    });
    return sites;
}

+ (nullable NSData *) bundledPropertyListData
{
    NSURL *url = [[NSBundle bundleForClass:self] URLForResource:@"RemarkableSites" withExtension:@"plist"];
    return url ? [NSData dataWithContentsOfURL:url] : nil;
}

+ (nullable NSString *) headerCommentOfPropertyListData:(NSData *)data
{
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSRange a = [s rangeOfString:@"<!--"];
    if (a.location == NSNotFound) return nil;
    NSRange b = [s rangeOfString:@"-->" options:0 range:NSMakeRange(NSMaxRange(a), s.length - NSMaxRange(a))];
    if (b.location == NSNotFound) return nil;
    return [s substringWithRange:NSMakeRange(NSMaxRange(a), b.location - NSMaxRange(a))];
}

// written by hand, not with NSPropertyListSerialization, to keep the layout of the file (keys in the order of the
// header comment, reals as typed: 44.1739, not 44.173900000000003) so that an export gives a readable diff
static NSString *BPPlistEscaped(NSString *s)
{
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    return [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
}

static NSString * _Nullable BPPlistValue(NSString *key, id value)
{
    if ([value isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"<string>%@</string>", BPPlistEscaped(value)];
    }
    if (![value isKindOfClass:[NSNumber class]]) return nil;
    NSNumber *n = value;
    if ([key isEqualToString:@"heading"] && n.doubleValue == floor(n.doubleValue)) {
        return [NSString stringWithFormat:@"<integer>%ld</integer>", (long)n.integerValue];
    }
    if ([key isEqualToString:@"latitude"] || [key isEqualToString:@"longitude"] || CFNumberIsFloatType((CFNumberRef)n)) {
        return [NSString stringWithFormat:@"<real>%.15g</real>", n.doubleValue];
    }
    return [NSString stringWithFormat:@"<integer>%lld</integer>", n.longLongValue];
}

+ (nullable NSData *) propertyListDataForEntries:(NSArray<NSDictionary *> *)entries headerComment:(nullable NSString *)comment
{
    NSArray *order = @[@"name", @"latitude", @"longitude", @"kind", @"heading"];
    NSMutableString *s = [NSMutableString stringWithString:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"];
    if (comment.length) [s appendFormat:@"<!--%@-->\n", comment];
    [s appendString:@"<plist version=\"1.0\">\n<array>\n"];
    for (NSDictionary *e in entries) {
        NSMutableArray *keys = [NSMutableArray array];
        for (NSString *k in order) if (e[k] != nil) [keys addObject:k];
        for (NSString *k in [e.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if (![order containsObject:k]) [keys addObject:k];
        }
        [s appendString:@"\t<dict>\n"];
        for (NSString *k in keys) {
            NSString *v = BPPlistValue(k, e[k]);
            if (!v) return nil;
            [s appendFormat:@"\t\t<key>%@</key>\n\t\t%@\n", BPPlistEscaped(k), v];
        }
        [s appendString:@"\t</dict>\n"];
    }
    [s appendString:@"</array>\n</plist>\n"];
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

+ (BOOL) isInMetropolitanFrance:(CLLocationCoordinate2D)c
{
    return c.latitude > 41.3 && c.latitude < 51.1 && c.longitude > -5.2 && c.longitude < 9.6;
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
