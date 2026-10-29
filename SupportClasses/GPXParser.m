//
//  GPXParser.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "GPXParser.h"

@implementation GPXParser {
    NSMutableArray<CLLocation *> *_points;     // trkpt
    NSMutableArray<CLLocation *> *_rtePoints;  // rtept
    NSMutableArray<CLLocation *> *_wptPoints;  // wpt: kept out of the trace (#28)
    NSMutableArray<NSString *> *_wptTypes;     // <type> of each wpt, @"" when none
    NSString *stringEle;
    NSString *stringType;                      // text of <type>, inside a wpt
    NSString *curType;
    BOOL inWpt;
    CLLocation *curloc;
    NSMutableDictionary<NSString *, NSString *> *brouterInfo;
}

- (nullable NSArray<CLLocation *> *)parseGPXData:(NSData *)data error:(NSError * _Nullable *)error {
    if (!data || data.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"GPXParser" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Empty GPX data"}];
        return nil;
    }

    _points = [NSMutableArray array];
    _rtePoints = [NSMutableArray array];
    _wptPoints = [NSMutableArray array];
    _wptTypes = [NSMutableArray array];
    inWpt = NO;

    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = self;
    parser.shouldProcessNamespaces = NO;
    parser.shouldReportNamespacePrefixes = NO;
    parser.shouldResolveExternalEntities = NO;

    BOOL ok = [parser parse];
    if (!ok) {
        if (error) *error = parser.parserError ?: [NSError errorWithDomain:@"GPXParser" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Unknown parse error"}];
        return nil;
    }

    if (_points.count) return [_points copy];
    if (_rtePoints.count) return [_rtePoints copy];
    return [_wptPoints copy];
}

- (NSString *)traceSource
{
    if (_points.count) return @"trk";
    if (_rtePoints.count) return @"rte";
    return @"wpt";
}

- (NSArray<NSString *> *)waypointTypes
{
    return [_wptTypes copy] ?: @[];
}

- (NSArray<CLLocation *> *)waypoints
{
    return [_wptPoints copy] ?: @[];
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
    attributes:(NSDictionary<NSString *, NSString *> *)attributeDict
{
    // Handle track points, waypoints and route points
    //    <trkpt lon="0.491229" lat="44.193329"><ele>140.25</ele></trkpt>
    if ([elementName isEqualToString:@"ele"]) {
        stringEle = @"";
    } else if (inWpt && [elementName isEqualToString:@"type"]) {
        stringType = @"";
    } else if ([elementName isEqualToString:@"trkpt"] ||
        [elementName isEqualToString:@"wpt"] ||
        [elementName isEqualToString:@"rtept"]) {

        NSString *latS = attributeDict[@"lat"];
        NSString *lonS = attributeDict[@"lon"];
        if (latS.length > 0 && lonS.length > 0) {
            CLLocationDegrees lat = [latS doubleValue];
            CLLocationDegrees lon = [lonS doubleValue];
            curloc = [[CLLocation alloc] initWithLatitude:lat longitude:lon];
        }
        inWpt = [elementName isEqualToString:@"wpt"];
        curType = nil;
    }
}

- (void) parser:(NSXMLParser *)parser foundCharacters:(nonnull NSString *)string
{
    if (stringEle) {
        stringEle = [stringEle stringByAppendingString:string];
    }
    if (stringType) {
        stringType = [stringType stringByAppendingString:string];
    }
}
- (void)parser:(NSXMLParser *)parser didEndElement:(nonnull NSString *)elementName namespaceURI:(nullable NSString *)namespaceURI qualifiedName:(nullable NSString *)qName
{
    // Handle track points, waypoints and route points
    //    <trkpt lon="0.491229" lat="44.193329"><ele>140.25</ele></trkpt>
    if ([elementName isEqualToString:@"ele"]) {
        NSString *s = stringEle;
        stringEle = nil;
        CLLocation *nloc = [[CLLocation alloc]initWithCoordinate:curloc.coordinate
                                                        altitude:[s doubleValue]
                                              horizontalAccuracy:kCLLocationAccuracyBest verticalAccuracy:kCLLocationAccuracyBest timestamp:[NSDate date]];
        curloc = nloc;

    }
    if (stringType && [elementName isEqualToString:@"type"]) {
        curType = [stringType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        stringType = nil;
    }
    if ([elementName isEqualToString:@"wpt"]) inWpt = NO;
    if (curloc) {
        if ([elementName isEqualToString:@"trkpt"]) {
            [_points addObject:curloc];
            curloc = nil;
        } else if ([elementName isEqualToString:@"rtept"]) {
            [_rtePoints addObject:curloc];
            curloc = nil;
        } else if ([elementName isEqualToString:@"wpt"]) {
            [_wptPoints addObject:curloc];
            [_wptTypes addObject:curType ?: @""];
            curloc = nil;
        }
    }
}


// This gets called for <!-- ... --> blocks
- (void)parser:(NSXMLParser *)parser foundComment:(NSString *)comment
{
    // Example comment: " track-length = 124597 filtered ascend = 236 ..."
    if ([comment containsString:@"track-length"]) {
        [self parseBRouterComment:comment];
    }
}


- (void)parseBRouterComment:(NSString *)comment
{
    if (!brouterInfo) brouterInfo = [NSMutableDictionary dictionary];

    NSString *trimmed = [comment stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // key: letters/digits/dash, possibly multiple words separated by spaces
    // value: non-greedy until next " key=" pattern or end (via lookahead)
    NSString *pattern =
    @"\\b([A-Za-z0-9][A-Za-z0-9-]*(?:\\s+[A-Za-z0-9][A-Za-z0-9-]*)*)\\s*=\\s*(.+?)(?=\\s+[A-Za-z0-9][A-Za-z0-9-]*(?:\\s+[A-Za-z0-9][A-Za-z0-9-]*)*\\s*=|$)";

    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                       options:0
                                                                         error:&err];
    if (err) {
        NSLog(@"Regex error: %@", err);
        return;
    }

    NSArray<NSTextCheckingResult *> *matches =
        [re matchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];

    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 3) continue;
        NSString *rawKey = [trimmed substringWithRange:[m rangeAtIndex:1]];
        NSString *rawVal = [trimmed substringWithRange:[m rangeAtIndex:2]];

        NSString *key = [[rawKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] copy];
        NSString *val = [[rawVal stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] copy];

        // Optional: normalize key (spaces -> dash) to have consistent dictionary keys
        NSString *normKey = [[key lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@"-"];

        brouterInfo[normKey] = val;
    }

    // Optional: also compute normalized numeric fields for convenience
    [self populateNormalizedBRouterInfo];
}


- (void)populateNormalizedBRouterInfo
{
    if (!brouterInfo) return;

    //  track-length = 14994 filtered ascend = 168 plain-ascend = 27 cost=26496 energy=.1kwh time=57m 15s
    // time=6h 10m 11s  -> time-seconds
    NSString *timeStr = brouterInfo[@"time"];
    NSNumber *tSeconds = [self secondsFromTimeString:timeStr];
    if (tSeconds) brouterInfo[@"n-time-seconds"] = tSeconds.stringValue;

    // track-length=124597 -> meters (already meters typically)
    NSString *lenStr = brouterInfo[@"track-length"];
    NSNumber *meters = [self numberFromString:lenStr];
    if (meters) brouterInfo[@"n-track-length-m"] = meters.stringValue;

    // energy=.6kwh -> watt-hours
    NSString *energyStr = brouterInfo[@"energy"];
    NSNumber *wh = [self wattHoursFromEnergyString:energyStr];
    if (wh) brouterInfo[@"n-energy-wh"] = wh.stringValue;
}

- (NSNumber *)secondsFromTimeString:(NSString *)s {
    if (s.length == 0) return nil;
    NSRegularExpression *re =
      [NSRegularExpression regularExpressionWithPattern:@"(?:(\\d+)\\s*h)?\\s*(?:(\\d+)\\s*m)?\\s*(?:(\\d+)\\s*s)?"
                                                options:NSRegularExpressionCaseInsensitive
                                                  error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m) return nil;
    NSInteger h = 0, mnt = 0, sec = 0;
    if ([m rangeAtIndex:1].location != NSNotFound) h   = [[s substringWithRange:[m rangeAtIndex:1]] integerValue];
    if ([m rangeAtIndex:2].location != NSNotFound) mnt = [[s substringWithRange:[m rangeAtIndex:2]] integerValue];
    if ([m rangeAtIndex:3].location != NSNotFound) sec = [[s substringWithRange:[m rangeAtIndex:3]] integerValue];
    return @(h*3600 + mnt*60 + sec);
}

- (NSNumber *)numberFromString:(NSString *)s {
    if (s.length == 0) return nil;
    NSScanner *sc = [NSScanner scannerWithString:s];
    double v = 0.0;
    if ([sc scanDouble:&v]) return @(v);
    return nil;
}

- (NSNumber *)wattHoursFromEnergyString:(NSString *)s {
    if (s.length == 0) return nil;
    NSString *lower = [s lowercaseString];
    NSScanner *sc = [NSScanner scannerWithString:lower];
    double v = 0.0;
    if (![sc scanDouble:&v]) return nil;
    if ([lower containsString:@"kwh"]) return @(v * 1000.0);
    if ([lower containsString:@"wh"])  return @(v);
    return nil; // unknown unit
}



- (NSDictionary *) brouterInfo
{
    return brouterInfo;
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    // parser.parserError will be available to the caller after parse returns NO
    NSLog(@"GPX parse error: %@", parseError);
}

static NSString *BPXMLEscaped(NSString *s)
{
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

// minimal GPX 1.1 track with elevations (route points from BRouter all have one)
+ (NSData *)gpxDataForPoints:(NSArray<CLLocation *> *)points name:(NSString *)name comment:(nullable NSString *)comment
{
    NSMutableString *xml = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    if (comment.length) [xml appendFormat:@"<!-- %@ -->\n", [comment stringByReplacingOccurrencesOfString:@"--" withString:@"- -"]];
    [xml appendString:@"<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" creator=\"BikePlanner\" version=\"1.1\">\n"];
    [xml appendFormat:@" <trk>\n  <name>%@</name>\n  <trkseg>\n", BPXMLEscaped(name)];
    for (CLLocation *p in points) {
        [xml appendFormat:@"   <trkpt lat=\"%.6f\" lon=\"%.6f\"><ele>%.2f</ele></trkpt>\n",
                          p.coordinate.latitude, p.coordinate.longitude, p.altitude];
    }
    [xml appendString:@"  </trkseg>\n </trk>\n</gpx>\n"];
    return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

@end
