//
//  BPSightsView.m
//  BikePlanner
//
//  Sights near the route in the Info section (#81).
//

#import "BPSightsView.h"
#import "BPSights.h"

NSString *const BPSightRowKey = @"key";
NSString *const BPSightRowAlong = @"along";
NSString *const BPSightRowOff = @"off";
NSString *const BPSightRowName = @"name";
NSString *const BPSightRowType = @"type";
NSString *const BPSightRowIncluded = @"included";

@interface BPSightsView () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation BPSightsView {
    NSStackView *_stack;
    NSView *_tableBox;          // header + table, as tall as the rows: one vertical scroll, the Info section's
    NSTableView *_table;
    NSLayoutConstraint *_tableHeight;
    NSTextField *_empty;
    BOOL _selectingFromCode;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    if (self = [super initWithFrame:frame]) {
        _categories = @[];
        _rows = @[];
        _includeDistance = 0;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _categoriesMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
        _categoriesMenu.accessibilityIdentifier = @"sightCategories";
        _categoriesMenu.toolTip = NSLocalizedString(@"Points of interest to look for along the route (search distance: Preferences)", @"tooltip");
        _categoriesMenu.menu.autoenablesItems = NO;
        _distanceMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        _distanceMenu.accessibilityIdentifier = @"sightIncludeDistance";
        _distanceMenu.toolTip = NSLocalizedString(@"Sights closer to the route are included in the track (GPX export); the others only if you check them", @"tooltip");
        for (NSNumber *m in [BPSightsView includeDistances]) {
            [_distanceMenu addItemWithTitle:m.integerValue ? [BPSightsView distanceText:m.doubleValue] : NSLocalizedString(@"None", @"sight include distance")];
            _distanceMenu.lastItem.tag = m.integerValue;
        }
        _distanceMenu.target = self;
        _distanceMenu.action = @selector(distanceChanged:);

        NSGridView *settings = [NSGridView gridViewWithViews:@[
            @[ [NSTextField labelWithString:NSLocalizedString(@"Sights:", @"Info section")], _categoriesMenu ],
            @[ [NSTextField labelWithString:NSLocalizedString(@"Include within:", @"Info section")], _distanceMenu ],
        ]];
        settings.rowSpacing = 6;
        [settings columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
        [_categoriesMenu.widthAnchor constraintEqualToConstant:230].active = YES;

        // a table: cells are made for the visible rows only (a grid of every row was slow with hundreds of sights).
        // No scroll view of its own (two vertical scrolls are awkward): it is as tall as its rows, in the scroll view
        // of the Info section, which still limits the cells made to the visible part
        _table = [[NSTableView alloc] init];
        _table.accessibilityIdentifier = @"sightsList";
        _table.dataSource = self;
        _table.delegate = self;
        _table.usesAlternatingRowBackgroundColors = YES;
        _table.allowsEmptySelection = YES;
        _table.style = NSTableViewStylePlain;
        _table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle; // only Name grows
        NSArray *columns = @[ @[ @"km", NSLocalizedString(@"km", @"sights list"), @42 ],
                              @[ @"name", NSLocalizedString(@"Name", @"sights list"), @150 ],
                              @[ @"type", NSLocalizedString(@"Type", @"sights list"), @80 ],
                              @[ @"off", NSLocalizedString(@"Off route", @"sights list"), @62 ],
                              @[ @"in", NSLocalizedString(@"In track", @"sights list"), @50 ] ];
        for (NSArray *c in columns) {
            NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
            col.title = c[1];
            col.width = [c[2] doubleValue];
            col.minWidth = [c[2] doubleValue];
            col.resizingMask = [c[0] isEqualToString:@"name"] ? NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask
                                                               : NSTableColumnUserResizingMask;
            [_table addTableColumn:col];
        }
        NSTableHeaderView *header = _table.headerView;
        header.translatesAutoresizingMaskIntoConstraints = NO;
        _table.translatesAutoresizingMaskIntoConstraints = NO;
        _tableBox = [[NSView alloc] init];
        _tableBox.translatesAutoresizingMaskIntoConstraints = NO;
        [_tableBox addSubview:header];
        [_tableBox addSubview:_table];
        _tableHeight = [_table.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            [header.topAnchor constraintEqualToAnchor:_tableBox.topAnchor],
            [header.leadingAnchor constraintEqualToAnchor:_tableBox.leadingAnchor],
            [header.trailingAnchor constraintEqualToAnchor:_tableBox.trailingAnchor],
            [header.heightAnchor constraintEqualToConstant:NSHeight(header.frame) > 0 ? NSHeight(header.frame) : 24],
            [_table.topAnchor constraintEqualToAnchor:header.bottomAnchor],
            [_table.leadingAnchor constraintEqualToAnchor:_tableBox.leadingAnchor],
            [_table.trailingAnchor constraintEqualToAnchor:_tableBox.trailingAnchor],
            [_table.bottomAnchor constraintEqualToAnchor:_tableBox.bottomAnchor],
            _tableHeight,
        ]];

        _empty = [NSTextField labelWithString:NSLocalizedString(@"No sight along the route.", @"Info section")];
        _empty.textColor = [NSColor secondaryLabelColor];

        NSTextField *title = [NSTextField labelWithString:NSLocalizedString(@"Sights along the route", @"Info section")];
        title.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
        _stack = [NSStackView stackViewWithViews:@[ title, settings, _tableBox, _empty ]];
        _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _stack.alignment = NSLayoutAttributeLeading;
        _stack.spacing = 8;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            // the table takes the whole width
            [_tableBox.leadingAnchor constraintEqualToAnchor:_stack.leadingAnchor],
            [_tableBox.trailingAnchor constraintEqualToAnchor:_stack.trailingAnchor],
        ]];
        [self rebuildCategoriesMenu];
        [self rebuildList];
        [_distanceMenu selectItemWithTag:_includeDistance];
    }
    return self;
}

