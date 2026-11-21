//
//  RAFilter.m
//  RideAnalyzer
//

#import "RAFilter.h"
#import "RARide.h"

@implementation RAFilter

- (instancetype)init
{
    self = [super init];
    if (self) {
        _text = @"";
        _deviceKeys = [NSSet set];
        _bikeIDs = [NSSet set];
        _tags = [NSSet set];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return [RAFilter filterWithPropertyList:self.propertyList];
}

- (BOOL)isEqual:(id)object
{
    return [object isKindOfClass:[RAFilter class]] && [[object propertyList] isEqual:self.propertyList];
}

- (NSUInteger)hash
{
    return self.propertyList.hash;
}

- (BOOL)isEmpty
{
    return [self words].count == 0 && !self.fromDay && !self.toDay && self.deviceKeys.count == 0 && self.bikeIDs.count == 0
        && self.minDistance <= 0 && self.maxDistance <= 0 && self.minAscent <= 0 && self.tags.count == 0;
}

static NSString *RAFold(NSString *s)
{
    return [s stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
                                  locale:[NSLocale currentLocale]];
}

- (NSArray<NSString *> *)words
{
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *w in [RAFold(self.text) componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (w.length) [words addObject:w];
    }
    return words;
}

- (BOOL)matchesRide:(RARide *)ride
{
    NSArray<NSString *> *words = [self words];
    if (words.count) {
        NSString *haystack = RAFold([NSString stringWithFormat:@"%@ %@ %@", ride.name, ride.notes,
                                     [ride.tags componentsJoinedByString:@" "]]);
        for (NSString *w in words) {
            if ([haystack rangeOfString:w].location == NSNotFound) return NO;
        }
    }
    if (self.fromDay || self.toDay) {
        if (!ride.startDate) return NO;
        NSCalendar *cal = [NSCalendar currentCalendar];
        if (self.fromDay && [ride.startDate compare:[cal startOfDayForDate:(NSDate *)self.fromDay]] == NSOrderedAscending) {
            return NO;
        }
        if (self.toDay) {
            NSDate *end = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:[cal startOfDayForDate:(NSDate *)self.toDay]
                                        options:0];
            if (end && [ride.startDate compare:end] != NSOrderedAscending) return NO;
        }
    }
    if (self.deviceKeys.count && ![self.deviceKeys containsObject:ride.deviceKey]) return NO;
    if (self.bikeIDs.count && ![self.bikeIDs containsObject:ride.bikeID]) return NO;
    if (self.minDistance > 0 && ride.distance < self.minDistance) return NO;
    if (self.maxDistance > 0 && ride.distance > self.maxDistance) return NO;
    if (self.minAscent > 0 && ride.ascent < self.minAscent) return NO;
    if (self.tags.count && ![self.tags intersectsSet:[NSSet setWithArray:ride.tags]]) return NO;
    return YES;
}

- (NSArray<RARide *> *)filteredRides:(NSArray<RARide *> *)rides
{
    if (self.empty) return rides;
    NSMutableArray<RARide *> *kept = [NSMutableArray array];
    for (RARide *r in rides) if ([self matchesRide:r]) [kept addObject:r];
    return kept;
}

- (RAFilter *)filterWithText:(NSString *)text
{
    RAFilter *f = [self copy];
    f.text = text;
    return f;
}

