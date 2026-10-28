//
//  POILocation.h
//  BikePlanner
//
//  Created by Daniel Braun on 18/08/2025.
//

#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int, PoiType_t) {
    POI_unknown,
    POI_drinking_water,
    POI_toilets,
    POI_bicycle_repair_station,
    POI_cemetery,
    POI_warning,
    // types of custom POIs (#3); appended: archived values of the types above must not change
    POI_food,
    POI_shelter,
    POI_viewpoint,
    POI_campsite,
    POI_store,
    POI_info,
    POI_generic,
};

@interface POILocation : CLLocation <NSSecureCoding> {
    PoiType_t poitype;
    //NSString *title;
    NSDictionary *info;
    BOOL selectedForExport;
    BOOL userAdded;
}
@property (nonatomic,readonly) PoiType_t poiType;
@property (nonatomic,readonly,nullable) NSString *title;     // custom POI: its name, else its type name
@property (nonatomic,readonly,nullable) NSString *name;      // custom POI: name given by the user (#3), nil if none
@property (nonatomic,readonly) NSDictionary *info;
@property (nonatomic,readonly) NSString *gpxSymbol;
@property (nonatomic,readonly) NSString *gpxType;
// stable identity (fetched POIs are re-created at each route change): OSM id + position, or position for custom POIs
@property (nonatomic,readonly) NSString *poiKey;


- (instancetype) initWithLatitude:(CLLocationDegrees)latitude longitude:(CLLocationDegrees)longitude ofType:(PoiType_t)poitype info:(NSDictionary *)info custom:(BOOL)useradded;

+ (PoiType_t) poiTypeForAmenity:(NSString *)s;
// types offered for custom POIs, default first (#3)
+ (NSArray<NSNumber *> *) customPoiTypes;
+ (NSString *) displayNameForType:(PoiType_t)type;

@end
NS_ASSUME_NONNULL_END
