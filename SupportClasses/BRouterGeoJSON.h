//
//  BRouterGeoJSON.h
//  BikePlanner
//
//  Route returned by BRouter with format=geojson (#53): points, statistics, and the distance by road class and
//  surface, from the way tags of properties.messages (the GPX output has no way tags).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

// road classes (stored in documents: do not rename)
extern NSString *const BPRoadCycleway;   // highway=cycleway
extern NSString *const BPRoadPath;       // path, footway, bridleway, pedestrian, steps
extern NSString *const BPRoadTrack;      // track
extern NSString *const BPRoadSmall;      // unclassified, residential, living_street, service, road
extern NSString *const BPRoadTertiary;
extern NSString *const BPRoadSecondary;
extern NSString *const BPRoadPrimary;    // primary, trunk (and links)
extern NSString *const BPRoadOther;      // ferries, anything else
// surface classes
extern NSString *const BPSurfacePaved;
extern NSString *const BPSurfaceUnpaved;
extern NSString *const BPSurfaceUnknown;

@interface BRouterGeoJSON : NSObject

+ (nullable instancetype)routeWithData:(NSData *)data error:(NSError **)error;

@property (readonly) NSArray<CLLocation *> *points;
/// same keys as -[GPXParser brouterInfo]: "n-track-length-m", "filtered-ascend", "n-time-seconds" (strings)
@property (readonly) NSDictionary<NSString *, NSString *> *info;
/// meters by road class / by surface class
@property (readonly) NSDictionary<NSString *, NSNumber *> *roadStats;
@property (readonly) NSDictionary<NSString *, NSNumber *> *surfaceStats;

+ (NSString *)roadClassForTags:(NSDictionary<NSString *, NSString *> *)tags;
+ (NSString *)surfaceClassForTags:(NSDictionary<NSString *, NSString *> *)tags;

@end

NS_ASSUME_NONNULL_END
