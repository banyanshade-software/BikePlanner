//
//  RARide.h
//  RideAnalyzer
//
//  One ride of the library (#82, R3): its summary figures, computed once at import from the track, and the name of
//  its original file in the library package.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RARide : NSObject

@property (copy, nonatomic) NSString *identifier;     // UUID
@property (copy, nonatomic) NSString *name;
@property (nullable, copy, nonatomic) NSDate *startDate;
@property (nonatomic) double distance;                // meters
@property (nonatomic) double ascent;                  // meters
@property (nonatomic) NSTimeInterval duration;        // seconds, first to last point (0 when the track has no times)
@property (copy, nonatomic) NSString *format;         // @"gpx", @"tcx" or @"fit"
@property (copy, nonatomic) NSString *fileName;       // original file, in the Rides folder of the library
@property (copy, nonatomic) NSString *contentHash;    // SHA-256 of the original file, hex (duplicates, R2)
@property (copy, nonatomic) NSString *deviceKey;      // which unit recorded it: @"p<product>-s<serial>", @"" unknown
@property (copy, nonatomic) NSString *deviceName;     // as the file names it (TCX Creator), @"" for FIT
@property (copy, nonatomic) NSString *sport;          // @"cycling", @"running", @"other", @"" unknown
@property (copy, nonatomic) NSString *garminActivityID; // Garmin Connect activity (R1), @"" for a local file
@property (copy, nonatomic) NSString *notes;
@property (copy, nonatomic) NSArray<NSString *> *tags;

/// @"p<product>-s<serial>": the same unit whatever the format (a FIT file has the manufacturer, a TCX file does not);
/// @"" when the file gives neither
+ (NSString *)deviceKeyForProduct:(nullable NSNumber *)product serialNumber:(nullable NSNumber *)serial;

/// km/h, 0 when the duration is unknown
@property (readonly, nonatomic) double averageSpeed;

/// a new ride, with a new identifier; figures computed from the trace (R3)
- (instancetype)initWithTrace:(NSArray<CLLocation *> *)trace name:(NSString *)name;
/// nil when the dictionary lacks the identifier or the file name
- (nullable instancetype)initWithPropertyList:(NSDictionary *)plist;
- (NSDictionary *)propertyList;

/// sum of the distances between consecutive points
+ (double)distanceOfTrace:(NSArray<CLLocation *> *)trace;
/// cumulative ascent, ignoring changes smaller than `threshold` meters (GPS / barometer noise)
+ (double)ascentOfTrace:(NSArray<CLLocation *> *)trace threshold:(double)threshold;

/// the same ride recorded twice (a file imported, then fetched from Garmin Connect, R2): same start within a minute
/// and same distance within 2 %
- (BOOL)isProbablySameRideAs:(RARide *)other;

@end

NS_ASSUME_NONNULL_END
