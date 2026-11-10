//
//  BPSiteEditorController.m
//  BikePlanner
//

#if BP_SITE_EDITOR

#import "BPSiteEditorController.h"
#import "Document.h"
#import "MapController.h"

static NSArray<NSString *> *BPSiteKinds(void) { return @[@"climb", @"monument", @"nature"]; }
static const NSTimeInterval kPreviewDelay = 0.3; // s: Street View reloads once the heading stops changing

#pragma mark - target: the front document window

@interface BPMapControllerSiteTarget : NSObject <BPSiteEditorTarget>
@property (weak) MapController *mapController;
@end

@implementation BPMapControllerSiteTarget

- (CLLocationCoordinate2D)mapCenter
{
    return self.mapController.mapView.centerCoordinate;
}

- (void)showSite:(BPRemarkableSite *)site
{
    [self.mapController showSite:site];
}

- (void)previewStreetViewAt:(CLLocationCoordinate2D)coordinate heading:(double)heading
{
    [self.mapController.svCtrl viewCoord:coordinate lookingAt:heading coalesce:NO];
}

@end

#pragma mark -

@implementation BPSiteEditorController {
    NSMutableArray<NSMutableDictionary *> *_entries;
    NSString *_header;
    NSData *_originalData;
    NSTableView *_table;
    NSMutableDictionary<NSString *, NSButton *> *_buttons;
}

+ (void)installMenu
{
    NSMenu *main = NSApp.mainMenu;
    if ([main indexOfItemWithTitle:@"Develop"] >= 0) return;
    NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:@"Develop" action:NULL keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Develop"];
    NSMenuItem *item = [menu addItemWithTitle:@"Start Sites Editor…" action:@selector(showEditor:) keyEquivalent:@""];
    item.target = self;
    top.submenu = menu;
    NSInteger window = [main indexOfItemWithTitle:@"Window"];
    [main insertItem:top atIndex:window >= 0 ? window : main.numberOfItems];
}

+ (void)showEditor:(id)sender
{
    [[self shared] showWindow:sender];
}

+ (instancetype)shared
{
    static BPSiteEditorController *shared;
    if (!shared) shared = [[self alloc] initWithPropertyListData:[BPRemarkableSites bundledPropertyListData]];
    return shared;
}

- (instancetype)initWithPropertyListData:(nullable NSData *)data
{
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 600, 560)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
          backing:NSBackingStoreBuffered defer:YES];
    panel.hidesOnDeactivate = NO;
    panel.releasedWhenClosed = NO;
    panel.minSize = NSMakeSize(560, 420);
    self = [super initWithWindow:panel];
    if (self) {
        _originalData = data;
        _buttons = [NSMutableDictionary dictionary];
        _targetProvider = ^id<BPSiteEditorTarget> {
            Document *d = (Document *)NSApp.mainWindow.windowController.document;
            if (![d isKindOfClass:[Document class]] || !d.mapController) return nil;
            BPMapControllerSiteTarget *t = [[BPMapControllerSiteTarget alloc] init];
            t.mapController = d.mapController;
            return t;
        };
        [self buildUI];
        [self loadData:data];
        [panel center];
    }
    return self;
}

- (void)loadData:(nullable NSData *)data
{
    _header = data ? [BPRemarkableSites headerCommentOfPropertyListData:data] : nil;
    id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers
                                                                 format:NULL error:NULL] : nil;
    _entries = [NSMutableArray array];
    if ([plist isKindOfClass:[NSArray class]]) {
        for (id e in plist) if ([e isKindOfClass:[NSMutableDictionary class]]) [_entries addObject:e];
    }
    _edited = NO;
    [_table reloadData];
    self.selectedIndex = _entries.count ? 0 : -1;
    [self update];
}

- (NSArray<NSDictionary *> *)entries
{
    return [_entries copy];
}

#pragma mark - UI

- (NSButton *)button:(NSString *)title action:(SEL)action identifier:(NSString *)identifier
{
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.identifier = identifier;
    b.accessibilityIdentifier = identifier;
    _buttons[identifier] = b;
    return b;
}

