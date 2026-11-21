//
//  RARideDetailController.m
//  RideAnalyzer
//

#import "RARideDetailController.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RAChartView.h"
#import "RAPower.h"
#import "RAEquipment.h"
#import "ElevationProfileView.h"
#import <MapKit/MapKit.h>

// the document view of the scroll view: the detail starts at the top
@interface RAFlippedView : NSView
@end

// a run of points of the same color class
@interface RAColoredPolyline : MKPolyline
@property (nonatomic) NSInteger colorClass;   // -1: no value
@property (nonatomic) BOOL casing;            // the white line under the track
@end

@implementation RAColoredPolyline
@end

// the colors of the classes, lowest first: light to dark for speed, heart rate, power; blue (descents) to red for
// the slope. Different in lightness, not only in hue.
static NSArray<NSColor *> *RAPalette(RAColorMode mode)
{
    NSColor *(^rgb)(int) = ^NSColor *(int hex) {
        return [NSColor colorWithSRGBRed:((hex >> 16) & 0xFF) / 255.0 green:((hex >> 8) & 0xFF) / 255.0
                                    blue:(hex & 0xFF) / 255.0 alpha:1];
    };
    switch (mode) {
        case RAColorBySpeed: return @[ rgb(0xFDB863), rgb(0xF07E26), rgb(0xC8410B), rgb(0x7F2704) ];
        case RAColorBySlope: return @[ rgb(0x2166AC), rgb(0x67A9CF), rgb(0x9E9E9E), rgb(0xF4A582), rgb(0xD6604D),
                                       rgb(0x8E0D1F) ];
        case RAColorByHeartRate: return @[ rgb(0xFCBBA1), rgb(0xFB6A4A), rgb(0xEF3B2C), rgb(0xCB181D), rgb(0x67000D) ];
        case RAColorByPower: return @[ rgb(0xC6DBEF), rgb(0x6BAED6), rgb(0x3182BD), rgb(0x08519C), rgb(0x08306B) ];
    }
    return @[];
}

@interface RARideDetailController () <MKMapViewDelegate, ElevationProfileViewDelegate, RAChartViewDelegate,
                                      NSTextFieldDelegate, NSTokenFieldDelegate>
@end

@implementation RARideDetailController
{
    NSStackView *_stack;
    NSTextField *_title;
    NSTextField *_subtitle;
    NSTextField *_message;
    NSTextField *_notes;
    NSTokenField *_tags;
    NSPopUpButton *_bikePopup;         // the bike of the ride (R13)
    NSTextField *_equipment;           // the parts mounted on it at the ride's date, mass, Crr, CdA
    NSStackView *_equipmentRow;
    NSGridView *_figures;
    NSPopUpButton *_colorPopup;
    NSStackView *_legend;
    MKMapView *_map;
    MKPointAnnotation *_cursor;
    ElevationProfileView *_profile;
    NSStackView *_charts;
    NSArray<NSView *> *_rideViews;     // hidden when no single ride is shown
    NSUInteger _generation;            // the analysis in flight belongs to the last ride shown
}

