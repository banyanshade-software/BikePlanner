//
//  RALibraryWindowController.m
//  RideAnalyzer
//

#import "RALibraryWindowController.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RAFilter.h"
#import "RAFilterSheet.h"
#import "RAGarminConnect.h"
#import "RAGarminFetchSheet.h"
#import "RARideDetailController.h"
#import "RATrendsViewController.h"
#import "RARangeSlider.h"
#import "RARidesMapViewController.h"
#import "BPTrackReader.h"

static NSUserInterfaceItemIdentifier const RAColumnDate = @"date";
static NSUserInterfaceItemIdentifier const RAColumnName = @"name";
static NSUserInterfaceItemIdentifier const RAColumnDistance = @"distance";
static NSUserInterfaceItemIdentifier const RAColumnAscent = @"ascent";
static NSUserInterfaceItemIdentifier const RAColumnDuration = @"duration";
static NSUserInterfaceItemIdentifier const RAColumnSpeed = @"speed";
static NSUserInterfaceItemIdentifier const RAColumnDevice = @"device";

static void *RAProgressContext = &RAProgressContext;

// toolbar items
static NSToolbarItemIdentifier const RAToolbarImport = @"import";
static NSToolbarItemIdentifier const RAToolbarDevice = @"importFromDevice";
static NSToolbarItemIdentifier const RAToolbarGarmin = @"garmin";
static NSToolbarItemIdentifier const RAToolbarFilter = @"filter";
static NSToolbarItemIdentifier const RAToolbarDelete = @"delete";
static NSToolbarItemIdentifier const RAToolbarTrends = @"trends";
static NSToolbarItemIdentifier const RAToolbarMap = @"ridesMap";

// a row of the sidebar
typedef NS_ENUM(NSInteger, RASidebarKind) { RASidebarAll, RASidebarHeader, RASidebarSavedFilter, RASidebarDevice };

@interface RALibraryWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate,
                                         NSMenuItemValidation, NSTextFieldDelegate, NSSearchFieldDelegate,
                                         NSToolbarDelegate, NSToolbarItemValidation>
@end

@implementation RALibraryWindowController
{
    NSSplitViewController *_split;
    NSTableView *_sidebar;
    NSArray<NSDictionary *> *_sidebarRows;      // @{ @"kind", @"title", @"key" (device), @"saved" (RASavedFilter) }
    NSDictionary *_sidebarSelection;            // the row that gives the base filter
    RAFilter *_baseFilter;                      // from the sidebar or the filter sheet
    NSSearchField *_search;
    NSTextField *_filterSummary;
    NSPopUpButton *_periodPopup, *_devicePopup, *_tagPopup;
    RARangeSlider *_distanceSlider;     // km, from 0 to the longest ride; the ends mean "no limit"
    NSTextField *_distanceLabel;
    NSButton *_saveFilterButton;
    NSButton *_clearFilterButton;
    NSTableView *_table;
    NSArray<RARide *> *_sorted;
    NSTextField *_footer;
    NSStackView *_progressBar;
    NSTextField *_progressLabel;
    NSProgressIndicator *_progressIndicator;
    NSProgress *_progress;
    RARideDetailController *_detail;
    RATrendsViewController *_trends;
    RARidesMapViewController *_ridesMap;
    NSTabViewController *_tabs;     // Ride (the detail), Trends and Map, beside the list
    NSDateFormatter *_dateFormatter;
    RAGarminFetchSheet *_garminSheet;
    RAFilterSheet *_filterSheet;
}

- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 800)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                  | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:YES];
    window.minSize = NSMakeSize(1080, 560);
    self = [super initWithWindow:window];
    if (self) {
        window.delegate = self;
        window.identifier = @"library";
        _sorted = @[];
        _sidebarRows = @[];
        _baseFilter = [[RAFilter alloc] init];
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateStyle = NSDateFormatterShortStyle;
        _dateFormatter.timeStyle = NSDateFormatterNoStyle;
        [self buildContent];
        [self buildToolbar];
        [window center];
        [window setFrameAutosaveName:@"RALibraryWindow"];
    }
    return self;
}

- (void)setDocument:(id)document
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (self.document) [nc removeObserver:self name:RALibraryDidChangeNotification object:self.document];
    [super setDocument:document];
    if (document) {
        [nc addObserver:self selector:@selector(libraryDidChange:) name:RALibraryDidChangeNotification object:document];
    }
    _detail.library = document;
    _trends.library = document;
    _ridesMap.library = document;
    [self reload];
}

