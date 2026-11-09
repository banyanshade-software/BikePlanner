//
//  BPRemarkableSites.m
//  BikePlanner
//

#import "BPRemarkableSites.h"
#import "BPEnvironment.h"

@interface BPRemarkableSite ()
@property (readwrite) NSString *name;
@property (readwrite) CLLocationCoordinate2D coordinate;
@property (readwrite) BPSiteKind kind;
@end

@implementation BPRemarkableSite

- (NSString *) displayText
{
    NSString *kind = nil;
    switch (self.kind) {
        case BPSiteKindClimb:    kind = NSLocalizedString(@"famous climb", @"remarkable site kind"); break;
        case BPSiteKindMonument: kind = NSLocalizedString(@"monument", @"remarkable site kind"); break;
        case BPSiteKindNature:   kind = NSLocalizedString(@"natural site", @"remarkable site kind"); break;
    }
    return [NSString stringWithFormat:@"%@ — %@", self.name, kind];
}

@end

typedef struct {
    const char *name;
    double lat, lon;
    BPSiteKind kind;
} BPSiteDef;

// summit of the climbs; center of the monuments and sites
static const BPSiteDef kSites[] = {
    // famous climbs
    { "Mont Ventoux",                    44.1739,  5.2789, BPSiteKindClimb },
    { "Col du Tourmalet",                42.9086,  0.1453, BPSiteKindClimb },
    { "Col du Galibier",                 45.0642,  6.4078, BPSiteKindClimb },
    { "Alpe d'Huez",                     45.0917,  6.0697, BPSiteKindClimb },
    { "Col d'Izoard",                    44.8203,  6.7350, BPSiteKindClimb },
    { "Col d'Aubisque",                  42.9767, -0.3386, BPSiteKindClimb },
    { "Col de la Madeleine",             45.4350,  6.3756, BPSiteKindClimb },
    { "Col de la Croix de Fer",          45.2269,  6.2039, BPSiteKindClimb },
    { "Col du Glandon",                  45.2392,  6.1767, BPSiteKindClimb },
    { "Col du Télégraphe",               45.2031,  6.4442, BPSiteKindClimb },
    { "Col du Lautaret",                 45.0353,  6.4053, BPSiteKindClimb },
    { "Col de la Bonette",               44.3264,  6.8072, BPSiteKindClimb },
    { "Col de Vars",                     44.5383,  6.7031, BPSiteKindClimb },
    { "Col d'Aspin",                     42.9431,  0.3256, BPSiteKindClimb },
    { "Col de Peyresourde",              42.7975,  0.4497, BPSiteKindClimb },
    { "Hautacam",                        43.0217, -0.0003, BPSiteKindClimb },
    { "Superbagnères",                   42.7600,  0.5847, BPSiteKindClimb },
    { "Puy de Dôme",                     45.7725,  2.9644, BPSiteKindClimb },
    { "Puy Mary (Pas de Peyrol)",        45.1103,  2.6703, BPSiteKindClimb },
    { "Mont Aigoual",                    44.1211,  3.5814, BPSiteKindClimb },
    { "La Planche des Belles Filles",    47.7722,  6.7778, BPSiteKindClimb },
    { "Grand Ballon",                    47.9017,  7.0983, BPSiteKindClimb },
    // monuments
    { "Mont-Saint-Michel",               48.6361, -1.5115, BPSiteKindMonument },
    { "Cité de Carcassonne",             43.2067,  2.3636, BPSiteKindMonument },
    { "Pont du Gard",                    43.9475,  4.5353, BPSiteKindMonument },
    { "Château de Chambord",             47.6161,  1.5170, BPSiteKindMonument },
    { "Château de Chenonceau",           47.3249,  1.0703, BPSiteKindMonument },
    { "Château de Villandry",            47.3403,  0.5144, BPSiteKindMonument },
    { "Château d'Amboise",               47.4131,  0.9856, BPSiteKindMonument },
    { "Rocamadour",                      44.7994,  1.6178, BPSiteKindMonument },
    { "Conques",                         44.5992,  2.3981, BPSiteKindMonument },
    { "Palais des Papes, Avignon",       43.9508,  4.8075, BPSiteKindMonument },
    { "Viaduc de Millau",                44.0775,  3.0225, BPSiteKindMonument },
    { "Arènes de Nîmes",                 43.8347,  4.3597, BPSiteKindMonument },
    { "Cathédrale de Chartres",          48.4477,  1.4878, BPSiteKindMonument },
    { "Cathédrale d'Albi",               43.9286,  2.1428, BPSiteKindMonument },
    { "Abbaye de Sénanque",              43.9278,  5.1867, BPSiteKindMonument },
    { "Vézelay",                         47.4664,  3.7483, BPSiteKindMonument },
    { "Château de Versailles",           48.8049,  2.1204, BPSiteKindMonument },
    { "Saint-Émilion",                   44.8936, -0.1553, BPSiteKindMonument },
    // natural sites
    { "Gorges du Verdon",                43.7967,  6.3983, BPSiteKindNature },
    { "Dune du Pilat",                   44.5892, -1.2128, BPSiteKindNature },
    { "Lac d'Annecy",                    45.8500,  6.1700, BPSiteKindNature },
    { "Seuil de Naurouze (Canal du Midi)", 43.3492, 1.8128, BPSiteKindNature },
    { "Gorges du Tarn",                  44.3653,  3.4119, BPSiteKindNature },
    { "Pont d'Arc (Gorges de l'Ardèche)", 44.3825, 4.4153, BPSiteKindNature },
    { "Cirque de Gavarnie",              42.7125, -0.0083, BPSiteKindNature },
    { "Pointe du Raz",                   48.0397, -4.7397, BPSiteKindNature },
    { "Falaises d'Étretat",              49.7069,  0.2003, BPSiteKindNature },
    { "Baie de Somme",                   50.2158,  1.6267, BPSiteKindNature },
    { "Calanques de Marseille",          43.2025,  5.4997, BPSiteKindNature },
    { "Lac de Serre-Ponçon",             44.5300,  6.3700, BPSiteKindNature },
    { "Chamonix-Mont-Blanc",             45.9237,  6.8694, BPSiteKindNature },
    { "Île de Ré",                       46.2031, -1.3664, BPSiteKindNature },
};

@implementation BPRemarkableSites

+ (NSArray<BPRemarkableSite *> *) sites
{
    static NSArray<BPRemarkableSite *> *sites;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *a = [NSMutableArray array];
        for (size_t i = 0; i < sizeof(kSites) / sizeof(kSites[0]); i++) {
            BPRemarkableSite *s = [[BPRemarkableSite alloc] init];
            s.name = @(kSites[i].name);
            s.coordinate = CLLocationCoordinate2DMake(kSites[i].lat, kSites[i].lon);
            s.kind = kSites[i].kind;
            [a addObject:s];
        }
        sites = a;
    });
    return sites;
}

+ (BPRemarkableSite *) randomSite
{
    NSArray<BPRemarkableSite *> *sites = [self sites];
    NSInteger forced = [BPEnvironment remarkableSiteIndex];
    if (forced >= 0 && forced < (NSInteger)sites.count) return sites[forced];
    return sites[arc4random_uniform((uint32_t)sites.count)];
}

@end
