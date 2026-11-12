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
};

@implementation BPPOIDescription

// useful tags of the fetched POI types (drinking water, toilets, repair stations, cemeteries), in display order
+ (NSArray<NSArray *> *)knownTags
{
    static NSArray *tags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tags = @[
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
                if ([k isEqualToString:@"id"]) continue; // added by BikePlanner, not a tag
                [all addObject:@[ k, [info[k] description] ]];
            }
            // the Overpass query fetches nodes with an amenity and ways with landuse=cemetery (BikePlan)
            if (osmid) {
                NSString *element = (info[@"landuse"] && !info[@"amenity"]) ? @"way" : @"node";
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

+ (NSString *)coordinateString:(CLLocationCoordinate2D)coord
{
    // not localized: a coordinate pasted elsewhere must use a decimal point
    return [NSString stringWithFormat:@"%.6f, %.6f", coord.latitude, coord.longitude];
}

@end
