//
//  RASurfaceFactors.m
//  RideAnalyzer
//
//  Why these defaults (rough estimates; the user can change them). The tyre database gives the Crr measured on a
//  smooth steel drum (bicyclerollingresistance.com); real surfaces add the losses of their roughness
//  ("impedance"), which a drum does not see:
//  - drum vs. road, impedance, rougher surfaces cost more (SILCA, Part 4B: Rolling Resistance and Impedance):
//    https://silca.cc/blogs/silca/part-4b-rolling-resistance-and-impedance
//    https://www.cyclingweekly.com/news/are-bicycle-tyre-tests-lying-to-you-rethinking-rolling-resistance-and-drum-resting
//  - smooth asphalt 0.0027–0.0040 for clinchers (Kyle 1988), against drum values of good tyres around 0.003–0.004:
//    asphalt ≈ × 1.15–1.3; a bicycle tyre on concrete 0.002, on asphalt 0.004, on a rough paved road 0.008
//    (rough ≈ × 2 asphalt): https://www.engineeringtoolbox.com/rolling-friction-resistance-d_1303.html
//  - field measurements on asphalt, fine gravel and coarse gravel: 0.01221, 0.01468, 0.01832 (fine gravel × 1.2,
//    coarse × 1.5 the asphalt; a heavy four-wheeled e-bike): Meyer, Kloss, Senner, "What is Slowing Me Down?
//    Estimation of Rolling Resistances During Cycling", Procedia Engineering 147 (2016),
//    https://doi.org/10.1016/j.proeng.2016.06.232
//  - asphalt 0.005, gravel 0.006, grass 0.007, off-road 0.020, sand 0.030 (slick tyres), from the studies of the
//    universities of Pretoria and Reims: https://www.omnicalculator.com/sports/cycling-wattage
//  - the surface is the main factor of the rolling resistance of mountain bikes (roll-down tests on several
//    surfaces): Steyn & Warnich 2014, https://repository.up.ac.za/handle/2263/42518; road, sand and grass:
//    Bertucci et al. 2013, https://pubmed.ncbi.nlm.nih.gov/23713547/
//  The sources agree on the order (smooth asphalt < asphalt < compacted / fine gravel < gravel < dirt, grass, sand)
//  more than on the ratios: gravel is × 1.2–1.5 asphalt in Meyer 2016 and higher in the off-road figures; the
//  defaults here are between them (#94).
//

#import "RASurfaceFactors.h"

NSString *const RASurfaceKeySmoothAsphalt = @"smoothAsphalt";
NSString *const RASurfaceKeyAsphalt = @"asphalt";
NSString *const RASurfaceKeyRoughAsphalt = @"roughAsphalt";
NSString *const RASurfaceKeyBadAsphalt = @"badAsphalt";
NSString *const RASurfaceKeyPavingStones = @"pavingStones";
NSString *const RASurfaceKeyCompacted = @"compacted";
NSString *const RASurfaceKeyFineGravel = @"fineGravel";
NSString *const RASurfaceKeyCobbles = @"cobbles";
NSString *const RASurfaceKeyMixed = @"mixed";
NSString *const RASurfaceKeyGravel = @"gravel";
NSString *const RASurfaceKeyDirt = @"dirt";
NSString *const RASurfaceKeyTrackGrade1 = @"trackGrade1";
NSString *const RASurfaceKeyTrackGrade2 = @"trackGrade2";
NSString *const RASurfaceKeyTrackGrade3 = @"trackGrade3";
NSString *const RASurfaceKeyTrackGrade45 = @"trackGrade45";
NSString *const RASurfaceKeyTrack = @"track";
NSString *const RASurfaceKeyPath = @"path";
NSString *const RASurfaceKeyRoad = @"road";

@implementation RASurfaceFactors

+ (NSArray<NSString *> *)categories
{
    return @[ RASurfaceKeySmoothAsphalt, RASurfaceKeyAsphalt, RASurfaceKeyRoad, RASurfaceKeyTrackGrade1, RASurfaceKeyRoughAsphalt,
              RASurfaceKeyPavingStones, RASurfaceKeyBadAsphalt, RASurfaceKeyCompacted, RASurfaceKeyMixed, RASurfaceKeyTrackGrade2,
              RASurfaceKeyFineGravel, RASurfaceKeyPath, RASurfaceKeyCobbles, RASurfaceKeyGravel, RASurfaceKeyTrackGrade3,
              RASurfaceKeyTrack, RASurfaceKeyDirt, RASurfaceKeyTrackGrade45 ];
}

