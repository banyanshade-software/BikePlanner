//
//  BPPOICache.m
//  BikePlanner
//
//  Cache of the Overpass answers per area (#84).
//

#import "BPPOICache.h"
#import "BPEnvironment.h"

const double BPPOICellSize = 0.02;
NSString *const BPPOIUtilitiesLayer = @"utilities";

static NSString *BPCellKey(BPPOICell c, NSString *layer)
{
    return [NSString stringWithFormat:@"%@/%ld_%ld", layer, (long)c.lat, (long)c.lon];
}

@implementation BPPOICache {
    NSURL *_directory;
    NSMutableDictionary<NSString *, NSDictionary *> *_memory;  // key → { date, elements }
}

+ (instancetype)shared
{
    static BPPOICache *cache;
    static NSString *path;
    NSString *current = [BPEnvironment poiCacheDirectory];
    if (!cache || ![current isEqualToString:path]) {
        cache = [[self alloc] initWithDirectory:[NSURL fileURLWithPath:current isDirectory:YES]];
        path = current;
    }
    return cache;
}

- (instancetype)initWithDirectory:(nullable NSURL *)directory
{
    if (self = [super init]) {
        _directory = directory;
        _memory = [NSMutableDictionary dictionary];
        _clock = ^{ return [NSDate date]; };
        _maxAge = 7 * 86400;
        _maxBytes = 50 * 1000 * 1000;
    }
    return self;
}

- (nullable NSURL *)fileForKey:(NSString *)key
{
    return [_directory URLByAppendingPathComponent:[key stringByAppendingPathExtension:@"json"]];
}

- (nullable NSArray<NSDictionary *> *)elementsForCell:(BPPOICell)cell layer:(NSString *)layer
{
    NSString *key = BPCellKey(cell, layer);
    NSDictionary *entry = _memory[key];
    if (!entry && _directory) {
        NSData *d = [NSData dataWithContentsOfURL:[self fileForKey:key]];
        id json = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        if ([json isKindOfClass:[NSDictionary class]] && [json[@"elements"] isKindOfClass:[NSArray class]]) {
            entry = json;
            _memory[key] = entry;
        }
    }
    if (!entry) return nil;
    NSTimeInterval age = self.clock().timeIntervalSince1970 - [entry[@"date"] doubleValue];
    if (age > self.maxAge) return nil;
    return entry[@"elements"];
}

- (void)setElements:(NSArray<NSDictionary *> *)elements forCell:(BPPOICell)cell layer:(NSString *)layer
{
    NSString *key = BPCellKey(cell, layer);
    NSDictionary *entry = @{ @"date": @(self.clock().timeIntervalSince1970), @"elements": elements ?: @[] };
    _memory[key] = entry;
    if (!_directory) return;
    NSURL *file = [self fileForKey:key];
    [[NSFileManager defaultManager] createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES
                                              attributes:nil error:NULL];
    NSData *d = [NSJSONSerialization dataWithJSONObject:entry options:0 error:NULL];
    if (d && [d writeToURL:file atomically:YES]) {
        // the date of the cell, for the eviction (the clock may be a test's)
        [[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate: self.clock() } ofItemAtPath:file.path error:NULL];
    }
    [self evictIfNeeded];
}

- (NSArray<NSURL *> *)files
{
    if (!_directory) return @[];
    NSMutableArray *files = [NSMutableArray array];
    NSDirectoryEnumerator *e = [[NSFileManager defaultManager] enumeratorAtURL:_directory
                                                    includingPropertiesForKeys:@[ NSURLFileSizeKey, NSURLContentModificationDateKey ]
                                                                       options:0 errorHandler:nil];
    for (NSURL *u in e) if ([u.pathExtension isEqualToString:@"json"]) [files addObject:u];
    return files;
}

