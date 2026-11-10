//
//  BPRoutePreview.m
//  BikePlanner
//

#import "BPRoutePreview.h"
#import "BikePlan.h"
#import "GPXParser.h"

static const CGFloat kBandHeight = 64;       // summary band, on top
static const double kMapMargin = 0.08;       // around the points, fraction of their extent
static const double kMinMapExtent = 2000;    // m: a single point or a short trace is shown in its surroundings

@implementation BPRoutePreview

- (instancetype)initWithName:(NSString *)name stages:(NSArray<NSArray<CLLocation *> *> *)stages
                   waypoints:(NSArray<CLLocation *> *)waypoints reference:(NSArray<CLLocation *> *)reference
                        pois:(NSArray<CLLocation *> *)pois length:(double)length ascent:(double)ascent
                    duration:(NSTimeInterval)duration
{
    self = [super init];
    _name = [name copy];
    _stages = stages;
    _waypoints = waypoints;
    _referenceTrace = reference;
    _pois = pois;
    _length = length;
    _ascent = ascent;
    _duration = duration;
    return self;
}

+ (NSError *)errorWithDescription:(NSString *)description
{
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

+ (double)lengthOf:(NSArray<CLLocation *> *)points
{
    double d = 0;
    for (NSUInteger i = 1; i < points.count; i++) d += [points[i] distanceFromLocation:points[i - 1]];
    return d;
}

// climbs of more than 5 m between turning points (noise of the elevations ignored); < 0 without elevations
+ (double)ascentOf:(NSArray<CLLocation *> *)points
{
    BOOL elevations = NO;
    for (CLLocation *p in points) if (p.altitude != 0) { elevations = YES; break; }
    if (!elevations) return -1;
    double up = 0, ref = points.firstObject.altitude;
    for (CLLocation *p in points) {
        if (p.altitude > ref + 5) { up += p.altitude - ref; ref = p.altitude; }
        else if (p.altitude < ref - 5) ref = p.altitude;
    }
    return up;
}

+ (nullable instancetype)previewOfFileAtURL:(NSURL *)url error:(NSError * _Nullable *)error
{
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    NSString *name = url.lastPathComponent.stringByDeletingPathExtension;
    if ([url.pathExtension.lowercaseString isEqualToString:@"bikeplan"]) {
        return [self previewOfBikePlanData:data name:name error:error];
    }
    return [self previewOfGPXData:data name:name error:error];
}

+ (nullable instancetype)previewOfBikePlanData:(NSData *)data name:(NSString *)name error:(NSError * _Nullable *)error
{
    BikePlan *plan = nil;
    @try {
        plan = [NSKeyedUnarchiver unarchivedObjectOfClass:[BikePlan class] fromData:data error:error];
    } @catch (NSException *exception) {
        plan = nil;
    }
    if (!plan) {
        if (error && !*error) *error = [self errorWithDescription:@"Not a BikePlanner document."];
        return nil;
    }
    NSMutableArray<CLLocation *> *pois = [NSMutableArray array];
    for (POILocation *poi in [plan.customPoiloc arrayByAddingObjectsFromArray:plan.poiloc ?: @[]]) {
        if (![plan isPOIExcluded:poi]) [pois addObject:poi];
    }
    NSArray *stages = plan.stagesRoutePoints;
    BrouterInfo *info = plan.brouterInfo;
    double length = info.meters > 0 ? info.meters : (info.kmlen > 0 ? info.kmlen * 1000.0 : [self lengthOf:plan.routePoints]);
    if (!stages.count) length = 0;
    double ascent = stages.count ? (info.mup > 0 ? info.mup : [self ascentOf:plan.routePoints]) : -1;
    return [[self alloc] initWithName:name stages:stages waypoints:stages.count ? @[] : (plan.waypointsLocations ?: @[])
                            reference:plan.gpxDisplayed ?: @[] pois:pois length:length ascent:ascent
                             duration:stages.count ? info.seconds : 0];
}

+ (nullable instancetype)previewOfGPXData:(NSData *)data name:(NSString *)name error:(NSError * _Nullable *)error
{
    GPXParser *parser = [[GPXParser alloc] init];
    NSArray<CLLocation *> *trace = [parser parseGPXData:data error:error];
    if (!trace) return nil;
    if (!trace.count) {
        if (error) *error = [self errorWithDescription:@"The GPX file has no point."];
        return nil;
    }
    BOOL onlyWaypoints = [parser.traceSource isEqualToString:@"wpt"];
    // a GPX exported by BikePlanner or BRouter says its length, ascent and time in a comment
    NSDictionary *info = parser.brouterInfo;
    double length = [info[@"n-track-length-m"] doubleValue];
    if (length <= 0) length = [self lengthOf:trace];
    double ascent = info[@"filtered-ascend"] ? [info[@"filtered-ascend"] doubleValue] : [self ascentOf:trace];
    NSTimeInterval duration = [info[@"n-time-seconds"] doubleValue];
    return [[self alloc] initWithName:name stages:onlyWaypoints ? @[] : @[trace] waypoints:onlyWaypoints ? trace : @[]
                            reference:@[] pois:onlyWaypoints ? @[] : parser.waypoints
                               length:onlyWaypoints ? 0 : length ascent:onlyWaypoints ? -1 : ascent
                             duration:onlyWaypoints ? 0 : duration];
}

- (NSString *)summary
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (_length > 0) {
        NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
        f.minimumFractionDigits = f.maximumFractionDigits = 1;
        [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"%@ km", @"preview: length"), [f stringFromNumber:@(_length / 1000)]]];
    }
    if (_ascent >= 0 && _length > 0) {
        [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"↑ %.0f m", @"preview: ascent"), _ascent]];
    }
    if (_duration > 0) {
        NSInteger min = ((NSInteger)_duration + 30) / 60;
        [parts addObject:min < 60 ? [NSString stringWithFormat:NSLocalizedString(@"%ld min", @"riding time < 1 h"), (long)min]
                                  : [NSString stringWithFormat:NSLocalizedString(@"%ld h %02ld", @"riding time, hours and minutes"),
                                     (long)(min / 60), (long)(min % 60)]];
    }
    if (_stages.count > 1) {
        [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"%lu stages", @"preview"), (unsigned long)_stages.count]];
    }
    if (!_stages.count && _waypoints.count) {
        [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"%lu waypoints, no route", @"preview"), (unsigned long)_waypoints.count]];
    }
    if (_pois.count) {
        [parts addObject:_pois.count == 1 ? NSLocalizedString(@"1 POI", @"preview")
                                          : [NSString stringWithFormat:NSLocalizedString(@"%lu POIs", @"preview"), (unsigned long)_pois.count]];
    }
    if (_referenceTrace.count) [parts addObject:NSLocalizedString(@"reference trace", @"preview")];
    return [parts componentsJoinedByString:@" · "];
}