- (void)dealloc
{
    [self observeProgress:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (RALibraryDocument *)library
{
    return (RALibraryDocument *)self.document;
}

#pragma mark - building the window

- (NSScrollView *)scrollViewWithTable:(NSTableView *)table
{
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = table;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    return scroll;
}

- (NSViewController *)controllerWithView:(NSView *)view
{
    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = view;
    return vc;
}

- (void)buildContent
{
    // sidebar (R3, owner's request): the filter on top, then the saved filters and the devices (one click applies
    // one; names editable)
    _sidebar = [[NSTableView alloc] init];
    _sidebar.headerView = nil;
    _sidebar.style = NSTableViewStyleSourceList;
    [_sidebar addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"section"]];
    _sidebar.dataSource = self;
    _sidebar.delegate = self;
    _sidebar.identifier = @"sidebar";
    NSMenu *sidebarMenu = [[NSMenu alloc] init];
    [sidebarMenu addItemWithTitle:NSLocalizedString(@"Delete Filter", @"sidebar menu") action:@selector(deleteSavedFilter:)
                    keyEquivalent:@""].target = self;
    _sidebar.menu = sidebarMenu;
    NSScrollView *sidebarScroll = [self scrollViewWithTable:_sidebar];

    // the filter: search, criteria, save
    _search = [[NSSearchField alloc] init];
    _search.placeholderString = NSLocalizedString(@"Name, notes, tags", @"search");
    _search.delegate = self;
    _search.target = self;
    _search.action = @selector(searchChanged:);
    _search.identifier = @"search";
    _clearFilterButton = [NSButton buttonWithTitle:NSLocalizedString(@"Clear", @"button") target:self
                                            action:@selector(clearFilter:)];
    _clearFilterButton.identifier = @"clearFilter";
    _saveFilterButton = [NSButton buttonWithTitle:NSLocalizedString(@"Save…", @"button") target:self
                                           action:@selector(saveFilter:)];
    _saveFilterButton.identifier = @"saveFilter";
    _clearFilterButton.controlSize = NSControlSizeSmall;
    _saveFilterButton.controlSize = NSControlSizeSmall;
    _filterSummary = [NSTextField labelWithString:@""];
    _filterSummary.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _filterSummary.textColor = [NSColor secondaryLabelColor];
    _filterSummary.lineBreakMode = NSLineBreakByTruncatingTail;
    _filterSummary.identifier = @"filterSummary";
    [_filterSummary setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    // the search field, the most used criteria as pop-up menus (period, device, distance, tag), More… for the sheet
    // with all of them; the summary of the filter, Clear, Save…
    _periodPopup = [self filterPopupWithIdentifier:@"filterPeriod" action:@selector(periodChosen:)];
    _devicePopup = [self filterPopupWithIdentifier:@"filterDevice" action:@selector(deviceChosen:)];
    _distanceLabel = [NSTextField labelWithString:@""];
    _distanceLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _distanceLabel.identifier = @"filterDistanceLabel";
    _distanceSlider = [[RARangeSlider alloc] initWithFrame:NSMakeRect(0, 0, 180, 22)];
    _distanceSlider.target = self;
    _distanceSlider.action = @selector(distanceChosen:);
    _distanceSlider.identifier = @"filterDistance";
    _distanceSlider.toolTip = NSLocalizedString(@"Distance of the rides: drag the two ends (arrow keys: left / right "
                                                @"move, up / down choose the end)", @"filter");
    _tagPopup = [self filterPopupWithIdentifier:@"filterTag" action:@selector(tagChosen:)];
    NSButton *more = [NSButton buttonWithTitle:NSLocalizedString(@"More…", @"filter bar") target:self
                                        action:@selector(editFilter:)];
    more.controlSize = NSControlSizeSmall;
    more.identifier = @"editFilter";
    _filterSummary.lineBreakMode = NSLineBreakByWordWrapping;
    _filterSummary.cell.wraps = YES;
    _filterSummary.cell.truncatesLastVisibleLine = YES;
    _filterSummary.maximumNumberOfLines = 3;
    _filterSummary.preferredMaxLayoutWidth = 190;
    NSTextField *filterTitle = [NSTextField labelWithString:NSLocalizedString(@"Filter", @"sidebar")];
    filterTitle.font = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
    filterTitle.textColor = [NSColor secondaryLabelColor];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[ more, _clearFilterButton, _saveFilterButton ]];
    buttons.spacing = 4;
    NSStackView *filterPanel = [NSStackView stackViewWithViews:@[ filterTitle, _search, _periodPopup, _devicePopup,
                                                                 _distanceLabel, _distanceSlider, _tagPopup, buttons,
                                                                 _filterSummary ]];
    filterPanel.orientation = NSUserInterfaceLayoutOrientationVertical;
    filterPanel.alignment = NSLayoutAttributeLeading;
    filterPanel.spacing = 6;
    filterPanel.detachesHiddenViews = YES;
    filterPanel.edgeInsets = NSEdgeInsetsMake(8, 10, 6, 10);
    [filterPanel setCustomSpacing:2 afterView:_distanceLabel];
    for (NSView *v in @[ _search, _periodPopup, _devicePopup, _distanceSlider, _tagPopup, _filterSummary ]) {
        [v.widthAnchor constraintEqualToAnchor:filterPanel.widthAnchor constant:-20].active = YES;
    }
    NSStackView *sidebarStack = [NSStackView stackViewWithViews:@[ filterPanel, sidebarScroll ]];
    sidebarStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    sidebarStack.alignment = NSLayoutAttributeLeading;
    sidebarStack.distribution = NSStackViewDistributionFill;
    sidebarStack.spacing = 0;
    for (NSView *v in @[ filterPanel, sidebarScroll ]) {
        [v.widthAnchor constraintEqualToAnchor:sidebarStack.widthAnchor].active = YES;
    }
    [sidebarScroll setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];

    // rides
    _table = [[NSTableView alloc] init];
    _table.identifier = @"rides";
    _table.allowsMultipleSelection = YES;
    _table.usesAlternatingRowBackgroundColors = YES;
    _table.dataSource = self;
    _table.delegate = self;
    NSArray *columns = @[
        @[ RAColumnDate, NSLocalizedString(@"Date", @"column"), @"startDate", @80 ],
        @[ RAColumnName, NSLocalizedString(@"Name", @"column"), @"name", @180 ],
        @[ RAColumnDistance, NSLocalizedString(@"km", @"column"), @"distance", @50 ],
        @[ RAColumnAscent, NSLocalizedString(@"Ascent", @"column"), @"ascent", @55 ],
        @[ RAColumnDuration, NSLocalizedString(@"Duration", @"column"), @"duration", @65 ],
        @[ RAColumnSpeed, NSLocalizedString(@"Avg.", @"column"), @"averageSpeed", @50 ],
        @[ RAColumnDevice, NSLocalizedString(@"Device", @"column"), @"deviceKey", @90 ],
    ];
    for (NSArray *c in columns) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:c[2] ascending:NO];
        col.width = [c[3] doubleValue];
        [_table addTableColumn:col];
    }
    _table.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"startDate" ascending:NO] ];
    [_table registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
    NSScrollView *tableScroll = [self scrollViewWithTable:_table];

    // progress of an import (R1, R2): text, bar, Cancel
    _progressLabel = [NSTextField labelWithString:@""];
    _progressLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _progressLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _progressIndicator = [[NSProgressIndicator alloc] init];
    _progressIndicator.style = NSProgressIndicatorStyleBar;
    _progressIndicator.indeterminate = NO;
    _progressIndicator.minValue = 0;
    _progressIndicator.maxValue = 1;
    _progressIndicator.identifier = @"importProgress";
    [_progressIndicator.widthAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
    NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"button") target:self
                                          action:@selector(cancelImport:)];
    cancel.controlSize = NSControlSizeSmall;
    cancel.identifier = @"importCancel";
    _progressBar = [NSStackView stackViewWithViews:@[ _progressLabel, _progressIndicator, cancel ]];
    _progressBar.edgeInsets = NSEdgeInsetsMake(4, 10, 4, 10);
    _progressBar.hidden = YES;

    _footer = [NSTextField labelWithString:@""];
    _footer.textColor = [NSColor secondaryLabelColor];
    _footer.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _footer.identifier = @"listFooter";
    NSStackView *list = [NSStackView stackViewWithViews:@[ _progressBar, tableScroll, _footer ]];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.distribution = NSStackViewDistributionFill;
    list.detachesHiddenViews = YES;
    [tableScroll setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    list.edgeInsets = NSEdgeInsetsMake(0, 0, 8, 0);
    list.spacing = 4;
    for (NSView *v in @[ _progressBar, tableScroll ]) {
        [v.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    }
    [_footer.leadingAnchor constraintEqualToAnchor:list.leadingAnchor constant:10].active = YES;

    // beside the list, two tabs: the detail of the selected ride (R4), the trends of the selected rides or of the
    // list (R6)
    _detail = [[RARideDetailController alloc] init];
    _detail.title = NSLocalizedString(@"Ride", @"tab");
    _trends = [[RATrendsViewController alloc] init];
    _ridesMap = [[RARidesMapViewController alloc] init];
    _tabs = [[NSTabViewController alloc] init];
    _tabs.tabStyle = NSTabViewControllerTabStyleSegmentedControlOnTop;
    [_tabs addChildViewController:_detail];
    [_tabs addChildViewController:_trends];
    [_tabs addChildViewController:_ridesMap];
    _tabs.tabViewItems[0].identifier = @"ride";
    _tabs.tabViewItems[1].identifier = @"trends";
    _tabs.tabViewItems[2].identifier = @"map";

    _split = [[NSSplitViewController alloc] init];
    NSSplitViewItem *s = [NSSplitViewItem sidebarWithViewController:[self controllerWithView:sidebarStack]];
    s.minimumThickness = 210;
    s.maximumThickness = 300;
    NSSplitViewItem *l = [NSSplitViewItem splitViewItemWithViewController:[self controllerWithView:list]];
    l.minimumThickness = 420;
    NSSplitViewItem *d = [NSSplitViewItem splitViewItemWithViewController:_tabs];
    d.minimumThickness = 420;
    [_split addSplitViewItem:s];
    [_split addSplitViewItem:l];
    [_split addSplitViewItem:d];
    _split.splitView.autosaveName = @"RALibrarySplit";
    self.window.contentViewController = _split;
}

#pragma mark - toolbar

- (void)buildToolbar
{
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"RALibraryToolbar"];
    toolbar.delegate = self;
    toolbar.allowsUserCustomization = YES;
    toolbar.autosavesConfiguration = YES;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    self.window.toolbar = toolbar;
    self.window.toolbarStyle = NSWindowToolbarStyleUnified;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return @[ NSToolbarToggleSidebarItemIdentifier, RAToolbarImport, RAToolbarDevice, RAToolbarGarmin,
              NSToolbarFlexibleSpaceItemIdentifier, RAToolbarTrends, RAToolbarMap, RAToolbarDelete, RAToolbarFilter ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return @[ NSToolbarToggleSidebarItemIdentifier, RAToolbarImport, RAToolbarDevice, RAToolbarGarmin, RAToolbarTrends, RAToolbarMap,
              RAToolbarDelete, RAToolbarFilter, NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier ];
}

- (nullable NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
    willBeInsertedIntoToolbar:(BOOL)flag
{
    // identifier → label, tooltip, SF Symbol, action
    NSDictionary<NSString *, NSArray *> *items = @{
        RAToolbarImport: @[ NSLocalizedString(@"Import", @"toolbar"),
                            NSLocalizedString(@"Import FIT, GPX or TCX files or folders", @"toolbar"),
                            @"square.and.arrow.down", NSStringFromSelector(@selector(importFiles:)) ],
        RAToolbarDevice: @[ NSLocalizedString(@"Device", @"toolbar"),
                            NSLocalizedString(@"Import the rides of a device connected by USB", @"toolbar"),
                            @"externaldrive", NSStringFromSelector(@selector(importFromDevice:)) ],
        RAToolbarGarmin: @[ NSLocalizedString(@"Garmin Connect", @"toolbar"),
                            NSLocalizedString(@"Fetch the rides from Garmin Connect", @"toolbar"),
                            @"icloud.and.arrow.down", NSStringFromSelector(@selector(fetchFromGarminConnect:)) ],
        RAToolbarTrends: @[ NSLocalizedString(@"Trends", @"toolbar"),
                            NSLocalizedString(@"Progression, totals and records (⇧⌘T)", @"toolbar"),
                            @"chart.bar.xaxis", NSStringFromSelector(@selector(showTrends:)) ],
        RAToolbarMap: @[ NSLocalizedString(@"Map", @"toolbar"),
                         NSLocalizedString(@"All the rides on one map, the most ridden roads standing out (⇧⌘M)", @"toolbar"),
                         @"map", NSStringFromSelector(@selector(showRidesMap:)) ],
        RAToolbarDelete: @[ NSLocalizedString(@"Delete", @"toolbar"),
                            NSLocalizedString(@"Delete the selected rides", @"toolbar"),
                            @"trash", NSStringFromSelector(@selector(delete:)) ],
        RAToolbarFilter: @[ NSLocalizedString(@"Filter", @"toolbar"),
                            NSLocalizedString(@"Filter the rides: period, devices, distance, ascent, tags (⌥⌘F)", @"toolbar"),
                            @"line.3.horizontal.decrease.circle", NSStringFromSelector(@selector(editFilter:)) ],
    };
    NSArray *spec = items[identifier];
    if (!spec) return nil;
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = spec[0];
    item.paletteLabel = spec[0];
    item.toolTip = spec[1];
    item.image = [NSImage imageWithSystemSymbolName:spec[2] accessibilityDescription:spec[0]];
    item.target = self;
    item.action = NSSelectorFromString(spec[3]);
    item.bordered = YES;
    return item;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
    return [self validateAction:item.action];
}

#pragma mark - filter (R3)

/// the base filter (sidebar or sheet) with the search text
- (RAFilter *)currentFilter
{
    return [_baseFilter filterWithText:_search.stringValue ?: @""];
}

- (void)setBaseFilter:(RAFilter *)filter
{
    _baseFilter = [filter copy];
    [self reload];
}

- (void)searchChanged:(id)sender
{
    [self reload];
}

- (IBAction)editFilter:(nullable id)sender
{
    RALibraryDocument *library = self.library;
    NSMutableArray<NSArray<NSString *> *> *devices = [NSMutableArray array];
    for (NSString *k in library.deviceKeys ?: @[]) [devices addObject:@[ k, [library labelForDeviceKey:k] ]];
    _filterSheet = [[RAFilterSheet alloc] initWithFilter:_baseFilter devices:devices tags:library.allTags ?: @[]];
    [_filterSheet beginSheetForWindow:self.window completion:^(RAFilter *filter) {
        self->_filterSheet = nil;
        if (!filter) return;
        self->_sidebarSelection = nil; // a filter of its own, no longer the one of the sidebar
        [self setBaseFilter:filter];
    }];
}

- (IBAction)clearFilter:(nullable id)sender
{
    _search.stringValue = @"";
    _sidebarSelection = nil;
    [self setBaseFilter:[[RAFilter alloc] init]];
}

- (IBAction)saveFilter:(nullable id)sender
{
    RAFilter *filter = [self currentFilter];
    if (filter.empty) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Save the filter", @"save filter");
    alert.informativeText = [filter summaryWithDeviceLabel:^NSString *(NSString *k) { return [self.library labelForDeviceKey:k]; }];
    NSTextField *name = [NSTextField textFieldWithString:@""];
    name.placeholderString = NSLocalizedString(@"Name of the filter", @"save filter");
    name.frame = NSMakeRect(0, 0, 260, 24);
    alert.accessoryView = name;
    [alert addButtonWithTitle:NSLocalizedString(@"Save", @"button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"button")];
    alert.window.initialFirstResponder = name;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        NSString *n = [name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (response != NSAlertFirstButtonReturn || n.length == 0) return;
        RASavedFilter *saved = [self.library saveFilter:filter name:n];
        self->_search.stringValue = @"";
        self->_sidebarSelection = @{ @"kind": @(RASidebarSavedFilter), @"saved": saved };
        [self setBaseFilter:saved.filter];
    }];
}

- (IBAction)deleteSavedFilter:(nullable id)sender
{
    NSInteger row = _sidebar.clickedRow >= 0 ? _sidebar.clickedRow : _sidebar.selectedRow;
    if (row < 0 || (NSUInteger)row >= _sidebarRows.count) return;
    RASavedFilter *saved = _sidebarRows[(NSUInteger)row][@"saved"];
    if (saved) [self.library removeSavedFilter:saved];
}

- (NSPopUpButton *)filterPopupWithIdentifier:(NSString *)identifier action:(SEL)action
{
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    p.controlSize = NSControlSizeSmall;
    p.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    p.target = self;
    p.action = action;
    p.identifier = identifier;
    return p;
}

// an item whose representedObject is what choosing it does
- (void)addItem:(NSString *)title value:(id)value to:(NSPopUpButton *)popup
{
    [popup addItemWithTitle:title];
    popup.lastItem.representedObject = value;
}

/// the presets of the period pop-up: from day (nil: no limit), as offsets from today
- (NSArray<NSArray *> *)periodPresets
{
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today = [cal startOfDayForDate:[NSDate date]];
    NSDateComponents *year = [cal components:NSCalendarUnitYear fromDate:today];
    NSDate *startOfYear = [cal dateFromComponents:year] ?: today;
    return @[ @[ NSLocalizedString(@"Any date", @"filter period"), [NSNull null] ],
              @[ NSLocalizedString(@"Last 30 days", @"filter period"),
                 [cal dateByAddingUnit:NSCalendarUnitDay value:-30 toDate:today options:0] ?: today ],
              @[ NSLocalizedString(@"Last 12 months", @"filter period"),
                 [cal dateByAddingUnit:NSCalendarUnitYear value:-1 toDate:today options:0] ?: today ],
              @[ NSLocalizedString(@"This year", @"filter period"), startOfYear ] ];
}

/// rebuilds the pop-ups from the library and selects what the base filter says; a value that no item gives shows
/// as "Custom" (set with More…)
- (void)updateFilterPopups
{
    RALibraryDocument *library = self.library;
    NSCalendar *cal = [NSCalendar currentCalendar];

    [_periodPopup removeAllItems];
    NSInteger periodIndex = -1;
    for (NSArray *preset in [self periodPresets]) {
        [self addItem:preset[0] value:preset[1] to:_periodPopup];
        id from = preset[1];
        BOOL same = _baseFilter.toDay == nil && ([from isKindOfClass:[NSNull class]] ? _baseFilter.fromDay == nil
            : (_baseFilter.fromDay && [cal isDate:(NSDate *)_baseFilter.fromDay inSameDayAsDate:from]));
        if (same) periodIndex = _periodPopup.numberOfItems - 1;
    }
    if (periodIndex < 0) {
        [self addItem:NSLocalizedString(@"Custom period", @"filter period") value:@"custom" to:_periodPopup];
        periodIndex = _periodPopup.numberOfItems - 1;
    }
    [_periodPopup selectItemAtIndex:periodIndex];

    [_devicePopup removeAllItems];
    [self addItem:NSLocalizedString(@"Any device", @"filter device") value:[NSNull null] to:_devicePopup];
    NSInteger deviceIndex = _baseFilter.deviceKeys.count == 0 ? 0 : -1;
    for (NSString *k in library.deviceKeys ?: @[]) {
        [self addItem:[library labelForDeviceKey:k] value:k to:_devicePopup];
        if (_baseFilter.deviceKeys.count == 1 && [_baseFilter.deviceKeys containsObject:k]) {
            deviceIndex = _devicePopup.numberOfItems - 1;
        }
    }
    if (deviceIndex < 0) {
        [self addItem:NSLocalizedString(@"Several devices", @"filter device") value:@"custom" to:_devicePopup];
        deviceIndex = _devicePopup.numberOfItems - 1;
    }
    [_devicePopup selectItemAtIndex:deviceIndex];

    // distance: from 0 to the longest ride, rounded up to 10 km (and up to the limits of the filter)
    double longest = 0;
    for (RARide *r in library.rides ?: @[]) longest = MAX(longest, r.distance);
    double top = MAX(50, ceil(MAX(longest, MAX(_baseFilter.minDistance, _baseFilter.maxDistance)) / 10000) * 10);
    _distanceSlider.minValue = 0;
    _distanceSlider.maxValue = top;
    _distanceSlider.step = 1;
    _distanceSlider.lowerValue = _baseFilter.minDistance / 1000;
    _distanceSlider.upperValue = _baseFilter.maxDistance > 0 ? _baseFilter.maxDistance / 1000 : top;
    [self updateDistanceLabel];

    [_tagPopup removeAllItems];
    [self addItem:NSLocalizedString(@"Any tag", @"filter tag") value:[NSNull null] to:_tagPopup];
    NSInteger tagIndex = _baseFilter.tags.count == 0 ? 0 : -1;
    for (NSString *t in library.allTags ?: @[]) {
        [self addItem:[@"#" stringByAppendingString:t] value:t to:_tagPopup];
        if (_baseFilter.tags.count == 1 && [_baseFilter.tags containsObject:t]) tagIndex = _tagPopup.numberOfItems - 1;
    }
    if (tagIndex < 0) {
        [self addItem:NSLocalizedString(@"Several tags", @"filter tag") value:@"custom" to:_tagPopup];
        tagIndex = _tagPopup.numberOfItems - 1;
    }
    [_tagPopup selectItemAtIndex:tagIndex];
    _tagPopup.hidden = _tagPopup.numberOfItems <= 1;
}

/// a criterion changed in the filter bar: the base filter is no longer the one of a saved filter or of a device
- (void)changeBaseFilter:(void (^)(RAFilter *filter))change
{
    RAFilter *f = [_baseFilter copy];
    change(f);
    _sidebarSelection = nil;
    [self setBaseFilter:f];
}

- (void)periodChosen:(NSPopUpButton *)sender
{
    id value = sender.selectedItem.representedObject;
    if ([value isEqual:@"custom"]) return;
    [self changeBaseFilter:^(RAFilter *f) {
        f.fromDay = [value isKindOfClass:[NSDate class]] ? value : nil;
        f.toDay = nil;
    }];
}

- (void)deviceChosen:(NSPopUpButton *)sender
{
    id value = sender.selectedItem.representedObject;
    if ([value isEqual:@"custom"]) return;
    [self changeBaseFilter:^(RAFilter *f) {
        f.deviceKeys = [value isKindOfClass:[NSString class]] ? [NSSet setWithObject:value] : [NSSet set];
    }];
}

/// the limits of the slider in meters; 0: no limit (an end of the slider)
- (double)sliderMinDistance
{
    return _distanceSlider.lowerValue > _distanceSlider.minValue ? _distanceSlider.lowerValue * 1000 : 0;
}

- (double)sliderMaxDistance
{
    return _distanceSlider.upperValue < _distanceSlider.maxValue ? _distanceSlider.upperValue * 1000 : 0;
}

- (void)updateDistanceLabel
{
    double lo = [self sliderMinDistance] / 1000, hi = [self sliderMaxDistance] / 1000;
    NSString *range = lo > 0 && hi > 0 ? [NSString localizedStringWithFormat:@"%.0f – %.0f km", lo, hi]
        : lo > 0 ? [NSString localizedStringWithFormat:NSLocalizedString(@"over %.0f km", @"filter distance"), lo]
        : hi > 0 ? [NSString localizedStringWithFormat:NSLocalizedString(@"under %.0f km", @"filter distance"), hi]
        : NSLocalizedString(@"any", @"filter distance");
    _distanceLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Distance: %@", @"filter distance"), range];
}

- (void)distanceChosen:(RARangeSlider *)sender
{
    [self updateDistanceLabel];
    if (sender.tracking) return;     // applied when the knob is released
    double lo = [self sliderMinDistance], hi = [self sliderMaxDistance];
    if (lo == _baseFilter.minDistance && hi == _baseFilter.maxDistance) return;
    [self changeBaseFilter:^(RAFilter *f) {
        f.minDistance = lo;
        f.maxDistance = hi;
    }];
}

- (void)tagChosen:(NSPopUpButton *)sender
{
    id value = sender.selectedItem.representedObject;
    if ([value isEqual:@"custom"]) return;
    [self changeBaseFilter:^(RAFilter *f) {
        f.tags = [value isKindOfClass:[NSString class]] ? [NSSet setWithObject:value] : [NSSet set];
    }];
}

- (void)updateFilterBar
{
    [self updateFilterPopups];
    RAFilter *f = [self currentFilter];
    NSString *summary = [_baseFilter summaryWithDeviceLabel:^NSString *(NSString *k) { return [self.library labelForDeviceKey:k]; }];
    _filterSummary.stringValue = summary.length ? summary : NSLocalizedString(@"All rides", @"filter summary");
    _filterSummary.toolTip = summary;
    _clearFilterButton.enabled = !f.empty;
    _saveFilterButton.enabled = !f.empty;
}

#pragma mark - content

- (void)libraryDidChange:(NSNotification *)n
{
    [self reload];
}

- (void)reloadSidebar
{
    RALibraryDocument *library = self.library;
    // all rides: Clear in the filter above
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    NSArray<RASavedFilter *> *saved = library.savedFilters ?: @[];
    if (saved.count) {
        [rows addObject:@{ @"kind": @(RASidebarHeader), @"title": NSLocalizedString(@"Saved Filters", @"sidebar") }];
        for (RASavedFilter *f in saved) [rows addObject:@{ @"kind": @(RASidebarSavedFilter), @"title": f.name, @"saved": f }];
    }
    NSArray<NSString *> *keys = library.deviceKeys ?: @[];
    if (keys.count) {
        [rows addObject:@{ @"kind": @(RASidebarHeader), @"title": NSLocalizedString(@"Devices", @"sidebar") }];
        for (NSString *k in keys) {
            [rows addObject:@{ @"kind": @(RASidebarDevice), @"title": [library labelForDeviceKey:k], @"key": k }];
        }
    }
    _sidebarRows = rows;
    [_sidebar reloadData];
    // keep the selected row (the same saved filter or device); none when the filter is the sheet's
    NSInteger selected = -1;
    for (NSUInteger i = 0; i < rows.count && _sidebarSelection; i++) {
        if ((_sidebarSelection[@"saved"] && rows[i][@"saved"] == _sidebarSelection[@"saved"])
            || (_sidebarSelection[@"key"] && [rows[i][@"key"] isEqualToString:_sidebarSelection[@"key"]])) {
            selected = (NSInteger)i;
        }
    }
    if (selected >= 0) [_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)selected] byExtendingSelection:NO];
    else [_sidebar deselectAll:self];
}

- (void)reload
{
    if (!_table) return;
    [self reloadSidebar];
    NSArray<RARide *> *selected = [self selectedRides];
    NSArray<RARide *> *rides = [[self currentFilter] filteredRides:self.library.rides ?: @[]];
    _sorted = [rides sortedArrayUsingDescriptors:_table.sortDescriptors];
    [_table reloadData];
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (RARide *r in selected) {
        NSUInteger i = [_sorted indexOfObjectIdenticalTo:r];
        if (i != NSNotFound) [rows addIndex:i];
    }
    [_table selectRowIndexes:rows byExtendingSelection:NO];
    [self updateFooter];
    [self updateFilterBar];
    [self showSelection];
    [_detail refreshRideInfo];
}

/// the detail of the selected ride; the trends of the selected rides, or of the list when fewer than two are
- (void)showSelection
{
    NSArray<RARide *> *selected = [self selectedRides];
    [_detail showRides:selected];
    BOOL several = selected.count >= 2;
    [_trends showRides:several ? selected : _sorted selected:several];
    [_ridesMap showRides:several ? selected : _sorted selected:several];
}

- (NSArray<RARide *> *)selectedRides
{
    NSMutableArray<RARide *> *rides = [NSMutableArray array];
    [_table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (i < self->_sorted.count) [rides addObject:self->_sorted[i]];
    }];
    return rides;
}

