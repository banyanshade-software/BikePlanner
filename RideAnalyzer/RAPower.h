//
//  RAPower.h
//  RideAnalyzer
//
//  Estimated power (#82, R11), for rides without a power meter: the power the rider gives to move the bike, from the
//  speed, the slope and the acceleration, against gravity, rolling resistance and air drag:
//      P = (m g sin θ + Crr m g cos θ + m a + ½ ρ CdA v_air |v_air|) v / η,   v_air = v + headwind
//  m: rider + bike (RAEquipment, R13), Crr: the tyres mounted at the date, CdA: bike and position, ρ: from the
//  altitude and the temperature, η: drivetrain efficiency (0.97). Negative values (braking, coasting) count as 0.
//  The wind (R12) is taken into account when given (RAWind); without it, still air.
//  Estimated values are always shown as such.
//

#import <Foundation/Foundation.h>

@class RARide, RAEquipment, RARideAnalysis, RATerrainStats;

NS_ASSUME_NONNULL_BEGIN

/// the wind at a place and time (R12): speed and the direction it blows from
@interface RAWind : NSObject
@property (nonatomic) double speed;            // m/s
@property (nonatomic) double fromDirection;    // degrees from north, where it comes from (as weather reports give it)
+ (instancetype)windWithSpeed:(double)speed fromDirection:(double)direction;
/// the component against the rider (m/s; negative: tailwind) for a direction of travel (degrees from north)
- (double)headwindForHeading:(double)heading;
@end

/// the wind at a point of the track, nil: still air
typedef RAWind * _Nullable (^RAWindProvider)(NSUInteger index);

extern const double RAGravity;              // 9.81 m/s²
extern const double RADrivetrainEfficiency; // 0.97

@interface RAPowerModel : NSObject
@property (nonatomic) double mass;          // kg, rider and bike
@property (nonatomic) double crr;
@property (nonatomic) double cdA;           // m²
@property (nonatomic) double efficiency;

/// rider weight, the ride's bike (else the default bike, else 12 kg, flat bar), its tyres at the date of the ride
+ (instancetype)modelForRide:(nullable RARide *)ride equipment:(nullable RAEquipment *)equipment;
/// kg/m³; temperature in °C (15 when unknown)
+ (double)airDensityAtAltitude:(double)altitude temperature:(double)temperature;
/// degrees from north, from a point to another
+ (double)headingFromLatitude:(double)lat1 longitude:(double)lon1 toLatitude:(double)lat2 longitude:(double)lon2;

/// W at the pedals, ≥ 0; speed m/s, slope %, acceleration m/s², headwind m/s
- (double)powerAtSpeed:(double)speed slope:(double)slope acceleration:(double)acceleration
              headwind:(double)headwind airDensity:(double)density;
/// one value per point (W), RANoValue where the ride does not move or has no times
- (NSArray<NSNumber *> *)powersOfAnalysis:(RARideAnalysis *)analysis wind:(nullable RAWindProvider)wind;
/// the average power over terrain stats (from their work sums, RARideStats), NaN without moving time; ≥ 0
- (double)averagePowerOfStats:(RATerrainStats *)stats;

@end

NS_ASSUME_NONNULL_END
