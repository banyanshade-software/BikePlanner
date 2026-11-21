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
- (instancetype)initWithTrace:(NSArray<CLLocation *> *)trace
                      metrics:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)metrics
                     calories:(nullable NSNumber *)calories
                     hasTimes:(BOOL)hasTimes NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (readonly, nonatomic) NSArray<CLLocation *> *trace;
@property (readonly, nonatomic) NSUInteger count;
@property (readonly, nonatomic) BOOL hasTimes;

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
