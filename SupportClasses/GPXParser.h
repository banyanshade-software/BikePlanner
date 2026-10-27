//
//  GPXParser.h
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GPXParser : NSObject <NSXMLParserDelegate>

// returns the trace: the track points (trkpt), else the route points (rtept), else the waypoints (wpt)
- (nullable NSArray<CLLocation *> *)parseGPXData:(NSData *)data error:(NSError * _Nullable *)error;
@property (readonly, nonatomic) NSArray<CLLocation *> *waypoints; // wpt of the last parsed file (e.g. POIs)
- (NSDictionary *)brouterInfo;
@end

NS_ASSUME_NONNULL_END