#pragma mark - geometry

- (NSArray<CLLocation *> *)allPoints
{
    NSMutableArray<CLLocation *> *all = [NSMutableArray array];
    for (NSArray<CLLocation *> *s in _stages) [all addObjectsFromArray:s];
    [all addObjectsFromArray:_waypoints];
    [all addObjectsFromArray:_referenceTrace];
    return all;
}

- (MKMapRect)mapRectForArea:(NSSize)area
{
    NSArray<CLLocation *> *all = [self allPoints];
    if (!all.count || area.width <= 0 || area.height <= 0) return MKMapRectNull;
    double minX = DBL_MAX, minY = DBL_MAX, maxX = -DBL_MAX, maxY = -DBL_MAX;
    for (CLLocation *p in all) {
        MKMapPoint m = MKMapPointForCoordinate(p.coordinate);
        minX = MIN(minX, m.x); maxX = MAX(maxX, m.x);
        minY = MIN(minY, m.y); maxY = MAX(maxY, m.y);
    }
    double minExtent = kMinMapExtent * MKMapPointsPerMeterAtLatitude(all.firstObject.coordinate.latitude);
    double w = MAX(maxX - minX, minExtent) * (1 + 2 * kMapMargin);
    double h = MAX(maxY - minY, minExtent) * (1 + 2 * kMapMargin);
    double aspect = area.width / area.height;
    if (w / h < aspect) w = h * aspect; else h = w / aspect;
    return MKMapRectMake((minX + maxX - w) / 2, (minY + maxY - h) / 2, w, h);
}

- (NSRect)mapAreaForSize:(NSSize)size
{
    return NSMakeRect(0, 0, size.width, MAX(size.height - kBandHeight, 1));
}

- (NSPoint)pointForCoordinate:(CLLocationCoordinate2D)coordinate inMapArea:(NSRect)area
{
    MKMapRect r = [self mapRectForArea:area.size];
    MKMapPoint m = MKMapPointForCoordinate(coordinate);
    return NSMakePoint(NSMinX(area) + (m.x - r.origin.x) / r.size.width * NSWidth(area),
                       NSMaxY(area) - (m.y - r.origin.y) / r.size.height * NSHeight(area));  // map y goes south
}

#pragma mark - drawing

- (void)takeMapSnapshotForSize:(NSSize)size timeout:(NSTimeInterval)timeout
                    completion:(void (^)(NSImage * _Nullable mapImage))completion
{
    NSRect area = [self mapAreaForSize:size];
    MKMapRect rect = [self mapRectForArea:area.size];
    if (MKMapRectIsNull(rect)) {
        completion(nil);
        return;
    }
    MKMapSnapshotOptions *options = [[MKMapSnapshotOptions alloc] init];
    options.mapRect = rect;
    options.size = area.size;
    options.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    MKMapSnapshotter *snapshotter = [[MKMapSnapshotter alloc] initWithOptions:options];
    __block BOOL done = NO;
    void (^finish)(NSImage *) = ^(NSImage *image) {
        if (done) return;
        done = YES;
        completion(image);
    };
    [snapshotter startWithCompletionHandler:^(MKMapSnapshot *snapshot, NSError *error) {
        if (error) NSLog(@"Quick Look: no map (%@)", error.localizedDescription);
        finish(snapshot.image);
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (done) return;
        NSLog(@"Quick Look: no map after %.0f s", timeout);
        [snapshotter cancel];
        finish(nil);
    });
}

