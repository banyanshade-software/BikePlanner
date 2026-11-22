//
//  RAEquipment.m
//  RideAnalyzer
//

#import "RAEquipment.h"
#import "RASurfaceFactors.h"
#import "RAPowerSettings.h"
#import "RARide.h"
#import "RATyreDatabase.h"

static NSString *RANewID(void)
{
    return [NSUUID UUID].UUIDString;
}

static NSString *RAString(id v, NSString *fallback)
{
    return [v isKindOfClass:[NSString class]] ? v : fallback;
}

static double RADouble(id v)
{
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : 0;
}

#pragma mark - bike

@implementation RABike

- (instancetype)init
{
    self = [super init];
    if (self) {
        _identifier = RANewID();
        _name = NSLocalizedString(@"Bike", @"equipment: default name");
        _kind = RABikeHybrid;
        _position = RAPositionFlatBar;
        _surface = RASurfaceAsphalt;
        _model = @"";
        _garminGearID = @"";
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return [RABike bikeWithPropertyList:self.propertyList];
}

+ (NSString *)nameOfKind:(RABikeKind)kind
{
    switch (kind) {
        case RABikeRoad: return NSLocalizedString(@"Road", @"bike kind");
        case RABikeHybrid: return NSLocalizedString(@"Hybrid", @"bike kind");
        case RABikeGravel: return NSLocalizedString(@"Gravel", @"bike kind");
        case RABikeMountain: return NSLocalizedString(@"Mountain", @"bike kind");
        case RABikeElectric: return NSLocalizedString(@"Electric", @"bike kind");
    }
    return @"";
}

+ (NSString *)nameOfPosition:(RARidingPosition)position
{
    switch (position) {
        case RAPositionUpright: return NSLocalizedString(@"Upright", @"riding position");
        case RAPositionFlatBar: return NSLocalizedString(@"Flat bar", @"riding position");
        case RAPositionHoods: return NSLocalizedString(@"Hoods", @"riding position");
        case RAPositionDrops: return NSLocalizedString(@"Drops", @"riding position");
    }
    return @"";
}

+ (double)defaultCdAForPosition:(RARidingPosition)position
{
    // usual values of the literature for a rider of average size (m²)
    switch (position) {
        case RAPositionUpright: return 0.55;
        case RAPositionFlatBar: return 0.45;
        case RAPositionHoods: return 0.36;
        case RAPositionDrops: return 0.30;
    }
    return 0.45;
}

+ (RARidingPosition)defaultPositionForKind:(RABikeKind)kind
{
    switch (kind) {
        case RABikeRoad:
        case RABikeGravel: return RAPositionHoods;
        case RABikeHybrid:
        case RABikeMountain: return RAPositionFlatBar;
        case RABikeElectric: return RAPositionUpright;
    }
    return RAPositionFlatBar;
}

+ (NSString *)nameOfSurface:(RASurface)surface
{
    switch (surface) {
        case RASurfaceSmoothAsphalt: return NSLocalizedString(@"Smooth asphalt", @"surface");
        case RASurfaceAsphalt: return NSLocalizedString(@"Ordinary asphalt", @"surface");
        case RASurfaceRoughAsphalt: return NSLocalizedString(@"Rough asphalt", @"surface");
        case RASurfaceMixedGravel: return NSLocalizedString(@"Asphalt and gravel", @"surface");
        case RASurfaceGravel: return NSLocalizedString(@"Gravel", @"surface");
    }
    return @"";
}

+ (NSString *)categoryOfSurface:(RASurface)surface
{
    switch (surface) {
        case RASurfaceSmoothAsphalt: return RASurfaceKeySmoothAsphalt;
        case RASurfaceAsphalt: return RASurfaceKeyAsphalt;
        case RASurfaceRoughAsphalt: return RASurfaceKeyRoughAsphalt;
        case RASurfaceMixedGravel: return RASurfaceKeyMixed;
        case RASurfaceGravel: return RASurfaceKeyGravel;
    }
    return RASurfaceKeyAsphalt;
}

+ (double)rollingFactorOfSurface:(RASurface)surface
{
    return [RASurfaceFactors defaultFactorOfCategory:[self categoryOfSurface:surface]];
}

+ (double)typicalWeightForKind:(RABikeKind)kind
{
    switch (kind) {
        case RABikeRoad: return 9;
        case RABikeHybrid: return 11;
        case RABikeGravel: return 10;
        case RABikeMountain: return 13;
        case RABikeElectric: return 23;
    }
    return 12;
}

- (double)effectiveCdA
{
    return self.cdA > 0 ? self.cdA : [RABike defaultCdAForPosition:self.position];
}

- (double)effectiveWeight
{
    return self.weight > 0 ? self.weight : [RABike typicalWeightForKind:self.kind];
}

- (NSDictionary *)propertyList
{
    return @{ @"identifier": self.identifier, @"name": self.name, @"kind": @(self.kind), @"weight": @(self.weight),
              @"position": @(self.position), @"cdA": @(self.cdA), @"garminGearID": self.garminGearID,
              @"surface": @(self.surface), @"model": self.model };
}

+ (nullable RABike *)bikeWithPropertyList:(nullable id)plist
{
    if (![plist isKindOfClass:[NSDictionary class]] || ![plist[@"identifier"] isKindOfClass:[NSString class]]) return nil;
    RABike *b = [[RABike alloc] init];
    b.identifier = plist[@"identifier"];
    b.name = RAString(plist[@"name"], b.name);
    b.kind = (RABikeKind)MIN(MAX(RADouble(plist[@"kind"]), RABikeRoad), RABikeElectric);
    b.weight = RADouble(plist[@"weight"]);
    b.position = (RARidingPosition)MIN(MAX(RADouble(plist[@"position"]), RAPositionUpright), RAPositionDrops);
    b.cdA = RADouble(plist[@"cdA"]);
    b.garminGearID = RAString(plist[@"garminGearID"], @"");
    b.surface = plist[@"surface"] ? (RASurface)MIN(MAX(RADouble(plist[@"surface"]), RASurfaceSmoothAsphalt), RASurfaceGravel)
                                  : RASurfaceAsphalt;
    b.model = RAString(plist[@"model"], @"");
    return b;
}

@end

#pragma mark - mounting

@implementation RAMounting

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bikeID = @"";
        _from = [[NSCalendar currentCalendar] startOfDayForDate:[NSDate date]];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return [RAMounting mountingWithPropertyList:self.propertyList];
}

