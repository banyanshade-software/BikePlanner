//
//  RARidesMapViewController.m
//  RideAnalyzer
//

#import "RARidesMapViewController.h"
#import "RAHeatmap.h"
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
    NSUInteger _generation;
    BOOL _computingStats;
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
    }
    return self;
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

    NSStackView *bottom = [NSStackView stackViewWithViews:@[ legendRow, _status, all ]];
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
}

- (void)showRides:(NSArray<RARide *> *)rides selected:(BOOL)selected
{
    _rides = [rides copy];
    _selected = selected;
    // computed only when the tab shows (refresh when it appears)
    if (self.viewLoaded && self.view.window && !self.view.hiddenOrHasHiddenAncestor) [self refresh];
}

- (void)computeMissingStats
{
    RALibraryDocument *library = _library;
    if (!library || _computingStats || library.ridesWithoutStats.count == 0) return;
    _computingStats = YES;
    [self updateStatus];
    [library computeMissingStatsWithCompletion:^(NSUInteger computed) {
        self->_computingStats = NO;
        self->_shownIdentifiers = @[];   // tracks added: compute again
        [self refresh];
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
    _shownIdentifiers = identifiers;
    NSUInteger generation = ++_generation;
    _computing = YES;
    [self updateStatus];
    NSArray<RARide *> *rides = _rides;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RAHeatmap *heatmap = [[RAHeatmap alloc] initWithRides:rides];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;   // the rides changed meanwhile
            self->_computing = NO;
            [self showHeatmap:heatmap];
        });
    });
}

- (void)showHeatmap:(RAHeatmap *)heatmap
{
    _heatmap = heatmap;
    [_mapView removeOverlays:_mapView.overlays];
    // the most ridden last: drawn on top
    for (NSUInteger l = 0; l < RAHeatLevelCount; l++) {
        [_mapView addOverlays:[heatmap polylinesOfLevel:l] level:MKOverlayLevelAboveRoads];
    }
    [self showAll:self];
    [self updateStatus];
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
        s = [s stringByAppendingFormat:@" · %@", NSLocalizedString(@"reading the tracks of older rides…", @"rides map status")];
    } else if (_computing) {
        s = [s stringByAppendingFormat:@" · %@", NSLocalizedString(@"drawing…", @"rides map status")];
    } else if (withoutTrack) {
        s = [s stringByAppendingFormat:@" · %@", [NSString localizedStringWithFormat:
             NSLocalizedString(@"%lu without track", @"rides map status"), (unsigned long)withoutTrack]];
    }
    if (_heatmap.maxCount > 1 && !_computing) {
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
