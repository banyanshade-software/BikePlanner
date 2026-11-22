//
//  RARideStats.h
//  RideAnalyzer
//
//  The figures of a ride that the trends need (#82, R6), computed once from its track (RARideAnalysis) and kept
//  with the ride in the library, so the trends do not read every file again. Also per kind of terrain (slope of
//  each moving interval): descents, flat, climbs of 1–4 %, 4–8 %, more than 8 %.
//

#import <Foundation/Foundation.h>
#import "RAPower.h"

@class RARideAnalysis, RAClimb;

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
// work per kg / per m² of CdA, for the estimated power (R11, RAPowerModel: energy = m (gravity + inertia)
// + m Crr rolling + CdA air): sums over the moving intervals of g sin θ ds, g cos θ ds, a ds, ½ ρ v_air |v_air| ds
@property (nonatomic) double gravityWork;           // J/kg
@property (nonatomic) double rollingWork;           // J/kg (per unit of Crr), where the road is unknown
/// R8: where the road is known, already × the factor of its surface (RARoadMatch): J/kg per unit of the tyres' Crr
@property (nonatomic) double surfaceRollingWork;
@property (nonatomic) double inertiaWork;           // J/kg
@property (nonatomic) double airWork;               // J/m²
/// not saved: the estimated power × time of these stats, filled by the trends (R11)
@property (nonatomic) double estimatedPowerSum;     // W × s
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
/// the climbs of the ride (R7, RAClimbDetector), in order
@property (copy, nonatomic) NSArray<RAClimb *> *climbs;
/// R8: computed with the roads of the ride (its surfaces in surfaceRollingWork)
@property (nonatomic) BOOL usesRoads;
/// the whole ride
@property (readonly, nonatomic) RATerrainStats *total;
/// one per terrain (RATerrainDescent… RATerrainSteep)
- (RATerrainStats *)statsForTerrain:(RATerrain)terrain;

+ (RARideStats *)statsOfAnalysis:(RARideAnalysis *)analysis;
/// the stats of one moving interval (from the point before to point i), nil when not moving or without times
+ (nullable RATerrainStats *)statsOfIntervalAtIndex:(NSUInteger)i ofAnalysis:(RARideAnalysis *)analysis
                                               wind:(nullable RAWindProvider)wind;
/// with the wind along the ride (R12; nil: still air), for the air drag of the estimated power (R11)
+ (RARideStats *)statsOfAnalysis:(RARideAnalysis *)analysis wind:(nullable RAWindProvider)wind;
- (NSDictionary *)propertyList;
/// nil for an older version or a damaged dictionary
+ (nullable RARideStats *)statsWithPropertyList:(nullable NSDictionary *)plist;

@end

NS_ASSUME_NONNULL_END