- (nullable NSButton *)buttonWithIdentifier:(NSString *)identifier
{
    return _buttons[identifier];
}

- (NSTextField *)field:(NSString *)identifier width:(CGFloat)width
{
    NSTextField *f = [NSTextField textFieldWithString:@""];
    f.accessibilityIdentifier = identifier;
    f.target = self;
    f.action = @selector(fieldChanged:);
    f.cell.sendsActionOnEndEditing = YES;
    [f.widthAnchor constraintEqualToConstant:width].active = YES;
    return f;
}

- (void)buildUI
{
    NSTableView *table = [[NSTableView alloc] init];
    NSArray *columns = @[ @[@"index", @"#", @30], @[@"name", @"Name", @190], @[@"kind", @"Kind", @80],
                          @[@"latitude", @"Latitude", @70], @[@"longitude", @"Longitude", @70], @[@"heading", @"Heading", @60] ];
    for (NSArray *c in columns) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        col.editable = NO;
        [table addTableColumn:col];
    }
    table.dataSource = self;
    table.delegate = self;
    table.usesAlternatingRowBackgroundColors = YES;
    table.allowsMultipleSelection = NO;
    table.target = self;
    table.doubleAction = @selector(goToSite:);
    table.accessibilityIdentifier = @"siteTable";
    _table = table;
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = table;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:160].active = YES;

    NSStackView *actions = [NSStackView stackViewWithViews:@[
        [self button:@"Go to" action:@selector(goToSite:) identifier:@"siteGoTo"],
        [self button:@"Add Here" action:@selector(addSiteHere:) identifier:@"siteAdd"],
        [self button:@"Set Position Here" action:@selector(setPositionHere:) identifier:@"siteSetPosition"],
        [self button:@"Remove" action:@selector(removeSite:) identifier:@"siteRemove"],
        [self button:@"↑" action:@selector(moveSiteUp:) identifier:@"siteUp"],
        [self button:@"↓" action:@selector(moveSiteDown:) identifier:@"siteDown"] ]];
    _buttons[@"siteGoTo"].toolTip = @"Show the site as a new document starting on it (also: double-click)";
    _buttons[@"siteAdd"].toolTip = @"New site at the center of the map, after the selected one";
    _buttons[@"siteSetPosition"].toolTip = @"Move the selected site to the center of the map";

    _nameField = [self field:@"siteName" width:240];
    _kindPopUp = [[NSPopUpButton alloc] init];
    [_kindPopUp addItemsWithTitles:BPSiteKinds()];
    _kindPopUp.accessibilityIdentifier = @"siteKind";
    _kindPopUp.target = self;
    _kindPopUp.action = @selector(fieldChanged:);
    _latitudeField = [self field:@"siteLatitude" width:100];
    _longitudeField = [self field:@"siteLongitude" width:100];
    _headingField = [self field:@"siteHeading" width:50];
    _headingSlider = [NSSlider sliderWithValue:0 minValue:0 maxValue:359 target:self action:@selector(headingSliderChanged:)];
    _headingSlider.continuous = YES;
    _headingSlider.accessibilityIdentifier = @"siteHeadingSlider";
    [_headingSlider.widthAnchor constraintEqualToConstant:220].active = YES;
    NSTextField *hint = [NSTextField labelWithString:@"° (0 = north, 90 = east)"];
    hint.textColor = NSColor.secondaryLabelColor;
    NSGridView *form = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Name:"], _nameField],
        @[[NSTextField labelWithString:@"Kind:"], _kindPopUp],
        @[[NSTextField labelWithString:@"Latitude:"], [NSStackView stackViewWithViews:@[_latitudeField,
            [NSTextField labelWithString:@"Longitude:"], _longitudeField]]],
        @[[NSTextField labelWithString:@"Heading:"], [NSStackView stackViewWithViews:@[_headingField, hint, _headingSlider]]] ]];
    [form columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    form.rowAlignment = NSGridRowAlignmentFirstBaseline;

    _statusLabel = [NSTextField wrappingLabelWithString:@""];
    _statusLabel.accessibilityIdentifier = @"siteStatus";
    [_statusLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *bottom = [NSStackView stackViewWithViews:@[ spacer,
        [self button:@"Revert" action:@selector(revertSites:) identifier:@"siteRevert"],
        [self button:@"Export Plist…" action:@selector(exportSites:) identifier:@"siteExport"] ]];
    _buttons[@"siteExport"].toolTip = @"Save RemarkableSites.plist (to BikePlanner/ in the source tree), then rebuild the app";

    NSStackView *stack = [NSStackView stackViewWithViews:@[scroll, actions, form, _statusLabel, bottom]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *content = self.window.contentView;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
        [bottom.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
        [_statusLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
    ]];
}

#pragma mark - table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _entries.count;
}

- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)column row:(NSInteger)row
{
    NSDictionary *e = _entries[row];
    NSString *key = column.identifier;
    if ([key isEqualToString:@"index"]) return @(row + 1);
    if ([key isEqualToString:@"latitude"] || [key isEqualToString:@"longitude"]) {
        return [NSString stringWithFormat:@"%.4f", [e[key] doubleValue]];
    }
    if ([key isEqualToString:@"heading"]) return [NSString stringWithFormat:@"%g", [e[key] doubleValue]];
    return e[key];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    _selectedIndex = _table.selectedRow;
    [self update];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex
{
    _selectedIndex = (selectedIndex >= 0 && selectedIndex < (NSInteger)_entries.count) ? selectedIndex : -1;
    if (_selectedIndex >= 0) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:_selectedIndex] byExtendingSelection:NO];
        [_table scrollRowToVisible:_selectedIndex];
    } else {
        [_table deselectAll:self];
    }
    [self update];
}