- (NSDictionary *)propertyList
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.text.length) d[@"text"] = self.text;
    if (self.fromDay) d[@"fromDay"] = self.fromDay;
    if (self.toDay) d[@"toDay"] = self.toDay;
    if (self.deviceKeys.count) d[@"deviceKeys"] = [self.deviceKeys.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if (self.bikeIDs.count) d[@"bikeIDs"] = [self.bikeIDs.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if (self.minDistance > 0) d[@"minDistance"] = @(self.minDistance);
    if (self.maxDistance > 0) d[@"maxDistance"] = @(self.maxDistance);
    if (self.minAscent > 0) d[@"minAscent"] = @(self.minAscent);
    if (self.tags.count) d[@"tags"] = [self.tags.allObjects sortedArrayUsingSelector:@selector(compare:)];
    return d;
}

static NSSet<NSString *> *RAStringSet(id value)
{
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    if ([value isKindOfClass:[NSArray class]]) {
        for (id s in value) if ([s isKindOfClass:[NSString class]]) [set addObject:s];
    }
    return set;
}

+ (RAFilter *)filterWithPropertyList:(nullable NSDictionary *)plist
{
    RAFilter *f = [[RAFilter alloc] init];
    if (![plist isKindOfClass:[NSDictionary class]]) return f;
    id v;
    if ([(v = plist[@"text"]) isKindOfClass:[NSString class]]) f.text = v;
    if ([(v = plist[@"fromDay"]) isKindOfClass:[NSDate class]]) f.fromDay = v;
    if ([(v = plist[@"toDay"]) isKindOfClass:[NSDate class]]) f.toDay = v;
    f.deviceKeys = RAStringSet(plist[@"deviceKeys"]);
    f.bikeIDs = RAStringSet(plist[@"bikeIDs"]);
    if ([(v = plist[@"minDistance"]) isKindOfClass:[NSNumber class]]) f.minDistance = [v doubleValue];
    if ([(v = plist[@"maxDistance"]) isKindOfClass:[NSNumber class]]) f.maxDistance = [v doubleValue];
    if ([(v = plist[@"minAscent"]) isKindOfClass:[NSNumber class]]) f.minAscent = [v doubleValue];
    f.tags = RAStringSet(plist[@"tags"]);
    return f;
}

- (NSString *)summaryWithDeviceLabel:(NSString * (^)(NSString *deviceKey))deviceLabel
{
    return [self summaryWithDeviceLabel:deviceLabel bikeLabel:nil];
}

- (NSString *)summaryWithDeviceLabel:(NSString * (^)(NSString *deviceKey))deviceLabel
                           bikeLabel:(nullable NSString * (^)(NSString *bikeID))bikeLabel
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterShortStyle;
    f.timeStyle = NSDateFormatterNoStyle;
    if (self.fromDay && self.toDay) {
        [parts addObject:[NSString stringWithFormat:@"%@ – %@", [f stringFromDate:(NSDate *)self.fromDay],
                          [f stringFromDate:(NSDate *)self.toDay]]];
    } else if (self.fromDay) {
        [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"since %@", @"filter"), [f stringFromDate:(NSDate *)self.fromDay]]];
    } else if (self.toDay) {
        [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"until %@", @"filter"), [f stringFromDate:(NSDate *)self.toDay]]];
    }
    NSMutableArray<NSString *> *devices = [NSMutableArray array];
    for (NSString *k in [self.deviceKeys.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [devices addObject:deviceLabel(k)];
    }
    if (devices.count) [parts addObject:[devices componentsJoinedByString:@", "]];
    NSMutableArray<NSString *> *bikes = [NSMutableArray array];
    for (NSString *b in [self.bikeIDs.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [bikes addObject:(bikeLabel ? bikeLabel(b) : nil) ?: NSLocalizedString(@"a bike", @"filter summary")];
    }
    if (bikes.count) [parts addObject:[bikes componentsJoinedByString:@", "]];
    if (self.minDistance > 0 && self.maxDistance > 0) {
        [parts addObject:[NSString localizedStringWithFormat:@"%.0f–%.0f km", self.minDistance / 1000, self.maxDistance / 1000]];
    } else if (self.minDistance > 0) {
        [parts addObject:[NSString localizedStringWithFormat:@"> %.0f km", self.minDistance / 1000]];
    } else if (self.maxDistance > 0) {
        [parts addObject:[NSString localizedStringWithFormat:@"< %.0f km", self.maxDistance / 1000]];
    }
    if (self.minAscent > 0) [parts addObject:[NSString localizedStringWithFormat:@"D+ > %.0f m", self.minAscent]];
    for (NSString *t in [self.tags.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[@"#" stringByAppendingString:t]];
    }
    return [parts componentsJoinedByString:@" · "];
}

@end

@implementation RASavedFilter

- (instancetype)initWithName:(NSString *)name filter:(RAFilter *)filter
{
    self = [super init];
    if (self) {
        _identifier = [NSUUID UUID].UUIDString;
        _name = [name copy];
        _filter = [filter copy];
    }
    return self;
}

- (NSDictionary *)propertyList
{
    return @{ @"identifier": self.identifier, @"name": self.name, @"filter": self.filter.propertyList };
}

+ (nullable RASavedFilter *)savedFilterWithPropertyList:(nullable NSDictionary *)plist
{
    if (![plist isKindOfClass:[NSDictionary class]] || ![plist[@"name"] isKindOfClass:[NSString class]]) return nil;
    RASavedFilter *s = [[RASavedFilter alloc] initWithName:plist[@"name"] filter:[RAFilter filterWithPropertyList:plist[@"filter"]]];
    if ([plist[@"identifier"] isKindOfClass:[NSString class]]) s.identifier = plist[@"identifier"];
    return s;
}

@end