+ (NSDictionary<NSString *, NSNumber *> *)defaults
{
    return @{ RASurfaceKeySmoothAsphalt: @1.15, RASurfaceKeyAsphalt: @1.3, RASurfaceKeyRoad: @1.3, RASurfaceKeyRoughAsphalt: @1.5,
              RASurfaceKeyBadAsphalt: @1.7, RASurfaceKeyPavingStones: @1.5, RASurfaceKeyCompacted: @1.8, RASurfaceKeyMixed: @1.8,
              RASurfaceKeyFineGravel: @2.0, RASurfaceKeyCobbles: @2.2, RASurfaceKeyGravel: @2.5, RASurfaceKeyDirt: @3.0,
              RASurfaceKeyTrackGrade1: @1.4, RASurfaceKeyTrackGrade2: @1.9, RASurfaceKeyTrackGrade3: @2.5,
              RASurfaceKeyTrackGrade45: @3.0, RASurfaceKeyTrack: @2.5, RASurfaceKeyPath: @2.0 };
}

+ (double)defaultFactorOfCategory:(NSString *)category
{
    NSNumber *f = [self defaults][category];
    return f != nil ? f.doubleValue : 1.3;
}

+ (NSString *)nameOfCategory:(NSString *)c
{
    NSDictionary *names = @{
        RASurfaceKeySmoothAsphalt: NSLocalizedString(@"Smooth asphalt", @"surface"),
        RASurfaceKeyAsphalt: NSLocalizedString(@"Asphalt, concrete", @"surface"),
        RASurfaceKeyRoad: NSLocalizedString(@"Road without surface on the map", @"surface"),
        RASurfaceKeyRoughAsphalt: NSLocalizedString(@"Rough asphalt", @"surface"),
        RASurfaceKeyBadAsphalt: NSLocalizedString(@"Bad asphalt", @"surface"),
        RASurfaceKeyPavingStones: NSLocalizedString(@"Paving stones, wood", @"surface"),
        RASurfaceKeyCompacted: NSLocalizedString(@"Compacted", @"surface"),
        RASurfaceKeyMixed: NSLocalizedString(@"Asphalt and gravel (usual roads of a bike)", @"surface"),
        RASurfaceKeyFineGravel: NSLocalizedString(@"Fine gravel", @"surface"),
        RASurfaceKeyCobbles: NSLocalizedString(@"Cobbles", @"surface"),
        RASurfaceKeyGravel: NSLocalizedString(@"Gravel", @"surface"),
        RASurfaceKeyDirt: NSLocalizedString(@"Dirt, grass, sand", @"surface"),
        RASurfaceKeyTrackGrade1: NSLocalizedString(@"Track, grade 1 (paved)", @"surface"),
        RASurfaceKeyTrackGrade2: NSLocalizedString(@"Track, grade 2", @"surface"),
        RASurfaceKeyTrackGrade3: NSLocalizedString(@"Track, grade 3", @"surface"),
        RASurfaceKeyTrackGrade45: NSLocalizedString(@"Track, grade 4–5", @"surface"),
        RASurfaceKeyTrack: NSLocalizedString(@"Track without surface on the map", @"surface"),
        RASurfaceKeyPath: NSLocalizedString(@"Path without surface on the map", @"surface") };
    return names[c] ?: c;
}

+ (NSString *)tagsOfCategory:(NSString *)c
{
    NSDictionary *tags = @{
        RASurfaceKeySmoothAsphalt: @"surface=asphalt|concrete + smoothness=excellent",
        RASurfaceKeyAsphalt: @"surface=asphalt|concrete|paved|chipseal",
        RASurfaceKeyRoad: @"highway=road… (no surface)",
        RASurfaceKeyRoughAsphalt: @"smoothness=intermediate",
        RASurfaceKeyBadAsphalt: @"smoothness=bad|very_bad|horrible",
        RASurfaceKeyPavingStones: @"surface=paving_stones|wood|metal",
        RASurfaceKeyCompacted: @"surface=compacted",
        RASurfaceKeyMixed: @"—",
        RASurfaceKeyFineGravel: @"surface=fine_gravel",
        RASurfaceKeyCobbles: @"surface=sett|cobblestone|unhewn_cobblestone",
        RASurfaceKeyGravel: @"surface=gravel|pebblestone|unpaved|rock",
        RASurfaceKeyDirt: @"surface=dirt|earth|ground|mud|sand|grass|woodchips",
        RASurfaceKeyTrackGrade1: @"highway=track + tracktype=grade1",
        RASurfaceKeyTrackGrade2: @"highway=track + tracktype=grade2",
        RASurfaceKeyTrackGrade3: @"highway=track + tracktype=grade3",
        RASurfaceKeyTrackGrade45: @"highway=track + tracktype=grade4|grade5",
        RASurfaceKeyTrack: @"highway=track (no surface, no tracktype)",
        RASurfaceKeyPath: @"highway=path|footway|bridleway (no surface)" };
    return tags[c] ?: @"";
}

