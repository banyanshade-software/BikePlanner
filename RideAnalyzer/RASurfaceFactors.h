//
//  RASurfaceFactors.h
//  RideAnalyzer
//
//  The factors of the rolling resistance by surface (#82, R8, R11; configurable, owner's request 2026-11-22): the
//  Crr of the tyres is measured on a smooth steel drum (tyre database), a real surface multiplies it. Each OSM way
//  falls into a category (its surface tag, else its smoothness, tracktype or highway); the bike's "usual roads"
//  (where the map says nothing) use the same categories. The defaults and their sources: RASurfaceFactors.m. The
//  values the user changed are kept in the equipment of the library (RAEquipment.surfaceFactors, undoable);
//  the stats keep the rolling work per category, so a change applies at once, without reading the rides again.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// categories
extern NSString *const RASurfaceKeySmoothAsphalt;   // asphalt / concrete, smoothness excellent
extern NSString *const RASurfaceKeyAsphalt;      // asphalt, concrete, paved, chip seal
extern NSString *const RASurfaceKeyRoughAsphalt;    // smoothness intermediate
extern NSString *const RASurfaceKeyBadAsphalt;      // smoothness bad, very bad, horrible
extern NSString *const RASurfaceKeyPavingStones;    // paving stones, wood, metal
extern NSString *const RASurfaceKeyCompacted;
extern NSString *const RASurfaceKeyFineGravel;
extern NSString *const RASurfaceKeyCobbles;         // sett, cobblestone
extern NSString *const RASurfaceKeyMixed;           // asphalt and gravel (a bike's usual roads only)
extern NSString *const RASurfaceKeyGravel;       // gravel, pebblestone, unpaved, rock
extern NSString *const RASurfaceKeyDirt;            // dirt, earth, ground, mud, sand, grass, woodchips
extern NSString *const RASurfaceKeyTrackGrade1, *const RASurfaceKeyTrackGrade2, *const RASurfaceKeyTrackGrade3;
extern NSString *const RASurfaceKeyTrackGrade45;    // tracktype grade4, grade5
extern NSString *const RASurfaceKeyTrack;           // a track without surface nor tracktype
extern NSString *const RASurfaceKeyPath;            // path, footway, bridleway without surface
extern NSString *const RASurfaceKeyRoad;            // a road or cycleway without surface (asphalt as a rule)

@interface RASurfaceFactors : NSObject

/// all the categories, smoothest first
+ (NSArray<NSString *> *)categories;
+ (NSString *)nameOfCategory:(NSString *)category;
/// the OSM tags of the category, as shown to the user
+ (NSString *)tagsOfCategory:(NSString *)category;
+ (double)defaultFactorOfCategory:(NSString *)category;
/// the category of a way of these OSM tags (surface, smoothness, tracktype, highway)
+ (NSString *)categoryOfTags:(NSDictionary<NSString *, NSString *> *)tags;
/// every category with its factor: the defaults, replaced by the overrides (> 0)
+ (NSDictionary<NSString *, NSNumber *> *)factorsWithOverrides:(nullable NSDictionary<NSString *, NSNumber *> *)overrides;
/// the bounds of a factor the user can enter
+ (double)minimumFactor;   // 0.8
+ (double)maximumFactor;   // 6
/// the sources of the defaults (title, URL), shown in the settings
+ (NSArray<NSArray<NSString *> *> *)sources;

@end

NS_ASSUME_NONNULL_END
