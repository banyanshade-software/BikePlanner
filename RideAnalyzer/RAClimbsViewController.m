//
//  RAClimbsViewController.m
//  RideAnalyzer
//

#import "RAClimbsViewController.h"
#import "RAClimbs.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RARideStats.h"
#import "RAPower.h"
#import "RATrends.h"
#import "RATimeChartView.h"
#import "RAComputation.h"

@interface RAClimbsViewController () <NSTableViewDataSource, NSTableViewDelegate, RATimeChartViewDelegate>
@end

@implementation RAClimbsViewController
{
    NSArray<RARide *> *_rides;
    RARide *_focus;
    BOOL _selected;
    NSArray<RAClimbGroup *> *_groups;
    NSArray<RAClimbPassage *> *_passages;   // of the chosen climb, newest first
    NSTextField *_status;
    NSTextField *_chartLabel;
    NSDateFormatter *_dateFormatter;
    RAComputation *_computation;    // the groups of climbs; cancelled when the rides change
    RAClimb *_pendingClimb;         // to select when the groups show (selectClimb:)
    NSProgressIndicator *_spinner;
}

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = NSLocalizedString(@"Climbs", @"tab");
        _rides = @[];
        _groups = @[];
        _passages = @[];
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateStyle = NSDateFormatterShortStyle;
    }
    _computation = [[RAComputation alloc] initWithLabel:@"climbs"];
    _computation.delay = 0.1;
    return self;
}

- (NSTableView *)tableWithIdentifier:(NSString *)identifier columns:(NSArray<NSArray *> *)columns
{
    NSTableView *t = [[NSTableView alloc] init];
    t.identifier = identifier;
    t.dataSource = self;
    t.delegate = self;
    t.usesAlternatingRowBackgroundColors = YES;
    for (NSArray *c in columns) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        [t addTableColumn:col];
    }
    return t;
}

- (NSScrollView *)scroll:(NSTableView *)t
{
    NSScrollView *s = [[NSScrollView alloc] init];
    s.documentView = t;
    s.hasVerticalScroller = YES;
    s.autohidesScrollers = YES;
    return s;
}