- (instancetype)init
{
    return [self initWithFrame:NSZeroRect];
}

+ (NSArray<NSNumber *> *)includeDistances
{
    return @[ @0, @100, @500, @2000, @5000 ];
}

#pragma mark - settings

- (void)setCategories:(NSArray<NSString *> *)categories
{
    _categories = [BPSights normalizedCategories:categories];
    [self rebuildCategoriesMenu];
}

+ (void)fillCategoriesMenu:(NSPopUpButton *)popup categories:(NSArray<NSString *> *)categories target:(id)target action:(SEL)action
{
    NSMenu *menu = popup.menu;
    menu.autoenablesItems = NO;
    [menu removeAllItems];
    // a pull-down menu shows its first item as title
    [menu addItemWithTitle:[BPSights summaryOfCategories:categories] action:nil keyEquivalent:@""];
    for (NSString *c in [BPSights allCategories]) {
        NSMenuItem *item = [menu addItemWithTitle:[BPSights localizedNameOfCategory:c] action:action keyEquivalent:@""];
        item.target = target;
        item.representedObject = c;
        item.identifier = [@"sightCategory." stringByAppendingString:c];
        item.state = [categories containsObject:c] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)rebuildCategoriesMenu
{
    [BPSightsView fillCategoriesMenu:_categoriesMenu categories:_categories target:self action:@selector(toggleCategory:)];
}

- (void)toggleCategory:(NSMenuItem *)item
{
    NSString *c = item.representedObject;
    NSMutableArray *cats = [_categories mutableCopy];
    if ([cats containsObject:c]) [cats removeObject:c]; else [cats addObject:c];
    self.categories = cats;
    if (self.categoriesHandler) self.categoriesHandler(self.categories);
}

- (void)setIncludeDistance:(NSInteger)meters
{
    _includeDistance = meters;
    if (![_distanceMenu selectItemWithTag:meters]) {
        // a value of another version: shown as is
        [_distanceMenu addItemWithTitle:[NSString stringWithFormat:@"%ld m", (long)meters]];
        _distanceMenu.lastItem.tag = meters;
        [_distanceMenu selectItemWithTag:meters];
    }
}

- (void)distanceChanged:(NSPopUpButton *)sender
{
    _includeDistance = sender.selectedTag;
    if (self.includeDistanceHandler) self.includeDistanceHandler(_includeDistance);
}

#pragma mark - list

+ (NSString *)kilometersText:(double)meters
{
    static NSNumberFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSNumberFormatter alloc] init];
        f.numberStyle = NSNumberFormatterDecimalStyle;
        f.minimumFractionDigits = 1;
        f.maximumFractionDigits = 1;
    });
    return [f stringFromNumber:@(meters / 1000.0)];
}

+ (NSString *)distanceText:(double)meters
{
    if (meters < 1000) return [NSString stringWithFormat:@"%ld m", (long)lround(meters / 10.0) * 10];
    if (fmod(meters, 1000) == 0) return [NSString stringWithFormat:@"%ld km", (long)(meters / 1000)];
    return [NSString stringWithFormat:@"%@ km", [self kilometersText:meters]];
}