#pragma mark - state

- (nullable NSMutableDictionary *)selected
{
    return _selectedIndex >= 0 ? _entries[_selectedIndex] : nil;
}

- (nullable BPRemarkableSite *)siteOf:(NSDictionary *)entry
{
    return [BPRemarkableSites sitesFromPropertyList:@[entry]].firstObject;
}

// fields, buttons, title and status from the entries and the selection
- (void)update
{
    NSMutableDictionary *e = [self selected];
    for (NSControl *c in @[_nameField, _kindPopUp, _latitudeField, _longitudeField, _headingField, _headingSlider]) {
        c.enabled = e != nil;
    }
    _nameField.stringValue = e[@"name"] ?: @"";
    [_kindPopUp selectItemWithTitle:e[@"kind"] ?: @"climb"];
    _latitudeField.stringValue = e ? [NSString stringWithFormat:@"%.5f", [e[@"latitude"] doubleValue]] : @"";
    _longitudeField.stringValue = e ? [NSString stringWithFormat:@"%.5f", [e[@"longitude"] doubleValue]] : @"";
    double heading = [e[@"heading"] doubleValue];
    _headingField.stringValue = e ? [NSString stringWithFormat:@"%g", heading] : @"";
    _headingSlider.doubleValue = heading;

    NSInteger i = _selectedIndex, n = _entries.count;
    // the first site stays Mont Ventoux (unit tests start on site 0): not moved, not removed, nothing moved above it
    _buttons[@"siteGoTo"].enabled = e != nil;
    _buttons[@"siteSetPosition"].enabled = e != nil;
    _buttons[@"siteRemove"].enabled = i > 0;
    _buttons[@"siteUp"].enabled = i > 1;
    _buttons[@"siteDown"].enabled = i > 0 && i < n - 1;
    _buttons[@"siteRevert"].enabled = _edited;

    self.window.title = [NSString stringWithFormat:@"Start Sites (%ld)", (long)n];
    self.window.documentEdited = _edited;
    NSArray<NSString *> *problems = self.problems;
    NSString *status = problems.count ? [@"⚠️ " stringByAppendingString:[problems componentsJoinedByString:@"\n⚠️ "]]
                                      : [NSString stringWithFormat:@"%ld sites, no problem.", (long)n];
    if (_edited) status = [status stringByAppendingString:@"\nNot exported yet: Export Plist…, then rebuild the app."];
    _statusLabel.stringValue = status;
}

