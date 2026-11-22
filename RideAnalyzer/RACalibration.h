//
//  RACalibration.h
//  RideAnalyzer
//
//  Calibration of the estimated power (#82, R11, #94) on the rides that have a power meter: per bike, the Crr
//  multiplier and the CdA that make the estimate best match the measured power. From the stats (no file read):
//  for each ride and terrain (flat, gentle, climb, steep — not the descents, where the measured power is mostly 0
//  while the model gives energy back), η × measured energy − m (gravity + inertia work) = k × (the model's rolling
//  energy) + CdA × (air work), solved by least squares for k and CdA.
//

#import <Foundation/Foundation.h>

@class RARide, RAEquipment;

NS_ASSUME_NONNULL_BEGIN

@interface RACalibrationResult : NSObject
@property (copy, nonatomic) NSString *bikeID;      // @"" rides without a bike
@property (copy, nonatomic) NSString *bikeName;
@property (nonatomic) NSUInteger rideCount, sampleCount;
/// × the current rolling resistance (multiply RAPowerRollingScale by it)
@property (nonatomic) double rollingFactor;
@property (nonatomic) double cdA;                  // m²
/// the average power estimated before / after, and measured, over the samples (W)
@property (nonatomic) double estimatedBefore, estimatedAfter, measured;
/// the error of the estimate per sample (W, root mean square) before / after
@property (nonatomic) double errorBefore, errorAfter;
/// NO when the data does not determine both (too few samples, all at the same speed…): nothing to apply
@property (nonatomic) BOOL valid;
@property (copy, nonatomic) NSString *note;
@end

@interface RACalibration : NSObject
/// one result per bike that has rides with a power meter among these rides (a sample: a terrain of a ride with at
/// least 2 minutes of measured power)
+ (NSArray<RACalibrationResult *> *)calibrateRides:(NSArray<RARide *> *)rides equipment:(RAEquipment *)equipment;
@end

NS_ASSUME_NONNULL_END