- (void)setRows:(NSArray<NSDictionary<NSString *, id> *> *)rows
{
    rows = [rows copy] ?: @[];
    if ([rows isEqualToArray:_rows]) return; // unchanged: no reload (refreshPOI calls this often)
    _rows = rows;
    [self rebuildList];
}

- (void)rebuildList
{
    _empty.hidden = _rows.count > 0;
    _tableBox.hidden = _rows.count == 0;
    [_table reloadData];
    _tableHeight.constant = _rows.count ? NSMaxY([_table rectOfRow:(NSInteger)_rows.count - 1]) : 0;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)_rows.count;
}

// also the value the table gives to a control cell (the checkbox): the same as the one set below, so that a reused
// cell never shows another row's value
- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)column row:(NSInteger)rowIndex
{
    if (rowIndex < 0 || rowIndex >= (NSInteger)_rows.count) return nil;
    NSDictionary *row = _rows[(NSUInteger)rowIndex];
    if ([column.identifier isEqualToString:@"in"]) return @([row[BPSightRowIncluded] boolValue] ? NSControlStateValueOn : NSControlStateValueOff);
    return nil;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)column row:(NSInteger)rowIndex
{
    NSDictionary *row = _rows[(NSUInteger)rowIndex];
    NSString *key = row[BPSightRowKey];
    NSString *ident = column.identifier;
    if ([ident isEqualToString:@"in"]) {
        NSButton *check = [tableView makeViewWithIdentifier:@"inCheck" owner:self];
        if (!check) {
            check = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxChanged:)];
            check.identifier = @"inCheck";
        }
        check.state = [row[BPSightRowIncluded] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        check.accessibilityIdentifier = [@"sightInclude." stringByAppendingString:key];
        return check;
    }
    NSTableCellView *cell = [tableView makeViewWithIdentifier:ident owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = ident;
        NSTextField *f = [NSTextField labelWithString:@""];
        f.lineBreakMode = NSLineBreakByTruncatingTail;
        f.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:f];
        cell.textField = f;
        [NSLayoutConstraint activateConstraints:@[
            [f.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [f.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [f.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        BOOL number = [ident isEqualToString:@"km"] || [ident isEqualToString:@"off"];
        f.alignment = number ? NSTextAlignmentRight : NSTextAlignmentLeft;
        if ([ident isEqualToString:@"type"] || [ident isEqualToString:@"off"]) f.textColor = [NSColor secondaryLabelColor];
    }
    NSString *text = @"";
    if ([ident isEqualToString:@"km"]) text = [BPSightsView kilometersText:[row[BPSightRowAlong] doubleValue]];
    else if ([ident isEqualToString:@"name"]) text = row[BPSightRowName] ?: @"";
    else if ([ident isEqualToString:@"type"]) text = row[BPSightRowType] ?: @"";
    else if ([ident isEqualToString:@"off"]) text = [BPSightsView distanceText:[row[BPSightRowOff] doubleValue]];
    cell.textField.stringValue = text;
    return cell;
}

// a click on a row shows the sight on the map
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger r = _table.selectedRow;
    if (_selectingFromCode || r < 0 || r >= (NSInteger)_rows.count) return;
    if (self.selectionHandler) self.selectionHandler(_rows[(NSUInteger)r][BPSightRowKey]);
}

- (void)checkboxChanged:(NSButton *)sender
{
    NSInteger r = [_table rowForView:sender];
    if (r < 0 || r >= (NSInteger)_rows.count) return;
    if (self.inclusionHandler) self.inclusionHandler(_rows[(NSUInteger)r][BPSightRowKey], sender.state == NSControlStateValueOn);
}

- (NSTableView *)tableView
{
    return _table;
}

- (nullable NSButton *)includeCheckboxForKey:(NSString *)key
{
    NSUInteger r = [_rows indexOfObjectPassingTest:^BOOL(NSDictionary *row, NSUInteger i, BOOL *stop) {
        return [row[BPSightRowKey] isEqualToString:key];
    }];
    if (r == NSNotFound) return nil;
    [_table scrollRowToVisible:(NSInteger)r];
    NSView *v = [_table viewAtColumn:[_table columnWithIdentifier:@"in"] row:(NSInteger)r makeIfNecessary:YES];
    return [v isKindOfClass:[NSButton class]] ? (NSButton *)v : nil;
}

- (void)selectRowWithKey:(NSString *)key
{
    NSUInteger r = [_rows indexOfObjectPassingTest:^BOOL(NSDictionary *row, NSUInteger i, BOOL *stop) {
        return [row[BPSightRowKey] isEqualToString:key];
    }];
    if (r == NSNotFound) return;
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:NO];
}

@end
