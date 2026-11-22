//
//  RARidesMapViewController.m
//  RideAnalyzer
//

#import "RARidesMapViewController.h"
#import "RAHeatmap.h"
#import "RAComputation.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RARideStats.h"

@interface RARidesMapViewController () <MKMapViewDelegate>
@end

@implementation RARidesMapViewController
{
    NSArray<RARide *> *_rides;
    BOOL _selected;
    NSArray<NSString *> *_shownIdentifiers;   // rides of the heatmap shown (or being computed)
    NSArray<RARide *> *_heatmapRides;         // the rides of the heatmap shown
    RAComputation *_computation;               // the heatmap, cancelled when the rides change
    NSProgressIndicator *_spinner;
    BOOL _computingStats;
    NSUInteger _statsDone, _statsTotal;       // older rides whose track is computed (by batches)
    NSUInteger _expectedTracks;               // rides with a track in the computation in progress
    BOOL _growing;                            // its rides include those shown: keep them until it has more
    BOOL _zoomed;                             // the map was zoomed on the tracks of these rides
}

+ (NSColor *)colorOfLevel:(NSUInteger)level
{
    switch (level) {
        case 0: return [NSColor colorWithSRGBRed:0.29 green:0.56 blue:0.85 alpha:0.75];
        case 1: return [NSColor colorWithSRGBRed:0.95 green:0.76 blue:0.31 alpha:0.9];
        case 2: return [NSColor colorWithSRGBRed:0.91 green:0.45 blue:0.23 alpha:0.95];
        default: return [NSColor colorWithSRGBRed:0.75 green:0.22 blue:0.17 alpha:1];
    }
}

+ (CGFloat)widthOfLevel:(NSUInteger)level
{
    return 2 + level;
}

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = NSLocalizedString(@"Map", @"tab");
        _rides = @[];
        _shownIdentifiers = @[];
        _computation = [[RAComputation alloc] initWithLabel:@"map"];
        _computation.delay = 0.1;     // typing in the search field: once
    }
    return self;
}

- (BOOL)isComputing
{
    return _computation.running;
}

