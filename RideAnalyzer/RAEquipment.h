//
//  RAEquipment.h
//  RideAnalyzer
//
//  Equipment of a library (#82, R13): the rider's weight, the bikes and their parts (tyres, chain, brake pads…).
//  A part is mounted on a bike over a time range (from a date, to a date or still mounted); a ride uses the parts
//  mounted on its bike at its date. Used by the estimated power (R11): mass, rolling resistance (Crr of the tyres)
//  and air drag (CdA of the bike and position). Bikes can come from the Garmin Connect gear.
//  Saved in the library; changed through -[RALibraryDocument changeEquipment:actionName:] (undoable).
//

#import <Foundation/Foundation.h>

@class RARide;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RABikeKind) {
    RABikeRoad,
    RABikeHybrid,       // city / trekking / fitness (e.g. Giant Rapid: flat bar)
    RABikeGravel,
    RABikeMountain,
    RABikeElectric,
};

typedef NS_ENUM(NSInteger, RARidingPosition) {
    RAPositionUpright,  // city bike
    RAPositionFlatBar,  // hybrid, mountain bike
    RAPositionHoods,    // road bike, hands on the hoods
    RAPositionDrops,    // road bike, in the drops
};

typedef NS_ENUM(NSInteger, RAPartKind) {
    RAPartTyre,
    RAPartChain,
    RAPartBrakePads,
    RAPartCassette,
    RAPartOther,
};

typedef NS_ENUM(NSInteger, RAWheel) {
    RAWheelFront,
    RAWheelRear,
    RAWheelBoth,        // a pair, same tyre front and rear
};

/// the usual road surface of a bike: the Crr of the tyres (measured on a smooth drum) is multiplied by a factor
typedef NS_ENUM(NSInteger, RASurface) {
    RASurfaceSmoothAsphalt,     // × 1.15
    RASurfaceAsphalt,           // × 1.3, the default
    RASurfaceRoughAsphalt,      // × 1.5 (chip seal, worn roads, cobbles here and there)
    RASurfaceMixedGravel,       // × 1.8 (some gravel, cycle paths)
    RASurfaceGravel,            // × 2.5
};

@interface RABike : NSObject <NSCopying>
@property (copy, nonatomic) NSString *identifier;
@property (copy, nonatomic) NSString *name;
@property (nonatomic) RABikeKind kind;
@property (nonatomic) double weight;            // kg, with bottles, bags… (0: unknown → 12 kg)
@property (nonatomic) RARidingPosition position;
/// m²; 0: from the position (rider included)
@property (nonatomic) double cdA;
@property (nonatomic) RASurface surface;
/// the model, as the user writes it (e.g. "Giant Rapid 4"), @"" none
@property (copy, nonatomic) NSString *model;
/// Garmin Connect gear (uuid), @"" for a bike created here
@property (copy, nonatomic) NSString *garminGearID;
+ (NSString *)nameOfKind:(RABikeKind)kind;
+ (NSString *)nameOfPosition:(RARidingPosition)position;
/// typical CdA (m²) of a rider in that position
+ (double)defaultCdAForPosition:(RARidingPosition)position;
/// the position of a kind of bike by default
+ (RARidingPosition)defaultPositionForKind:(RABikeKind)kind;
+ (NSString *)nameOfSurface:(RASurface)surface;
/// the default factor of the Crr on that surface (drum tests are on smooth steel; the sources: RASurfaceFactors.m);
/// the factor used is the library's (-[RAEquipment factorOfBikeSurface:])
+ (double)rollingFactorOfSurface:(RASurface)surface;
/// the surface category (RASurfaceFactors) of a bike's usual roads
+ (NSString *)categoryOfSurface:(RASurface)surface;
/// a usual weight of a kind of bike (kg), when the user has not weighed it
+ (double)typicalWeightForKind:(RABikeKind)kind;
@property (readonly, nonatomic) double effectiveCdA;
@property (readonly, nonatomic) double effectiveWeight;
- (NSDictionary *)propertyList;
+ (nullable RABike *)bikeWithPropertyList:(nullable id)plist;
@end

/// a part on a bike from a day to a day (nil: still mounted)
@interface RAMounting : NSObject <NSCopying>
@property (copy, nonatomic) NSString *bikeID;
@property (copy, nonatomic) NSDate *from;
@property (copy, nonatomic, nullable) NSDate *to;
/// the date falls in [from, end of the day `to`]
- (BOOL)containsDate:(NSDate *)date;
- (NSDictionary *)propertyList;
+ (nullable RAMounting *)mountingWithPropertyList:(nullable id)plist;
@end

