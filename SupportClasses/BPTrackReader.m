//
//  BPTrackReader.m
//  BikePlanner
//
//  Reading the tracks to import: GPX and TCX (#76).
//

#import "BPTrackReader.h"
#import "GPXParser.h"
#import "BPFITDecoder.h"

static NSString *const BPTrackReaderErrorDomain = @"BPTrackReader";

@interface BPTrackReader () <NSXMLParserDelegate>
@end

@implementation BPTrackReader {
    NSMutableArray<CLLocation *> *_tcxTrace;
    NSMutableArray<CLLocation *> *_tcxPoints;
    NSMutableArray<NSString *> *_tcxTypes;
    NSMutableArray<NSString *> *_tcxNames;
    // TCX parsing state
    NSMutableArray<NSString *> *_elements;     // open elements (local names)
    NSMutableString *_text;                    // text of the current element
    NSMutableDictionary<NSString *, NSString *> *_cur; // fields of the current Trackpoint / CoursePoint
    NSISO8601DateFormatter *_dateFormatter, *_fractionalDateFormatter;
    NSUInteger _tcxTimed;                      // trackpoints of the trace that have a Time
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *_tcxMetrics;
    double _tcxCalories;
    BOOL _tcxHasCalories;
}

/// FIT sport (2: cycling, 1: running) or TCX Activity Sport (Biking, Running, Other) → @"cycling", @"running",
/// @"other"; nil when unknown
+ (nullable NSString *)sportNameForFIT:(nullable NSNumber *)fit tcx:(nullable NSString *)tcx
{
    if (fit != nil) {
        switch (fit.unsignedIntegerValue) {
            case 2: return @"cycling";
            case 1: return @"running";
            default: return @"other";
        }
    }
    if (tcx.length) {
        NSString *t = tcx.lowercaseString;
        return [t isEqualToString:@"biking"] ? @"cycling" : [t isEqualToString:@"running"] ? @"running" : @"other";
    }
    return nil;
}

+ (NSArray<NSDictionary<NSString *, NSNumber *> *> *)emptyMetricsForCount:(NSUInteger)count
{
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [a addObject:@{}];
    return a;
}

+ (BOOL)isTCXData:(NSData *)data
{
    // the root element, after the XML declaration and comments: look at the beginning of the file
    NSData *head = [data subdataWithRange:NSMakeRange(0, MIN(data.length, (NSUInteger)4096))];
    NSString *s = [[NSString alloc] initWithData:head encoding:NSUTF8StringEncoding]
               ?: [[NSString alloc] initWithData:head encoding:NSISOLatin1StringEncoding];
    return [s rangeOfString:@"<TrainingCenterDatabase"].location != NSNotFound
        || [s rangeOfString:@":TrainingCenterDatabase"].location != NSNotFound;
}

+ (BOOL)isFITData:(NSData *)data
{
    return [BPFITDecoder isFITData:data];
}

+ (NSArray<UTType *> *)importContentTypes
{
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *ext in @[ @"gpx", @"tcx", @"fit" ]) {
        UTType *t = [UTType typeWithFilenameExtension:ext];
        if (t) [types addObject:t];
    }
    return types;
}

+ (nullable BPTrackReader *)readerWithContentsOfURL:(NSURL *)url error:(NSError * _Nullable *)error
{
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    return [self readerWithData:data error:error];
}

+ (nullable BPTrackReader *)readerWithData:(NSData *)data error:(NSError * _Nullable *)error
{
    if (!data.length) {
        if (error) *error = [NSError errorWithDomain:BPTrackReaderErrorDomain code:1
                                            userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedString(@"The file is empty.", @"") }];
        return nil;
    }
    BPTrackReader *r = [[BPTrackReader alloc] init];
    BOOL ok = [self isFITData:data] ? [r parseFIT:data error:error]
            : [self isTCXData:data] ? [r parseTCX:data error:error] : [r parseGPX:data error:error];
    return ok ? r : nil;
}

#pragma mark - GPX

- (BOOL)parseGPX:(NSData *)data error:(NSError * _Nullable *)error
{
    GPXParser *p = [[GPXParser alloc] init];
    NSArray<CLLocation *> *trace = [p parseGPXData:data error:error];
    if (!trace) return NO;
    _format = @"gpx";
    _hasTimes = p.hasTimes;
    _trace = trace;
    _metrics = [BPTrackReader emptyMetricsForCount:trace.count];
    _traceSource = p.traceSource;
    _waypoints = p.waypoints;
    _waypointTypes = p.waypointTypes;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    [p.waypointNames enumerateObjectsUsingBlock:^(NSString *name, NSUInteger i, BOOL *stop) {
        [names addObject:[name caseInsensitiveCompare:p.waypointTypes[i]] == NSOrderedSame ? @"" : name];
    }];
    _waypointNames = names;
    return YES;
}

