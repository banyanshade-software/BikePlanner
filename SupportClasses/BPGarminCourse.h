//
//  BPGarminCourse.h
//  BikePlanner
//
//  Sending a course to Garmin Connect (#79), what does not depend on the web page: the activity type chosen from the
//  surfaces of the route, and the texts of the buttons of the Garmin Connect pages (French and English interfaces).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BPGarminActivity) {
    BPGarminActivityRoad,     // "Cyclisme sur route"
    BPGarminActivityGravel,   // "Gravel bike"
    BPGarminActivityMountain, // "VTT"
};

@interface BPGarminCourse : NSObject

/// owner's rule (2026-11-18), from the meters by surface class (BRouterGeoJSON: paved / unpaved / unknown): unknown the
/// majority, or no statistics → gravel; else paved / (paved + unpaved): ≤ 20 % mountain, ≥ 90 % road, gravel between
+ (BPGarminActivity)activityForSurfaceStats:(nullable NSDictionary<NSString *, NSNumber *> *)stats;
/// the texts of the button of an activity in the course editor, lowercase (French, English)
+ (NSArray<NSString *> *)buttonTextsForActivity:(BPGarminActivity)activity;

/// texts of the buttons of the steps, lowercase (French, English)
+ (NSArray<NSString *> *)importButtonTexts;      // courses page: "Importer"
+ (NSArray<NSString *> *)startButtonTexts;       // import popup: "Mise en route"
+ (NSArray<NSString *> *)saveButtonTexts;        // editor: "Enregistrer"

@end

NS_ASSUME_NONNULL_END