- (void)changed
{
    _edited = YES;
    NSInteger keep = _selectedIndex;
    [_table reloadData];
    self.selectedIndex = keep;
}

- (NSArray<NSString *> *)problems
{
    NSMutableArray<NSString *> *p = [NSMutableArray array];
    NSCountedSet *names = [[NSCountedSet alloc] initWithArray:[_entries valueForKey:@"name"]];
    [_entries enumerateObjectsUsingBlock:^(NSMutableDictionary *e, NSUInteger i, BOOL *stop) {
        NSString *name = e[@"name"];
        NSString *label = [NSString stringWithFormat:@"#%lu %@", (unsigned long)i + 1, name.length ? name : @"(no name)"];
        if (!name.length) [p addObject:[label stringByAppendingString:@": no name"]];
        else if ([names countForObject:name] > 1) [p addObject:[label stringByAppendingString:@": same name as another site"]];
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake([e[@"latitude"] doubleValue], [e[@"longitude"] doubleValue]);
        if (![BPRemarkableSites isInMetropolitanFrance:c]) {
            [p addObject:[label stringByAppendingString:@": outside metropolitan France"]];
        }
    }];
    if (_entries.count && ![_entries[0][@"name"] isEqualToString:@"Mont Ventoux"]) {
        [p addObject:@"The first site must stay Mont Ventoux (unit tests start on it)"];
    }
    return p;
}

- (nullable NSData *)exportData
{
    return [BPRemarkableSites propertyListDataForEntries:_entries headerComment:_header];
}

#pragma mark - actions

- (nullable id<BPSiteEditorTarget>)target
{
    id<BPSiteEditorTarget> t = self.targetProvider ? self.targetProvider() : nil;
    if (!t) NSBeep(); // no document window
    return t;
}

- (IBAction)goToSite:(id)sender
{
    NSMutableDictionary *e = [self selected];
    BPRemarkableSite *site = e ? [self siteOf:e] : nil;
    if (site) [[self target] showSite:site];
}

- (IBAction)addSiteHere:(id)sender
{
    id<BPSiteEditorTarget> t = [self target];
    if (!t) return;
    CLLocationCoordinate2D c = t.mapCenter;
    NSMutableDictionary *e = [@{ @"name": @"New site", @"latitude": @(round(c.latitude * 1e5) / 1e5),
                                 @"longitude": @(round(c.longitude * 1e5) / 1e5), @"kind": @"climb", @"heading": @0 } mutableCopy];
    NSInteger at = _selectedIndex >= 0 ? _selectedIndex + 1 : (NSInteger)_entries.count;
    [_entries insertObject:e atIndex:at];
    _selectedIndex = at;
    [self changed];
    [self.window makeFirstResponder:_nameField];
    [_nameField selectText:self];
}

- (IBAction)setPositionHere:(id)sender
{
    NSMutableDictionary *e = [self selected];
    id<BPSiteEditorTarget> t = e ? [self target] : nil;
    if (!t) return;
    CLLocationCoordinate2D c = t.mapCenter;
    e[@"latitude"] = @(round(c.latitude * 1e5) / 1e5);
    e[@"longitude"] = @(round(c.longitude * 1e5) / 1e5);
    [self changed];
    [self schedulePreview];
}

- (IBAction)removeSite:(id)sender
{
    if (_selectedIndex <= 0) return;
    NSInteger i = _selectedIndex;
    [_entries removeObjectAtIndex:i];
    _selectedIndex = MIN(i, (NSInteger)_entries.count - 1);
    [self changed];
}

- (void)moveFrom:(NSInteger)from to:(NSInteger)to
{
    if (from <= 0 || to <= 0 || to >= (NSInteger)_entries.count) return;
    [_entries exchangeObjectAtIndex:from withObjectAtIndex:to];
    _selectedIndex = to;
    [self changed];
}

- (IBAction)moveSiteUp:(id)sender
{
    [self moveFrom:_selectedIndex to:_selectedIndex - 1];
}

