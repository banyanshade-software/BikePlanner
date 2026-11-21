//
//  RALibraryWindowController.m
//  RideAnalyzer
//

#import "RALibraryWindowController.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RAGarminConnect.h"
#import "RAGarminFetchSheet.h"
#import "BPTrackReader.h"

static NSUserInterfaceItemIdentifier const RAColumnDate = @"date";
static NSUserInterfaceItemIdentifier const RAColumnName = @"name";
static NSUserInterfaceItemIdentifier const RAColumnDistance = @"distance";
static NSUserInterfaceItemIdentifier const RAColumnAscent = @"ascent";
static NSUserInterfaceItemIdentifier const RAColumnDuration = @"duration";
static NSUserInterfaceItemIdentifier const RAColumnSpeed = @"speed";
static NSUserInterfaceItemIdentifier const RAColumnDevice = @"device";

static void *RAProgressContext = &RAProgressContext;

// a row of the sidebar
typedef NS_ENUM(NSInteger, RASidebarKind) { RASidebarAll, RASidebarHeader, RASidebarDevice };

@interface RALibraryWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate,
                                         NSMenuItemValidation, NSTextFieldDelegate>
@end

@implementation RALibraryWindowController
{
    NSSplitViewController *_split;
    NSTableView *_sidebar;
    NSArray<NSDictionary *> *_sidebarRows;      // @{ @"kind": @(RASidebarKind), @"key": device key }
    NSString *_deviceFilter;                    // nil: all rides
    NSTableView *_table;
    NSArray<RARide *> *_sorted;
    NSTextField *_footer;
    NSStackView *_progressBar;
    NSTextField *_progressLabel;
    NSProgressIndicator *_progressIndicator;
    NSProgress *_progress;
    NSTextField *_detailTitle;
    NSTextField *_detailSubtitle;
    NSGridView *_detailFigures;
    NSStackView *_detail;
    NSDateFormatter *_dateFormatter;
    NSDateFormatter *_longDateFormatter;
    RAGarminFetchSheet *_garminSheet;
}

- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 760)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                  | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered defer:YES];
    window.minSize = NSMakeSize(800, 500);
    self = [super initWithWindow:window];
    if (self) {
        window.delegate = self;
        window.identifier = @"library";
        _sorted = @[];
        _sidebarRows = @[];
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateStyle = NSDateFormatterShortStyle;
        _dateFormatter.timeStyle = NSDateFormatterNoStyle;
        _longDateFormatter = [[NSDateFormatter alloc] init];
        _longDateFormatter.dateStyle = NSDateFormatterFullStyle;
        _longDateFormatter.timeStyle = NSDateFormatterShortStyle;
        [self buildContent];
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
    // sidebar: all rides, then the devices (R3)
    _sidebar = [[NSTableView alloc] init];
    _sidebar.headerView = nil;
    _sidebar.style = NSTableViewStyleSourceList;
    [_sidebar addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"section"]];
    _sidebar.dataSource = self;
    _sidebar.delegate = self;
    _sidebar.identifier = @"sidebar";
    NSScrollView *sidebarScroll = [self scrollViewWithTable:_sidebar];

    // rides
    _table = [[NSTableView alloc] init];
    _table.identifier = @"rides";
    _table.allowsMultipleSelection = YES;
    _table.usesAlternatingRowBackgroundColors = YES;
    _table.dataSource = self;
    _table.delegate = self;
    NSArray *columns = @[
        @[ RAColumnDate, NSLocalizedString(@"Date", @"column"), @"startDate", @90 ],
        @[ RAColumnName, NSLocalizedString(@"Name", @"column"), @"name", @200 ],
        @[ RAColumnDistance, NSLocalizedString(@"km", @"column"), @"distance", @60 ],
        @[ RAColumnAscent, NSLocalizedString(@"Ascent", @"column"), @"ascent", @60 ],
        @[ RAColumnDuration, NSLocalizedString(@"Duration", @"column"), @"duration", @70 ],
        @[ RAColumnSpeed, NSLocalizedString(@"Avg.", @"column"), @"averageSpeed", @60 ],
        @[ RAColumnDevice, NSLocalizedString(@"Device", @"column"), @"deviceKey", @100 ],
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
    _progressBar.edgeInsets = NSEdgeInsetsMake(6, 10, 6, 10);
    _progressBar.hidden = YES;

    _footer = [NSTextField labelWithString:@""];
    _footer.textColor = [NSColor secondaryLabelColor];
    _footer.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    NSStackView *list = [NSStackView stackViewWithViews:@[ _progressBar, tableScroll, _footer ]];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.distribution = NSStackViewDistributionFill;
    list.detachesHiddenViews = YES;
    [tableScroll setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    list.edgeInsets = NSEdgeInsetsMake(0, 0, 8, 0);
    list.spacing = 6;
    [tableScroll.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    [_progressBar.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    [_footer.leadingAnchor constraintEqualToAnchor:list.leadingAnchor constant:10].active = YES;

    // detail (R4: map, profile and curves to come)
    _detailTitle = [NSTextField labelWithString:@""];
    _detailTitle.font = [NSFont boldSystemFontOfSize:20];
    _detailSubtitle = [NSTextField labelWithString:@""];
    _detailSubtitle.textColor = [NSColor secondaryLabelColor];
    _detailFigures = [NSGridView gridViewWithNumberOfColumns:2 rows:0];
    _detailFigures.rowSpacing = 6;
    _detailFigures.columnSpacing = 16;
    NSTextField *placeholder = [NSTextField wrappingLabelWithString:NSLocalizedString(
        @"Map, elevation profile and curves of the ride: to come.", @"detail placeholder")];
    placeholder.textColor = [NSColor tertiaryLabelColor];
    _detail = [NSStackView stackViewWithViews:@[ _detailTitle, _detailSubtitle, _detailFigures, placeholder ]];
    _detail.orientation = NSUserInterfaceLayoutOrientationVertical;
    _detail.alignment = NSLayoutAttributeLeading;
    _detail.spacing = 10;
    _detail.edgeInsets = NSEdgeInsetsMake(40, 20, 20, 20);
    NSView *detailContainer = [[NSView alloc] init];
    _detail.translatesAutoresizingMaskIntoConstraints = NO;
    [detailContainer addSubview:_detail];
    [NSLayoutConstraint activateConstraints:@[
        [_detail.topAnchor constraintEqualToAnchor:detailContainer.topAnchor],
        [_detail.leadingAnchor constraintEqualToAnchor:detailContainer.leadingAnchor],
        [_detail.trailingAnchor constraintEqualToAnchor:detailContainer.trailingAnchor],
        [_detail.bottomAnchor constraintLessThanOrEqualToAnchor:detailContainer.bottomAnchor],
    ]];

    _split = [[NSSplitViewController alloc] init];
    NSSplitViewItem *s = [NSSplitViewItem sidebarWithViewController:[self controllerWithView:sidebarScroll]];
    s.minimumThickness = 180;
    s.maximumThickness = 260;
    NSSplitViewItem *l = [NSSplitViewItem splitViewItemWithViewController:[self controllerWithView:list]];
    l.minimumThickness = 420;
    NSSplitViewItem *d = [NSSplitViewItem splitViewItemWithViewController:[self controllerWithView:detailContainer]];
    d.minimumThickness = 300;
    [_split addSplitViewItem:s];
    [_split addSplitViewItem:l];
    [_split addSplitViewItem:d];
    _split.splitView.autosaveName = @"RALibrarySplit";
    self.window.contentViewController = _split;
}

#pragma mark - content

- (void)libraryDidChange:(NSNotification *)n
{
    [self reload];
}

- (void)reloadSidebar
{
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithObject:@{ @"kind": @(RASidebarAll) }];
    NSArray<NSString *> *keys = self.library.deviceKeys ?: @[];
    if (keys.count) {
        [rows addObject:@{ @"kind": @(RASidebarHeader) }];
        for (NSString *k in keys) [rows addObject:@{ @"kind": @(RASidebarDevice), @"key": k }];
    }
    if (_deviceFilter && ![keys containsObject:_deviceFilter]) _deviceFilter = nil;
    _sidebarRows = rows;
    [_sidebar reloadData];
    NSUInteger selected = 0;
    for (NSUInteger i = 0; i < rows.count; i++) {
        if (_deviceFilter && [rows[i][@"key"] isEqualToString:_deviceFilter]) selected = i;
    }
    [_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:selected] byExtendingSelection:NO];
}

- (void)reload
{
    if (!_table) return;
    [self reloadSidebar];
    NSArray<RARide *> *selected = [self selectedRides];
    NSArray<RARide *> *rides = self.library.rides ?: @[];
    if (_deviceFilter) {
        rides = [rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"deviceKey == %@", _deviceFilter]];
    }
    _sorted = [rides sortedArrayUsingDescriptors:_table.sortDescriptors];
    [_table reloadData];
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (RARide *r in selected) {
        NSUInteger i = [_sorted indexOfObjectIdenticalTo:r];
        if (i != NSNotFound) [rows addIndex:i];
    }
    [_table selectRowIndexes:rows byExtendingSelection:NO];
    [self updateFooter];
    [self updateDetail];
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
    _footer.stringValue = [NSString localizedStringWithFormat:
        NSLocalizedString(@"%lu rides · %@ km · %.0f m ascent · %@", @"list footer"),
        (unsigned long)_sorted.count, [self kilometers:distance], ascent, [self durationString:duration]];
}