+ (NSString *)categoryOfTags:(NSDictionary<NSString *, NSString *> *)tags
{
    NSString *surface = tags[@"surface"] ?: @"", *smoothness = tags[@"smoothness"] ?: @"";
    NSString *highway = tags[@"highway"] ?: @"", *tracktype = tags[@"tracktype"] ?: @"";
    if (surface.length) {
        if ([@[ @"asphalt", @"paved", @"concrete", @"chipseal" ] containsObject:surface] || [surface hasPrefix:@"concrete:"]) {
            if ([smoothness isEqualToString:@"excellent"]) return RASurfaceKeySmoothAsphalt;
            if ([smoothness isEqualToString:@"intermediate"]) return RASurfaceKeyRoughAsphalt;
            if ([@[ @"bad", @"very_bad", @"horrible" ] containsObject:smoothness]) return RASurfaceKeyBadAsphalt;
            return RASurfaceKeyAsphalt;
        }
        if ([@[ @"paving_stones", @"wood", @"metal" ] containsObject:surface]) return RASurfaceKeyPavingStones;
        if ([surface isEqualToString:@"compacted"]) return RASurfaceKeyCompacted;
        if ([surface isEqualToString:@"fine_gravel"]) return RASurfaceKeyFineGravel;
        if ([@[ @"sett", @"cobblestone", @"unhewn_cobblestone" ] containsObject:surface]) return RASurfaceKeyCobbles;
        if ([@[ @"gravel", @"pebblestone", @"unpaved", @"rock" ] containsObject:surface]) return RASurfaceKeyGravel;
        if ([@[ @"dirt", @"earth", @"ground", @"mud", @"sand", @"grass", @"woodchips" ] containsObject:surface]) return RASurfaceKeyDirt;
    }
    if ([highway isEqualToString:@"track"]) {
        if ([tracktype isEqualToString:@"grade1"]) return RASurfaceKeyTrackGrade1;
        if ([tracktype isEqualToString:@"grade2"]) return RASurfaceKeyTrackGrade2;
        if ([tracktype isEqualToString:@"grade3"]) return RASurfaceKeyTrackGrade3;
        if ([tracktype isEqualToString:@"grade4"] || [tracktype isEqualToString:@"grade5"]) return RASurfaceKeyTrackGrade45;
        return RASurfaceKeyTrack;
    }
    if ([@[ @"path", @"footway", @"bridleway" ] containsObject:highway]) return RASurfaceKeyPath;
    return RASurfaceKeyRoad;      // roads, cycleways, pedestrian streets: asphalt as a rule
}

+ (NSDictionary<NSString *, NSNumber *> *)factorsWithOverrides:(nullable NSDictionary<NSString *, NSNumber *> *)overrides
{
    NSMutableDictionary *d = [[self defaults] mutableCopy];
    for (NSString *k in overrides) {
        id v = overrides[k];
        if ([v isKindOfClass:[NSNumber class]] && [v doubleValue] > 0 && d[k]) d[k] = v;
    }
    return d;
}

+ (double)minimumFactor
{
    return 0.8;
}

+ (double)maximumFactor
{
    return 6;
}

+ (NSArray<NSArray<NSString *> *> *)sources
{
    return @[
        @[ @"SILCA — Rolling Resistance and Impedance (drum vs. road)", @"https://silca.cc/blogs/silca/part-4b-rolling-resistance-and-impedance" ],
        @[ @"Cycling Weekly — drum tests and real roads", @"https://www.cyclingweekly.com/news/are-bicycle-tyre-tests-lying-to-you-rethinking-rolling-resistance-and-drum-resting" ],
        @[ @"Engineering ToolBox — bicycle tyre on concrete, asphalt, rough road", @"https://www.engineeringtoolbox.com/rolling-friction-resistance-d_1303.html" ],
        @[ @"Meyer, Kloss, Senner 2016 — asphalt, fine and coarse gravel", @"https://doi.org/10.1016/j.proeng.2016.06.232" ],
        @[ @"Omni Calculator — Crr by surface", @"https://www.omnicalculator.com/sports/cycling-wattage" ],
        @[ @"Steyn & Warnich 2014 — mountain bike, surfaces", @"https://repository.up.ac.za/handle/2263/42518" ],
        @[ @"Bertucci et al. 2013 — road, sand, grass", @"https://pubmed.ncbi.nlm.nih.gov/23713547/" ] ];
}

@end
