//
//  BPPOIDescription.m
//  BikePlanner
//
//  What the POI callout shows (#72).
//

#import "BPPOIDescription.h"

typedef NS_ENUM(int, BPTagKind) {
    BPTagText,      // value shown as is
    BPTagYesNo,     // yes / no / limited translated, other values as is
    BPTagValue,     // an OSM value made readable: "archaeological_site" → "Archaeological site", "a;b" → "A, b" (#81)
    BPTagMeters,    // "1287" → "1287 m"
    BPTagWikipedia, // "fr:Title" → the article's URL (a link in the callout)
};

@implementation BPPOIDescription

// useful tags of the fetched POI types (drinking water, toilets, repair stations, cemeteries; sights, #81), in
// display order
+ (NSArray<NSArray *> *)knownTags
{
    static NSArray *tags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tags = @[
            // sights (#81)
            @[ @"historic",                    NSLocalizedString(@"Historic", @"POI tag"),       @(BPTagValue) ],
            @[ @"castle_type",                 NSLocalizedString(@"Castle type", @"POI tag"),    @(BPTagValue) ],
            @[ @"tourism",                     NSLocalizedString(@"Tourism", @"POI tag"),        @(BPTagValue) ],
            @[ @"natural",                     NSLocalizedString(@"Natural", @"POI tag"),        @(BPTagValue) ],
            @[ @"heritage",                    NSLocalizedString(@"Heritage", @"POI tag"),       @(BPTagText) ],
            @[ @"start_date",                  NSLocalizedString(@"Date", @"POI tag"),           @(BPTagText) ],
            @[ @"ele",                         NSLocalizedString(@"Elevation", @"POI tag"),      @(BPTagMeters) ],
            @[ @"cuisine",                     NSLocalizedString(@"Cuisine", @"POI tag"),        @(BPTagValue) ],
            @[ @"drinking_water",              NSLocalizedString(@"Drinking water", @"POI tag"), @(BPTagYesNo) ],
            @[ @"bottle",                      NSLocalizedString(@"Bottle refill", @"POI tag"),  @(BPTagYesNo) ],
            @[ @"fountain",                    NSLocalizedString(@"Fountain", @"POI tag"),       @(BPTagText) ],
            @[ @"seasonal",                    NSLocalizedString(@"Seasonal", @"POI tag"),       @(BPTagYesNo) ],
            @[ @"opening_hours",               NSLocalizedString(@"Opening hours", @"POI tag"),  @(BPTagText) ],
            @[ @"access",                      NSLocalizedString(@"Access", @"POI tag"),         @(BPTagText) ],
            @[ @"fee",                         NSLocalizedString(@"Fee", @"POI tag"),            @(BPTagYesNo) ],
            @[ @"charge",                      NSLocalizedString(@"Charge", @"POI tag"),         @(BPTagText) ],
            @[ @"toilets:disposal",            NSLocalizedString(@"Toilets", @"POI tag"),        @(BPTagText) ],
            @[ @"unisex",                      NSLocalizedString(@"Unisex", @"POI tag"),         @(BPTagYesNo) ],
            @[ @"wheelchair",                  NSLocalizedString(@"Wheelchair", @"POI tag"),     @(BPTagYesNo) ],
            @[ @"service:bicycle:pump",        NSLocalizedString(@"Pump", @"POI tag"),           @(BPTagYesNo) ],
            @[ @"valves",                      NSLocalizedString(@"Valves", @"POI tag"),         @(BPTagText) ],
            @[ @"service:bicycle:tools",       NSLocalizedString(@"Tools", @"POI tag"),          @(BPTagYesNo) ],
            @[ @"service:bicycle:chain_tool",  NSLocalizedString(@"Chain tool", @"POI tag"),     @(BPTagYesNo) ],
            @[ @"service:bicycle:stand",       NSLocalizedString(@"Repair stand", @"POI tag"),   @(BPTagYesNo) ],
            @[ @"covered",                     NSLocalizedString(@"Covered", @"POI tag"),        @(BPTagYesNo) ],
            @[ @"indoor",                      NSLocalizedString(@"Indoor", @"POI tag"),         @(BPTagYesNo) ],
            @[ @"religion",                    NSLocalizedString(@"Religion", @"POI tag"),       @(BPTagText) ],
            @[ @"denomination",                NSLocalizedString(@"Denomination", @"POI tag"),   @(BPTagText) ],
            @[ @"operator",                    NSLocalizedString(@"Operator", @"POI tag"),       @(BPTagText) ],
            @[ @"description",                 NSLocalizedString(@"Description", @"POI tag"),    @(BPTagText) ],
            @[ @"note",                        NSLocalizedString(@"Note", @"POI tag"),           @(BPTagText) ],
            @[ @"website",                     NSLocalizedString(@"Website", @"POI tag"),        @(BPTagText) ],
            @[ @"contact:website",             NSLocalizedString(@"Website", @"POI tag"),        @(BPTagText) ],
            @[ @"url",                         NSLocalizedString(@"Website", @"POI tag"),        @(BPTagText) ],
            @[ @"phone",                       NSLocalizedString(@"Phone", @"POI tag"),          @(BPTagText) ],
            @[ @"contact:phone",               NSLocalizedString(@"Phone", @"POI tag"),          @(BPTagText) ],
            @[ @"wikipedia",                   NSLocalizedString(@"Wikipedia", @"POI tag"),      @(BPTagWikipedia) ],
            @[ @"check_date",                  NSLocalizedString(@"Last checked", @"POI tag"),   @(BPTagText) ],
        ];
    });
    return tags;
}

