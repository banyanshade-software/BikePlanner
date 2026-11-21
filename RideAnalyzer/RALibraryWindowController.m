//
//  RALibraryWindowController.m
//  RideAnalyzer
//

#import "RALibraryWindowController.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "BPTrackReader.h"

static NSUserInterfaceItemIdentifier const RAColumnDate = @"date";
static NSUserInterfaceItemIdentifier const RAColumnName = @"name";
static NSUserInterfaceItemIdentifier const RAColumnDistance = @"distance";
static NSUserInterfaceItemIdentifier const RAColumnAscent = @"ascent";
static NSUserInterfaceItemIdentifier const RAColumnDuration = @"duration";
static NSUserInterfaceItemIdentifier const RAColumnSpeed = @"speed";

@interface RALibraryWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSMenuItemValidation>
@end

@implementation RALibraryWindowController
{
    NSSplitViewController *_split;
    NSTableView *_sidebar;
    NSArray<NSString *> *_sections;
    NSTableView *_table;
    NSArray<RARide *> *_sorted;
    NSTextField *_footer;
    NSTextField *_detailTitle;
    NSTextField *_detailSubtitle;
    NSGridView *_detailFigures;
    NSStackView *_detail;
    NSDateFormatter *_dateFormatter;
    NSDateFormatter *_longDateFormatter;
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
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateStyle = NSDateFormatterShortStyle;
        _dateFormatter.timeStyle = NSDateFormatterNoStyle;
        _longDateFormatter = [[NSDateFormatter alloc] init];
        _longDateFormatter.dateStyle = NSDateFormatterFullStyle;
        _longDateFormatter.timeStyle = NSDateFormatterShortStyle;
        _sections = @[
            NSLocalizedString(@"All Rides", @"sidebar"),
            NSLocalizedString(@"Trends", @"sidebar"),
            NSLocalizedString(@"Map of All Rides", @"sidebar"),
            NSLocalizedString(@"Equipment", @"sidebar"),
        ];
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
    // sidebar
    _sidebar = [[NSTableView alloc] init];
    _sidebar.headerView = nil;
    _sidebar.style = NSTableViewStyleSourceList;
    NSTableColumn *sc = [[NSTableColumn alloc] initWithIdentifier:@"section"];
    [_sidebar addTableColumn:sc];
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
        @[ RAColumnName, NSLocalizedString(@"Name", @"column"), @"name", @220 ],
        @[ RAColumnDistance, NSLocalizedString(@"km", @"column"), @"distance", @60 ],
        @[ RAColumnAscent, NSLocalizedString(@"Ascent", @"column"), @"ascent", @60 ],
        @[ RAColumnDuration, NSLocalizedString(@"Duration", @"column"), @"duration", @70 ],
        @[ RAColumnSpeed, NSLocalizedString(@"Avg.", @"column"), @"averageSpeed", @60 ],
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
    _footer = [NSTextField labelWithString:@""];
    _footer.textColor = [NSColor secondaryLabelColor];
    _footer.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    NSStackView *list = [NSStackView stackViewWithViews:@[ tableScroll, _footer ]];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.distribution = NSStackViewDistributionFill;
    [tableScroll setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    list.edgeInsets = NSEdgeInsetsMake(0, 0, 8, 0);
    list.spacing = 6;
    [tableScroll.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
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
    [_detail setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
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
    l.minimumThickness = 360;
    NSSplitViewItem *d = [NSSplitViewItem splitViewItemWithViewController:[self controllerWithView:detailContainer]];
    d.minimumThickness = 320;
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

- (void)reload
{
    if (!_table) return;
    NSArray<RARide *> *selected = [self selectedRides];
    NSArray<RARide *> *rides = self.library.rides ?: @[];
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
    _detailSubtitle.stringValue = [NSString stringWithFormat:@"%@ · %@",
        ride.startDate ? [_longDateFormatter stringFromDate:ride.startDate] : @"—", ride.format.uppercaseString];
    [self addFigure:NSLocalizedString(@"Distance", @"figure")
              value:[NSString stringWithFormat:@"%@ km", [self kilometers:ride.distance]]];
    [self addFigure:NSLocalizedString(@"Ascent", @"figure")
              value:[NSString localizedStringWithFormat:@"%.0f m", ride.ascent]];
    [self addFigure:NSLocalizedString(@"Duration", @"figure") value:[self durationString:ride.duration]];
    [self addFigure:NSLocalizedString(@"Average speed", @"figure")
              value:ride.averageSpeed > 0 ? [NSString localizedStringWithFormat:@"%.1f km/h", ride.averageSpeed]
                                          : @"—"];
}

#pragma mark - table data source and delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return tableView == _sidebar ? (NSInteger)_sections.count : (NSInteger)_sorted.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn
                           row:(NSInteger)row
{
    NSString *text = @"";
    BOOL numeric = NO;
    BOOL editable = NO;
    if (tableView == _sidebar) {
        text = _sections[(NSUInteger)row];
    } else {
        RARide *ride = _sorted[(NSUInteger)row];
        NSString *ident = tableColumn.identifier;
        numeric = ![ident isEqualToString:RAColumnDate] && ![ident isEqualToString:RAColumnName];
        if ([ident isEqualToString:RAColumnDate]) {
            text = ride.startDate ? [_dateFormatter stringFromDate:ride.startDate] : @"—";
        } else if ([ident isEqualToString:RAColumnName]) {
            text = ride.name;
            editable = YES;
        } else if ([ident isEqualToString:RAColumnDistance]) {
            text = [self kilometers:ride.distance];
        } else if ([ident isEqualToString:RAColumnAscent]) {
            text = [NSString localizedStringWithFormat:@"%.0f", ride.ascent];
        } else if ([ident isEqualToString:RAColumnDuration]) {
            text = [self durationString:ride.duration];
        } else if ([ident isEqualToString:RAColumnSpeed]) {
            text = ride.averageSpeed > 0 ? [NSString localizedStringWithFormat:@"%.1f", ride.averageSpeed] : @"—";
        }
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
    if (notification.object == _table) [self updateDetail];
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

// drag and drop of files or folders on the list (R2)
- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
    if (tableView != _table || !self.library) return NSDragOperationNone;
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

#pragma mark - actions

- (void)importURLs:(NSArray<NSURL *> *)urls
{
    RAImportSummary *summary = [self.library importFilesAtURLs:urls];
    if (urls.count == 1 && summary.imported == 1) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString localizedStringWithFormat:NSLocalizedString(@"%lu rides imported", @"import summary"),
                         (unsigned long)summary.imported];
    alert.informativeText = [NSString localizedStringWithFormat:
        NSLocalizedString(@"Already in the library: %lu. Unreadable: %lu.", @"import summary"),
        (unsigned long)summary.duplicates, (unsigned long)summary.unreadable];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (IBAction)importFiles:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = YES;
    panel.allowedContentTypes = [BPTrackReader importContentTypes];
    panel.message = NSLocalizedString(@"Choose FIT, GPX or TCX files, or folders (e.g. Garmin/Activity on the device).",
                                      @"import panel");
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) [self importURLs:panel.URLs];
    }];
}

- (IBAction)fetchFromGarminConnect:(id)sender
{
    // R1: Personal API key from the Garmin Connect web session (#79), new activities as FIT
}

- (IBAction)delete:(nullable id)sender
{
    NSArray<RARide *> *rides = [self selectedRides];
    if (rides.count) [self.library removeRides:rides];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(delete:)) return _table.selectedRowIndexes.count > 0;
    if (item.action == @selector(fetchFromGarminConnect:)) return NO; // not implemented yet
    return YES;
}

@end
