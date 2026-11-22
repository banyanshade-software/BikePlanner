//
//  RAPower.h
//  RideAnalyzer
//
//  Estimated power (#82, R11), for rides without a power meter: the power the rider gives to move the bike, from the
//  speed, the slope and the acceleration, against gravity, rolling resistance and air drag:
//      P = (m g sin θ + Crr m g cos θ + (m + m_w) a + ½ ρ CdA v_air |v_air|) v / η,   v_air = v + headwind
//  m: rider + bike (RAEquipment, R13); m_w: the wheels' inertia (1.5 kg, in the acceleration only); Crr: the tyres
//  mounted at the date (tyre database, pressure) × the surface factor of the bike; CdA: bike and position; ρ: from
//  the altitude and the temperature; η: drivetrain efficiency (0.97). Speed: the sensor's when the file has it,
//  smoothed over 5 s; slope over 100 m. Negative values count as 0, and so do the moments without pedalling when
//  the file has the cadence (cadence 0: freewheeling).
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
extern const double RAWheelInertia;         // 1.5 kg
extern NSString *const RAPowerGravity, *const RAPowerRolling, *const RAPowerAir, *const RAPowerInertia,
                *const RAPowerLosses, *const RAPowerTotal;

@interface RAPowerModel : NSObject <NSCopying>
@property (nonatomic) double mass;          // kg, rider and bike
@property (nonatomic) double crr;           // tyres × the bike's usual roads (where the road is unknown)
/// the tyres alone (R8: × the factor of each road's surface where it is known, RARideAnalysis.surfaceCategories)
@property (nonatomic) double tyreCrr;
/// the factor of each surface category (RASurfaceFactors, with the library's changes)
@property (copy, nonatomic) NSDictionary<NSString *, NSNumber *> *surfaceFactors;
/// the Crr on a surface category (@"": the bike's usual roads, crr)
- (double)crrOnSurface:(NSString *)category;
@property (nonatomic) double cdA;           // m²
@property (nonatomic) double wheelInertia;  // kg, equivalent mass of the wheels (1.5)
@property (nonatomic) double efficiency;
/// s: the speed is averaged over this time, the acceleration measured over that one (#94 settings: 5, 6)
@property (nonatomic) double speedSmoothing, accelerationWindow;
/// cadence 0 → 0 W (YES)
@property (nonatomic) BOOL freewheelingIsZero;

/// rider weight, the ride's bike (else the default bike, else 12 kg, flat bar), its tyres at the date of the ride,
/// the library's parameters (RAEquipment.powerParameters, RAPowerSettings)
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

// #94: what the estimate is made of, and what moves it
/// average W over the moving time of the stats, per force at the wheel — RAPowerGravity, RAPowerRolling, RAPowerAir,
/// RAPowerInertia (each can be negative: a descent gives back) —, RAPowerLosses (drivetrain) and RAPowerTotal
/// (averagePowerOfStats); nil without moving time
- (nullable NSDictionary<NSString *, NSNumber *> *)breakdownOfStats:(RATerrainStats *)stats;
/// the change of the average power (W) for a change of each parameter: [name, change of the parameter as text, ΔW]
- (NSArray<NSArray *> *)sensitivityOfStats:(RATerrainStats *)stats;

@end

NS_ASSUME_NONNULL_END