- (BOOL)containsDate:(NSDate *)date
{
    NSCalendar *cal = [NSCalendar currentCalendar];
    if ([date compare:[cal startOfDayForDate:self.from]] == NSOrderedAscending) return NO;
    if (self.to) {
        NSDate *end = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:[cal startOfDayForDate:(NSDate *)self.to] options:0];
        if (end && [date compare:end] != NSOrderedAscending) return NO;
    }
    return YES;
}

- (NSDictionary *)propertyList
{
    NSMutableDictionary *d = [@{ @"bikeID": self.bikeID, @"from": self.from } mutableCopy];
    if (self.to) d[@"to"] = self.to;
    return d;
}

+ (nullable RAMounting *)mountingWithPropertyList:(nullable id)plist
{
    if (![plist isKindOfClass:[NSDictionary class]] || ![plist[@"from"] isKindOfClass:[NSDate class]]) return nil;
    RAMounting *m = [[RAMounting alloc] init];
    m.bikeID = RAString(plist[@"bikeID"], @"");
    m.from = plist[@"from"];
    m.to = [plist[@"to"] isKindOfClass:[NSDate class]] ? plist[@"to"] : nil;
    return m;
}

@end

#pragma mark - part

@implementation RAPart

- (instancetype)init
{
    self = [super init];
    if (self) {
        _identifier = RANewID();
        _name = NSLocalizedString(@"Tyre", @"equipment: default name");
        _model = @"";
        _wheel = RAWheelBoth;
        _mountings = @[];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return [RAPart partWithPropertyList:self.propertyList];
}

+ (double)defaultCrrForModel:(NSString *)model width:(double)width
{
    // the tyre database (published tests), else an estimate from the width
    RATyre *tyre = [[RATyreDatabase shared] tyreMatchingModel:model width:width];
    if (tyre) return tyre.crr;
    if (width <= 0) return 0.0050;
    if (width <= 28) return 0.0040;
    if (width <= 35) return 0.0045;
    if (width <= 45) return 0.0055;
    return 0.0070;
}

+ (NSString *)nameOfKind:(RAPartKind)kind
{
    switch (kind) {
        case RAPartTyre: return NSLocalizedString(@"Tyre", @"part kind");
        case RAPartChain: return NSLocalizedString(@"Chain", @"part kind");
        case RAPartBrakePads: return NSLocalizedString(@"Brake pads", @"part kind");
        case RAPartCassette: return NSLocalizedString(@"Cassette", @"part kind");
        case RAPartOther: return NSLocalizedString(@"Other", @"part kind");
    }
    return @"";
}

+ (NSString *)nameOfWheel:(RAWheel)wheel
{
    switch (wheel) {
        case RAWheelFront: return NSLocalizedString(@"Front", @"wheel");
        case RAWheelRear: return NSLocalizedString(@"Rear", @"wheel");
        case RAWheelBoth: return NSLocalizedString(@"Front and rear", @"wheel");
    }
    return @"";
}

- (double)effectiveCrr
{
    return [self effectiveCrrWithSettings:[RAPowerSettings defaultSettings]];
}

- (double)effectiveCrrWithSettings:(RAPowerSettings *)settings
{
    if (self.kind != RAPartTyre) return 0;
    if (self.crr > 0) return self.crr;
    RATyre *tyre = [[RATyreDatabase shared] tyreMatchingModel:self.model width:self.width];
    if (!tyre) return [RAPart defaultCrrForModel:self.model width:self.width];
    double factor = 1;
    if (self.pressure > 0 && tyre.pressureBar > 0) {
        // lower pressure, more rolling resistance (on a drum; rough roads are another matter: the surface factor)
        factor = MIN(MAX(pow(tyre.pressureBar / self.pressure, settings.pressureExponent), settings.pressureMinFactor),
                     settings.pressureMaxFactor);
    }
    return tyre.crr * factor;
}

- (NSString *)crrSource
{
    if (self.kind != RAPartTyre) return @"";
    RATyre *tyre = [[RATyreDatabase shared] tyreMatchingModel:self.model width:self.width];
    if (!tyre) return NSLocalizedString(@"estimate from the width", @"Crr source");
    NSString *s = [NSString stringWithFormat:NSLocalizedString(@"%@, measured at %@ (%@)", @"Crr source"),
                   tyre.displayName, tyre.pressure, tyre.source];
    if (self.pressure > 0 && tyre.pressureBar > 0) {
        s = [s stringByAppendingFormat:NSLocalizedString(@", corrected for %.1f bar", @"Crr source"), self.pressure];
    }
    return s;
}

- (nullable NSString *)bikeIDAtDate:(NSDate *)date
{
    for (RAMounting *m in self.mountings) if ([m containsDate:date]) return m.bikeID;
    return nil;
}

- (NSDictionary *)propertyList
{
    return @{ @"identifier": self.identifier, @"name": self.name, @"kind": @(self.kind), @"model": self.model,
              @"width": @(self.width), @"wheel": @(self.wheel), @"crr": @(self.crr), @"pressure": @(self.pressure), @"wearLimit": @(self.wearLimit),
              @"wearWarned": @(self.wearWarned), @"mountings": [self.mountings valueForKey:@"propertyList"] };
}

+ (nullable RAPart *)partWithPropertyList:(nullable id)plist
{
    if (![plist isKindOfClass:[NSDictionary class]] || ![plist[@"identifier"] isKindOfClass:[NSString class]]) return nil;
    RAPart *p = [[RAPart alloc] init];
    p.identifier = plist[@"identifier"];
    p.name = RAString(plist[@"name"], p.name);
    p.kind = (RAPartKind)MIN(MAX(RADouble(plist[@"kind"]), RAPartTyre), RAPartOther);
    p.model = RAString(plist[@"model"], @"");
    p.width = RADouble(plist[@"width"]);
    p.wheel = (RAWheel)MIN(MAX(RADouble(plist[@"wheel"]), RAWheelFront), RAWheelBoth);
    p.crr = RADouble(plist[@"crr"]);
    p.pressure = RADouble(plist[@"pressure"]);
    p.wearLimit = RADouble(plist[@"wearLimit"]);
    p.wearWarned = RADouble(plist[@"wearWarned"]) != 0;
    NSMutableArray<RAMounting *> *mountings = [NSMutableArray array];
    id list = plist[@"mountings"];
    if ([list isKindOfClass:[NSArray class]]) {
        for (id m in list) {
            RAMounting *mounting = [RAMounting mountingWithPropertyList:m];
            if (mounting) [mountings addObject:mounting];
        }
    }
    p.mountings = mountings;
    return p;
}

@end

#pragma mark - equipment

#pragma mark - weighings

@implementation RAWeighing

+ (instancetype)weighingOnDate:(NSDate *)date kilograms:(double)kilograms
{
    RAWeighing *w = [[RAWeighing alloc] init];
    w.date = date;
    w.kilograms = kilograms;
    return w;
}

- (NSDictionary *)propertyList
{
    return @{ @"date": self.date, @"kg": @(self.kilograms) };
}

+ (nullable RAWeighing *)weighingWithPropertyList:(nullable id)plist
{
    if (![plist isKindOfClass:[NSDictionary class]] || ![plist[@"date"] isKindOfClass:[NSDate class]]) return nil;
    double kg = RADouble(plist[@"kg"]);
    return kg > 0 ? [RAWeighing weighingOnDate:plist[@"date"] kilograms:kg] : nil;
}

@end

@implementation RAEquipment

- (instancetype)init
{
    self = [super init];
    if (self) {
        _defaultBikeID = @"";
        _bikes = @[];
        _parts = @[];
        _weighings = @[];
        _usesWeighings = YES;
        _surfaceFactors = @{};
        _powerParameters = @{};
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return [RAEquipment equipmentWithPropertyList:self.propertyList];
}

- (nullable RABike *)bikeWithID:(NSString *)identifier
{
    for (RABike *b in self.bikes) if ([b.identifier isEqualToString:identifier]) return b;
    return nil;
}

- (nullable RAPart *)partWithID:(NSString *)identifier
{
    for (RAPart *p in self.parts) if ([p.identifier isEqualToString:identifier]) return p;
    return nil;
}

- (nullable RABike *)bikeOfRide:(RARide *)ride
{
    return [self bikeWithID:ride.bikeID.length ? ride.bikeID : self.defaultBikeID];
}

- (NSArray<RAPart *> *)partsOfBike:(NSString *)bikeID atDate:(NSDate *)date
{
    NSMutableArray<RAPart *> *parts = [NSMutableArray array];
    for (RAPart *p in self.parts) {
        if ([[p bikeIDAtDate:date] isEqualToString:bikeID]) [parts addObject:p];
    }
    return parts;
}

- (double)crrOfBike:(NSString *)bikeID atDate:(NSDate *)date
{
    double front = 0, rear = 0;
    for (RAPart *p in [self partsOfBike:bikeID atDate:date]) {
        if (p.kind != RAPartTyre) continue;
        RAPowerSettings *settings = self.powerSettings;
        if (p.wheel == RAWheelFront || p.wheel == RAWheelBoth) front = [p effectiveCrrWithSettings:settings];
        if (p.wheel == RAWheelRear || p.wheel == RAWheelBoth) rear = [p effectiveCrrWithSettings:settings];
    }
    if (front <= 0 && rear <= 0) return 0.0050;
    if (front <= 0) front = rear;
    if (rear <= 0) rear = front;
    return 0.4 * front + 0.6 * rear;     // the rear wheel carries most of the weight
}

- (nullable RAPart *)tyreOfBike:(NSString *)bikeID wheel:(RAWheel)wheel atDate:(NSDate *)date
{
    RAPart *found = nil;
    for (RAPart *p in [self partsOfBike:bikeID atDate:date]) {
        if (p.kind != RAPartTyre) continue;
        if (p.wheel == wheel) return p;
        if (p.wheel == RAWheelBoth || wheel == RAWheelBoth) found = found ?: p;
    }
    return found;
}

- (nullable RAMounting *)lastMountingOfPart:(RAPart *)part onBike:(NSString *)bikeID
{
    RAMounting *last = nil;
    for (RAMounting *m in part.mountings) {
        if ([m.bikeID isEqualToString:bikeID] && (!last || [m.from compare:last.from] != NSOrderedAscending)) last = m;
    }
    return last;
}

- (RAPart *)mountTyreOnBike:(NSString *)bikeID wheel:(RAWheel)wheel fromDate:(nullable NSDate *)date
{
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *day = date ? [cal startOfDayForDate:(NSDate *)date] : [NSDate dateWithTimeIntervalSinceReferenceDate:0];
    NSDate *dayBefore = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:day options:0] ?: day;
    NSMutableArray<RAPart *> *parts = [self.parts mutableCopy];
    for (RAPart *p in self.parts) {
        if (p.kind != RAPartTyre) continue;
        BOOL sameWheel = p.wheel == wheel || p.wheel == RAWheelBoth || wheel == RAWheelBoth;
        if (!sameWheel) continue;
        NSMutableArray<RAMounting *> *mountings = [NSMutableArray array];
        BOOL changed = NO;
        for (RAMounting *mt in p.mountings) {
            BOOL here = [mt.bikeID isEqualToString:bikeID];
            BOOL after = here && [[cal startOfDayForDate:mt.from] compare:day] != NSOrderedAscending;
            BOOL across = here && !after && (!mt.to || [(NSDate *)mt.to compare:day] != NSOrderedAscending);
            if (after) { changed = YES; continue; }                     // mounted that day or later: replaced
            RAMounting *kept = [mt copy];
            if (across) { kept.to = dayBefore; changed = YES; }        // taken off the day before
            [mountings addObject:kept];
        }
        if (!changed) continue;
        BOOL stillOn = NO;      // the pair still was on the bike at that day: its other wheel goes on
        for (RAMounting *mt in p.mountings) if ([mt.bikeID isEqualToString:bikeID] && [mt containsDate:day]) stillOn = YES;
        if (p.wheel == RAWheelBoth && wheel != RAWheelBoth && stillOn) {
            RAPart *other = [p copy];
            other.identifier = RANewID();
            other.wheel = wheel == RAWheelFront ? RAWheelRear : RAWheelFront;
            other.wearWarned = NO;
            RAMounting *on = [[RAMounting alloc] init];
            on.bikeID = bikeID;
            on.from = day;
            other.mountings = @[ on ];
            [parts addObject:other];
        }
        p.mountings = mountings;
        if (mountings.count == 0) [parts removeObject:p];             // never used elsewhere: replaced
    }
    RAPart *tyre = [[RAPart alloc] init];
    tyre.wheel = wheel;
    tyre.name = [NSString stringWithFormat:@"%@ (%@)", [RAPart nameOfKind:RAPartTyre], [RAPart nameOfWheel:wheel]];
    RAMounting *on = [[RAMounting alloc] init];
    on.bikeID = bikeID;
    on.from = day;
    tyre.mountings = @[ on ];
    [parts addObject:tyre];
    self.parts = parts;
    return tyre;
}

- (NSArray<RAPart *> *)tyreHistoryOfBike:(NSString *)bikeID
{
    NSMutableArray<RAPart *> *tyres = [NSMutableArray array];
    for (RAPart *p in self.parts) {
        if (p.kind == RAPartTyre && [self lastMountingOfPart:p onBike:bikeID]) [tyres addObject:p];
    }
    [tyres sortUsingComparator:^NSComparisonResult(RAPart *a, RAPart *b) {
        return [[self lastMountingOfPart:b onBike:bikeID].from compare:(NSDate *)[self lastMountingOfPart:a onBike:bikeID].from];
    }];
    return tyres;
}

- (double)effectiveRiderWeight
{
    return self.riderWeight > 0 ? self.riderWeight : self.powerSettings.riderWeight;
}

- (RAPowerSettings *)powerSettings
{
    return [RAPowerSettings settingsWithOverrides:self.powerParameters];
}

- (double)weightOfBike:(RABike *)bike
{
    return bike.weight > 0 ? bike.weight : [self.powerSettings weightForKind:bike.kind];
}

- (double)cdAOfBike:(RABike *)bike
{
    return bike.cdA > 0 ? bike.cdA : [self.powerSettings cdAForPosition:bike.position];
}

- (NSDictionary<NSString *, NSNumber *> *)effectiveSurfaceFactors
{
    return [RASurfaceFactors factorsWithOverrides:self.surfaceFactors];
}

- (double)factorOfSurfaceCategory:(NSString *)category
{
    NSNumber *f = self.effectiveSurfaceFactors[category];
    return f != nil ? f.doubleValue : [RASurfaceFactors defaultFactorOfCategory:category];
}

- (double)factorOfBikeSurface:(RASurface)surface
{
    return [self factorOfSurfaceCategory:[RABike categoryOfSurface:surface]];
}

- (double)riderWeightAtDate:(nullable NSDate *)date
{
    if (!self.usesWeighings || self.weighings.count == 0) return self.effectiveRiderWeight;
    if (!date) return self.weighings.lastObject.kilograms;
    // the day of the ride counts: a weighing that morning or that evening
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *endOfDay = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:[cal startOfDayForDate:(NSDate *)date] options:0]
                       ?: (NSDate *)date;
    RAWeighing *found = self.weighings.firstObject;
    for (RAWeighing *w in self.weighings) {
        if ([w.date compare:endOfDay] != NSOrderedAscending) break;
        found = w;
    }
    return found.kilograms;
}

