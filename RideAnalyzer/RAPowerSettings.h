//
//  RAPowerSettings.h
//  RideAnalyzer
//
//  The parameters of the estimated power (#82, R11, #94; owner's request 2026-11-22: configurable, which also shows
//  how much the estimate takes into account). Each has a default, bounds, a unit and an explanation; the values the
//  user changed are kept in the equipment of the library (RAEquipment.powerParameters, undoable). The surface
//  factors of the rolling resistance are apart (RASurfaceFactors). Most parameters apply at once (the stats keep
//  the work of each force); `freewheelingIsZero` changes the stats: they are computed again.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// keys
extern NSString *const RAPowerEfficiency;          // drivetrain efficiency, 0.97
extern NSString *const RAPowerWheelInertia;        // kg, 1.5
extern NSString *const RAPowerRollingScale;        // × every Crr (calibration), 1
extern NSString *const RAPowerPressureExponent;    // Crr ∝ (test pressure / pressure)^x, 0.4
extern NSString *const RAPowerPressureMinFactor;   // 0.7
extern NSString *const RAPowerPressureMaxFactor;   // 1.5
extern NSString *const RAPowerSpeedSmoothing;      // s, 5
extern NSString *const RAPowerAccelerationWindow;  // s, 6
extern NSString *const RAPowerFreewheelingIsZero;  // 1: cadence 0 → 0 W
extern NSString *const RAPowerRiderWeight;         // kg when nothing is known, 75
extern NSString *const RAPowerCdAUpright, *const RAPowerCdAFlatBar, *const RAPowerCdAHoods, *const RAPowerCdADrops;
extern NSString *const RAPowerWeightRoad, *const RAPowerWeightHybrid, *const RAPowerWeightGravel,
                     *const RAPowerWeightMountain, *const RAPowerWeightElectric;

@interface RAPowerSettings : NSObject

/// the defaults, replaced by the overrides (bounded); never nil values
+ (instancetype)settingsWithOverrides:(nullable NSDictionary<NSString *, NSNumber *> *)overrides;
+ (instancetype)defaultSettings;

@property (readonly, nonatomic) double efficiency, wheelInertia, rollingScale;
@property (readonly, nonatomic) double pressureExponent, pressureMinFactor, pressureMaxFactor;
@property (readonly, nonatomic) double speedSmoothing, accelerationWindow;
@property (readonly, nonatomic) BOOL freewheelingIsZero;
@property (readonly, nonatomic) double riderWeight;
/// by RARidingPosition (upright, flat bar, hoods, drops)
- (double)cdAForPosition:(NSInteger)position;
/// by RABikeKind (road, hybrid, gravel, mountain, electric)
- (double)weightForKind:(NSInteger)kind;
- (double)valueForParameter:(NSString *)key;

// the description of the parameters (the settings window)
/// in the order shown, by group
+ (NSArray<NSString *> *)groups;
+ (NSArray<NSString *> *)parametersOfGroup:(NSString *)group;
+ (NSString *)nameOfGroup:(NSString *)group;
+ (NSString *)nameOfParameter:(NSString *)key;
+ (NSString *)unitOfParameter:(NSString *)key;
+ (NSString *)explanationOfParameter:(NSString *)key;
+ (double)defaultOfParameter:(NSString *)key;
+ (double)minimumOfParameter:(NSString *)key;
+ (double)maximumOfParameter:(NSString *)key;
/// a yes / no parameter (a checkbox)
+ (BOOL)isSwitch:(NSString *)key;
/// a change needs the stats of the rides again (Analyse Again is done by itself)
+ (BOOL)changesStats:(NSString *)key;
+ (NSArray<NSString *> *)allParameters;

@end

NS_ASSUME_NONNULL_END