- (void)loadView
{
    _title = [NSTextField labelWithString:@""];
    _title.font = [NSFont boldSystemFontOfSize:20];
    _title.lineBreakMode = NSLineBreakByTruncatingTail;
    _subtitle = [NSTextField labelWithString:@""];
    _subtitle.textColor = [NSColor secondaryLabelColor];
    _message = [NSTextField wrappingLabelWithString:@""];
    _message.textColor = [NSColor secondaryLabelColor];

    _notes = [NSTextField textFieldWithString:@""];
    _notes.placeholderString = NSLocalizedString(@"Notes", @"detail");
    _notes.delegate = self;
    _notes.identifier = @"rideNotes";
    _notes.usesSingleLineMode = NO;
    _notes.cell.wraps = YES;
    _notes.cell.scrollable = NO;
    _tags = [[NSTokenField alloc] init];
    _tags.placeholderString = NSLocalizedString(@"Tags", @"detail");
    _tags.delegate = self;
    _tags.identifier = @"rideTags";

    // equipment of the ride (R13): its bike, and what was mounted on it that day
    _bikePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _bikePopup.target = self;
    _bikePopup.action = @selector(bikeChosen:);
    _bikePopup.identifier = @"rideBike";
    _equipment = [NSTextField wrappingLabelWithString:@""];
    _equipment.textColor = [NSColor secondaryLabelColor];
    _equipment.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _equipment.identifier = @"rideEquipment";
    [_equipment setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    _equipmentRow = [NSStackView stackViewWithViews:@[ [NSTextField labelWithString:NSLocalizedString(@"Bike", @"detail")],
                                                       _bikePopup, _equipment ]];
    _equipmentRow.spacing = 8;
    _equipmentRow.alignment = NSLayoutAttributeFirstBaseline;

    _figures = [NSGridView gridViewWithNumberOfColumns:4 rows:0];
    _figures.rowSpacing = 6;
    _figures.columnSpacing = 12;

    _colorPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_colorPopup addItemsWithTitles:@[ NSLocalizedString(@"Speed", @"color by"), NSLocalizedString(@"Slope", @"color by"),
                                       NSLocalizedString(@"Heart Rate", @"color by"), NSLocalizedString(@"Power", @"color by") ]];
    _colorPopup.target = self;
    _colorPopup.action = @selector(colorModeChanged:);
    _colorPopup.identifier = @"colorBy";
    _colorPopup.autoenablesItems = NO;
    NSTextField *colorLabel = [NSTextField labelWithString:NSLocalizedString(@"Color by", @"map")];
    _legend = [NSStackView stackViewWithViews:@[]];
    _legend.spacing = 10;
    NSStackView *mapBar = [NSStackView stackViewWithViews:@[ colorLabel, _colorPopup, _legend ]];

    _map = [[MKMapView alloc] init];
    _map.delegate = self;
    _map.identifier = @"rideMap";
    [_map.heightAnchor constraintEqualToConstant:320].active = YES;
    _cursor = [[MKPointAnnotation alloc] init];

    _profile = [[ElevationProfileView alloc] initWithFrame:NSZeroRect];
    _profile.delegate = self;
    _profile.identifier = @"elevationProfile";
    [_profile.heightAnchor constraintEqualToConstant:150].active = YES;

    _charts = [NSStackView stackViewWithViews:@[]];
    _charts.orientation = NSUserInterfaceLayoutOrientationVertical;
    _charts.alignment = NSLayoutAttributeLeading;
    _charts.spacing = 6;

    _stack = [NSStackView stackViewWithViews:@[ _title, _subtitle, _message, _notes, _tags, _equipmentRow, _figures, mapBar, _map,
                                                _profile, _charts ]];
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.alignment = NSLayoutAttributeLeading;
    _stack.spacing = 10;
    _stack.edgeInsets = NSEdgeInsetsMake(12, 20, 20, 20);
    _stack.detachesHiddenViews = YES;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *v in @[ _notes, _tags, _equipmentRow, _map, _profile, _charts ]) {
        [v.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-40].active = YES;
    }
    _rideViews = @[ _subtitle, _notes, _tags, _equipmentRow, _figures, mapBar, _map, _profile, _charts ];

    // a flipped document view, so the detail starts at the top of the scroll view
    NSView *document = [[RAFlippedView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:_stack];
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = document;
    [NSLayoutConstraint activateConstraints:@[
        [_stack.topAnchor constraintEqualToAnchor:document.topAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
    ]];
    self.view = scroll;
    _cursorIndex = NSNotFound;
    [self showRides:@[]];
}

#pragma mark - showing a ride

- (void)showRides:(NSArray<RARide *> *)rides
{
    (void)self.view;
    RARide *ride = rides.count == 1 ? rides.firstObject : nil;
    BOOL same = ride && ride == _ride;
    _ride = ride;
    for (NSView *v in _rideViews) v.hidden = ride == nil;
    if (!ride) {
        _generation++;
        _analysis = nil;
        _title.stringValue = rides.count == 0 ? NSLocalizedString(@"No Ride Selected", @"detail")
            : [NSString localizedStringWithFormat:NSLocalizedString(@"%lu Rides Selected", @"detail"),
               (unsigned long)rides.count];
        _message.hidden = YES;
        return;
    }
    [self refreshRideInfo];
    if (same && _analysis) return;
    // the track: read from the original file, in the background
    _analysis = nil;
    _cursorIndex = NSNotFound;
    [self clearTrack];
    _message.hidden = NO;
    _message.stringValue = NSLocalizedString(@"Reading the track…", @"detail");
    NSData *data = [self.library originalDataOfRide:ride];
    NSUInteger generation = ++_generation;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RARideAnalysis *analysis = data ? [RARideAnalysis analysisOfData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return; // another ride was selected meanwhile
            [self showAnalysis:analysis];
        });
    });
}

