//
//  POILocation.m
//  BikePlanner
//
//  Created by Daniel Braun on 18/08/2025.
//

#import "POILocation.h"



@implementation POILocation

+ (PoiType_t) poiTypeForAmenity:(NSString *)s
{
    if ((0)) {
        
    } else if ([s isEqualToString:@"drinking_water"]) {
        return POI_drinking_water;
    } else if ([s isEqualToString:@"cemetery"]) {
        return POI_cemetery;
    } else if ([s isEqualToString:@"toilets"]) {
        return POI_toilets;
    } else if ([s isEqualToString:@"bicycle_repair_station"]) {
        return POI_bicycle_repair_station;
    } else {
        return POI_unknown;
    }
}


- (instancetype) initWithLatitude:(CLLocationDegrees)latitude longitude:(CLLocationDegrees)longitude ofType:(PoiType_t)_poitype info:(NSDictionary *)dic;
{
    self = [super initWithLatitude:latitude longitude:longitude];
    if (self) {
        if (!_poitype) {
            NSLog(@"unknown POItype"); // for breakpoint
        } else if (POI_drinking_water == _poitype) {
            //NSLog(@"water"); // to be removed
        }
        poitype = _poitype;
        info = dic;
    }
    return self;
}

- (PoiType_t) poiType
{
    return poitype;
}

- (NSString *) title
{
    switch (poitype) {
        default:
            return nil;
            break;
        case POI_drinking_water:        return @"water"; break;
        case POI_toilets:               return @"toilets"; break;
        case POI_bicycle_repair_station:return @"repair_station"; break;
        case POI_cemetery:              return @"cemetery"; break;
    }
}
- (NSDictionary *) info
{
    return info;
}
- (NSString *) gpxSymbol
{
    switch (poitype) {
        default:
            return nil;
            break;
        case POI_drinking_water:        return @"Drinking Water"; break;
        case POI_toilets:               return @"toilets"; break;
        case POI_bicycle_repair_station:return @"bicycle_repair_station"; break;
        case POI_cemetery:              return @"cemetery"; break;
    }
}
- (NSString *)gpxType
{
    switch (poitype) {
        default:
            return nil;
            break;
        case POI_drinking_water:        return @"WATER"; break;
        case POI_toilets:               return @"TOILET"; break;
        case POI_bicycle_repair_station:return @"SERVICE"; break;
        case POI_cemetery:              return @"CEMETERY"; break;
    }
}
/*
 AID STATION
 ALERT
 CROSSING
 DANGER
 ENERGY GEL
 FOOD
 GENERIC
 INFO
 OBSTACLE
 SERVICE
 SHARP CURVE
 SHOWER
 TOILET
 TRANSITION
 WATER

 */

+ (BOOL) supportsSecureCoding
{
    return YES;
}


- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeInt:poitype forKey:@"poitype"];
    [coder encodeObject:info forKey:@"info"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) return self;
    poitype = [coder decodeIntForKey:@"poitype"];
    info = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"info"];
    return self;
}

@end
