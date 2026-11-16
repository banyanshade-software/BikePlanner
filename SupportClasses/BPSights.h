//
//  BPSights.h
//  BikePlanner
//
//  Sights near the route (#81): the categories chosen in the Info section (culture, viewpoints…), their OpenStreetMap
//  tags, the Overpass clause that fetches them and the classification of the answer. No UI (also in the Quick Look
//  extension, with BikePlan).
//

#import <Foundation/Foundation.h>
#import "POILocation.h"

NS_ASSUME_NONNULL_BEGIN

/// radius of the search of sights around the route, meters
extern const NSUInteger BPSightsSearchRadius;

@interface BPSights : NSObject

/// culture, viewpoint, church, nature, food, accommodation, bikeshop (in the order of the menu)
+ (NSArray<NSString *> *)allCategories;
+ (NSString *)localizedNameOfCategory:(NSString *)category;
/// "Culture, Viewpoints", "None"
+ (NSString *)summaryOfCategories:(NSArray<NSString *> *)categories;
/// known categories only, without duplicates, in the order of allCategories
+ (NSArray<NSString *> *)normalizedCategories:(nullable NSArray<NSString *> *)categories;

/// one Overpass clause around a point for the selected categories (a key/value regex on their tags); nil if none
+ (nullable NSString *)overpassClauseForCategories:(NSArray<NSString *> *)categories radius:(NSUInteger)radius
                                          latitude:(double)latitude longitude:(double)longitude;
/// the category of a sight type (POI_culture → culture…); nil for another type
+ (nullable NSString *)categoryOfType:(PoiType_t)type;
/// the POI type of an element with these tags if it is a sight of one of the categories, else POI_unknown;
/// *category: its category
+ (PoiType_t)typeForTags:(NSDictionary<NSString *, NSString *> *)tags categories:(NSArray<NSString *> *)categories
                category:(NSString * _Nullable * _Nullable)category;

@end

NS_ASSUME_NONNULL_END