- (void)refreshRideInfo
{
    RARide *ride = _ride;
    if (!ride) return;
    _title.stringValue = ride.name;
    NSString *date = ride.startDate ? [NSDateFormatter localizedStringFromDate:ride.startDate
        dateStyle:NSDateFormatterFullStyle timeStyle:NSDateFormatterShortStyle] : @"—";
    _subtitle.stringValue = [NSString stringWithFormat:@"%@ · %@ · %@", date,
                             [self.library labelForDeviceKey:ride.deviceKey] ?: @"", ride.format.uppercaseString];
    if (_notes.currentEditor == nil) _notes.stringValue = ride.notes;
    if (_tags.currentEditor == nil) _tags.objectValue = ride.tags;
    [self updateEquipment];
    [self updateFigures];
}

#pragma mark - equipment of the ride (R13)

- (void)updateEquipment
{
    RARide *ride = _ride;
    RAEquipment *e = self.library.equipment;
    if (!ride || !e) return;
    [_bikePopup removeAllItems];
    [_bikePopup addItemWithTitle:NSLocalizedString(@"None", @"detail: no bike")];
    _bikePopup.lastItem.representedObject = @"";
    for (RABike *b in e.bikes) {
        [_bikePopup addItemWithTitle:b.name];
        _bikePopup.lastItem.representedObject = b.identifier;
    }
    RABike *bike = [e bikeOfRide:ride];
    [_bikePopup selectItemAtIndex:MAX(0, [_bikePopup indexOfItemWithRepresentedObject:bike.identifier ?: @""])];
    if (e.bikes.count == 0) {
        _equipment.stringValue = NSLocalizedString(@"No bike yet: Window ▸ Equipment.", @"detail");
        return;
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (bike && ride.startDate) {
        for (RAPart *p in [e partsOfBike:bike.identifier atDate:(NSDate *)ride.startDate]) {
            NSString *what = p.model.length ? p.model : p.name;
            [parts addObject:p.kind == RAPartTyre
                ? [NSString stringWithFormat:@"%@ (%@)", what, [[RAPart nameOfWheel:p.wheel] lowercaseString]] : what];
        }
    }
    RAPowerModel *model = [RAPowerModel modelForRide:ride equipment:e];
    NSString *figures = [NSString localizedStringWithFormat:NSLocalizedString(@"%.0f kg · Crr %.4f · CdA %.2f m²", @"detail: equipment"),
                         model.mass, model.crr, model.cdA];
    _equipment.stringValue = parts.count ? [NSString stringWithFormat:@"%@ — %@", [parts componentsJoinedByString:@", "], figures]
                                         : figures;
}

- (void)bikeChosen:(id)sender
{
    RARide *ride = _ride;
    NSString *bike = _bikePopup.selectedItem.representedObject;
    if (ride && [bike isKindOfClass:[NSString class]]) [self.library setBikeID:bike ofRides:@[ ride ]];
}

- (NSString *)durationString:(NSTimeInterval)t
{
    if (t <= 0) return @"—";
    long minutes = lround(t / 60);
    return [NSString localizedStringWithFormat:NSLocalizedString(@"%ld h %02ld", @"duration: hours, minutes"),
            minutes / 60, minutes % 60];
}

- (void)addFigures:(NSArray<NSArray<NSString *> *> *)pairs
{
    // two label / value pairs per row
    for (NSUInteger i = 0; i < pairs.count; i += 2) {
        NSMutableArray<NSView *> *row = [NSMutableArray array];
        for (NSUInteger k = i; k < MIN(i + 2, pairs.count); k++) {
            NSTextField *l = [NSTextField labelWithString:pairs[k][0]];
            l.textColor = [NSColor secondaryLabelColor];
            NSTextField *v = [NSTextField labelWithString:pairs[k][1]];
            v.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
            [row addObjectsFromArray:@[ l, v ]];
        }
        while (row.count < 4) [row addObject:[NSGridCell emptyContentView]];
        [_figures addRowWithViews:row];
    }
}

- (void)updateFigures
{
    while (_figures.numberOfRows > 0) [_figures removeRowAtIndex:0];
    RARide *ride = _ride;
    if (!ride) return;
    RARideAnalysis *a = _analysis;
    NSMutableArray<NSArray<NSString *> *> *pairs = [NSMutableArray array];
    [pairs addObject:@[ NSLocalizedString(@"Distance", @"figure"),
                        [NSString localizedStringWithFormat:@"%.1f km", ride.distance / 1000] ]];
    [pairs addObject:@[ NSLocalizedString(@"Ascent", @"figure"), [NSString localizedStringWithFormat:@"%.0f m", ride.ascent] ]];
    if (a && a.hasTimes) {
        [pairs addObject:@[ NSLocalizedString(@"Moving · pauses", @"figure"),
                            [NSString stringWithFormat:@"%@ · %@", [self durationString:a.movingTime],
                             a.pauseTime >= 60 ? [self durationString:a.pauseTime] : @"0"] ]];
        [pairs addObject:@[ NSLocalizedString(@"Speed avg · max", @"figure"),
                            [NSString localizedStringWithFormat:@"%.1f · %.1f km/h", a.averageSpeed, a.maxSpeed] ]];
    } else {
        [pairs addObject:@[ NSLocalizedString(@"Duration", @"figure"), [self durationString:ride.duration] ]];
    }
    if (a && a.hasHeartRate) {
        [pairs addObject:@[ NSLocalizedString(@"Heart rate avg · max", @"figure"),
                            [NSString localizedStringWithFormat:@"%.0f · %.0f bpm", a.averageHeartRate, a.maxHeartRate] ]];
    }
    if (a && a.hasPower) {
        [pairs addObject:@[ a.powerIsEstimated ? NSLocalizedString(@"Estimated power avg · max", @"figure")
                                               : NSLocalizedString(@"Power avg · max", @"figure"),
                            [NSString localizedStringWithFormat:@"%.0f · %.0f W", a.averagePower, a.maxPower] ]];
    }
    if (a && a.hasCadence && RAHasValue(a.averageCadence)) {
        [pairs addObject:@[ NSLocalizedString(@"Cadence", @"figure"),
                            [NSString localizedStringWithFormat:@"%.0f rpm", a.averageCadence] ]];
    }
    if (a && a.hasTemperature) {
        [pairs addObject:@[ NSLocalizedString(@"Temperature", @"figure"),
                            [NSString localizedStringWithFormat:@"%.0f °C", a.averageTemperature] ]];
    }
    if (a.calories != nil) {
        [pairs addObject:@[ NSLocalizedString(@"Calories", @"figure"),
                            [NSString localizedStringWithFormat:@"%.0f kcal", a.calories.doubleValue] ]];
    }
    if (ride.garminActivityID.length) {
        [pairs addObject:@[ NSLocalizedString(@"Garmin Connect", @"figure"), ride.garminActivityID ]];
    }
    [self addFigures:pairs];
}

- (void)showAnalysis:(nullable RARideAnalysis *)analysis
{
    _analysis = analysis;
    if (!analysis) {
        _message.stringValue = NSLocalizedString(@"The original file of this ride could not be read.", @"detail");
        _map.hidden = YES;
        _profile.hidden = YES;
        _charts.hidden = YES;
        return;
    }
    if (!analysis.hasPower && analysis.hasTimes) {
        // no power meter: the estimated power (R11), from the equipment of the library
        RAPowerModel *model = [RAPowerModel modelForRide:_ride equipment:self.library.equipment];
        [analysis useEstimatedPowers:[model powersOfAnalysis:analysis wind:nil]];
    }
    _message.hidden = YES;
    _map.hidden = NO;
    _profile.hidden = NO;
    _charts.hidden = NO;
    [self updateFigures];
    for (NSInteger m = RAColorBySpeed; m <= RAColorByPower; m++) {
        [_colorPopup itemAtIndex:m].enabled = [RATrackColoring analysis:analysis supportsMode:(RAColorMode)m];
    }
    if (![RATrackColoring analysis:analysis supportsMode:self.colorMode]) _colorMode = RAColorBySlope;
    [_colorPopup selectItemAtIndex:self.colorMode];
    [self drawTrack];
    [_profile setGpxPoints:analysis.trace];
    [self buildCharts];
    [self moveCursorToIndex:NSNotFound];
}

#pragma mark - map

- (void)clearTrack
{
    [_map removeOverlays:_map.overlays];
    [_map removeAnnotations:_map.annotations];
    for (NSView *v in _legend.arrangedSubviews.copy) [v removeFromSuperview];
    for (NSView *v in _charts.arrangedSubviews.copy) [v removeFromSuperview];
}

- (void)setColorMode:(RAColorMode)colorMode
{
    _colorMode = colorMode;
    if (_analysis) {
        [_colorPopup selectItemAtIndex:colorMode];
        [self drawTrack];
    }
}

- (void)colorModeChanged:(NSPopUpButton *)sender
{
    self.colorMode = (RAColorMode)sender.indexOfSelectedItem;
}

- (void)drawTrack
{
    RARideAnalysis *a = _analysis;
    [_map removeOverlays:_map.overlays];
    if (!a) return;
    NSUInteger n = a.count;
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * n);
    for (NSUInteger i = 0; i < n; i++) coords[i] = a.trace[i].coordinate;
    RAColoredPolyline *casing = [RAColoredPolyline polylineWithCoordinates:coords count:n];
    casing.casing = YES;
    NSMutableArray<id<MKOverlay>> *overlays = [NSMutableArray arrayWithObject:casing];
    // one polyline per run of points of the same class (a run shares its last point with the next)
    NSArray<NSNumber *> *classes = [RATrackColoring classesOfAnalysis:a mode:self.colorMode];
    NSUInteger start = 0;
    for (NSUInteger i = 1; i <= n; i++) {
        if (i < n && [classes[i] isEqualToNumber:classes[start]]) continue;
        NSUInteger end = MIN(i, n - 1);
        if (end > start) {
            RAColoredPolyline *run = [RAColoredPolyline polylineWithCoordinates:coords + start count:end - start + 1];
            run.colorClass = classes[start].integerValue;
            [overlays addObject:run];
        }
        start = end;
        if (i == n) break;
    }
    [_map addOverlays:overlays level:MKOverlayLevelAboveRoads];
    MKMapRect rect = casing.boundingMapRect;
    [_map setVisibleMapRect:rect edgePadding:NSEdgeInsetsMake(30, 30, 30, 30) animated:NO];
    free(coords);
    [self updateLegend];
}