- (IBAction)moveSiteDown:(id)sender
{
    [self moveFrom:_selectedIndex to:_selectedIndex + 1];
}

// a number typed with a decimal comma or point
static double BPParse(NSString *s)
{
    return [[s stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];
}

- (void)fieldChanged:(id)sender
{
    NSMutableDictionary *e = [self selected];
    if (!e) return;
    NSMutableDictionary *before = [e mutableCopy];
    NSString *name = [_nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    e[@"name"] = name;
    e[@"kind"] = _kindPopUp.titleOfSelectedItem ?: @"climb";
    double lat = BPParse(_latitudeField.stringValue), lon = BPParse(_longitudeField.stringValue);
    if (CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon))) {
        e[@"latitude"] = @(lat);
        e[@"longitude"] = @(lon);
    }
    [self setHeading:BPParse(_headingField.stringValue) of:e];
    if ([e isEqualToDictionary:before]) {
        [self update]; // e.g. an invalid value typed: shown again
        return;
    }
    BOOL moved = ![e[@"latitude"] isEqual:before[@"latitude"]] || ![e[@"longitude"] isEqual:before[@"longitude"]]
                 || ![e[@"heading"] isEqual:before[@"heading"]];
    [self changed];
    if (moved) [self schedulePreview];
}

- (void)setHeading:(double)heading of:(NSMutableDictionary *)e
{
    heading = fmod(round(heading), 360);
    if (heading < 0) heading += 360;
    e[@"heading"] = @((NSInteger)heading);
}

- (void)headingSliderChanged:(NSSlider *)sender
{
    NSMutableDictionary *e = [self selected];
    if (!e) return;
    NSNumber *before = e[@"heading"];
    [self setHeading:sender.doubleValue of:e];
    _headingField.stringValue = [e[@"heading"] stringValue];
    if ([e[@"heading"] isEqual:before]) return;
    _edited = YES;
    [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:_selectedIndex]
                      columnIndexes:[NSIndexSet indexSetWithIndex:[_table columnWithIdentifier:@"heading"]]];
    self.window.documentEdited = YES;
    _buttons[@"siteRevert"].enabled = YES;
    [self schedulePreview];
}

// Street View at the selected site with its heading, once the changes stop (each view reloads the page)
- (void)schedulePreview
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preview) object:nil];
    [self performSelector:@selector(preview) withObject:nil afterDelay:kPreviewDelay];
}

- (void)preview
{
    NSMutableDictionary *e = [self selected];
    if (!e) return;
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake([e[@"latitude"] doubleValue], [e[@"longitude"] doubleValue]);
    [[self target] previewStreetViewAt:c heading:[e[@"heading"] doubleValue]];
}

- (IBAction)revertSites:(id)sender
{
    if (!_edited) return;
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Revert to the list of the app?";
    a.informativeText = @"The changes not exported are lost.";
    [a addButtonWithTitle:@"Revert"];
    [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertFirstButtonReturn) [self loadData:self->_originalData];
    }];
}

- (IBAction)exportSites:(id)sender
{
    NSArray<NSString *> *problems = self.problems;
    if (!problems.count) {
        [self chooseExportFile];
        return;
    }
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Export the list anyway?";
    a.informativeText = [[problems componentsJoinedByString:@"\n"]
                         stringByAppendingString:@"\n\nThe unit tests will fail with this list."];
    [a addButtonWithTitle:@"Cancel"];
    [a addButtonWithTitle:@"Export Anyway"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertSecondButtonReturn) [self chooseExportFile];
    }];
}

- (void)chooseExportFile
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"RemarkableSites.plist";
    panel.message = @"Save over BikePlanner/RemarkableSites.plist in the source tree, then rebuild the app.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK || !panel.URL) return;
        NSError *err = nil;
        NSData *data = [self exportData];
        if (data && [data writeToURL:panel.URL options:NSDataWritingAtomic error:&err]) {
            self->_originalData = data;
            self->_edited = NO;
            [self update];
        } else if (err) {
            [[NSAlert alertWithError:err] beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }];
}

@end

#endif
