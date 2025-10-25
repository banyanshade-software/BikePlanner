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
};

@interface POILocation : CLLocation <NSSecureCoding> {
    PoiType_t poitype;
    //NSString *title;
    NSDictionary *info;
    BOOL selectedForExport;
}
@property (nonatomic,readonly) PoiType_t poiType;
@property (nonatomic,readonly) NSString *title;
@property (nonatomic,readonly) NSDictionary *info;
@property (nonatomic,readonly) NSString *gpxSymbol;
@property (nonatomic,readonly) NSString *gpxType;


- (instancetype) initWithLatitude:(CLLocationDegrees)latitude longitude:(CLLocationDegrees)longitude ofType:(PoiType_t)poitype info:(NSDictionary *)info;

+ (PoiType_t) poiTypeForAmenity:(NSString *)s;

@end
NS_ASSUME_NONNULL_END