- (void)strokeLine:(NSArray<CLLocation *> *)points inArea:(NSRect)area color:(NSColor *)color width:(CGFloat)width
{
    if (points.count < 2) return;
    NSBezierPath *path = [NSBezierPath bezierPath];
    path.lineWidth = width;
    path.lineJoinStyle = NSLineJoinStyleRound;
    path.lineCapStyle = NSLineCapStyleRound;
    [path moveToPoint:[self pointForCoordinate:points[0].coordinate inMapArea:area]];
    for (NSUInteger i = 1; i < points.count; i++) {
        [path lineToPoint:[self pointForCoordinate:points[i].coordinate inMapArea:area]];
    }
    [color setStroke];
    [path stroke];
}

- (void)dotAt:(CLLocationCoordinate2D)c inArea:(NSRect)area color:(NSColor *)color radius:(CGFloat)r
{
    NSPoint p = [self pointForCoordinate:c inMapArea:area];
    NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(p.x - r, p.y - r, 2 * r, 2 * r)];
    [color setFill];
    [dot fill];
    dot.lineWidth = 1.5;
    [[NSColor whiteColor] setStroke];
    [dot stroke];
}

- (void)drawInRect:(NSRect)rect mapImage:(nullable NSImage *)mapImage
{
    // colors of the map in the app: route blue, odd stages purple (#31), reference trace orange
    NSColor *blue = [NSColor colorWithSRGBRed:0.0 green:0.45 blue:1.0 alpha:1];
    NSColor *purple = [NSColor colorWithSRGBRed:0.62 green:0.25 blue:0.85 alpha:1];
    NSColor *orange = [NSColor colorWithSRGBRed:1.0 green:0.55 blue:0.0 alpha:0.85];

    [[NSColor colorWithWhite:0.97 alpha:1] setFill];
    NSRectFill(rect);
    NSRect area = [self mapAreaForSize:rect.size];
    area = NSOffsetRect(area, NSMinX(rect), NSMinY(rect));
    if (mapImage) {
        [mapImage drawInRect:area fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    } else {
        [[NSColor colorWithSRGBRed:0.92 green:0.93 blue:0.90 alpha:1] setFill];
        NSRectFill(area);
    }

    [NSGraphicsContext saveGraphicsState];
    NSRectClip(area);
    CGFloat lw = MAX(3, NSWidth(area) / 220);
    [self strokeLine:_referenceTrace inArea:area color:orange width:lw];
    [_stages enumerateObjectsUsingBlock:^(NSArray<CLLocation *> *stage, NSUInteger i, BOOL *stop) {
        [self strokeLine:stage inArea:area color:(i % 2) ? purple : blue width:lw];
    }];
    if (_waypoints.count > 1) [self strokeLine:_waypoints inArea:area color:[NSColor colorWithWhite:0.4 alpha:0.6] width:1.5];
    for (CLLocation *p in _waypoints) [self dotAt:p.coordinate inArea:area color:blue radius:4];
    for (NSUInteger i = 1; i < _stages.count; i++) [self dotAt:_stages[i].firstObject.coordinate inArea:area color:purple radius:5];
    if (_stages.count) {
        [self dotAt:_stages.firstObject.firstObject.coordinate inArea:area color:[NSColor systemGreenColor] radius:6];
        [self dotAt:_stages.lastObject.lastObject.coordinate inArea:area color:[NSColor systemRedColor] radius:6];
    }
    [NSGraphicsContext restoreGraphicsState];

    // summary band
    NSRect band = NSMakeRect(NSMinX(rect), NSMaxY(area), NSWidth(rect), NSMaxY(rect) - NSMaxY(area));
    NSDictionary *title = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:18],
                             NSForegroundColorAttributeName: [NSColor colorWithWhite:0.1 alpha:1] };
    NSDictionary *detail = @{ NSFontAttributeName: [NSFont systemFontOfSize:14],
                              NSForegroundColorAttributeName: [NSColor colorWithWhite:0.35 alpha:1] };
    CGFloat x = NSMinX(band) + 16, w = NSWidth(band) - 32;
    [_name drawWithRect:NSMakeRect(x, NSMaxY(band) - 30, w, 22)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine attributes:title];
    [self.summary drawWithRect:NSMakeRect(x, NSMaxY(band) - 54, w, 20)
                       options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine attributes:detail];
}

- (NSBitmapImageRep *)bitmapOfSize:(NSSize)size mapImage:(nullable NSImage *)mapImage
{
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size.width
                                                                    pixelsHigh:(NSInteger)size.height bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [self drawInRect:NSMakeRect(0, 0, size.width, size.height) mapImage:mapImage];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

@end
