//
//  BPOverpassServers.m
//  BikePlanner
//
//  Overpass servers in rotation (#84).
//

#import "BPOverpassServers.h"
#import "BPEnvironment.h"
#import <os/log.h>

@implementation BPOverpassServer

- (instancetype)initWithURL:(NSURL *)url zones:(NSArray<NSValue *> *)zones
{
    if (self = [super init]) {
        _url = url;
        _zones = [zones copy];
    }
    return self;
}

+ (nullable instancetype)serverWithSpec:(NSString *)spec
{
    NSArray<NSString *> *parts = [[spec stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                                  componentsSeparatedByString:@" "];
    NSURL *url = parts.firstObject.length ? [NSURL URLWithString:parts.firstObject] : nil;
    if (!url.scheme || !url.host) return nil;
    NSMutableArray<NSValue *> *zones = [NSMutableArray array];
    if (parts.count > 1) {
        for (NSString *z in [parts[1] componentsSeparatedByString:@";"]) {
            NSArray<NSString *> *c = [z componentsSeparatedByString:@","];
            if (c.count != 4) return nil;
            BPGeoBox b = BPGeoBoxMake(c[0].doubleValue, c[1].doubleValue, c[2].doubleValue, c[3].doubleValue);
            if (b.south >= b.north || b.west >= b.east) return nil;
            [zones addObject:[NSValue valueWithBytes:&b objCType:@encode(BPGeoBox)]];
        }
    }
    return [[self alloc] initWithURL:url zones:zones];
}

- (BOOL)worldwide
{
    return _zones.count == 0;
}

- (BOOL)covers:(BPGeoBox)box
{
    if (self.worldwide) return YES;
    for (NSValue *v in _zones) {
        BPGeoBox z;
        [v getValue:&z size:sizeof(z)];
        if (box.south >= z.south && box.north <= z.north && box.west >= z.west && box.east <= z.east) return YES;
    }
    return NO;
}

- (NSString *)description
{
    return self.url.host ?: self.url.absoluteString;
}

@end

@implementation BPOverpassServerPool {
    NSUInteger _next;                                       // round robin
    NSMutableDictionary<NSURL *, NSDate *> *_demotedUntil;
    NSMutableDictionary<NSURL *, NSNumber *> *_failures;    // consecutive
    NSMutableDictionary<NSURL *, NSDate *> *_respondedAt;   // last HTTP answer, whatever its status
    NSUserDefaults *_defaults;                              // kept from one launch to the next; nil: memory only
}

static NSString *const BPOverpassServerStateKey = @"BPOverpassServerState";

static BPOverpassServerPool *bpSharedPool;
static NSArray<NSString *> *bpSharedSpecs;

+ (void)resetShared
{
    bpSharedPool = nil;
    bpSharedSpecs = nil;
}

+ (instancetype)shared
{
#define pool bpSharedPool
#define specs bpSharedSpecs
    NSArray<NSString *> *current = [BPEnvironment overpassServerSpecs];
    if (!pool || ![current isEqualToArray:specs]) {
        NSMutableArray *servers = [NSMutableArray array];
        for (NSString *s in current) {
            BPOverpassServer *server = [BPOverpassServer serverWithSpec:s];
            if (server) [servers addObject:server];
        }
        // kept across launches for the real servers only: not in the unit test host, nor for test servers
        // (BPOverpassURL / BPOverpassServers, UI tests)
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        BOOL testServers = [ud objectForKey:@"BPOverpassServers"] || [ud stringForKey:@"BPOverpassURL"].length;
        pool = [[self alloc] initWithServers:servers
                                    defaults:([BPEnvironment isUnitTestHost] || testServers) ? nil : ud];
        specs = current;
    }
    return pool;
#undef pool
#undef specs
}

- (instancetype)initWithServers:(NSArray<BPOverpassServer *> *)servers
{
    return [self initWithServers:servers defaults:nil];
}

- (instancetype)initWithServers:(NSArray<BPOverpassServer *> *)servers defaults:(nullable NSUserDefaults *)defaults
{
    if (self = [super init]) {
        _defaults = defaults;
        _servers = [servers copy];
        _demotedUntil = [NSMutableDictionary dictionary];
        _failures = [NSMutableDictionary dictionary];
        _respondedAt = [NSMutableDictionary dictionary];
        _clock = ^{ return [NSDate date]; };
        _baseDemotion = 600;
        _maxDemotion = 7200;
        _slowAnswer = 20;
        [self loadState];
    }
    return self;
}

// { url: { until, failures, responded } } (seconds since 1970)
- (void)loadState
{
    NSDictionary *state = [_defaults dictionaryForKey:BPOverpassServerStateKey];
    for (BPOverpassServer *s in _servers) {
        NSDictionary *d = state[s.url.absoluteString];
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        if (d[@"until"]) _demotedUntil[s.url] = [NSDate dateWithTimeIntervalSince1970:[d[@"until"] doubleValue]];
        if ([d[@"failures"] integerValue] > 0) _failures[s.url] = d[@"failures"];
        if (d[@"responded"]) _respondedAt[s.url] = [NSDate dateWithTimeIntervalSince1970:[d[@"responded"] doubleValue]];
    }
}

- (void)saveState
{
    if (!_defaults) return;
    NSMutableDictionary *state = [[_defaults dictionaryForKey:BPOverpassServerStateKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (BPOverpassServer *s in _servers) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        if (_demotedUntil[s.url]) d[@"until"] = @(_demotedUntil[s.url].timeIntervalSince1970);
        if (_failures[s.url] != nil) d[@"failures"] = _failures[s.url];
        if (_respondedAt[s.url]) d[@"responded"] = @(_respondedAt[s.url].timeIntervalSince1970);
        state[s.url.absoluteString] = d;
    }
    [_defaults setObject:state forKey:BPOverpassServerStateKey];
}

- (BOOL)isDemoted:(BPOverpassServer *)server
{
    NSDate *until = _demotedUntil[server.url];
    return until && [until compare:self.clock()] == NSOrderedDescending;
}

- (nullable BPOverpassServer *)nextServerFor:(BPGeoBox)box excluding:(NSSet<NSURL *> *)tried
{
    NSMutableArray<BPOverpassServer *> *candidates = [NSMutableArray array];
    for (BPOverpassServer *s in _servers) if ([s covers:box] && ![tried containsObject:s.url]) [candidates addObject:s];
    if (!candidates.count) return nil;
    // round robin over the whole list, so that each candidate gets its turn
    NSUInteger n = _servers.count;
    for (NSUInteger k = 0; k < n; k++) {
        BPOverpassServer *s = _servers[(_next + k) % n];
        if ([candidates containsObject:s] && ![self isDemoted:s]) {
            _next = (_next + k + 1) % n;
            return s;
        }
    }
    // all demoted: the one that answered last (reachable, even if it failed), else the one available first
    BPOverpassServer *best = nil;
    for (BPOverpassServer *s in candidates) {
        NSDate *at = _respondedAt[s.url];
        if (at && (!best || [at compare:_respondedAt[best.url]] == NSOrderedDescending)) best = s;
    }
    if (best) return best;
    best = candidates.firstObject;
    for (BPOverpassServer *s in candidates) {
        if ([_demotedUntil[s.url] compare:_demotedUntil[best.url]] == NSOrderedAscending) best = s;
    }
    return best;
}

- (void)serverFailed:(BPOverpassServer *)server retryAfter:(NSTimeInterval)retryAfter
{
    NSUInteger failures = _failures[server.url].unsignedIntegerValue;
    NSTimeInterval period = MIN(self.baseDemotion * pow(2, failures), self.maxDemotion);
    period = MAX(period, MIN(retryAfter, self.maxDemotion));
    _failures[server.url] = @(failures + 1);
    _demotedUntil[server.url] = [self.clock() dateByAddingTimeInterval:period];
    [self saveState];
    os_log(OS_LOG_DEFAULT, "Overpass: %{public}@ demoted for %.0f s", server.url.host ?: @"?", period);
}

- (void)serverResponded:(BPOverpassServer *)server
{
    _respondedAt[server.url] = self.clock();
    [self saveState];
}

- (void)server:(BPOverpassServer *)server answeredAfter:(NSTimeInterval)seconds
{
    [self serverResponded:server];
    if (seconds > self.slowAnswer) {
        [self serverFailed:server retryAfter:0];
        return;
    }
    [_failures removeObjectForKey:server.url];
    [_demotedUntil removeObjectForKey:server.url];
    [self saveState];
}

@end