- (void)loadView
{
    _mapView = [[MKMapView alloc] init];
    _mapView.mapType = MKMapTypeMutedStandard;      // the tracks stand out
    _mapView.delegate = self;
    _mapView.showsZoomControls = YES;
    _mapView.showsScale = YES;
    _mapView.identifier = @"ridesMap";

    _status = [NSTextField labelWithString:@""];
    _status.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _status.textColor = [NSColor secondaryLabelColor];
    _status.identifier = @"ridesMapStatus";
    _status.lineBreakMode = NSLineBreakByTruncatingTail;
    [_status setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *all = [NSButton buttonWithTitle:NSLocalizedString(@"Show All", @"rides map") target:self
                                       action:@selector(showAll:)];
    all.controlSize = NSControlSizeSmall;
    all.identifier = @"ridesMapShowAll";

    // legend: a line of each level's color and width
    NSMutableArray<NSView *> *legend = [NSMutableArray array];
    for (NSUInteger l = 0; l < RAHeatLevelCount; l++) {
        NSBox *line = [[NSBox alloc] init];
        line.boxType = NSBoxCustom;
        line.borderWidth = 0;
        line.fillColor = [RARidesMapViewController colorOfLevel:l];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [line.widthAnchor constraintEqualToConstant:18].active = YES;
        [line.heightAnchor constraintEqualToConstant:[RARidesMapViewController widthOfLevel:l]].active = YES;
        NSTextField *t = [NSTextField labelWithString:[RAHeatmap legendOfLevel:l]];
        t.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        NSStackView *item = [NSStackView stackViewWithViews:@[ line, t ]];
        item.spacing = 4;
        [legend addObject:item];
    }
    NSStackView *legendRow = [NSStackView stackViewWithViews:legend];
    legendRow.spacing = 12;
    legendRow.identifier = @"ridesMapLegend";

    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    _spinner.identifier = @"ridesMapSpinner";
    __weak RARidesMapViewController *weakSelf = self;
    _computation.runningHandler = ^(BOOL running) {
        RARidesMapViewController *me = weakSelf;
        if (!me) return;
        if (running) [me->_spinner startAnimation:nil]; else [me->_spinner stopAnimation:nil];
        [me updateStatus];
    };
    NSStackView *bottom = [NSStackView stackViewWithViews:@[ legendRow, _spinner, _status, all ]];
    bottom.spacing = 12;
    bottom.edgeInsets = NSEdgeInsetsMake(6, 10, 6, 10);
    [bottom setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *stack = [NSStackView stackViewWithViews:@[ _mapView, bottom ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 0;
    stack.distribution = NSStackViewDistributionFill;
    [_mapView.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [bottom.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [_mapView setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    self.view = stack;
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    [self refresh];
    [self computeMissingStats];
}

#pragma mark - data

- (void)setLibrary:(nullable RALibraryDocument *)library
{
    _library = library;
    _rides = @[];
    _shownIdentifiers = @[];
    [_computation cancel];
    _heatmapRides = nil;
    _zoomed = NO;
}

- (void)showRides:(NSArray<RARide *> *)rides selected:(BOOL)selected
{
    _rides = [rides copy];
    _selected = selected;
    // computed only when the tab shows (refresh when it appears); a computation for other rides is useless
    if (self.viewLoaded && self.view.window && !self.view.hiddenOrHasHiddenAncestor) {
        [self refresh];
    } else if (_computation.running && ![[_rides valueForKey:@"identifier"] isEqualToArray:_shownIdentifiers]) {
        [_computation cancel];
        _shownIdentifiers = @[];
    }
}

- (void)computeMissingStats
{
    RALibraryDocument *library = _library;
    if (!library || _computingStats || library.ridesWithoutStats.count == 0) return;
    _computingStats = YES;
    [self updateStatus];
    // the tracks of the older rides come by batches: the map grows with them
    [library computeMissingStatsWithProgress:^(NSUInteger done, NSUInteger total) {
        self->_statsDone = done;
        self->_statsTotal = total;
        self->_shownIdentifiers = @[];   // tracks added: compute again
        [self refreshVisible];
    } completion:^(NSUInteger computed) {
        self->_computingStats = NO;
        self->_shownIdentifiers = @[];
        [self refreshVisible];
    }];
}

- (void)refresh
{
    (void)self.view;
    NSArray<NSString *> *identifiers = [_rides valueForKey:@"identifier"];
    if ([identifiers isEqualToArray:_shownIdentifiers]) {
        [self updateStatus];
        return;
    }
    // more tracks of the same rides (missing stats computed), or more rides: the map shown stays until the new one
    // has more; other rides: replaced at once
    NSSet *shown = [NSSet setWithArray:[_heatmapRides valueForKey:@"identifier"] ?: @[]];
    _growing = _heatmap && [shown isSubsetOfSet:[NSSet setWithArray:identifiers]];
    if (!_growing) _zoomed = NO;
    _shownIdentifiers = identifiers;
    NSArray<RARide *> *rides = [_rides copy];
    _expectedTracks = 0;
    for (RARide *r in rides) if ([RAHeatmap pointCountOfPackedTrack:r.stats.track] >= 2) _expectedTracks++;
    // the rides changed again before the end: this one is cancelled, its result never shows; meanwhile the
    // heatmaps of the first rides show as it goes (a long computation)
    [_computation start:^id(RACancellation *c) {
        return [[RAHeatmap alloc] initWithRides:rides cellSize:40 cancellation:c
                                        partial:^(RAHeatmap *partial) { [c deliverPartialResult:partial]; }];
    } partial:^(RAHeatmap *partial) {
        if (self->_growing && partial.rideCount <= self->_heatmap.rideCount) return;   // fewer than shown
        self->_growing = NO;
        [self showHeatmap:partial rides:rides];
    } completion:^(RAHeatmap *heatmap) {
        if (heatmap) [self showHeatmap:heatmap rides:rides];
    }];
    [self updateStatus];
}

- (void)showHeatmap:(RAHeatmap *)heatmap rides:(NSArray<RARide *> *)rides
{
    BOOL grew = _heatmap && !MKMapRectIsNull(_heatmap.boundingRect)
                && !MKMapRectContainsRect(_mapView.visibleMapRect, heatmap.boundingRect);
    _heatmap = heatmap;
    _heatmapRides = rides;
    [_mapView removeOverlays:_mapView.overlays];
    // the most ridden last: drawn on top
    for (NSUInteger l = 0; l < RAHeatLevelCount; l++) {
        [_mapView addOverlays:[heatmap polylinesOfLevel:l] level:MKOverlayLevelAboveRoads];
    }
    // zoomed on the tracks once per set of rides; again when they go out of the view (more rides came)
    if (!_zoomed || grew) {
        [self showAll:self];
        _zoomed = YES;
    }
    [self updateStatus];
}

/// computes when the tab shows
- (void)refreshVisible
{
    if (self.viewLoaded && self.view.window && !self.view.hiddenOrHasHiddenAncestor) [self refresh];
}

- (IBAction)showAll:(nullable id)sender
{
    if (!_heatmap || MKMapRectIsNull(_heatmap.boundingRect)) return;
    MKMapRect r = _heatmap.boundingRect;
    // a single point or a straight line: some room around it
    double margin = MAX(MAX(r.size.width, r.size.height) * 0.05, 2000 * MKMapPointsPerMeterAtLatitude(
                        MKCoordinateForMapPoint(MKMapPointMake(MKMapRectGetMidX(r), MKMapRectGetMidY(r))).latitude));
    [_mapView setVisibleMapRect:MKMapRectInset(r, -margin, -margin) edgePadding:NSEdgeInsetsMake(20, 20, 20, 20)
                       animated:NO];
}

- (void)updateStatus
{
    NSUInteger withoutTrack = 0;
    for (RARide *r in _rides) if ([RAHeatmap pointCountOfPackedTrack:r.stats.track] < 2) withoutTrack++;
    NSString *s = [NSString localizedStringWithFormat:_selected
        ? NSLocalizedString(@"%lu selected rides", @"rides map status")
        : NSLocalizedString(@"%lu rides of the list", @"rides map status"), (unsigned long)_rides.count];
    if (_computingStats) {
        s = [s stringByAppendingFormat:@" · %@", _statsTotal
             ? [NSString localizedStringWithFormat:NSLocalizedString(@"reading the tracks of older rides (%lu / %lu)…", @"rides map status"),
                (unsigned long)_statsDone, (unsigned long)_statsTotal]
             : NSLocalizedString(@"reading the tracks of older rides…", @"rides map status")];
    } else if (self.computing) {
        s = [s stringByAppendingFormat:@" · %@", _heatmap && _heatmap.rideCount < _expectedTracks
             ? [NSString localizedStringWithFormat:NSLocalizedString(@"drawing… %lu / %lu rides", @"rides map status"),
                (unsigned long)_heatmap.rideCount, (unsigned long)_expectedTracks]
             : NSLocalizedString(@"drawing…", @"rides map status")];
    } else if (withoutTrack) {
        s = [s stringByAppendingFormat:@" · %@", [NSString localizedStringWithFormat:
             NSLocalizedString(@"%lu without track", @"rides map status"), (unsigned long)withoutTrack]];
    }
    if (_heatmap.maxCount > 1 && !self.computing) {
        s = [s stringByAppendingFormat:@" · %@", [NSString localizedStringWithFormat:
             NSLocalizedString(@"up to %lu rides on a road", @"rides map status"), (unsigned long)_heatmap.maxCount]];
    }
    _status.stringValue = s;
}

#pragma mark - map

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay
{
    if (![overlay isKindOfClass:[MKPolyline class]]) return [[MKOverlayRenderer alloc] initWithOverlay:overlay];
    NSUInteger level = (NSUInteger)[((MKPolyline *)overlay).title integerValue];
    MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
    r.strokeColor = [RARidesMapViewController colorOfLevel:level];
    r.lineWidth = [RARidesMapViewController widthOfLevel:level];
    r.lineCap = kCGLineCapRound;
    r.lineJoin = kCGLineJoinRound;
    return r;
}

@end