- (NSUInteger)diskSize
{
    NSUInteger total = 0;
    for (NSURL *u in [self files]) {
        NSNumber *size = nil;
        [u getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        total += size.unsignedIntegerValue;
    }
    return total;
}

// the oldest cells first, until below the limit
- (void)evictIfNeeded
{
    NSArray<NSURL *> *files = [self files];
    NSUInteger total = 0;
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSURL *u in files) {
        NSNumber *size = nil;
        NSDate *date = nil;
        [u getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        [u getResourceValue:&date forKey:NSURLContentModificationDateKey error:NULL];
        total += size.unsignedIntegerValue;
        [items addObject:@{ @"url": u, @"size": size ?: @0, @"date": date ?: [NSDate distantPast] }];
    }
    if (total <= self.maxBytes) return;
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { return [x[@"date"] compare:y[@"date"]]; }];
    for (NSDictionary *item in items) {
        if (total <= self.maxBytes) break;
        NSURL *u = item[@"url"];
        [[NSFileManager defaultManager] removeItemAtURL:u error:NULL];
        total -= [item[@"size"] unsignedIntegerValue];
        NSString *layer = u.URLByDeletingLastPathComponent.lastPathComponent;
        [_memory removeObjectForKey:[NSString stringWithFormat:@"%@/%@", layer, u.URLByDeletingPathExtension.lastPathComponent]];
    }
}

- (void)removeAll
{
    [_memory removeAllObjects];
    if (_directory) [[NSFileManager defaultManager] removeItemAtURL:_directory error:NULL];
}

#pragma mark - cells

+ (BPPOICell)cellOfLatitude:(double)latitude longitude:(double)longitude
{
    BPPOICell c = { (NSInteger)floor(latitude / BPPOICellSize + 1e-9), (NSInteger)floor(longitude / BPPOICellSize + 1e-9) };
    return c;
}

+ (BPGeoBox)boxOfCell:(BPPOICell)cell
{
    return BPGeoBoxMake(cell.lat * BPPOICellSize, cell.lon * BPPOICellSize,
                        (cell.lat + 1) * BPPOICellSize, (cell.lon + 1) * BPPOICellSize);
}

+ (NSArray<NSValue *> *)cellsAlongRoute:(NSArray<CLLocation *> *)route radius:(double)radius
{
    NSMutableArray<NSValue *> *cells = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    if (!route.count) return cells;
    // points along the route at most `step` apart (interpolated), each with the cells of the square of the radius
    double step = MAX(100, MIN(radius, 1000));
    void (^addAround)(CLLocationCoordinate2D) = ^(CLLocationCoordinate2D p) {
        double dLat = radius / 111195.0, dLon = radius / (111195.0 * MAX(0.01, cos(p.latitude * M_PI / 180)));
        BPPOICell lo = [BPPOICache cellOfLatitude:p.latitude - dLat longitude:p.longitude - dLon];
        BPPOICell hi = [BPPOICache cellOfLatitude:p.latitude + dLat longitude:p.longitude + dLon];
        for (NSInteger lat = lo.lat; lat <= hi.lat; lat++) {
            for (NSInteger lon = lo.lon; lon <= hi.lon; lon++) {
                NSString *k = [NSString stringWithFormat:@"%ld_%ld", (long)lat, (long)lon];
                if ([seen containsObject:k]) continue;
                [seen addObject:k];
                BPPOICell c = { lat, lon };
                [cells addObject:[NSValue valueWithBytes:&c objCType:@encode(BPPOICell)]];
            }
        }
    };
    // the cell of the start first (then those around it): "from the start"
    CLLocationCoordinate2D start = route.firstObject.coordinate;
    BPPOICell first = [BPPOICache cellOfLatitude:start.latitude longitude:start.longitude];
    [seen addObject:[NSString stringWithFormat:@"%ld_%ld", (long)first.lat, (long)first.lon]];
    [cells addObject:[NSValue valueWithBytes:&first objCType:@encode(BPPOICell)]];
    addAround(start);
    for (NSUInteger i = 1; i < route.count; i++) {
        CLLocation *a = route[i - 1], *b = route[i];
        double d = [b distanceFromLocation:a];
        NSUInteger n = (NSUInteger)ceil(d / step);
        for (NSUInteger k = 1; k <= n; k++) {
            double t = (double)k / n;
            addAround(CLLocationCoordinate2DMake(a.coordinate.latitude + t * (b.coordinate.latitude - a.coordinate.latitude),
                                                 a.coordinate.longitude + t * (b.coordinate.longitude - a.coordinate.longitude)));
        }
    }
    return cells;
}

@end