- (NSString *)kilometers:(double)meters
{
    return [NSString localizedStringWithFormat:@"%.1f", meters / 1000];
}

- (NSString *)durationString:(NSTimeInterval)t
{
    if (t <= 0) return @"—";
    long minutes = lround(t / 60);
    return [NSString localizedStringWithFormat:NSLocalizedString(@"%ld h %02ld", @"duration: hours, minutes"),
            minutes / 60, minutes % 60];
}

- (void)updateFooter
{
    double distance = 0, ascent = 0, duration = 0;
    for (RARide *r in _sorted) {
        distance += r.distance;
        ascent += r.ascent;
        duration += r.duration;
    }
    NSUInteger total = self.library.rides.count;
    NSString *of = _sorted.count == total ? @""
        : [NSString localizedStringWithFormat:NSLocalizedString(@" (of %lu)", @"list footer"), (unsigned long)total];
    _footer.stringValue = [NSString localizedStringWithFormat:
        NSLocalizedString(@"%lu rides%@ · %@ km · %.0f m ascent · %@", @"list footer"),
        (unsigned long)_sorted.count, of, [self kilometers:distance], ascent, [self durationString:duration]];
}

#pragma mark - table data source and delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return tableView == _sidebar ? (NSInteger)_sidebarRows.count : (NSInteger)_sorted.count;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
    return tableView == _sidebar && [_sidebarRows[(NSUInteger)row][@"kind"] integerValue] == RASidebarHeader;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    return ![self tableView:tableView isGroupRow:row];
}

