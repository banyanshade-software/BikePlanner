//
//  BPFITDecoder.h
//  BikePlanner
//
//  Minimal decoder of Garmin FIT files (#76), only what the track import needs: `record` messages (position,
//  altitude, time) and `course_point` messages; for Ride Analyzer (#82) also `file_id` (device) and the sport of
//  `sport` / `session`. Written from the published FIT protocol description, without the FIT SDK (whose license
//  restricts redistribution). Handles definition / data messages in both byte orders, compressed timestamp headers,
//  developer fields (skipped), unknown messages (skipped) and checks the CRCs.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPFITDecoder : NSObject

/// ".FIT" signature after a 12- or 14-byte header
+ (BOOL)isFITData:(NSData *)data;
/// NO (and an error) for a bad header or CRC, a truncated file or an undefined local message type
- (BOOL)decodeData:(NSData *)data error:(NSError * _Nullable *)error;

/// records that have a position, in file order; altitude 0 when the file has none
@property (readonly, nonatomic) NSArray<CLLocation *> *records;
/// course points that have a position
@property (readonly, nonatomic) NSArray<CLLocation *> *coursePoints;
/// FIT `course_point` type of each course point (0xFF: none)
@property (readonly, nonatomic) NSArray<NSNumber *> *coursePointTypes;
/// name of each course point, @"" when none
@property (readonly, nonatomic) NSArray<NSString *> *coursePointNames;

// file_id and sport (#82, Ride Analyzer): which device recorded the file, and what kind of activity
/// every record has a timestamp
@property (readonly, nonatomic) BOOL hasTimes;
/// FIT file type of the first file_id (4: activity, 6: course…); nil when the file has no file_id, 0xFF when unset
@property (readonly, nonatomic, nullable) NSNumber *fileType;
/// FIT manufacturer (1: Garmin…), product (for Garmin: garmin_product), serial number, creation time; nil when absent
@property (readonly, nonatomic, nullable) NSNumber *manufacturer;
@property (readonly, nonatomic, nullable) NSNumber *product;
@property (readonly, nonatomic, nullable) NSNumber *serialNumber;
@property (readonly, nonatomic, nullable) NSDate *timeCreated;
/// FIT sport of the first sport or session message (2: cycling…); nil when absent
@property (readonly, nonatomic, nullable) NSNumber *sport;
/// for each record of `records`: @"hr" (bpm), @"cadence" (rpm), @"speed" (m/s), @"power" (W), @"temperature" (°C),
/// those the record has
@property (readonly, nonatomic) NSArray<NSDictionary<NSString *, NSNumber *> *> *recordMetrics;
/// total_calories of the sessions (kcal); nil when absent
@property (readonly, nonatomic, nullable) NSNumber *calories;

@end

NS_ASSUME_NONNULL_END