#pragma mark - FIT

// GPX type of the custom POI for a FIT course_point type; nil: a turn cue (left, right, straight, forks, slight /
// sharp turns, U-turn), not a POI; @"": the default custom POI type
+ (nullable NSString *)gpxTypeForFITCoursePointType:(NSUInteger)type
{
    switch (type) {
        case 1:  return @"OVERLOOK"; // summit
        case 3:  return @"WATER";
        case 4:  return @"FOOD";
        case 5:  return @"DANGER";
        case 9:  return @"INFO";     // first aid
        case 6: case 7: case 8:      // left, right, straight
        case 16: case 17: case 18:   // left / right / middle fork
        case 19: case 20: case 21: case 22: case 23: // slight / sharp left / right, U-turn
            return nil;
        default: return @"";
    }
}

- (BOOL)parseFIT:(NSData *)data error:(NSError * _Nullable *)error
{
    BPFITDecoder *d = [[BPFITDecoder alloc] init];
    if (![d decodeData:data error:error]) return NO;
    _format = @"fit";
    _trace = d.records;
    _metrics = d.recordMetrics.count == d.records.count ? d.recordMetrics : [BPTrackReader emptyMetricsForCount:d.records.count];
    _calories = d.calories;
    _deviceAscent = d.totalAscent;
    _hasTimes = d.hasTimes;
    _deviceManufacturer = d.manufacturer;
    _deviceProduct = d.product;
    _deviceSerialNumber = d.serialNumber;
    _sport = [BPTrackReader sportNameForFIT:d.sport tcx:nil];
    _traceSource = @"trk";
    NSMutableArray<CLLocation *> *points = [NSMutableArray array];
    NSMutableArray<NSString *> *types = [NSMutableArray array], *names = [NSMutableArray array];
    [d.coursePoints enumerateObjectsUsingBlock:^(CLLocation *p, NSUInteger i, BOOL *stop) {
        NSString *type = [BPTrackReader gpxTypeForFITCoursePointType:d.coursePointTypes[i].unsignedIntegerValue];
        if (!type) return;
        [points addObject:p];
        [types addObject:type];
        [names addObject:d.coursePointNames[i]];
    }];
    _waypoints = points;
    _waypointTypes = types;
    _waypointNames = names;
    return YES;
}

#pragma mark - TCX

// GPX type of the custom POI for a TCX CoursePoint PointType (TCX v2 schema); nil: a turn cue, not a POI;
// @"": the default custom POI type (Generic, Valley, climb categories, Sprint, unknown)
+ (nullable NSString *)gpxTypeForTCXPointType:(NSString *)pointType
{
    NSString *t = pointType.lowercaseString;
    if ([@[ @"left", @"right", @"straight" ] containsObject:t]) return nil;
    NSDictionary *map = @{ @"water": @"WATER", @"food": @"FOOD", @"danger": @"DANGER", @"summit": @"OVERLOOK",
                           @"first aid": @"INFO" };
    return map[t] ?: @"";
}

- (BOOL)parseTCX:(NSData *)data error:(NSError * _Nullable *)error
{
    _tcxTrace = [NSMutableArray array];
    _tcxPoints = [NSMutableArray array];
    _tcxTypes = [NSMutableArray array];
    _tcxNames = [NSMutableArray array];
    _elements = [NSMutableArray array];
    _dateFormatter = [[NSISO8601DateFormatter alloc] init];
    _fractionalDateFormatter = [[NSISO8601DateFormatter alloc] init];
    _fractionalDateFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    _tcxTimed = 0;
    _tcxMetrics = [NSMutableArray array];
    _tcxCalories = 0;
    _tcxHasCalories = NO;

    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = self;
    parser.shouldProcessNamespaces = YES; // element names without prefix (extensions use ns3:…)
    parser.shouldResolveExternalEntities = NO;
    if (![parser parse]) {
        if (error) *error = parser.parserError ?: [NSError errorWithDomain:BPTrackReaderErrorDomain code:2
                                                                  userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedString(@"The file could not be read.", @"") }];
        return NO;
    }
    _format = @"tcx";
    _trace = [_tcxTrace copy];
    _metrics = [_tcxMetrics copy];
    _calories = _tcxHasCalories ? @(_tcxCalories) : nil;
    _hasTimes = _tcxTrace.count > 0 && _tcxTimed == _tcxTrace.count;
    _traceSource = @"trk";
    _waypoints = [_tcxPoints copy];
    _waypointTypes = [_tcxTypes copy];
    _waypointNames = [_tcxNames copy];
    _elements = nil;
    _cur = nil;
    return YES;
}

