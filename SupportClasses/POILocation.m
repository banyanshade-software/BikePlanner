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
    } else if ([s isEqualToString:@"cemetery"] || [s isEqualToString:@"grave_yard"]) {
        return POI_cemetery;
    } else if ([s isEqualToString:@"toilets"]) {
        return POI_toilets;
    } else if ([s isEqualToString:@"bicycle_repair_station"]) {
        return POI_bicycle_repair_station;
    } else if ([s isEqualToString:@"warning"]) {
        return POI_warning;
    } else {
        return POI_unknown;
    }
}


- (instancetype) initWithLatitude:(CLLocationDegrees)latitude longitude:(CLLocationDegrees)longitude ofType:(PoiType_t)_poitype info:(NSDictionary *)dic custom:(BOOL)_useradded
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
        userAdded = _useradded;
    }
    return self;
}

- (PoiType_t) poiType
{
    return poitype;
}

+ (NSArray<NSNumber *> *) customPoiTypes
{
    return @[ @(POI_warning), @(POI_drinking_water), @(POI_food), @(POI_toilets), @(POI_bicycle_repair_station),
              @(POI_shelter), @(POI_viewpoint), @(POI_campsite), @(POI_store), @(POI_info), @(POI_generic) ];
}

+ (NSString *) displayNameForType:(PoiType_t)type
{
    switch (type) {
        case POI_warning:                return NSLocalizedString(@"Danger", @"custom POI type");
        case POI_drinking_water:         return NSLocalizedString(@"Water", @"custom POI type");
        case POI_food:                   return NSLocalizedString(@"Food", @"custom POI type");
        case POI_toilets:                return NSLocalizedString(@"Toilets", @"custom POI type");
        case POI_bicycle_repair_station: return NSLocalizedString(@"Bike repair", @"custom POI type");
        case POI_shelter:                return NSLocalizedString(@"Shelter", @"custom POI type");
        case POI_viewpoint:              return NSLocalizedString(@"Viewpoint", @"custom POI type");
        case POI_campsite:               return NSLocalizedString(@"Campsite", @"custom POI type");
        case POI_store:                  return NSLocalizedString(@"Store", @"custom POI type");
        case POI_info:                   return NSLocalizedString(@"Information", @"custom POI type");
        case POI_generic:                return NSLocalizedString(@"Other", @"custom POI type");
        case POI_cemetery:               return NSLocalizedString(@"Cemetery", @"custom POI type");
        case POI_unknown:                return NSLocalizedString(@"POI", @"custom POI type");
    }
    return NSLocalizedString(@"POI", @"custom POI type");
}

- (nullable NSString *) name
{
    NSString *n = userAdded ? info[@"name"] : nil;
    return n.length ? n : nil;
}

- (NSString *) title
{
    if (userAdded) return self.name ?: [POILocation displayNameForType:poitype]; // #3
    switch (poitype) {
        default:
            return nil;
            break;
        case POI_drinking_water:
            return NSLocalizedString(@"water", "water (poi title)");
            break;
        case POI_toilets:
            return NSLocalizedString(@"toilets", "toilets (poi title)");
            break;
        case POI_bicycle_repair_station:
            return NSLocalizedString(@"repair station", "bike repair (poi title)");
            break;
        case POI_cemetery:
            return NSLocalizedString(@"cemetery", "cemetery (poi title");
            break;
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
        case POI_warning:               return @"..." ; break;
        case POI_food:                  return @"Restaurant"; break;
        case POI_shelter:               return @"Building"; break;
        case POI_viewpoint:             return @"Scenic Area"; break;
        case POI_campsite:              return @"Campground"; break;
        case POI_store:                 return @"Shopping Center"; break;
        case POI_info:                  return @"Information"; break;
        case POI_generic:               return @"Flag, Blue"; break;
    }
}
- (NSString *) poiKey
{
    NSString *pos = [NSString stringWithFormat:@"%.6f,%.6f", self.coordinate.latitude, self.coordinate.longitude];
    id osmid = info[@"id"];
    if (osmid) return [NSString stringWithFormat:@"osm:%@@%@", osmid, pos];
    return [@"custom:" stringByAppendingString:pos];
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
        case POI_cemetery:              return @"GENERIC"; break;
        case POI_warning:               return @"DANGER"; break;
        case POI_food:                  return @"FOOD"; break;
        case POI_shelter:               return @"SHELTER"; break;
        case POI_viewpoint:             return @"OVERLOOK"; break;
        case POI_campsite:              return @"CAMPSITE"; break;
        case POI_store:                 return @"STORE"; break;
        case POI_info:                  return @"INFO"; break;
        case POI_generic:               return @"GENERIC"; break;
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
    [coder encodeBool:userAdded forKey:@"custom"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) return self;
    poitype = [coder decodeIntForKey:@"poitype"];
    info = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"info"];
    // documents saved before #3 did not store it: custom POIs are the ones without OSM id
    userAdded = [coder containsValueForKey:@"custom"] ? [coder decodeBoolForKey:@"custom"] : (info[@"id"] == nil);
    return self;
}

@end
