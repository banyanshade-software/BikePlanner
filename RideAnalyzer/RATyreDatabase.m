//
//  RATyreDatabase.m
//  RideAnalyzer
//

#import "RATyreDatabase.h"

/// lower case, letters and digits only; "GP5000" → "grandprix5000"
static NSString *RANormalized(NSString *s)
{
    NSString *folded = [s stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
                                              locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < folded.length; i++) {
        unichar c = [folded characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) [out appendFormat:@"%C", c];
    }
    NSRegularExpression *gp = [NSRegularExpression regularExpressionWithPattern:@"(^|[a-z])gp([0-9])" options:0 error:NULL];
    return [gp stringByReplacingMatchesInString:out options:0 range:NSMakeRange(0, out.length) withTemplate:@"$1grandprix$2"];
}

@implementation RATyre

- (NSString *)name
{
    return [NSString stringWithFormat:@"%@ %@", self.brand, self.model];
}

- (NSString *)displayName
{
    NSString *variant = self.variant.length ? [NSString stringWithFormat:@" (%@)", self.variant] : @"";
    return [NSString localizedStringWithFormat:@"%@%@ — %.0f mm", self.name, variant, self.width];
}

+ (nullable RATyre *)tyreWithPropertyList:(nullable id)plist
{
    if (![plist isKindOfClass:[NSDictionary class]]) return nil;
    NSString * (^str)(NSString *) = ^NSString *(NSString *k) {
        id v = plist[k];
        return [v isKindOfClass:[NSString class]] ? v : @"";
    };
    id crr = plist[@"crr"], width = plist[@"width"];
    if (![crr isKindOfClass:[NSNumber class]] || [crr doubleValue] <= 0 || str(@"model").length == 0) return nil;
    RATyre *t = [[RATyre alloc] init];
    t.brand = str(@"brand");
    t.model = str(@"model");
    t.variant = str(@"variant");
    t.width = [width isKindOfClass:[NSNumber class]] ? [width doubleValue] : 0;
    t.crr = [crr doubleValue];
    t.pressure = str(@"pressure");
    t.category = str(@"category");
    t.source = str(@"source");
    return t;
}

@end

@implementation RATyreDatabase

+ (RATyreDatabase *)shared
{
    static RATyreDatabase *db;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"RATyres" withExtension:@"plist"];
        NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
        id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
        if (!plist) NSLog(@"RideAnalyzer: the tyre database RATyres.plist is missing or unreadable");
        db = [[RATyreDatabase alloc] initWithPropertyList:plist];
    });
    return db;
}

- (instancetype)initWithPropertyList:(nullable id)plist
{
    self = [super init];
    if (!self) return nil;
    NSMutableArray<RATyre *> *tyres = [NSMutableArray array];
    id list = [plist isKindOfClass:[NSDictionary class]] ? plist[@"tyres"] : nil;
    if ([list isKindOfClass:[NSArray class]]) {
        for (id t in list) {
            RATyre *tyre = [RATyre tyreWithPropertyList:t];
            if (tyre) [tyres addObject:tyre];
        }
    }
    [tyres sortUsingComparator:^NSComparisonResult(RATyre *a, RATyre *b) {
        NSComparisonResult r = [a.name localizedStandardCompare:b.name];
        if (r != NSOrderedSame) return r;
        return a.width < b.width ? NSOrderedAscending : a.width > b.width ? NSOrderedDescending : NSOrderedSame;
    }];
    _tyres = tyres;
    id note = [plist isKindOfClass:[NSDictionary class]] ? plist[@"note"] : nil;
    _note = [note isKindOfClass:[NSString class]] ? note : @"";
    return self;
}

- (nullable RATyre *)tyreMatchingModel:(NSString *)model width:(double)width
{
    NSString *n = RANormalized(model);
    if (n.length < 3) return nil;
    RATyre *best = nil;
    double bestScore = 0;
    for (RATyre *t in self.tyres) {
        double score = 0;
        for (NSString *key in @[ RANormalized(t.name), RANormalized(t.model) ]) {
            double s = 0;
            if ([n isEqualToString:key]) s = 1000 + key.length;                         // the name exactly
            else if ([n containsString:key]) s = 100 + key.length;                      // "Schwalbe Marathon Plus 40-622"
            else if (n.length >= 4 && [key containsString:n]) s = 50 - (double)(key.length - n.length); // a short name
            score = MAX(score, s);
        }
        if (score <= 0) continue;
        if (width > 0 && t.width > 0) score -= MIN(fabs(t.width - width), 40) / 100; // then the nearest width
        if (!best || score > bestScore) {
            best = t;
            bestScore = score;
        }
    }
    return best;
}

- (NSArray<RATyre *> *)tyresMatchingText:(NSString *)text
{
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *w in [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
        NSString *n = RANormalized(w);
        if (n.length) [words addObject:n];
    }
    if (words.count == 0) return self.tyres;
    NSMutableArray<RATyre *> *found = [NSMutableArray array];
    for (RATyre *t in self.tyres) {
        NSString *hay = RANormalized([NSString stringWithFormat:@"%@ %@ %@ %@", t.brand, t.model, t.variant, t.category]);
        BOOL all = YES;
        for (NSString *w in words) if (![hay containsString:w]) { all = NO; break; }
        if (all) [found addObject:t];
    }
    return found;
}

@end