- (void)loadView
{
    _status = [NSTextField labelWithString:@""];
    _status.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _status.textColor = [NSColor secondaryLabelColor];
    _status.identifier = @"climbsStatus";
    _climbsTable = [self tableWithIdentifier:@"climbs" columns:@[
        @[ @"name", NSLocalizedString(@"Climb", @"column"), @150 ],
        @[ @"length", NSLocalizedString(@"km", @"column"), @45 ],
        @[ @"gradient", NSLocalizedString(@"%", @"column"), @40 ],
        @[ @"gain", NSLocalizedString(@"D+", @"column"), @45 ],
        @[ @"passages", NSLocalizedString(@"Passages", @"column"), @60 ],
        @[ @"best", NSLocalizedString(@"Best time", @"column"), @65 ],
        @[ @"mine", NSLocalizedString(@"This ride", @"column"), @80 ] ]];
    _passagesTable = [self tableWithIdentifier:@"climbPassages" columns:@[
        @[ @"date", NSLocalizedString(@"Date", @"column"), @75 ],
        @[ @"ride", NSLocalizedString(@"Ride", @"column"), @120 ],
        @[ @"time", NSLocalizedString(@"Time", @"column"), @55 ],
        @[ @"vam", NSLocalizedString(@"VAM", @"column"), @50 ],
        @[ @"hr", NSLocalizedString(@"bpm", @"column"), @40 ],
        @[ @"power", NSLocalizedString(@"W", @"column"), @55 ],
        @[ @"rank", NSLocalizedString(@"Rank", @"column"), @45 ] ]];
    _timeChart = [[RATimeChartView alloc] initWithFrame:NSZeroRect];
    _timeChart.identifier = @"climbTimeChart";
    _timeChart.delegate = self;
    _timeChart.color = [NSColor systemOrangeColor];
    _timeChart.emptyMessage = NSLocalizedString(@"Choose a climb ridden with times.", @"climbs");
    _chartLabel = [NSTextField labelWithString:NSLocalizedString(@"Time on the climb (min) — lower is better", @"climbs")];
    _chartLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _chartLabel.textColor = [NSColor secondaryLabelColor];

    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    _spinner.identifier = @"climbsSpinner";
    __weak RAClimbsViewController *weakSelf = self;
    _computation.runningHandler = ^(BOOL running) {
        RAClimbsViewController *me = weakSelf;
        if (!me) return;
        if (running) [me->_spinner startAnimation:nil]; else [me->_spinner stopAnimation:nil];
    };
    NSStackView *statusRow = [NSStackView stackViewWithViews:@[ _spinner, _status ]];
    statusRow.spacing = 6;
    NSScrollView *climbs = [self scroll:_climbsTable], *passages = [self scroll:_passagesTable];
    NSStackView *stack = [NSStackView stackViewWithViews:@[ statusRow, climbs, passages, _chartLabel, _timeChart ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.edgeInsets = NSEdgeInsetsMake(10, 12, 12, 12);
    for (NSView *v in @[ climbs, passages, _timeChart ]) {
        [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24].active = YES;
    }
    [climbs.heightAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
    [passages.heightAnchor constraintEqualToConstant:150].active = YES;
    [_timeChart.heightAnchor constraintEqualToConstant:170].active = YES;
    [climbs setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    self.view = stack;
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    [self refresh];
}

#pragma mark - data

- (void)setLibrary:(nullable RALibraryDocument *)library
{
    _library = library;
    _rides = @[];
    _focus = nil;
}

- (NSArray<RAClimbGroup *> *)groups
{
    return _groups;
}

- (void)showRides:(NSArray<RARide *> *)rides focus:(nullable RARide *)focus selected:(BOOL)selected
{
    _rides = [rides copy];
    _focus = focus;
    _selected = selected;
    if (self.viewLoaded && self.view.window && !self.view.hiddenOrHasHiddenAncestor) [self refresh];
    else [_computation cancel];      // for other rides: useless
}

- (void)refresh
{
    (void)self.view;
    // grouped in the background (the passages of every ride compared); a change of rides cancels it
    NSArray<RARide *> *rides = [_rides copy];
    RARide *focus = _focus;
    BOOL selected = _selected;
    [_computation start:^id(RACancellation *c) {
        NSArray<RAClimbGroup *> *all = [RAClimbGroup groupsOfRides:rides cancellation:c];
        if (!all || !focus) return all;
        // the climbs of the selected ride, in the order of the ride
        NSMutableArray<RAClimbGroup *> *mine = [NSMutableArray array];
        NSMapTable<RAClimbGroup *, NSNumber *> *starts = [NSMapTable strongToStrongObjectsMapTable];
        for (RAClimbGroup *g in all) {
            for (RAClimbPassage *p in g.passages) {
                if (p.ride == focus) { [mine addObject:g]; [starts setObject:@(p.climb.startDistance) forKey:g]; break; }
            }
        }
        [mine sortUsingComparator:^NSComparisonResult(RAClimbGroup *x, RAClimbGroup *y) {
            return [[starts objectForKey:x] compare:(NSNumber *)[starts objectForKey:y]];
        }];
        return mine;
    } completion:^(NSArray<RAClimbGroup *> *groups) {
        if (groups) [self showGroups:groups rides:rides focus:focus selected:selected];
    }];
}

- (void)showGroups:(NSArray<RAClimbGroup *> *)all rides:(NSArray<RARide *> *)rides focus:(nullable RARide *)focus
          selected:(BOOL)selected
{
    RAClimbGroup *chosen = [self chosenGroup];
    RALibraryDocument *library = _library;
    for (RAClimbGroup *g in all) g.name = library ? [library nameOfClimb:g.reference] : @"";
    _groups = all;
    [_climbsTable reloadData];
    [_climbsTable tableColumnWithIdentifier:@"mine"].hidden = focus == nil;
    // keep the chosen climb (the same reference), else the first
    NSInteger row = _groups.count ? 0 : -1;
    for (NSUInteger i = 0; i < _groups.count && chosen; i++) {
        if ([_groups[i].reference isSameClimbAs:chosen.reference]) row = (NSInteger)i;
    }
    if (row >= 0) [_climbsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self showPassages];
    if (_pendingClimb) {
        [self selectGroupOfClimb:(RAClimb *)_pendingClimb];
        _pendingClimb = nil;
    }
    NSUInteger withClimbs = 0;
    for (RARide *r in rides) if (r.stats.climbs.count) withClimbs++;
    _status.stringValue = focus
        ? [NSString localizedStringWithFormat:NSLocalizedString(@"%lu climbs in this ride, compared with the %lu rides of the list", @"climbs"),
           (unsigned long)_groups.count, (unsigned long)rides.count]
        : [NSString localizedStringWithFormat:NSLocalizedString(@"%lu climbs in %lu %@", @"climbs: n climbs in n rides"),
           (unsigned long)_groups.count, (unsigned long)withClimbs,
           selected ? NSLocalizedString(@"selected rides", @"climbs") : NSLocalizedString(@"rides of the list", @"climbs")];
}

- (BOOL)isComputing
{
    return _computation.running;
}

- (nullable RAClimbPassage *)passageOf:(RARide *)ride in:(RAClimbGroup *)group
{
    for (RAClimbPassage *p in group.passages) if (p.ride == ride) return p;
    return nil;
}

- (nullable RAClimbGroup *)chosenGroup
{
    NSInteger row = _climbsTable.selectedRow;
    return row >= 0 && (NSUInteger)row < _groups.count ? _groups[(NSUInteger)row] : nil;
}

- (void)showPassages
{
    RAClimbGroup *g = [self chosenGroup];
    _passages = g ? [[g.passages reverseObjectEnumerator] allObjects] : @[];
    [_passagesTable reloadData];
    NSMutableArray<RATrendPoint *> *points = [NSMutableArray array];
    for (RAClimbPassage *p in g.passages) {
        if (!p.date || isnan(p.climb.time)) continue;
        RATrendPoint *pt = [[RATrendPoint alloc] init];
        pt.date = (NSDate *)p.date;
        pt.value = p.climb.time / 60;
        pt.rides = 1;
        pt.ride = p.ride;
        [points addObject:pt];
    }
    _timeChart.points = points;
    _timeChart.trendLine = [RATrends trendLineOfPoints:points];
}

#pragma mark - formatting

- (NSString *)duration:(double)seconds
{
    if (isnan(seconds) || seconds <= 0) return @"—";
    long s = lround(seconds);
    return s >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60]
                     : [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
}

/// measured power, else the estimate with the equipment of the ride's date (shown with ≈)
- (NSString *)powerOfPassage:(RAClimbPassage *)p
{
    RATerrainStats *s = p.climb.stats;
    if (s.powerTime > 0 && s.powerTime >= s.time / 2) return [NSString localizedStringWithFormat:@"%.0f", s.power];
    double est = [[RAPowerModel modelForRide:p.ride equipment:_library.equipment] averagePowerOfStats:s];
    return isfinite(est) && est > 0 ? [NSString localizedStringWithFormat:@"≈ %.0f", est] : @"—";
}

- (NSString *)nameOfGroup:(RAClimbGroup *)g
{
    if (g.name.length) return g.name;
    RAClimbPassage *first = g.passages.firstObject;
    return [NSString localizedStringWithFormat:NSLocalizedString(@"km %.1f of %@", @"unnamed climb: where it starts"),
            first.climb.startDistance / 1000, first.ride.name ?: @""];
}

#pragma mark - tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)(tableView == _climbsTable ? _groups.count : _passages.count);
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSString *c = tableColumn.identifier;
    NSString *text = @"";
    BOOL numeric = YES, editable = NO;
    if (tableView == _climbsTable) {
        RAClimbGroup *g = _groups[(NSUInteger)row];
        RAClimb *ref = g.reference;
        if ([c isEqualToString:@"name"]) { text = [self nameOfGroup:g]; numeric = NO; editable = YES; }
        else if ([c isEqualToString:@"length"]) text = [NSString localizedStringWithFormat:@"%.1f", ref.length / 1000];
        else if ([c isEqualToString:@"gradient"]) text = [NSString localizedStringWithFormat:@"%.1f", ref.averageGradient];
        else if ([c isEqualToString:@"gain"]) text = [NSString localizedStringWithFormat:@"%.0f", ref.gain];
        else if ([c isEqualToString:@"passages"]) text = [NSString localizedStringWithFormat:@"%lu", (unsigned long)g.passages.count];
        else if ([c isEqualToString:@"best"]) text = [self duration:g.best.climb.time];
        else if ([c isEqualToString:@"mine"] && _focus) {
            RAClimbPassage *p = [self passageOf:_focus in:g];
            NSUInteger rank = p ? [g rankOfPassage:p] : 0;
            text = p ? (rank ? [NSString localizedStringWithFormat:@"%@ (%lu/%lu)", [self duration:p.climb.time],
                                (unsigned long)rank, (unsigned long)g.passages.count] : [self duration:p.climb.time]) : @"";
        }
    } else {
        RAClimbPassage *p = _passages[(NSUInteger)row];
        RAClimbGroup *g = [self chosenGroup];
        if ([c isEqualToString:@"date"]) text = p.date ? [_dateFormatter stringFromDate:(NSDate *)p.date] : @"—";
        else if ([c isEqualToString:@"ride"]) { text = p.ride.name ?: @""; numeric = NO; }
        else if ([c isEqualToString:@"time"]) text = [self duration:p.climb.time];
        else if ([c isEqualToString:@"vam"]) text = isnan(p.climb.climbingSpeed) ? @"—" : [NSString localizedStringWithFormat:@"%.0f", p.climb.climbingSpeed];
        else if ([c isEqualToString:@"hr"]) {
            double hr = p.climb.stats.heartRate;
            text = isnan(hr) ? @"—" : [NSString localizedStringWithFormat:@"%.0f", hr];
        }
        else if ([c isEqualToString:@"power"]) text = [self powerOfPassage:p];
        else if ([c isEqualToString:@"rank"]) {
            NSUInteger rank = g ? [g rankOfPassage:p] : 0;
            text = rank ? [NSString localizedStringWithFormat:@"%lu", (unsigned long)rank] : @"—";
        }
    }
    NSTextField *f = editable ? [NSTextField textFieldWithString:text] : [NSTextField labelWithString:text];
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    f.bordered = NO;
    f.drawsBackground = NO;
    if (numeric) f.alignment = NSTextAlignmentRight;
    if (tableView == _passagesTable && _passages[(NSUInteger)row].ride == _focus && _focus) {
        f.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    }
    if (editable) {
        f.placeholderString = NSLocalizedString(@"Name of the climb", @"climbs");
        f.target = self;
        f.action = @selector(nameEdited:);
        f.identifier = @"climbName";
    }
    return f;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (notification.object == _climbsTable) [self showPassages];
}

- (void)nameEdited:(NSTextField *)sender
{
    NSInteger row = [_climbsTable rowForView:sender];
    if (row >= 0) [self renameClimbAtRow:row to:sender.stringValue];
}

- (void)renameClimbAtRow:(NSInteger)row to:(NSString *)name
{
    if (row < 0 || (NSUInteger)row >= _groups.count) return;
    RAClimbGroup *g = _groups[(NSUInteger)row];
    // the default name typed back unchanged is not a name
    if ([name isEqualToString:[self nameOfGroup:g]] && g.name.length == 0) return;
    [_library setName:name ofClimb:g.reference];
}

- (BOOL)selectClimb:(RAClimb *)climb
{
    _pendingClimb = climb;      // selected again when the groups being computed show
    [self refresh];
    return [self selectGroupOfClimb:climb];
}

- (BOOL)selectGroupOfClimb:(RAClimb *)climb
{
    for (NSUInteger i = 0; i < _groups.count; i++) {
        if ([_groups[i].reference isSameClimbAs:climb]) {
            [_climbsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [_climbsTable scrollRowToVisible:(NSInteger)i];
            [self showPassages];
            return YES;
        }
    }
    return NO;
}

- (void)timeChartView:(RATimeChartView *)chart didSelectPoint:(nullable RATrendPoint *)point
{
    if (!point.ride) return;
    for (NSUInteger i = 0; i < _passages.count; i++) {
        if (_passages[i].ride == point.ride) {
            [_passagesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [_passagesTable scrollRowToVisible:(NSInteger)i];
        }
    }
}

@end