- (void)updateLegend
{
    for (NSView *v in _legend.arrangedSubviews.copy) [v removeFromSuperview];
    NSArray<NSString *> *labels = [RATrackColoring legendForMode:self.colorMode analysis:(RARideAnalysis *)_analysis];
    NSArray<NSColor *> *colors = RAPalette(self.colorMode);
    for (NSUInteger i = 0; i < labels.count && i < colors.count; i++) {
        NSView *swatch = [[NSView alloc] init];
        swatch.wantsLayer = YES;
        swatch.layer.backgroundColor = colors[i].CGColor;
        swatch.layer.cornerRadius = 2;
        [swatch.widthAnchor constraintEqualToConstant:14].active = YES;
        [swatch.heightAnchor constraintEqualToConstant:5].active = YES;
        NSTextField *label = [NSTextField labelWithString:labels[i]];
        label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        NSStackView *item = [NSStackView stackViewWithViews:@[ swatch, label ]];
        item.spacing = 4;
        [_legend addArrangedSubview:item];
    }
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay
{
    if (![overlay isKindOfClass:[RAColoredPolyline class]]) return [[MKOverlayRenderer alloc] initWithOverlay:overlay];
    RAColoredPolyline *line = (RAColoredPolyline *)overlay;
    MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:line];
    r.lineCap = kCGLineCapRound;
    r.lineJoin = kCGLineJoinRound;
    if (line.casing) {
        r.strokeColor = [NSColor whiteColor];
        r.lineWidth = 8;
        return r;
    }
    NSArray<NSColor *> *colors = RAPalette(self.colorMode);
    NSInteger c = line.colorClass;
    r.strokeColor = c >= 0 && (NSUInteger)c < colors.count ? colors[(NSUInteger)c] : [NSColor systemGrayColor];
    r.lineWidth = 4;
    return r;
}

