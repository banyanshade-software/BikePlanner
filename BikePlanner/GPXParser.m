//
//  GPXParser.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "GPXParser.h"

@implementation GPXParser {
    NSMutableArray<CLLocation *> *_points;
    NSString *stringEle;
    CLLocation *curloc;
}

- (nullable NSArray<CLLocation *> *)parseGPXData:(NSData *)data error:(NSError * _Nullable *)error {
    if (!data || data.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"GPXParser" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Empty GPX data"}];
        return nil;
    }

    _points = [NSMutableArray array];

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

    return [_points copy];
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
    }
}

- (void) parser:(NSXMLParser *)parser foundCharacters:(nonnull NSString *)string
{
    if (stringEle) {
        stringEle = [stringEle stringByAppendingString:string];
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
    if ([elementName isEqualToString:@"trkpt"] ||
        [elementName isEqualToString:@"wpt"] ||
        [elementName isEqualToString:@"rtept"]) {
        [_points addObject:curloc];
        curloc = nil;
    }
}


- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    // parser.parserError will be available to the caller after parse returns NO
    NSLog(@"GPX parse error: %@", parseError);
}

@end
