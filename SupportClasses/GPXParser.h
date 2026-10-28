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
@property (readonly, nonatomic) NSArray<NSString *> *waypointTypes; // <type> of each wpt, @"" when none
@property (readonly, nonatomic) NSString *traceSource; // what the trace is made of: @"trk", @"rte" or @"wpt"
- (NSDictionary *)brouterInfo;
@end

NS_ASSUME_NONNULL_END