- (nullable CLLocation *)locationFromFields:(NSDictionary<NSString *, NSString *> *)f
{
    NSString *lat = f[@"LatitudeDegrees"], *lon = f[@"LongitudeDegrees"];
    if (!lat.length || !lon.length) return nil; // no position: a pause or an indoor activity
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat.doubleValue, lon.doubleValue);
    if (!CLLocationCoordinate2DIsValid(c)) return nil;
    NSString *timeString = f[@"Time"];
    NSDate *time = timeString.length ? ([_dateFormatter dateFromString:timeString] ?: [_fractionalDateFormatter dateFromString:timeString]) : nil;
    return [[CLLocation alloc] initWithCoordinate:c altitude:f[@"AltitudeMeters"].doubleValue
                               horizontalAccuracy:kCLLocationAccuracyBest verticalAccuracy:kCLLocationAccuracyBest
                                        timestamp:time ?: [NSDate date]];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(nullable NSString *)namespaceURI
 qualifiedName:(nullable NSString *)qName attributes:(NSDictionary<NSString *, NSString *> *)attributeDict
{
    [_elements addObject:elementName];
    _text = [NSMutableString string];
    if ([elementName isEqualToString:@"Trackpoint"] || [elementName isEqualToString:@"CoursePoint"]) {
        _cur = [NSMutableDictionary dictionary];
    } else if ([elementName isEqualToString:@"Activity"] && !_sport) {
        _sport = [BPTrackReader sportNameForFIT:nil tcx:attributeDict[@"Sport"]];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    [_text appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(nullable NSString *)namespaceURI
 qualifiedName:(nullable NSString *)qName
{
    NSString *parent = _elements.count >= 2 ? _elements[_elements.count - 2] : nil;
    NSString *text = [_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (_cur) {
        if ([elementName isEqualToString:@"Trackpoint"]) {
            CLLocation *loc = [self locationFromFields:_cur];
            if (loc) {
                [_tcxTrace addObject:loc];
                if (_cur[@"Time"].length) _tcxTimed++;
                // heart rate, cadence, speed (m/s), power: as in the FIT records
                NSMutableDictionary<NSString *, NSNumber *> *m = [NSMutableDictionary dictionary];
                NSDictionary<NSString *, NSString *> *keys = @{ @"HeartRate": @"hr", @"Cadence": @"cadence",
                                                                @"Speed": @"speed", @"Watts": @"power" };
                [keys enumerateKeysAndObjectsUsingBlock:^(NSString *field, NSString *key, BOOL *stop) {
                    NSString *v = self->_cur[field];
                    if (v.length) m[key] = @(v.doubleValue);
                }];
                [_tcxMetrics addObject:m];
            }
            _cur = nil;
        } else if ([elementName isEqualToString:@"CoursePoint"]) {
            CLLocation *loc = [self locationFromFields:_cur];
            NSString *pointType = _cur[@"PointType"] ?: @"";
            NSString *type = [BPTrackReader gpxTypeForTCXPointType:pointType];
            if (loc && type) {
                NSString *name = _cur[@"Name"] ?: @"";
                if ([name caseInsensitiveCompare:pointType] == NSOrderedSame) name = @"";
                [_tcxPoints addObject:loc];
                [_tcxTypes addObject:type];
                [_tcxNames addObject:name];
            }
            _cur = nil;
        } else if ([parent isEqualToString:@"Trackpoint"] || [parent isEqualToString:@"CoursePoint"]
                   || [parent isEqualToString:@"Position"]) {
            // direct fields only (not those of the extensions, e.g. HeartRateBpm/Value)
            _cur[elementName] = text;
        } else if ([parent isEqualToString:@"HeartRateBpm"] && [elementName isEqualToString:@"Value"]) {
            _cur[@"HeartRate"] = text;
        } else if ([parent isEqualToString:@"TPX"]
                   && ([elementName isEqualToString:@"Speed"] || [elementName isEqualToString:@"Watts"])) {
            _cur[elementName] = text; // ActivityExtension v2
        }
    } else if ([parent isEqualToString:@"Lap"] && [elementName isEqualToString:@"Calories"] && text.length) {
        _tcxCalories += text.doubleValue;
        _tcxHasCalories = YES;
    } else if ([parent isEqualToString:@"Creator"] && [_elements containsObject:@"Activity"]) {
        // the device that recorded the activity (#82): Name, UnitId (serial number), ProductID
        if ([elementName isEqualToString:@"Name"] && text.length && !_deviceName) _deviceName = text;
        if ([elementName isEqualToString:@"UnitId"] && text.longLongValue > 0) _deviceSerialNumber = @(text.longLongValue);
        if ([elementName isEqualToString:@"ProductID"] && text.longLongValue > 0) _deviceProduct = @(text.longLongValue);
    }
    [_elements removeLastObject];
    _text = [NSMutableString string];
}

@end