#pragma mark - profile and curves

- (void)addChart:(NSString *)title values:(NSArray<NSNumber *> *)values color:(NSColor *)color
{
    RAChartView *chart = [[RAChartView alloc] initWithFrame:NSZeroRect];
    chart.title = title;
    chart.color = color;
    chart.delegate = self;
    chart.identifier = [@"chart." stringByAppendingString:title];
    [chart setValues:values distances:(NSArray<NSNumber *> *)_analysis.distances];
    [chart.heightAnchor constraintEqualToConstant:80].active = YES;
    [_charts addArrangedSubview:chart];
    [chart.widthAnchor constraintEqualToAnchor:_charts.widthAnchor].active = YES;
}

- (void)buildCharts
{
    for (NSView *v in _charts.arrangedSubviews.copy) [v removeFromSuperview];
    RARideAnalysis *a = _analysis;
    if (!a) return;
    if ([RATrackColoring analysis:a supportsMode:RAColorBySpeed]) {
        [self addChart:NSLocalizedString(@"Speed (km/h)", @"chart") values:a.speeds color:[NSColor systemOrangeColor]];
    }
    if (a.hasHeartRate) [self addChart:NSLocalizedString(@"Heart rate (bpm)", @"chart") values:a.heartRates color:[NSColor systemRedColor]];
    if (a.hasCadence) [self addChart:NSLocalizedString(@"Cadence (rpm)", @"chart") values:a.cadences color:[NSColor systemPurpleColor]];
    if (a.hasPower) {
        [self addChart:a.powerIsEstimated ? NSLocalizedString(@"Estimated power (W)", @"chart") : NSLocalizedString(@"Power (W)", @"chart")
                values:a.powers color:a.powerIsEstimated ? [NSColor systemIndigoColor] : [NSColor systemBlueColor]];
    }
    if (a.hasTemperature) {
        [self addChart:NSLocalizedString(@"Temperature (°C)", @"chart") values:a.temperatures color:[NSColor systemTealColor]];
    }
}

