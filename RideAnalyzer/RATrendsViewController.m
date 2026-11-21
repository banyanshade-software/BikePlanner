//
//  RATrendsViewController.m
//  RideAnalyzer
//

#import "RATrendsViewController.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RAFilter.h"
#import "RATimeChartView.h"

// the document view of the scroll view: the content starts at the top
@interface RATrendsFlippedView : NSView
@end

@interface RATrendsViewController () <RATimeChartViewDelegate>
@end

@implementation RATrendsViewController
{
    NSPopUpButton *_measurePopup, *_terrainPopup, *_groupingPopup, *_totalPopup, *_periodPopup;
    NSArray<RARide *> *_rides;
    BOOL _selected;
    NSTextField *_selection;
    NSGridView *_recordsGrid;
    BOOL _computingStats;
}

- (NSPopUpButton *)popup:(NSArray<NSString *> *)titles identifier:(NSString *)identifier
{
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [p addItemsWithTitles:titles];
    p.target = self;
    p.action = @selector(controlsChanged:);
    p.identifier = identifier;
    return p;
}

- (NSStackView *)labeled:(NSString *)label control:(NSView *)control
{
    NSTextField *l = [NSTextField labelWithString:label];
    l.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    l.textColor = [NSColor secondaryLabelColor];
    NSStackView *s = [NSStackView stackViewWithViews:@[ l, control ]];
    s.orientation = NSUserInterfaceLayoutOrientationVertical;
    s.alignment = NSLayoutAttributeLeading;
    s.spacing = 2;
    return s;
}

- (NSTextField *)heading:(NSString *)text
{
    NSTextField *t = [NSTextField labelWithString:text];
    t.font = [NSFont boldSystemFontOfSize:15];
    return t;
}

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    self.title = NSLocalizedString(@"Trends", @"tab");
    _rides = @[];
    _measure = RATrendPowerPerBeat;
    _terrain = RATerrainClimb;
    _grouping = RATrendPerRide;
    _totalMeasure = RATotalDistance;
    _period = RAPeriodMonth;
    return self;
}

- (void)loadView
{
    NSMutableArray<NSString *> *measures = [NSMutableArray array];
    for (NSInteger m = RATrendSpeed; m <= RATrendClimbingSpeed; m++) [measures addObject:[RATrends nameOfMeasure:(RATrendMeasure)m]];
    _measurePopup = [self popup:measures identifier:@"trendsMeasure"];
    NSMutableArray<NSString *> *terrains = [NSMutableArray array];
    for (NSInteger t = RATerrainAll; t <= RATerrainSteep; t++) [terrains addObject:[RATrends nameOfTerrain:(RATerrain)t]];
    _terrainPopup = [self popup:terrains identifier:@"trendsTerrain"];
    _groupingPopup = [self popup:@[ NSLocalizedString(@"Per ride", @"trends"), NSLocalizedString(@"Per week", @"trends"),
                                    NSLocalizedString(@"Per month", @"trends") ] identifier:@"trendsGrouping"];
    NSMutableArray<NSString *> *totals = [NSMutableArray array];
    for (NSInteger m = RATotalDistance; m <= RATotalRides; m++) [totals addObject:[RATrends nameOfTotal:(RATotalMeasure)m]];
    _totalPopup = [self popup:totals identifier:@"totalsMeasure"];
    _periodPopup = [self popup:@[ NSLocalizedString(@"Per week", @"trends"), NSLocalizedString(@"Per month", @"trends"),
                                  NSLocalizedString(@"Per year", @"trends") ] identifier:@"totalsPeriod"];

    NSStackView *controls = [NSStackView stackViewWithViews:@[
        [self labeled:NSLocalizedString(@"Measure", @"trends") control:_measurePopup],
        [self labeled:NSLocalizedString(@"Terrain", @"trends") control:_terrainPopup],
        [self labeled:NSLocalizedString(@"Group", @"trends") control:_groupingPopup] ]];
    controls.alignment = NSLayoutAttributeBottom;
    controls.spacing = 14;
    _status = [NSTextField labelWithString:@""];
    _status.identifier = @"trendsStatus";
    _status.textColor = [NSColor secondaryLabelColor];
    _status.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    _trendChart = [[RATimeChartView alloc] initWithFrame:NSZeroRect];
    _trendChart.delegate = self;
    _trendChart.identifier = @"trendChart";
    _trendChart.emptyMessage = NSLocalizedString(@"No ride with this measure on this terrain.", @"trends");
    [_trendChart.heightAnchor constraintEqualToConstant:240].active = YES;
    _selection = [NSTextField labelWithString:@" "];
    _selection.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSStackView *totalControls = [NSStackView stackViewWithViews:@[ _totalPopup, _periodPopup ]];
    _totalsChart = [[RATimeChartView alloc] initWithFrame:NSZeroRect];
    _totalsChart.style = RATimeChartBars;
    _totalsChart.color = [NSColor systemOrangeColor];
    _totalsChart.delegate = self;
    _totalsChart.identifier = @"totalsChart";
    _totalsChart.emptyMessage = NSLocalizedString(@"No dated ride.", @"trends");
    [_totalsChart.heightAnchor constraintEqualToConstant:180].active = YES;

    _recordsGrid = [NSGridView gridViewWithNumberOfColumns:3 rows:0];
    _recordsGrid.rowSpacing = 6;
    _recordsGrid.columnSpacing = 16;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        controls, _status, [self heading:NSLocalizedString(@"Progression", @"trends")], _trendChart, _selection,
        [self heading:NSLocalizedString(@"Totals", @"trends")], totalControls, _totalsChart,
        [self heading:NSLocalizedString(@"Records", @"trends")], _recordsGrid ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(12, 14, 16, 14);
    controls.spacing = 10;
    for (NSView *v in @[ _trendChart, _totalsChart ]) {
        [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-28].active = YES;
    }
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    NSView *document = [[RATrendsFlippedView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:stack];
    scroll.documentView = document;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
    ]];
    self.view = scroll;
    [self syncControls];
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
}