- (NSView *)sidebarViewForRow:(NSInteger)row
{
    NSDictionary *item = _sidebarRows[(NSUInteger)row];
    NSTextField *f = [NSTextField labelWithString:item[@"title"] ?: @""];
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    RASidebarKind kind = (RASidebarKind)[item[@"kind"] integerValue];
    if (kind == RASidebarDevice || kind == RASidebarSavedFilter) {
        // names editable in place (double-click), undoable
        f.editable = YES;
        f.delegate = self;
        f.identifier = kind == RASidebarDevice ? [@"device." stringByAppendingString:item[@"key"]]
                                               : [@"filter." stringByAppendingString:((RASavedFilter *)item[@"saved"]).identifier];
    }
    return f;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn
                           row:(NSInteger)row
{
    if (tableView == _sidebar) return [self sidebarViewForRow:row];
    RARide *ride = _sorted[(NSUInteger)row];
    NSString *ident = tableColumn.identifier;
    NSString *text = @"";
    BOOL numeric = NO;
    BOOL editable = NO;
    if ([ident isEqualToString:RAColumnDate]) {
        text = ride.startDate ? [_dateFormatter stringFromDate:ride.startDate] : @"—";
    } else if ([ident isEqualToString:RAColumnName]) {
        text = ride.name;
        editable = YES;
    } else if ([ident isEqualToString:RAColumnDistance]) {
        text = [self kilometers:ride.distance];
        numeric = YES;
    } else if ([ident isEqualToString:RAColumnAscent]) {
        text = [NSString localizedStringWithFormat:@"%.0f", ride.ascent];
        numeric = YES;
    } else if ([ident isEqualToString:RAColumnDuration]) {
        text = [self durationString:ride.duration];
        numeric = YES;
    } else if ([ident isEqualToString:RAColumnSpeed]) {
        text = ride.averageSpeed > 0 ? [NSString localizedStringWithFormat:@"%.1f", ride.averageSpeed] : @"—";
        numeric = YES;
    } else if ([ident isEqualToString:RAColumnDevice]) {
        text = [self.library labelForDeviceKey:ride.deviceKey];
    }
    NSTextField *field = [NSTextField labelWithString:text];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    if (numeric) field.alignment = NSTextAlignmentRight;
    if (editable) {
        field.editable = YES;
        field.target = self;
        field.action = @selector(renameFromField:);
    }
    return field;
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors
{
    if (tableView == _table) [self reload];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (notification.object == _table) {
        [self showSelection];
        return;
    }
    if (notification.object != _sidebar) return;
    NSInteger row = _sidebar.selectedRow;
    if (row < 0) return; // deselected by the code (a filter of the sheet)
    NSDictionary *item = _sidebarRows[(NSUInteger)row];
    RAFilter *filter = [[RAFilter alloc] init];
    switch ((RASidebarKind)[item[@"kind"] integerValue]) {
        case RASidebarAll:
        case RASidebarHeader:
            _sidebarSelection = nil;
            break;
        case RASidebarSavedFilter:
            filter = ((RASavedFilter *)item[@"saved"]).filter;
            _sidebarSelection = item;
            break;
        case RASidebarDevice:
            filter.deviceKeys = [NSSet setWithObject:item[@"key"]];
            _sidebarSelection = item;
            break;
    }
    if ([filter isEqual:_baseFilter]) return;
    [self setBaseFilter:filter];
}

- (void)renameFromField:(NSTextField *)field
{
    NSInteger row = [_table rowForView:field];
    if (row < 0 || (NSUInteger)row >= _sorted.count) return;
    NSString *name = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    RARide *ride = _sorted[(NSUInteger)row];
    if (name.length == 0) {
        field.stringValue = ride.name;
        return;
    }
    [self.library renameRide:ride to:name];
}

// end of the edition of a device or filter name in the sidebar
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    NSString *label = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([field.identifier hasPrefix:@"device."]) {
        NSString *key = [field.identifier substringFromIndex:@"device.".length];
        [self.library setLabel:label forDeviceKey:key];
        field.stringValue = [self.library labelForDeviceKey:key];
    } else if ([field.identifier hasPrefix:@"filter."]) {
        NSString *identifier = [field.identifier substringFromIndex:@"filter.".length];
        for (RASavedFilter *f in self.library.savedFilters) {
            if ([f.identifier isEqualToString:identifier]) {
                [self.library renameSavedFilter:f to:label];
                field.stringValue = f.name;
            }
        }
    }
}

// drag and drop of files or folders on the list (R2)
- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
    if (tableView != _table || !self.library || self.library.importing) return NSDragOperationNone;
    [tableView setDropRow:-1 dropOperation:NSTableViewDropOn];
    return NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation
{
    NSArray<NSURL *> *urls = [info.draggingPasteboard readObjectsForClasses:@[ [NSURL class] ]
        options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
    if (urls.count == 0) return NO;
    [self importURLs:urls];
    return YES;
}

#pragma mark - progress of an import

- (void)observeProgress:(nullable NSProgress *)progress
{
    if (_progress) {
        [_progress removeObserver:self forKeyPath:@"fractionCompleted" context:RAProgressContext];
        [_progress removeObserver:self forKeyPath:@"localizedDescription" context:RAProgressContext];
    }
    _progress = progress;
    if (progress) {
        [progress addObserver:self forKeyPath:@"fractionCompleted" options:0 context:RAProgressContext];
        [progress addObserver:self forKeyPath:@"localizedDescription" options:0 context:RAProgressContext];
    }
    [self updateProgressBar];
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object
                        change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context
{
    if (context != RAProgressContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateProgressBar]; }); // reported from any thread
}

- (void)updateProgressBar
{
    _progressBar.hidden = _progress == nil;
    if (!_progress) return;
    _progressIndicator.doubleValue = _progress.fractionCompleted;
    _progressLabel.stringValue = _progress.localizedDescription ?: @"";
}

- (IBAction)cancelImport:(nullable id)sender
{
    [_progress cancel];
}

- (void)showSummary:(RAImportSummary *)summary
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = summary.cancelled
        ? [NSString localizedStringWithFormat:NSLocalizedString(@"Import cancelled: %lu rides imported", @"import summary"),
           (unsigned long)summary.imported]
        : [NSString localizedStringWithFormat:NSLocalizedString(@"%lu rides imported", @"import summary"),
           (unsigned long)summary.imported];
    alert.informativeText = [NSString localizedStringWithFormat:
        NSLocalizedString(@"Already in the library: %lu. Unreadable: %lu.", @"import summary"),
        (unsigned long)summary.duplicates, (unsigned long)summary.unreadable];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - actions

- (void)importURLs:(NSArray<NSURL *> *)urls
{
    NSProgress *progress = [self.library importFilesAtURLs:urls completion:^(RAImportSummary *summary) {
        [self observeProgress:nil];
        if (urls.count == 1 && summary.imported == 1 && !summary.cancelled) return; // one file: no summary needed
        [self showSummary:summary];
    }];
    if (progress) [self observeProgress:progress];
    else NSBeep(); // an import is running
}

- (IBAction)importFiles:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = YES;
    panel.allowedContentTypes = [BPTrackReader importContentTypes];
    panel.message = NSLocalizedString(@"Choose FIT, GPX or TCX files, or folders.", @"import panel");
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) [self importURLs:panel.URLs];
    }];
}