- (void)addFigure:(NSString *)label value:(NSString *)value
{
    NSTextField *l = [NSTextField labelWithString:label];
    l.textColor = [NSColor secondaryLabelColor];
    NSTextField *v = [NSTextField labelWithString:value];
    v.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    [_detailFigures addRowWithViews:@[ l, v ]];
}

- (void)updateDetail
{
    while (_detailFigures.numberOfRows > 0) [_detailFigures removeRowAtIndex:0];
    NSArray<RARide *> *selected = [self selectedRides];
    if (selected.count != 1) {
        _detailTitle.stringValue = selected.count == 0 ? NSLocalizedString(@"No Ride Selected", @"detail")
            : [NSString localizedStringWithFormat:NSLocalizedString(@"%lu Rides Selected", @"detail"),
               (unsigned long)selected.count];
        _detailSubtitle.stringValue = @"";
        return;
    }
    RARide *ride = selected.firstObject;
    _detailTitle.stringValue = ride.name;
    _detailSubtitle.stringValue = [NSString stringWithFormat:@"%@ · %@ · %@",
        ride.startDate ? [_longDateFormatter stringFromDate:ride.startDate] : @"—",
        [self.library labelForDeviceKey:ride.deviceKey], ride.format.uppercaseString];
    [self addFigure:NSLocalizedString(@"Distance", @"figure")
              value:[NSString stringWithFormat:@"%@ km", [self kilometers:ride.distance]]];
    [self addFigure:NSLocalizedString(@"Ascent", @"figure")
              value:[NSString localizedStringWithFormat:@"%.0f m", ride.ascent]];
    [self addFigure:NSLocalizedString(@"Duration", @"figure") value:[self durationString:ride.duration]];
    [self addFigure:NSLocalizedString(@"Average speed", @"figure")
              value:ride.averageSpeed > 0 ? [NSString localizedStringWithFormat:@"%.1f km/h", ride.averageSpeed]
                                          : @"—"];
    if (ride.garminActivityID.length) {
        [self addFigure:NSLocalizedString(@"Garmin Connect", @"figure") value:ride.garminActivityID];
    }
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
    switch ((RASidebarKind)[item[@"kind"] integerValue]) {
        case RASidebarAll:
            return [NSTextField labelWithString:NSLocalizedString(@"All Rides", @"sidebar")];
        case RASidebarHeader:
            return [NSTextField labelWithString:NSLocalizedString(@"Devices", @"sidebar")];
        case RASidebarDevice: {
            // the device name can be edited in place (double-click), undoable
            NSTextField *f = [NSTextField labelWithString:[self.library labelForDeviceKey:item[@"key"]]];
            f.editable = YES;
            f.delegate = self;
            f.identifier = [@"device." stringByAppendingString:item[@"key"]];
            f.lineBreakMode = NSLineBreakByTruncatingTail;
            return f;
        }
    }
    return [NSTextField labelWithString:@""];
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
        [self updateDetail];
    } else if (notification.object == _sidebar) {
        NSInteger row = _sidebar.selectedRow;
        NSString *filter = row >= 0 ? _sidebarRows[(NSUInteger)row][@"key"] : nil;
        if (filter == _deviceFilter || [filter isEqualToString:_deviceFilter]) return;
        _deviceFilter = filter;
        [self reload];
    }
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

// end of the edition of a device name in the sidebar
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    if (![field.identifier hasPrefix:@"device."]) return;
    NSString *key = [field.identifier substringFromIndex:@"device.".length];
    NSString *label = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    [self.library setLabel:label forDeviceKey:key];
    field.stringValue = [self.library labelForDeviceKey:key];
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
    id<RAKeyStore> store = [RAKeychainKeyStore shared];
    _garminSheet = [[RAGarminFetchSheet alloc] initWithKey:[store keyForLibrary:library.libraryID]
                                                 lastFetch:library.garminLastFetch];
    [_garminSheet beginSheetForWindow:self.window completion:^(BOOL fetch, NSString *key, NSDate *since) {
        self->_garminSheet = nil;
        if (!fetch) return;
        if (![key isEqualToString:[store keyForLibrary:library.libraryID] ?: @""]) {
            [store setKey:key forLibrary:library.libraryID];
        }
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

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(delete:)) return _table.selectedRowIndexes.count > 0;
    if (item.action == @selector(importFiles:) || item.action == @selector(importFromDevice:)
        || item.action == @selector(fetchFromGarminConnect:)) {
        return self.library && !self.library.importing;
    }
    return YES;
}

@end