- (NSArray<RARide *> *)rides
{
    return _rides;
}

- (void)showRides:(NSArray<RARide *> *)rides selected:(BOOL)selected
{
    _rides = [rides copy];
    _selected = selected;
    // charts are drawn only when the tab shows (refresh when it appears)
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
        [self refresh];
    }];
}

- (void)syncControls
{
    [_measurePopup selectItemAtIndex:_measure - RATrendSpeed];
    [_terrainPopup selectItemAtIndex:_terrain - RATerrainAll];
    [_groupingPopup selectItemAtIndex:_grouping];
    [_totalPopup selectItemAtIndex:_totalMeasure];
    [_periodPopup selectItemAtIndex:_period];
}

- (void)controlsChanged:(id)sender
{
    _measure = (RATrendMeasure)(_measurePopup.indexOfSelectedItem + RATrendSpeed);
    _terrain = (RATerrain)(_terrainPopup.indexOfSelectedItem + RATerrainAll);
    _grouping = (RATrendGrouping)_groupingPopup.indexOfSelectedItem;
    _totalMeasure = (RATotalMeasure)_totalPopup.indexOfSelectedItem;
    _period = (RAPeriod)_periodPopup.indexOfSelectedItem;
    [self refresh];
}

- (void)updateStatus
{
    NSUInteger missing = 0;
    for (RARide *r in _rides) if (!r.stats) missing++;
    NSString *s = [NSString localizedStringWithFormat:_selected
        ? NSLocalizedString(@"%lu selected rides", @"trends status")
        : NSLocalizedString(@"%lu rides of the list (select several to compare only them)", @"trends status"),
        (unsigned long)_rides.count];
    if (_computingStats) {
        s = [s stringByAppendingFormat:@" · %@", [NSString localizedStringWithFormat:
             NSLocalizedString(@"computing the figures of %lu rides…", @"trends status"), (unsigned long)missing]];
    } else if (missing) {
        s = [s stringByAppendingFormat:@" · %@", [NSString localizedStringWithFormat:
             NSLocalizedString(@"%lu without track figures (file unreadable)", @"trends status"), (unsigned long)missing]];
    }
    _status.stringValue = s;
}

- (void)refresh
{
    (void)self.view;
    [self syncControls];
    NSArray<RARide *> *rides = _rides;
    NSArray<RATrendPoint *> *points = [RATrends pointsForRides:rides measure:_measure terrain:_terrain grouping:_grouping];
    _trendChart.points = points;
    _trendChart.trendLine = [RATrends trendLineOfPoints:points];
    _selection.stringValue = points.count
        ? [NSString localizedStringWithFormat:NSLocalizedString(@"%@ · %@ · %lu points — click one for details", @"trends"),
           [RATrends nameOfMeasure:_measure], [RATrends nameOfTerrain:_terrain], (unsigned long)points.count]
        : @" ";
    _totalsChart.points = [RATrends totalsForRides:rides measure:_totalMeasure period:_period];
    _totalsChart.barLabelFormat = _period == RAPeriodYear ? @"yyyy" : _period == RAPeriodMonth ? @"MMM yy" : @"d MMM";
    _records = [RATrends recordsForRides:rides];
    while (_recordsGrid.numberOfRows > 0) [_recordsGrid removeRowAtIndex:0];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterMediumStyle;
    for (RARecord *r in _records) {
        NSTextField *title = [NSTextField labelWithString:r.title];
        title.textColor = [NSColor secondaryLabelColor];
        NSString *ride = r.ride.startDate ? [NSString stringWithFormat:@"%@ (%@)", r.ride.name, [f stringFromDate:(NSDate *)r.ride.startDate]]
                                          : r.ride.name;
        NSTextField *value = [NSTextField labelWithString:r.value];
        value.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
        [_recordsGrid addRowWithViews:@[ title, [NSTextField labelWithString:ride], value ]];
    }
    [self updateStatus];
}

#pragma mark - selection

- (void)timeChartView:(RATimeChartView *)chart didSelectPoint:(nullable RATrendPoint *)point
{
    if (!point) return;
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterMediumStyle;
    if (chart == _trendChart) {
        NSString *who = point.ride ? [NSString stringWithFormat:@"%@, %@", point.ride.name, [f stringFromDate:point.date]]
            : [NSString localizedStringWithFormat:NSLocalizedString(@"%@: %lu rides", @"trends"), [f stringFromDate:point.date],
               (unsigned long)point.rides];
        _selection.stringValue = [NSString localizedStringWithFormat:@"%@ — %.2f", who, point.value];
    } else {
        f.dateFormat = _totalsChart.barLabelFormat;
        _selection.stringValue = [NSString localizedStringWithFormat:NSLocalizedString(@"%@: %.0f (%lu rides)", @"trends"),
                                  [f stringFromDate:point.date], point.value, (unsigned long)point.rides];
    }
}

@end

@implementation RATrendsFlippedView
- (BOOL)isFlipped
{
    return YES;
}
@end