- (IBAction)importFromDevice:(id)sender
{
    NSArray<NSURL *> *folders = [RALibraryDocument deviceActivityFoldersInVolumes:nil];
    if (folders.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"No device found", @"import from device");
        alert.informativeText = NSLocalizedString(
            @"Connect the bike computer or the watch with its USB cable: it shows as a disk with a Garmin/Activity "
            @"folder. Recent devices that do not show as a disk send their rides to Garmin Connect: use File ▸ "
            @"Fetch from Garmin Connect…", @"import from device");
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    // the sandbox needs the user's choice: the panel opens on the Activity folder, the user confirms it
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = YES;
    panel.directoryURL = folders.firstObject;
    panel.prompt = NSLocalizedString(@"Import", @"import from device");
    panel.message = NSLocalizedString(@"Select the Activity folder to import all its rides (those already in the "
                                      @"library are skipped), or some of its files.", @"import from device");
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) [self importURLs:panel.URLs];
    }];
}

- (IBAction)fetchFromGarminConnect:(id)sender
{
    RALibraryDocument *library = self.library;
    if (!library || library.importing) return;
    _garminSheet = [[RAGarminFetchSheet alloc] initWithKey:library.garminKey
                                            keepInDocument:library.keepsGarminKeyInDocument
                                                 lastFetch:library.garminLastFetch];
    [_garminSheet beginSheetForWindow:self.window
                           completion:^(BOOL fetch, NSString *key, BOOL keepInDocument, NSDate *since) {
        self->_garminSheet = nil;
        if (!fetch) return;
        [library setGarminKey:key keepInDocument:keepInDocument];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:
                                 [NSURLSessionConfiguration ephemeralSessionConfiguration]];
        RAGarminConnect *client = [[RAGarminConnect alloc] initWithKey:key session:session];
        NSProgress *progress = [library fetchFromGarmin:client since:since
                                             completion:^(RAImportSummary *summary, NSError *error) {
            [session finishTasksAndInvalidate];
            [self observeProgress:nil];
            if (error) {
                [self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
            } else if (summary) {
                [self showSummary:summary];
            }
        }];
        [self observeProgress:progress];
    }];
}

