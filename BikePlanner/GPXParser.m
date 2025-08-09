//
//  GPXParser.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "GPXParser.h"

@implementation GPXParser {
    NSMutableArray<CLLocation *> *_points;
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
    if ([elementName isEqualToString:@"trkpt"] ||
        [elementName isEqualToString:@"wpt"] ||
        [elementName isEqualToString:@"rtept"]) {

        NSString *latS = attributeDict[@"lat"];
        NSString *lonS = attributeDict[@"lon"];
        if (latS.length > 0 && lonS.length > 0) {
            CLLocationDegrees lat = [latS doubleValue];
            CLLocationDegrees lon = [lonS doubleValue];
            CLLocation *loc = [[CLLocation alloc] initWithLatitude:lat longitude:lon];
            [_points addObject:loc];
        }
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    // parser.parserError will be available to the caller after parse returns NO
    NSLog(@"GPX parse error: %@", parseError);
}

@end