+ (NSString *)displayValue:(NSString *)value kind:(BPTagKind)kind
{
    if (kind == BPTagYesNo) {
        if ([value isEqualToString:@"yes"])     return NSLocalizedString(@"yes", @"POI tag value");
        if ([value isEqualToString:@"no"])      return NSLocalizedString(@"no", @"POI tag value");
        if ([value isEqualToString:@"limited"]) return NSLocalizedString(@"limited", @"POI tag value");
    }
    if (kind == BPTagValue) {
        NSString *v = [[value stringByReplacingOccurrencesOfString:@"_" withString:@" "]
                       stringByReplacingOccurrencesOfString:@";" withString:@", "];
        return v.length ? [[v substringToIndex:1].uppercaseString stringByAppendingString:[v substringFromIndex:1]] : v;
    }
    if (kind == BPTagMeters) return [value stringByAppendingString:@" m"];
    if (kind == BPTagWikipedia) {
        NSRange colon = [value rangeOfString:@":"];
        NSString *lang = colon.location != NSNotFound && colon.location <= 3 ? [value substringToIndex:colon.location] : @"en";
        NSString *title = colon.location != NSNotFound && colon.location <= 3 ? [value substringFromIndex:NSMaxRange(colon)] : value;
        title = [[title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                 stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        NSString *encoded = [title stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
        return encoded ? [NSString stringWithFormat:@"https://%@.wikipedia.org/wiki/%@", lang, encoded] : value;
    }
    return value;
}

- (instancetype)initWithType:(PoiType_t)type info:(NSDictionary *)info custom:(BOOL)custom
{
    self = [super init];
    if (self) {
        _custom = custom;
        id n = info[@"name"];
        _name = ([n isKindOfClass:[NSString class]] && [n length]) ? n : nil;
        _typeName = [POILocation displayNameForType:type];
        NSMutableArray *rows = [NSMutableArray array];
        NSMutableArray *all = [NSMutableArray array];
        id osmid = info[@"id"];
        if (!custom) {
            for (NSArray *t in [[self class] knownTags]) {
                id v = info[t[0]];
                if (![v isKindOfClass:[NSString class]] || ![v length]) continue;
                [rows addObject:@[ t[1], [[self class] displayValue:v kind:[t[2] intValue]] ]];
            }
            for (NSString *k in [info.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                if ([k isEqualToString:@"id"] || [k isEqualToString:@"osmType"]) continue; // added by BikePlanner, not tags
                [all addObject:@[ k, [info[k] description] ]];
            }
            // the element type kept by the app (#81: sights are also ways and relations); before it, nodes with an
            // amenity and ways with landuse=cemetery
            if (osmid) {
                NSString *type = info[@"osmType"];
                NSString *element = [@[ @"node", @"way", @"relation" ] containsObject:type] ? type
                                  : (info[@"landuse"] && !info[@"amenity"]) ? @"way" : @"node";
                _osmURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.openstreetmap.org/%@/%@",
                                                element, osmid]];
            }
        }
        _rows = rows;
        _allTags = all;
    }
    return self;
}

+ (NSString *)positionStringForDistance:(double)alongMeters offset:(double)offsetMeters stage:(NSInteger)stage
{
    NSString *km = [NSString localizedStringWithFormat:NSLocalizedString(@"km %.1f", @"POI position along the route"),
                    alongMeters / 1000.0];
    if (stage >= 0) {
        km = [NSString localizedStringWithFormat:NSLocalizedString(@"%@ (stage %ld)", @"POI position: km, stage"),
              km, (long)stage + 1];
    }
    NSString *off;
    if (offsetMeters < 20) {
        off = NSLocalizedString(@"on the route", @"POI position");
    } else if (offsetMeters < 1000) {
        off = [NSString localizedStringWithFormat:NSLocalizedString(@"%.0f m off route", @"POI position"),
               round(offsetMeters / 10) * 10];
    } else {
        off = [NSString localizedStringWithFormat:NSLocalizedString(@"%.1f km off route", @"POI position"),
               offsetMeters / 1000.0];
    }
    return [NSString stringWithFormat:@"%@ · %@", km, off];
}

+ (nullable NSURL *)linkURLForValue:(NSString *)value
{
    NSString *v = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([v rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location != NSNotFound) return nil;
    NSString *lower = v.lowercaseString;
    if ([lower hasPrefix:@"www."]) v = [@"https://" stringByAppendingString:v];
    else if (![lower hasPrefix:@"http://"] && ![lower hasPrefix:@"https://"]) return nil;
    NSURL *url = [NSURL URLWithString:v];
    return url.host.length ? url : nil;
}

+ (NSString *)coordinateString:(CLLocationCoordinate2D)coord
{
    // not localized: a coordinate pasted elsewhere must use a decimal point
    return [NSString stringWithFormat:@"%.6f, %.6f", coord.latitude, coord.longitude];
}

@end
