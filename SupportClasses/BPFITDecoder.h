//
//  BPFITDecoder.h
//  BikePlanner
//
//  Minimal decoder of Garmin FIT files (#76), only what the track import needs: `record` messages (position,
//  altitude, time) and `course_point` messages. Written from the published FIT protocol description, without the
//  FIT SDK (whose license restricts redistribution). Handles definition / data messages in both byte orders,
//  compressed timestamp headers, developer fields (skipped), unknown messages (skipped) and checks the CRCs.
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

@end

NS_ASSUME_NONNULL_END
