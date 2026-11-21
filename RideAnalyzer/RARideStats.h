//
//  RARideStats.h
//  RideAnalyzer
//
//  The figures of a ride that the trends need (#82, R6), computed once from its track (RARideAnalysis) and kept
//  with the ride in the library, so the trends do not read every file again. Also per kind of terrain (slope of
//  each moving interval): descents, flat, climbs of 1–4 %, 4–8 %, more than 8 %.
//

#import <Foundation/Foundation.h>

@class RARideAnalysis;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RATerrain) {
    RATerrainAll = -1,
    RATerrainDescent = 0,   // < -1 %
    RATerrainFlat,          // -1 to 1 %
    RATerrainGentle,        // 1 to 4 %
    RATerrainClimb,         // 4 to 8 %
    RATerrainSteep,         // > 8 %
};
extern const NSInteger RATerrainCount;
/// the terrain of a slope (%)
RATerrain RATerrainOfSlope(double slope);

/// moving time, distance, ascent, heart rate and power over some intervals
@interface RATerrainStats : NSObject
@property (nonatomic) NSTimeInterval time;          // moving
@property (nonatomic) double distance;              // m
@property (nonatomic) double ascent;                // m (sum of the rises of the intervals)
@property (nonatomic) double heartRateSum;          // bpm × s
@property (nonatomic) NSTimeInterval heartRateTime; // s with a heart rate
@property (nonatomic) double powerSum;              // W × s
@property (nonatomic) NSTimeInterval powerTime;     // s with a power
/// NaN when there is no time / no value
@property (readonly, nonatomic) double speed;       // km/h
@property (readonly, nonatomic) double heartRate;   // bpm
@property (readonly, nonatomic) double power;       // W
@property (readonly, nonatomic) double climbingSpeed; // VAM, m/h
- (void)add:(RATerrainStats *)other;
- (NSDictionary *)propertyList;
+ (RATerrainStats *)statsWithPropertyList:(nullable NSDictionary *)plist;
@end

/// raise when the way the stats are computed changes: older stats are computed again
extern const NSInteger RARideStatsVersion;

@interface RARideStats : NSObject

@property (nonatomic) NSInteger version;

@property (nonatomic) NSTimeInterval movingTime;
@property (nonatomic) double maxSpeed;          // km/h
@property (nonatomic) double maxHeartRate;      // bpm, NaN without
@property (nonatomic) double maxPower;          // W, NaN without
@property (nonatomic) double calories;          // kcal, NaN without
/// the track, simplified to about 8 m and packed (RAHeatmap): the map of all rides (R10) without reading the files
@property (copy, nonatomic) NSData *track;
/// the whole ride
@property (readonly, nonatomic) RATerrainStats *total;
/// one per terrain (RATerrainDescent… RATerrainSteep)
- (RATerrainStats *)statsForTerrain:(RATerrain)terrain;

+ (RARideStats *)statsOfAnalysis:(RARideAnalysis *)analysis;
- (NSDictionary *)propertyList;
/// nil for an older version or a damaged dictionary
+ (nullable RARideStats *)statsWithPropertyList:(nullable NSDictionary *)plist;

@end

NS_ASSUME_NONNULL_END