@interface RAPart : NSObject <NSCopying>
@property (copy, nonatomic) NSString *identifier;
@property (copy, nonatomic) NSString *name;
@property (nonatomic) RAPartKind kind;
@property (copy, nonatomic) NSString *model;    // e.g. "Continental Grand Prix 5000"
@property (nonatomic) double width;             // mm, tyres (0: unknown)
@property (nonatomic) RAWheel wheel;            // tyres
/// rolling resistance; 0: the default for the model and width (and pressure)
@property (nonatomic) double crr;
/// the tyre's usual pressure (bar), 0: unknown (the database's test pressure)
@property (nonatomic) double pressure;
/// km after which the part is worn (0: none)
@property (nonatomic) double wearLimit;
/// the wear warning was shown (once per part)
@property (nonatomic) BOOL wearWarned;
@property (copy, nonatomic) NSArray<RAMounting *> *mountings;
/// for a tyre: the Crr of its model in the tyre database (RATyreDatabase, nearest width), else an estimate from its
/// width (≤ 28 mm 0.0040, ≤ 35 0.0045, ≤ 45 0.0055, more 0.0070; 0.0050 when unknown)
+ (double)defaultCrrForModel:(NSString *)model width:(double)width;
+ (NSString *)nameOfKind:(RAPartKind)kind;
+ (NSString *)nameOfWheel:(RAWheel)wheel;
/// its Crr, else the default — the database's value corrected for the pressure (Crr ∝ (test pressure / pressure)^0.4,
/// within ×0.7…×1.5); 0 for a part that is not a tyre
@property (readonly, nonatomic) double effectiveCrr;
/// where the default Crr comes from (tyre, test pressure, source; or "estimate from the width")
@property (readonly, nonatomic) NSString *crrSource;
/// the bike it is on at that date, nil when not mounted
- (nullable NSString *)bikeIDAtDate:(NSDate *)date;
- (NSDictionary *)propertyList;
+ (nullable RAPart *)partWithPropertyList:(nullable id)plist;
@end

/// a weighing of the rider (R11: from Garmin Connect)
@interface RAWeighing : NSObject
@property (copy, nonatomic) NSDate *date;
@property (nonatomic) double kilograms;
+ (instancetype)weighingOnDate:(NSDate *)date kilograms:(double)kilograms;
- (NSDictionary *)propertyList;
+ (nullable RAWeighing *)weighingWithPropertyList:(nullable id)plist;
@end

@interface RAEquipment : NSObject <NSCopying>
@property (nonatomic) double riderWeight;       // kg, entered, 0: unknown (→ 75 kg)
/// the rider's weighings (Garmin Connect, R11), oldest first
@property (copy, nonatomic) NSArray<RAWeighing *> *weighings;
/// the weight of each ride is the weighing of its date (YES by default), else the entered weight
@property (nonatomic) BOOL usesWeighings;
/// the rider's weight for a ride on that date: the last weighing on or before it (the first one for an older ride),
/// when usesWeighings and there are some; else the entered weight; else 75 kg
- (double)riderWeightAtDate:(nullable NSDate *)date;
/// adds weighings, one per day (a newer value of the same day replaces it); YES if something changed
- (BOOL)mergeWeighings:(NSArray<RAWeighing *> *)weighings;
/// R8 / R11: the factors of the rolling resistance by surface category (RASurfaceFactors) the user changed, @{} none
@property (copy, nonatomic) NSDictionary<NSString *, NSNumber *> *surfaceFactors;
/// every category with the factor used (defaults and changes)
@property (readonly, nonatomic) NSDictionary<NSString *, NSNumber *> *effectiveSurfaceFactors;
- (double)factorOfSurfaceCategory:(NSString *)category;
/// the factor of a bike's usual roads, with the library's changes
- (double)factorOfBikeSurface:(RASurface)surface;
@property (copy, nonatomic) NSString *defaultBikeID;   // @"" none
@property (copy, nonatomic) NSArray<RABike *> *bikes;
@property (copy, nonatomic) NSArray<RAPart *> *parts;

- (nullable RABike *)bikeWithID:(NSString *)identifier;
- (nullable RAPart *)partWithID:(NSString *)identifier;
/// the bike of a ride: its own, else the default one
- (nullable RABike *)bikeOfRide:(RARide *)ride;
/// the parts mounted on a bike at a date
- (NSArray<RAPart *> *)partsOfBike:(NSString *)bikeID atDate:(NSDate *)date;
/// the rolling resistance of the tyres of a bike at a date: front 40 %, rear 60 % (a pair counts for both); 0.005
/// when no tyre is known. Not multiplied by the surface factor (RAPowerModel does)
- (double)crrOfBike:(NSString *)bikeID atDate:(NSDate *)date;
@property (readonly, nonatomic) double effectiveRiderWeight;

/// meters ridden: by a bike, by a part (rides on its bike while mounted)
- (double)distanceOfBike:(NSString *)bikeID rides:(NSArray<RARide *> *)rides;
- (double)distanceOfPart:(RAPart *)part rides:(NSArray<RARide *> *)rides;
/// parts over their wear limit
- (NSArray<RAPart *> *)wornPartsWithRides:(NSArray<RARide *> *)rides;

// the tyres of a bike, as the bike sheet shows them (front and rear, with their history)
/// the tyre on that wheel of a bike at a date (a pair counts for both wheels), nil none
- (nullable RAPart *)tyreOfBike:(NSString *)bikeID wheel:(RAWheel)wheel atDate:(NSDate *)date;
/// a new tyre on a wheel of a bike from a day (nil: since always, for the first tyre entered): the tyre on that
/// wheel until then is taken off the day before — a pair keeps the other wheel through a copy mounted from the same
/// day; a tyre mounted on that day or later is replaced (a correction, its mounting removed). Returns the new part
/// (wheel set, to fill in: model, width…). Not undoable by itself: call within changeEquipment:actionName:.
- (RAPart *)mountTyreOnBike:(NSString *)bikeID wheel:(RAWheel)wheel fromDate:(nullable NSDate *)date;
/// the tyres ever mounted on a bike, the latest mounting first
- (NSArray<RAPart *> *)tyreHistoryOfBike:(NSString *)bikeID;
/// the latest mounting of a part on a bike, nil none
- (nullable RAMounting *)lastMountingOfPart:(RAPart *)part onBike:(NSString *)bikeID;

- (NSDictionary *)propertyList;
+ (RAEquipment *)equipmentWithPropertyList:(nullable id)plist;

@end

NS_ASSUME_NONNULL_END
