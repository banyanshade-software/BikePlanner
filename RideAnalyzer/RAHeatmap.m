//
//  RAHeatmap.m
//  RideAnalyzer
//

#import "RAHeatmap.h"
#import "RAComputation.h"
#import "RARide.h"
#import "RARideStats.h"

const NSUInteger RAHeatLevelCount = 4;

typedef struct { float lat, lon; } RAPackedPoint;

@implementation RAHeatmap
{
    double _cell;                                   // map points
    NSMutableDictionary<NSNumber *, NSNumber *> *_counts;
    NSArray<NSMutableArray<MKPolyline *> *> *_levels;
}

#pragma mark - packed tracks

static double RAPerpendicular(MKMapPoint p, MKMapPoint a, MKMapPoint b)
{
    double dx = b.x - a.x, dy = b.y - a.y;
    double len2 = dx * dx + dy * dy;
    if (len2 == 0) return hypot(p.x - a.x, p.y - a.y);
    double t = MAX(0, MIN(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

+ (NSData *)packedTrackOfTrace:(NSArray<CLLocation *> *)trace tolerance:(double)tolerance
{
    NSUInteger n = trace.count;
    if (n == 0) return [NSData data];
    MKMapPoint *pts = malloc(n * sizeof(MKMapPoint));
    BOOL *keep = calloc(n, sizeof(BOOL));
    for (NSUInteger i = 0; i < n; i++) pts[i] = MKMapPointForCoordinate(trace[i].coordinate);
    double tol = tolerance * MKMapPointsPerMeterAtLatitude(trace[0].coordinate.latitude);
    keep[0] = keep[n - 1] = YES;
    // Douglas–Peucker, with an explicit stack of ranges
    NSMutableArray<NSValue *> *stack = [NSMutableArray arrayWithObject:[NSValue valueWithRange:NSMakeRange(0, n - 1)]];
    while (stack.count) {
        NSRange r = stack.lastObject.rangeValue;
        [stack removeLastObject];
        NSUInteger first = r.location, last = r.length;
        if (last <= first + 1) continue;
        double worst = -1;
        NSUInteger index = first;
        for (NSUInteger i = first + 1; i < last; i++) {
            double d = RAPerpendicular(pts[i], pts[first], pts[last]);
            if (d > worst) { worst = d; index = i; }
        }
        if (worst > tol) {
            keep[index] = YES;
            [stack addObject:[NSValue valueWithRange:NSMakeRange(first, index)]];
            [stack addObject:[NSValue valueWithRange:NSMakeRange(index, last)]];
        }
    }
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i < n; i++) {
        if (!keep[i]) continue;
        RAPackedPoint p = { (float)trace[i].coordinate.latitude, (float)trace[i].coordinate.longitude };
        [data appendBytes:&p length:sizeof p];
    }
    free(pts);
    free(keep);
    return data;
}

+ (NSUInteger)pointCountOfPackedTrack:(NSData *)track
{
    return track.length / sizeof(RAPackedPoint);
}

+ (CLLocationCoordinate2D)coordinateAtIndex:(NSUInteger)index ofPackedTrack:(NSData *)track
{
    if (index >= [self pointCountOfPackedTrack:track]) return kCLLocationCoordinate2DInvalid;
    const RAPackedPoint *p = (const RAPackedPoint *)track.bytes + index;
    return CLLocationCoordinate2DMake(p->lat, p->lon);
}

#pragma mark - levels

+ (NSUInteger)levelOfCount:(NSUInteger)count
{
    return count >= 10 ? 3 : count >= 4 ? 2 : count >= 2 ? 1 : 0;
}

+ (NSString *)legendOfLevel:(NSUInteger)level
{
    switch (level) {
        case 0: return NSLocalizedString(@"1 ride", @"heatmap legend");
        case 1: return NSLocalizedString(@"2–3", @"heatmap legend");
        case 2: return NSLocalizedString(@"4–9", @"heatmap legend");
        default: return NSLocalizedString(@"10+", @"heatmap legend");
    }
}

#pragma mark - computing

- (instancetype)initWithRides:(NSArray<RARide *> *)rides
{
    return [self initWithRides:rides cellSize:40];
}

- (NSNumber *)keyOfPoint:(MKMapPoint)p
{
    long long x = (long long)floor(p.x / _cell), y = (long long)floor(p.y / _cell);
    return @((x << 32) ^ (y & 0xffffffffLL));
}

/// the points of a track, map points, every half cell (so that every cell crossed is visited)
- (NSArray<NSValue *> *)densified:(NSData *)track
{
    NSUInteger n = [RAHeatmap pointCountOfPackedTrack:track];
    NSMutableArray<NSValue *> *out = [NSMutableArray array];
    MKMapPoint prev = MKMapPointMake(0, 0);
    for (NSUInteger i = 0; i < n; i++) {
        MKMapPoint p = MKMapPointForCoordinate([RAHeatmap coordinateAtIndex:i ofPackedTrack:track]);
        if (i > 0) {
            double d = hypot(p.x - prev.x, p.y - prev.y);
            NSUInteger steps = MAX(1, (NSUInteger)ceil(d / (_cell / 2)));
            for (NSUInteger k = 1; k < steps; k++) {
                double t = (double)k / steps;
                MKMapPoint q = MKMapPointMake(prev.x + (p.x - prev.x) * t, prev.y + (p.y - prev.y) * t);
                [out addObject:[NSValue valueWithBytes:&q objCType:@encode(MKMapPoint)]];
            }
        }
        [out addObject:[NSValue valueWithBytes:&p objCType:@encode(MKMapPoint)]];
        prev = p;
    }
    return out;
}

static MKMapPoint RAPoint(NSValue *v)
{
    MKMapPoint p;
    [v getValue:&p size:sizeof p];
    return p;
}

- (instancetype)initWithRides:(NSArray<RARide *> *)rides cellSize:(double)meters
{
    return (RAHeatmap *)[self initWithRides:rides cellSize:meters cancellation:nil];
}

- (nullable instancetype)initWithRides:(NSArray<RARide *> *)rides cellSize:(double)meters
                          cancellation:(nullable RACancellation *)cancellation
{
    self = [super init];
    if (!self) return nil;
    _counts = [NSMutableDictionary dictionary];
    NSMutableArray *levels = [NSMutableArray array];
    for (NSUInteger l = 0; l < RAHeatLevelCount; l++) [levels addObject:[NSMutableArray array]];
    _levels = levels;
    _boundingRect = MKMapRectNull;

    NSMutableArray<NSData *> *tracks = [NSMutableArray array];
    for (RARide *r in rides) {
        NSData *t = r.stats.track;
        if ([RAHeatmap pointCountOfPackedTrack:t] >= 2) [tracks addObject:t];
    }
    _rideCount = tracks.count;
    if (tracks.count == 0) return self;
    // one grid for all the rides: the cell size at the latitude of the first point
    double lat = [RAHeatmap coordinateAtIndex:0 ofPackedTrack:tracks[0]].latitude;
    _cell = meters * MKMapPointsPerMeterAtLatitude(lat);

    // 1. the rides crossing each cell
    NSMutableArray<NSArray<NSValue *> *> *dense = [NSMutableArray array];
    for (NSData *t in tracks) {
        if (cancellation.cancelled) return nil;
        @autoreleasepool {
            NSArray<NSValue *> *points = [self densified:t];
            [dense addObject:points];
            NSMutableSet<NSNumber *> *cells = [NSMutableSet set];
            for (NSValue *v in points) {
                MKMapPoint p = RAPoint(v);
                [cells addObject:[self keyOfPoint:p]];
                _boundingRect = MKMapRectUnion(_boundingRect, MKMapRectMake(p.x, p.y, 0, 0));
            }
            for (NSNumber *k in cells) {
                NSUInteger c = _counts[k].unsignedIntegerValue + 1;
                _counts[k] = @(c);
                _maxCount = MAX(_maxCount, c);
            }
        }
    }

    // 2. each piece of track gets the level of the cell of its middle; consecutive pieces of a level are joined
    for (NSArray<NSValue *> *points in dense) {
        if (cancellation.cancelled) return nil;
        @autoreleasepool {
            NSMutableData *run = [NSMutableData data];
            NSUInteger runLevel = NSNotFound;
            for (NSUInteger i = 1; i < points.count; i++) {
                MKMapPoint a = RAPoint(points[i - 1]), b = RAPoint(points[i]);
                MKMapPoint mid = MKMapPointMake((a.x + b.x) / 2, (a.y + b.y) / 2);
                NSUInteger level = [RAHeatmap levelOfCount:_counts[[self keyOfPoint:mid]].unsignedIntegerValue];
                if (level != runLevel) {
                    [self closeRun:run level:runLevel];
                    run = [NSMutableData dataWithBytes:&a length:sizeof a];
                    runLevel = level;
                }
                [run appendBytes:&b length:sizeof b];
            }
            [self closeRun:run level:runLevel];
        }
    }
    return self;
}

- (void)closeRun:(NSData *)run level:(NSUInteger)level
{
    NSUInteger n = run.length / sizeof(MKMapPoint);
    if (level >= RAHeatLevelCount || n < 2) return;
    MKPolyline *line = [MKPolyline polylineWithPoints:(const MKMapPoint *)run.bytes count:n];
    line.title = [NSString stringWithFormat:@"%lu", (unsigned long)level];   // the renderer reads the level here
    [_levels[level] addObject:line];
}

- (NSArray<MKPolyline *> *)polylinesOfLevel:(NSUInteger)level
{
    return level < RAHeatLevelCount ? [_levels[level] copy] : @[];
}

- (NSUInteger)countAtCoordinate:(CLLocationCoordinate2D)coordinate
{
    if (_cell <= 0) return 0;
    return _counts[[self keyOfPoint:MKMapPointForCoordinate(coordinate)]].unsignedIntegerValue;
}

@end