- (IBAction)delete:(nullable id)sender
{
    NSArray<RARide *> *rides = [self selectedRides];
    if (rides.count) [self.library removeRides:rides];
}

- (IBAction)showTrends:(nullable id)sender
{
    // the Trends tab, or back to the Ride tab when it shows
    _tabs.selectedTabViewItemIndex = _tabs.selectedTabViewItemIndex == 1 ? 0 : 1;
    [self showSelection];
}

- (IBAction)showRidesMap:(nullable id)sender
{
    // the Map tab, or back to the Ride tab when it shows
    _tabs.selectedTabViewItemIndex = _tabs.selectedTabViewItemIndex == 2 ? 0 : 2;
    [self showSelection];
}

- (IBAction)focusSearch:(nullable id)sender
{
    [self.window makeFirstResponder:_search];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    return [self validateAction:item.action];
}

// menus and toolbar
- (BOOL)validateAction:(nullable SEL)action
{
    if (action == @selector(delete:)) return _table.selectedRowIndexes.count > 0;
    if (action == @selector(importFiles:) || action == @selector(importFromDevice:)
        || action == @selector(fetchFromGarminConnect:)) {
        return self.library && !self.library.importing;
    }
    if (action == @selector(saveFilter:) || action == @selector(clearFilter:)) return ![self currentFilter].empty;
    if (action == @selector(deleteSavedFilter:)) {
        NSInteger row = _sidebar.clickedRow >= 0 ? _sidebar.clickedRow : _sidebar.selectedRow;
        return row >= 0 && (NSUInteger)row < _sidebarRows.count && _sidebarRows[(NSUInteger)row][@"saved"] != nil;
    }
    return YES;
}

@end