- (BOOL)mergeWeighings:(NSArray<RAWeighing *> *)weighings
{
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSMutableDictionary<NSDate *, RAWeighing *> *byDay = [NSMutableDictionary dictionary];
    for (RAWeighing *w in self.weighings) byDay[[cal startOfDayForDate:w.date]] = w;
    BOOL changed = NO;
    for (RAWeighing *w in weighings) {
        if (w.kilograms <= 0) continue;
        NSDate *day = [cal startOfDayForDate:w.date];
        RAWeighing *old = byDay[day];
        if (old && ([old.date compare:w.date] == NSOrderedDescending
                    || ([old.date isEqualToDate:w.date] && old.kilograms == w.kilograms))) continue;
        byDay[day] = w;
        changed = YES;
    }
    if (!changed) return NO;
    self.weighings = [byDay.allValues sortedArrayUsingComparator:^NSComparisonResult(RAWeighing *a, RAWeighing *b) {
        return [a.date compare:b.date];
    }];
    return YES;
}

- (double)distanceOfBike:(NSString *)bikeID rides:(NSArray<RARide *> *)rides
{
    double d = 0;
    for (RARide *r in rides) if ([[self bikeOfRide:r].identifier isEqualToString:bikeID]) d += r.distance;
    return d;
}

- (double)distanceOfPart:(RAPart *)part rides:(NSArray<RARide *> *)rides
{
    double d = 0;
    for (RARide *r in rides) {
        if (!r.startDate) continue;
        NSString *bike = [part bikeIDAtDate:(NSDate *)r.startDate];
        if (bike && [[self bikeOfRide:r].identifier isEqualToString:bike]) d += r.distance;
    }
    return d;
}

