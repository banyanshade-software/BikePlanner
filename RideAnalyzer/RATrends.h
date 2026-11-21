//
//  RATrends.h
//  RideAnalyzer
//
//  The progression over time (#82, R6), from the stats of the rides (RARideStats): a measure per ride, week or
//  month, on a kind of terrain (e.g. W/bpm in the climbs of 4–8 %); totals per week, month or year; records.
//

#import <Foundation/Foundation.h>
#import "RARideStats.h"

@class RARide;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RATrendMeasure) {
    RATrendSpeed,            // km/h
    RATrendHeartRate,        // bpm
    RATrendPower,            // W (measured)
    RATrendPowerPerBeat,     // W/bpm
    RATrendSpeedPerBeat,     // km/h per 100 bpm: efficiency without a power meter
    RATrendClimbingSpeed,    // VAM, m/h
};

typedef NS_ENUM(NSInteger, RATrendGrouping) {
    RATrendPerRide,
    RATrendPerWeek,
    RATrendPerMonth,
};

typedef NS_ENUM(NSInteger, RATotalMeasure) {
    RATotalDistance,         // km
    RATotalAscent,           // m
    RATotalTime,             // h (moving)
    RATotalRides,
};

typedef NS_ENUM(NSInteger, RAPeriod) {
    RAPeriodWeek,
    RAPeriodMonth,
    RAPeriodYear,
};

/// one point of a chart: a ride or a period
@interface RATrendPoint : NSObject
@property (copy, nonatomic) NSDate *date;      // the ride's start, or the start of the period
@property (nonatomic) double value;
@property (nonatomic) NSUInteger rides;        // rides behind the point
@property (nonatomic, nullable, weak) RARide *ride; // per ride
@end

/// a record of the rides (longest, most ascent…)
@interface RARecord : NSObject
@property (copy, nonatomic) NSString *title;
@property (strong, nonatomic) RARide *ride;
@property (copy, nonatomic) NSString *value;
@end

/// at least this much moving time on the terrain for a ride to count (2 min)
extern const NSTimeInterval RATrendMinimumTime;

@interface RATrends : NSObject

/// the measure of each ride / week / month, oldest first; rides without stats, without date or with too little
/// time on the terrain are left out; a period's value is computed from the sums of its rides (time-weighted)
+ (NSArray<RATrendPoint *> *)pointsForRides:(NSArray<RARide *> *)rides measure:(RATrendMeasure)measure
                                    terrain:(RATerrain)terrain grouping:(RATrendGrouping)grouping;
/// a straight line through the points (least squares on the date): value at the first and last point; nil with
/// fewer than 2 points
+ (nullable NSArray<NSNumber *> *)trendLineOfPoints:(NSArray<RATrendPoint *> *)points;

/// totals per period, oldest first, from the first to the last ride (empty periods included, value 0)
+ (NSArray<RATrendPoint *> *)totalsForRides:(NSArray<RARide *> *)rides measure:(RATotalMeasure)measure
                                     period:(RAPeriod)period;

/// longest ride, most ascent, best average speed (rides over 50 km), longest moving time, highest max power
+ (NSArray<RARecord *> *)recordsForRides:(NSArray<RARide *> *)rides;

/// the name of a measure, a terrain, with the unit
+ (NSString *)nameOfMeasure:(RATrendMeasure)measure;
+ (NSString *)nameOfTerrain:(RATerrain)terrain;
+ (NSString *)nameOfTotal:(RATotalMeasure)measure;

@end

NS_ASSUME_NONNULL_END