- (void)moveCursorToDistance:(double)distance
{
    if (!_analysis) return;
    [self moveCursorToIndex:[_analysis indexAtDistance:distance]];
}

- (void)moveCursorToIndex:(NSUInteger)index
{
    RARideAnalysis *a = _analysis;
    _cursorIndex = a && index < a.count ? index : NSNotFound;
    double distance = _cursorIndex == NSNotFound ? NAN : a.distances[_cursorIndex].doubleValue;
    for (RAChartView *chart in _charts.arrangedSubviews) {
        if ([chart isKindOfClass:[RAChartView class]]) chart.cursorDistance = distance;
    }
    if (_cursorIndex == NSNotFound) {
        [_map removeAnnotation:_cursor];
        return;
    }
    _profile.highlightDistance = distance;
    _cursor.coordinate = a.trace[_cursorIndex].coordinate;
    if (![_map.annotations containsObject:_cursor]) [_map addAnnotation:_cursor];
}

- (void)elevationProfileView:(id)view didSelectDistance:(double)distance
{
    [self moveCursorToDistance:distance];
}

- (void)elevationProfileView:(id)view didShowRangeFrom:(double)from to:(double)to
{
    for (RAChartView *chart in _charts.arrangedSubviews) {
        if ([chart isKindOfClass:[RAChartView class]]) [chart setVisibleFrom:from to:to];
    }
}

- (void)chartView:(RAChartView *)chart didSelectDistance:(double)distance
{
    [self moveCursorToDistance:distance];
}

#pragma mark - notes and tags (R3)

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    RARide *ride = _ride;
    if (!ride) return;
    if (notification.object == _notes) {
        [self.library setNotes:_notes.stringValue ofRide:ride];
    } else if (notification.object == _tags) {
        NSArray *tokens = [_tags.objectValue isKindOfClass:[NSArray class]] ? _tags.objectValue : @[];
        NSMutableArray<NSString *> *tags = [NSMutableArray array];
        for (id t in tokens) if ([t isKindOfClass:[NSString class]]) [tags addObject:t];
        [self.library setTags:tags ofRide:ride];
    }
}

- (nullable NSArray *)tokenField:(NSTokenField *)tokenField completionsForSubstring:(NSString *)substring
                    indexOfToken:(NSInteger)tokenIndex indexOfSelectedItem:(nullable NSInteger *)selectedIndex
{
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (NSString *t in self.library.allTags) {
        if ([t rangeOfString:substring options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSAnchoredSearch].location != NSNotFound) {
            [matches addObject:t];
        }
    }
    return matches;
}

@end

@implementation RAFlippedView
- (BOOL)isFlipped
{
    return YES;
}
@end