- (NSArray<RAPart *> *)wornPartsWithRides:(NSArray<RARide *> *)rides
{
    NSMutableArray<RAPart *> *worn = [NSMutableArray array];
    for (RAPart *p in self.parts) {
        if (p.wearLimit > 0 && [self distanceOfPart:p rides:rides] >= p.wearLimit * 1000) [worn addObject:p];
    }
    return worn;
}

- (NSDictionary *)propertyList
{
    return @{ @"riderWeight": @(self.riderWeight), @"defaultBikeID": self.defaultBikeID,
              @"bikes": [self.bikes valueForKey:@"propertyList"], @"parts": [self.parts valueForKey:@"propertyList"],
              @"weighings": [self.weighings valueForKey:@"propertyList"], @"usesWeighings": @(self.usesWeighings),
              @"surfaceFactors": self.surfaceFactors, @"powerParameters": self.powerParameters };
}

+ (RAEquipment *)equipmentWithPropertyList:(nullable id)plist
{
    RAEquipment *e = [[RAEquipment alloc] init];
    if (![plist isKindOfClass:[NSDictionary class]]) return e;
    e.riderWeight = RADouble(plist[@"riderWeight"]);
    e.defaultBikeID = RAString(plist[@"defaultBikeID"], @"");
    NSMutableArray *bikes = [NSMutableArray array], *parts = [NSMutableArray array];
    if ([plist[@"bikes"] isKindOfClass:[NSArray class]]) {
        for (id b in plist[@"bikes"]) { RABike *bike = [RABike bikeWithPropertyList:b]; if (bike) [bikes addObject:bike]; }
    }
    if ([plist[@"parts"] isKindOfClass:[NSArray class]]) {
        for (id p in plist[@"parts"]) { RAPart *part = [RAPart partWithPropertyList:p]; if (part) [parts addObject:part]; }
    }
    e.bikes = bikes;
    e.parts = parts;
    NSMutableArray<RAWeighing *> *weighings = [NSMutableArray array];
    if ([plist[@"weighings"] isKindOfClass:[NSArray class]]) {
        for (id w in plist[@"weighings"]) { RAWeighing *x = [RAWeighing weighingWithPropertyList:w]; if (x) [weighings addObject:x]; }
    }
    [weighings sortUsingComparator:^NSComparisonResult(RAWeighing *a, RAWeighing *b) { return [a.date compare:b.date]; }];
    e.weighings = weighings;
    e.usesWeighings = plist[@"usesWeighings"] ? [plist[@"usesWeighings"] boolValue] : YES;
    NSMutableDictionary<NSString *, NSNumber *> *factors = [NSMutableDictionary dictionary];
    if ([plist[@"surfaceFactors"] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *f = plist[@"surfaceFactors"];
        for (id k in f) {
            if ([k isKindOfClass:[NSString class]] && [f[k] isKindOfClass:[NSNumber class]] && [f[k] doubleValue] > 0) factors[k] = f[k];
        }
    }
    e.surfaceFactors = factors;
    NSMutableDictionary<NSString *, NSNumber *> *parameters = [NSMutableDictionary dictionary];
    if ([plist[@"powerParameters"] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *f = plist[@"powerParameters"];
        for (id k in f) {
            if ([k isKindOfClass:[NSString class]] && [f[k] isKindOfClass:[NSNumber class]]) parameters[k] = f[k];
        }
    }
    e.powerParameters = parameters;
    return e;
}

@end
