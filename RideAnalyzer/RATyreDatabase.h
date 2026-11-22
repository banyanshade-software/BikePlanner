//
//  RATyreDatabase.h
//  RideAnalyzer
//
//  The tyre database (#82, R13, owner's request): tyres with the rolling resistance coefficient (Crr) measured by
//  published tests (RATyres.plist, a resource of the app: brand, model, width, Crr, test pressure, category, source).
//  The Crr of a tyre of the equipment defaults to the database's value for its model (nearest width), else to an
//  estimate from its width. Drum tests on a smooth surface: real roads give higher values.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RATyre : NSObject
@property (copy, nonatomic) NSString *brand;
@property (copy, nonatomic) NSString *model;
@property (copy, nonatomic) NSString *variant;      // @"" none
@property (nonatomic) double width;                 // mm, as tested
@property (nonatomic) double crr;
@property (copy, nonatomic) NSString *pressure;     // of the test, as published ("80 psi / 5.5 bar")
/// the test pressure in bar (from `pressure`), 0 when not given
@property (readonly, nonatomic) double pressureBar;
@property (copy, nonatomic) NSString *category;     // road, touring, gravel
@property (copy, nonatomic) NSString *source;
/// "Continental Grand Prix 5000" (brand and model)
@property (readonly, nonatomic) NSString *name;
/// "Continental Grand Prix 5000 — 25 mm"
@property (readonly, nonatomic) NSString *displayName;
+ (nullable RATyre *)tyreWithPropertyList:(nullable id)plist;
@end

@interface RATyreDatabase : NSObject

/// the database of the app (RATyres.plist in the main bundle)
+ (RATyreDatabase *)shared;
- (instancetype)initWithPropertyList:(nullable id)plist;

/// sorted by brand, model, width
@property (readonly, nonatomic) NSArray<RATyre *> *tyres;
/// the note of the database (where the values come from, their limits)
@property (readonly, nonatomic) NSString *note;

/// the tyre of a model name as the user writes it ("GP5000", "Schwalbe Marathon Plus"…): the most specific model
/// name that matches, then the nearest width (width 0: the first); nil when none matches
- (nullable RATyre *)tyreMatchingModel:(NSString *)model width:(double)width;
/// tyres whose brand or model contain every word of the text
- (NSArray<RATyre *> *)tyresMatchingText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
