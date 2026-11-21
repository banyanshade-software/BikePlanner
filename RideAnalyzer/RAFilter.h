//
//  RAFilter.h
//  RideAnalyzer
//
//  Which rides to show (#82, R3): combinable criteria, used by the list and later by the statistics, the climbs,
//  the map of all rides and the zones (R6, R7, R10, R14). A filter can be saved in the library with a name.
//  Every criterion is optional; an empty filter keeps every ride.
//

#import <Foundation/Foundation.h>

@class RARide;

NS_ASSUME_NONNULL_BEGIN

@interface RAFilter : NSObject <NSCopying>

/// words searched in the name, the notes and the tags (all the words, any order, case and accents ignored)
@property (copy, nonatomic) NSString *text;
/// rides that start on or after / before the end of these days (local time); a ride without date never matches a
/// period
@property (copy, nonatomic, nullable) NSDate *fromDay;
@property (copy, nonatomic, nullable) NSDate *toDay;
/// device keys (RARide.deviceKey, @"" = unknown device); empty: any device
@property (copy, nonatomic) NSSet<NSString *> *deviceKeys;
/// meters; 0: no limit
@property (nonatomic) double minDistance;
@property (nonatomic) double maxDistance;
@property (nonatomic) double minAscent;
/// rides that have at least one of these tags; empty: any
@property (copy, nonatomic) NSSet<NSString *> *tags;

@property (readonly, nonatomic, getter=isEmpty) BOOL empty;
- (BOOL)matchesRide:(RARide *)ride;
- (NSArray<RARide *> *)filteredRides:(NSArray<RARide *> *)rides;

/// the same filter with another search text
- (RAFilter *)filterWithText:(NSString *)text;

/// saved in the library
- (NSDictionary *)propertyList;
+ (RAFilter *)filterWithPropertyList:(nullable NSDictionary *)plist;

/// a short description of the criteria, for the filter bar ("2026 · Edge · > 30 km"); device names from the block
- (NSString *)summaryWithDeviceLabel:(NSString * (^)(NSString *deviceKey))deviceLabel;

@end

/// a filter saved in the library, with its name
@interface RASavedFilter : NSObject
@property (copy, nonatomic) NSString *identifier;
@property (copy, nonatomic) NSString *name;
@property (copy, nonatomic) RAFilter *filter;
- (instancetype)initWithName:(NSString *)name filter:(RAFilter *)filter;
- (NSDictionary *)propertyList;
+ (nullable RASavedFilter *)savedFilterWithPropertyList:(nullable NSDictionary *)plist;
@end

NS_ASSUME_NONNULL_END
