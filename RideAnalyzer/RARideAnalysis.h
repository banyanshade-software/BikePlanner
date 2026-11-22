//
//  RARideAnalysis.h
//  RideAnalyzer
//
//  What the detail of a ride shows (#82, R4): its points with the distance and time from the start, speed, slope,
//  heart rate, cadence, power and temperature, and the summary (moving time, pauses, maxima, averages, calories).
//  Computed from the original file of the ride, on demand (not stored).
//  And the colors of the track on the map (by speed, slope, heart rate or power).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

/// a value that the file does not give
extern const double RANoValue;
static inline BOOL RAHasValue(double v) { return !isnan(v); }

@interface RARideAnalysis : NSObject

/// nil when the data is not a track with at least 2 points
+ (nullable instancetype)analysisOfData:(NSData *)data;
/// only the points from trimStart to trimEnd seconds after the first one (trimEnd 0: to the end; RARide trim);
/// the calories of the file are dropped when something is cut
+ (nullable instancetype)analysisOfData:(NSData *)data trimStart:(NSTimeInterval)trimStart trimEnd:(NSTimeInterval)trimEnd;
/// the indexes of a trace kept by a trim (all of them without times)
+ (NSRange)rangeOfTrace:(NSArray<CLLocation *> *)trace trimStart:(NSTimeInterval)trimStart trimEnd:(NSTimeInterval)trimEnd;
- (instancetype)initWithTrace:(NSArray<CLLocation *> *)trace
                      metrics:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)metrics
                     calories:(nullable NSNumber *)calories
                     hasTimes:(BOOL)hasTimes NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (readonly, nonatomic) NSArray<CLLocation *> *trace;
@property (readonly, nonatomic) NSUInteger count;
@property (readonly, nonatomic) BOOL hasTimes;
/// the index in the file's trace of the first point (a trim cuts the start; R8 road matches are by file index)
@property (nonatomic) NSUInteger firstFileIndex;
/// R8: the surface category of the road of each point (RARoadMatch, RASurfaceFactors), @"" where unknown; nil: no
/// road match (the bike's usual roads then)
@property (copy, nonatomic, nullable) NSArray<NSString *> *surfaceCategories;
/// #94: the moments without pedalling (cadence 0) do no work in the stats (YES; the library's parameter)
@property (nonatomic) BOOL freewheelingIsZero;

// one value per point (RANoValue when missing)
@property (readonly, nonatomic) NSArray<NSNumber *> *distances;   // meters from the start
@property (readonly, nonatomic) NSArray<NSNumber *> *elapsed;     // seconds from the start (0 without times)
@property (readonly, nonatomic) NSArray<NSNumber *> *altitudes;   // meters
@property (readonly, nonatomic) NSArray<NSNumber *> *speeds;      // km/h: recorded, else from distance / time
@property (readonly, nonatomic) NSArray<NSNumber *> *slopes;      // %, over about 100 m
@property (readonly, nonatomic) NSArray<NSNumber *> *heartRates;  // bpm
@property (readonly, nonatomic) NSArray<NSNumber *> *cadences;    // rpm
@property (readonly, nonatomic) NSArray<NSNumber *> *powers;      // W
@property (readonly, nonatomic) NSArray<NSNumber *> *temperatures;// °C
/// which channels the file has
@property (readonly, nonatomic) BOOL hasHeartRate, hasCadence, hasPower, hasTemperature;

// summary
@property (readonly, nonatomic) double distance;          // meters
@property (readonly, nonatomic) double ascent;            // meters (3 m threshold, as RARide)
@property (readonly, nonatomic) NSTimeInterval elapsedTime;
/// time moving: intervals faster than 3 km/h; pauses: the rest
@property (readonly, nonatomic) NSTimeInterval movingTime;
@property (readonly, nonatomic) NSTimeInterval pauseTime;
@property (readonly, nonatomic) double averageSpeed;      // km/h, over the moving time
@property (readonly, nonatomic) double maxSpeed;          // km/h
@property (readonly, nonatomic) double averageHeartRate, maxHeartRate;   // RANoValue without heart rate
@property (readonly, nonatomic) double averagePower, maxPower;           // while moving
@property (readonly, nonatomic) double averageCadence;    // while pedaling (> 0)
@property (readonly, nonatomic) double averageTemperature;
@property (readonly, nonatomic, nullable) NSNumber *calories;

/// the powers are estimated (R11), not measured
@property (readonly, nonatomic) BOOL powerIsEstimated;
/// for a ride without power meter: these estimated powers (RAPowerModel, one per point) become its powers (curves,
/// colors, averages), marked as estimated. Ignored when the file has measured powers.
- (void)useEstimatedPowers:(NSArray<NSNumber *> *)powers;

/// the point nearest to a distance from the start
- (NSUInteger)indexAtDistance:(double)distance;

@end

typedef NS_ENUM(NSInteger, RAColorMode) {
    RAColorBySpeed,
    RAColorBySlope,
    RAColorByHeartRate,
    RAColorByPower,
};

/// the colors of the track: each point gets a class (0 = lowest), a class has a color and a legend
@interface RATrackColoring : NSObject
/// classes of the points; -1 for a point without value (drawn in gray)
+ (NSArray<NSNumber *> *)classesOfAnalysis:(RARideAnalysis *)analysis mode:(RAColorMode)mode;
/// the legend of each class ("< 18", "18–24"…), lowest first
+ (NSArray<NSString *> *)legendForMode:(RAColorMode)mode analysis:(RARideAnalysis *)analysis;
/// a mode the ride can be colored by (heart rate and power need the data)
+ (BOOL)analysis:(RARideAnalysis *)analysis supportsMode:(RAColorMode)mode;
@end

NS_ASSUME_NONNULL_END
