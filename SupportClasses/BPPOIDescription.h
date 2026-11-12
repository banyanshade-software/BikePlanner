//
//  BPPOIDescription.h
//  BikePlanner
//
//  What the POI callout shows (#72), computed from the type and the info of a POI (OSM tags + "id" for a fetched
//  POI, "name" for a custom one): no UI, unit-tested.
//

#import <Foundation/Foundation.h>
#import "POILocation.h"

NS_ASSUME_NONNULL_BEGIN

@interface BPPOIDescription : NSObject

- (instancetype)initWithType:(PoiType_t)type info:(NSDictionary *)info custom:(BOOL)custom NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (readonly, nonatomic) BOOL custom;
/// OSM "name" tag, or the name given to a custom POI; nil if none
@property (readonly, nonatomic, nullable) NSString *name;
/// localized type name ("Water", "Danger"…)
@property (readonly, nonatomic) NSString *typeName;
/// useful OSM tags translated, in display order: { label, value }
@property (readonly, nonatomic) NSArray<NSArray<NSString *> *> *rows;
/// every OSM tag, sorted by key: { key, value }; empty for a custom POI
@property (readonly, nonatomic) NSArray<NSArray<NSString *> *> *allTags;
/// the element on openstreetmap.org (node, or way for a cemetery area); nil for a custom POI
@property (readonly, nonatomic, nullable) NSURL *osmURL;

/// "km 12.4 (stage 2) · 180 m off route"; stage < 0: no stage (route not cut in stages)
+ (NSString *)positionStringForDistance:(double)alongMeters offset:(double)offsetMeters stage:(NSInteger)stage;
/// the link of a tag value that is a web address (http/https, or starting with "www."), nil otherwise
+ (nullable NSURL *)linkURLForValue:(NSString *)value;
/// "44.123456, 0.543210"
+ (NSString *)coordinateString:(CLLocationCoordinate2D)coord;

@end

NS_ASSUME_NONNULL_END
