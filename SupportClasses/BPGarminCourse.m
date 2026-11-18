//
//  BPGarminCourse.m
//  BikePlanner
//
//  Sending a course to Garmin Connect (#79).
//

#import "BPGarminCourse.h"
#import "BRouterGeoJSON.h"

@implementation BPGarminCourse

+ (BPGarminActivity)activityForSurfaceStats:(nullable NSDictionary<NSString *, NSNumber *> *)stats
{
    double paved = stats[BPSurfacePaved].doubleValue, unpaved = stats[BPSurfaceUnpaved].doubleValue;
    double unknown = stats[BPSurfaceUnknown].doubleValue;
    double total = paved + unpaved + unknown;
    if (total <= 0 || unknown > total / 2 || paved + unpaved <= 0) return BPGarminActivityGravel;
    double ratio = paved / (paved + unpaved);
    if (ratio <= 0.20) return BPGarminActivityMountain;
    if (ratio >= 0.90) return BPGarminActivityRoad;
    return BPGarminActivityGravel;
}

+ (NSArray<NSString *> *)buttonTextsForActivity:(BPGarminActivity)activity
{
    switch (activity) {
        case BPGarminActivityRoad:     return @[ @"cyclisme sur route", @"road cycling" ];
        case BPGarminActivityMountain: return @[ @"vtt", @"mountain biking" ];
        case BPGarminActivityGravel:
        default:                       return @[ @"gravel bike", @"gravel", @"gravel/unpaved cycling" ];
    }
}

+ (NSArray<NSString *> *)importButtonTexts
{
    return @[ @"importer", @"import" ];
}

+ (NSArray<NSString *> *)startButtonTexts
{
    return @[ @"mise en route", @"get started" ];
}

+ (NSArray<NSString *> *)saveButtonTexts
{
    return @[ @"enregistrer", @"save" ];
}

@end
