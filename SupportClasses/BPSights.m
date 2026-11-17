//
//  BPSights.m
//  BikePlanner
//
//  Sights near the route (#81).
//

#import "BPSights.h"

@implementation BPSights

// category → OSM key → values (war memorials, historic=memorial, are left out: one in every village)
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSArray<NSString *> *> *> *)tags
{
    static NSDictionary *tags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tags = @{
            @"culture": @{ @"tourism": @[ @"museum", @"attraction" ],
                           @"historic": @[ @"castle", @"ruins", @"archaeological_site", @"monument", @"fort", @"manor" ] },
            @"viewpoint": @{ @"tourism": @[ @"viewpoint" ] },
            @"church": @{ @"amenity": @[ @"place_of_worship" ] },
            @"nature": @{ @"natural": @[ @"waterfall", @"peak", @"cave_entrance" ] },
            @"food": @{ @"amenity": @[ @"restaurant", @"cafe", @"bar", @"pub", @"ice_cream" ], @"shop": @[ @"bakery" ] },
            @"accommodation": @{ @"tourism": @[ @"hotel", @"guest_house", @"hostel", @"camp_site", @"chalet",
                                                @"alpine_hut", @"wilderness_hut" ] },
            @"bikeshop": @{ @"shop": @[ @"bicycle" ] },
        };
    });
    return tags;
}

+ (PoiType_t)typeOfCategory:(NSString *)category
{
    NSDictionary *types = @{ @"culture": @(POI_culture), @"viewpoint": @(POI_viewpoint), @"church": @(POI_church),
                             @"nature": @(POI_nature), @"food": @(POI_food), @"accommodation": @(POI_accommodation),
                             @"bikeshop": @(POI_bike_shop) };
    return (PoiType_t)[types[category] intValue];
}

+ (nullable NSString *)categoryOfType:(PoiType_t)type
{
    for (NSString *c in [self allCategories]) if ([self typeOfCategory:c] == type) return c;
    return nil;
}

+ (NSArray<NSString *> *)allCategories
{
    return @[ @"culture", @"viewpoint", @"church", @"nature", @"food", @"accommodation", @"bikeshop" ];
}

+ (NSString *)localizedNameOfCategory:(NSString *)category
{
    NSDictionary *names = @{
        @"culture": NSLocalizedString(@"Culture", @"sight category"),
        @"viewpoint": NSLocalizedString(@"Viewpoints", @"sight category"),
        @"church": NSLocalizedString(@"Churches and chapels", @"sight category"),
        @"nature": NSLocalizedString(@"Nature", @"sight category"),
        @"food": NSLocalizedString(@"Food and drink", @"sight category"),
        @"accommodation": NSLocalizedString(@"Accommodation", @"sight category"),
        @"bikeshop": NSLocalizedString(@"Bike shops", @"sight category"),
    };
    return names[category] ?: category;
}

+ (NSString *)summaryOfCategories:(NSArray<NSString *> *)categories
{
    NSArray *cats = [self normalizedCategories:categories];
    if (!cats.count) return NSLocalizedString(@"None", @"no sight category");
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *c in cats) [names addObject:[self localizedNameOfCategory:c]];
    return [names componentsJoinedByString:@", "];
}

+ (NSArray<NSString *> *)normalizedCategories:(nullable NSArray<NSString *> *)categories
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *c in [self allCategories]) if ([categories containsObject:c]) [result addObject:c];
    return result;
}

+ (nullable NSString *)overpassClauseForCategories:(NSArray<NSString *> *)categories radius:(NSUInteger)radius
                                          latitude:(double)latitude longitude:(double)longitude
{
    NSMutableSet<NSString *> *keys = [NSMutableSet set], *values = [NSMutableSet set];
    for (NSString *c in [self normalizedCategories:categories]) {
        [[self tags][c] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray<NSString *> *vals, BOOL *stop) {
            [keys addObject:key];
            [values addObjectsFromArray:vals];
        }];
    }
    if (!keys.count) return nil;
    NSArray *k = [keys.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSArray *v = [values.allObjects sortedArrayUsingSelector:@selector(compare:)];
    // nodes, ways (castles) and relations, with their center (out center)
    return [NSString stringWithFormat:@"  nwr(around:%lu,%.6f,%.6f)[~\"^(%@)$\"~\"^(%@)$\"];\n", (unsigned long)radius,
            latitude, longitude, [k componentsJoinedByString:@"|"], [v componentsJoinedByString:@"|"]];
}

+ (PoiType_t)typeForTags:(NSDictionary<NSString *, NSString *> *)tags categories:(NSArray<NSString *> *)categories
                category:(NSString * _Nullable * _Nullable)category
{
    for (NSString *c in [self normalizedCategories:categories]) {
        __block BOOL match = NO;
        [[self tags][c] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray<NSString *> *vals, BOOL *stop) {
            NSString *value = tags[key];
            if (value && [vals containsObject:value]) match = *stop = YES;
        }];
        if (match) {
            if (category) *category = c;
            return [self typeOfCategory:c];
        }
    }
    return POI_unknown;
}

@end
