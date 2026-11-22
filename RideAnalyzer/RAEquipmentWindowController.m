//
//  RAEquipmentWindowController.m
//  RideAnalyzer
//

#import "RAEquipmentWindowController.h"
#import "RAEquipment.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RATyreDatabase.h"
#import "RATyreDatabaseWindowController.h"
#import "RALibraryWindowController.h"

@interface RAEquipmentWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation RAEquipmentWindowController
{
    __weak RALibraryDocument *_library;
    NSNumberFormatter *_number;
    NSDateFormatter *_day;
    NSTextField *_status;
    RATyreDatabaseWindowController *_tyreDatabase;
    // the bike sheet: the selected bike and its tyres
    NSView *_sheet;
    NSTextField *_noBike;
    NSMutableDictionary<NSString *, NSControl *> *_sheetControls;
    NSTextField *_frontCrr, *_rearCrr, *_figures;
    NSTableView *_historyTable;
    NSButton *_usesWeighings;          // the weight of the day, from the Garmin Connect weighings (R11)
}

- (instancetype)initWithLibrary:(RALibraryDocument *)library
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1060, 760)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                  | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:YES];
    window.minSize = NSMakeSize(900, 640);
    window.identifier = @"equipment";
    self = [super initWithWindow:window];
    if (!self) return nil;
    _library = library;
    _number = [[NSNumberFormatter alloc] init];
    _number.numberStyle = NSNumberFormatterDecimalStyle;
    _number.maximumFractionDigits = 4;
    _number.lenient = YES;
    _day = [[NSDateFormatter alloc] init];
    _day.dateStyle = NSDateFormatterShortStyle;
    _day.timeStyle = NSDateFormatterNoStyle;
    _day.lenient = YES;
    [self buildContent];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryDidChange:)
                                                 name:RALibraryDidChangeNotification object:library];
    [self reload];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
    return [NSString stringWithFormat:NSLocalizedString(@"%@ — Equipment", @"equipment window title"), displayName];
}

#pragma mark - building

- (NSTableView *)tableWithIdentifier:(NSString *)identifier columns:(NSArray<NSArray *> *)columns
{
    NSTableView *t = [[NSTableView alloc] init];
    t.identifier = identifier;
    t.dataSource = self;
    t.delegate = self;
    t.usesAlternatingRowBackgroundColors = YES;
    t.rowHeight = 24;
    for (NSArray *c in columns) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        [t addTableColumn:col];
    }
    return t;
}

- (NSScrollView *)scroll:(NSTableView *)table
{
    NSScrollView *s = [[NSScrollView alloc] init];
    s.documentView = table;
    s.hasVerticalScroller = YES;
    s.autohidesScrollers = YES;
    return s;
}

- (NSStackView *)header:(NSString *)title add:(SEL)add remove:(SEL)remove identifier:(NSString *)identifier
{
    NSTextField *t = [NSTextField labelWithString:title];
    t.font = [NSFont boldSystemFontOfSize:13];
    NSButton *plus = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameAddTemplate] target:self action:add];
    plus.identifier = [identifier stringByAppendingString:@"Add"];
    NSButton *minus = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameRemoveTemplate] target:self action:remove];
    minus.identifier = [identifier stringByAppendingString:@"Remove"];
    NSStackView *s = [NSStackView stackViewWithViews:@[ t, plus, minus ]];
    s.spacing = 6;
    return s;
}

- (void)buildContent
{
    _riderWeightField = [NSTextField textFieldWithString:@""];
    _riderWeightField.formatter = _number;
    _riderWeightField.placeholderString = @"75";
    _riderWeightField.identifier = @"riderWeight";
    _riderWeightField.target = self;
    _riderWeightField.action = @selector(riderWeightChanged:);
    [_riderWeightField.widthAnchor constraintEqualToConstant:60].active = YES;
    _defaultBikePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _defaultBikePopup.target = self;
    _defaultBikePopup.action = @selector(defaultBikeChosen:);
    _defaultBikePopup.identifier = @"defaultBike";
    NSStackView *top = [NSStackView stackViewWithViews:@[
        [NSTextField labelWithString:NSLocalizedString(@"Rider weight:", @"equipment")], _riderWeightField,
        [NSTextField labelWithString:NSLocalizedString(@"kg", @"unit")],
        [NSTextField labelWithString:NSLocalizedString(@"Default bike:", @"equipment")], _defaultBikePopup,
        [NSButton buttonWithTitle:NSLocalizedString(@"Tyre Database…", @"equipment") target:self
                           action:@selector(showTyreDatabase:)] ]];
    top.views.lastObject.identifier = @"showTyreDatabase";
    top.spacing = 6;
    _usesWeighings = [NSButton checkboxWithTitle:@"" target:self action:@selector(usesWeighingsChanged:)];
    _usesWeighings.identifier = @"usesWeighings";
    NSButton *getWeighings = [NSButton buttonWithTitle:NSLocalizedString(@"Get from Garmin Connect", @"equipment")
                                                target:self action:@selector(updateWeighingsFromGarmin:)];
    getWeighings.controlSize = NSControlSizeSmall;
    getWeighings.identifier = @"getWeighings";
    NSStackView *weights = [NSStackView stackViewWithViews:@[ _usesWeighings, getWeighings ]];
    weights.spacing = 8;
    [top setCustomSpacing:24 afterView:top.views[2]];
    [top setCustomSpacing:24 afterView:_defaultBikePopup];

    _bikesTable = [self tableWithIdentifier:@"bikes" columns:@[
        @[ @"name", NSLocalizedString(@"Bike", @"column"), @150 ],
        @[ @"distance", NSLocalizedString(@"Ridden (km)", @"column"), @80 ] ]];
    _historyTable = [self tableWithIdentifier:@"tyreHistory" columns:@[
        @[ @"wheel", NSLocalizedString(@"Wheel", @"column"), @100 ],
        @[ @"tyre", NSLocalizedString(@"Tyre", @"column"), @230 ],
        @[ @"pressure", NSLocalizedString(@"bar", @"column: tyre pressure"), @45 ],
        @[ @"from", NSLocalizedString(@"From", @"column"), @80 ],
        @[ @"to", NSLocalizedString(@"To", @"column"), @80 ],
        @[ @"distance", NSLocalizedString(@"Ridden (km)", @"column"), @80 ] ]];
    _historyTable.rowHeight = 18;
    _partsTable = [self tableWithIdentifier:@"parts" columns:@[
        @[ @"name", NSLocalizedString(@"Part", @"column"), @120 ],
        @[ @"kind", NSLocalizedString(@"Kind", @"column"), @100 ],
        @[ @"model", NSLocalizedString(@"Model", @"column"), @170 ],
        @[ @"width", NSLocalizedString(@"Width (mm)", @"column"), @70 ],
        @[ @"wheel", NSLocalizedString(@"Wheel", @"column"), @110 ],
        @[ @"crr", NSLocalizedString(@"Crr", @"column"), @70 ],
        @[ @"bike", NSLocalizedString(@"On bike", @"column"), @120 ],
        @[ @"from", NSLocalizedString(@"From", @"column"), @80 ],
        @[ @"to", NSLocalizedString(@"To", @"column"), @80 ],
        @[ @"distance", NSLocalizedString(@"Ridden (km)", @"column"), @80 ],
        @[ @"wearLimit", NSLocalizedString(@"Worn at (km)", @"column"), @80 ] ]];

    NSTextField *help = [NSTextField wrappingLabelWithString:NSLocalizedString(
        @"Crr: rolling resistance of a tyre; empty, the value shown in gray comes from the tyre database (published "
        @"tests, Tyre Database…) for its model, else from its width. "
        @"CdA: air drag of bike and rider; empty, from the riding position. To: empty while the part is mounted. "
        @"Choosing another bike for a part already ridden moves it from today. On the bike sheet, editing a tyre "
        @"corrects it; Change Tyre… mounts a new one from a date and keeps the old one in the history.", @"equipment")];
    help.textColor = [NSColor secondaryLabelColor];
    help.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _status = [NSTextField labelWithString:@""];
    _status.textColor = [NSColor systemOrangeColor];
    _status.identifier = @"equipmentStatus";

    NSScrollView *bikes = [self scroll:_bikesTable];
    NSScrollView *parts = [self scroll:_partsTable];
    NSStackView *bikeList = [NSStackView stackViewWithViews:@[
        [self header:NSLocalizedString(@"Bikes", @"equipment") add:@selector(addBike:) remove:@selector(removeBike:)
          identifier:@"bike"], bikes ]];
    bikeList.orientation = NSUserInterfaceLayoutOrientationVertical;
    bikeList.alignment = NSLayoutAttributeLeading;
    [bikes.widthAnchor constraintEqualToConstant:250].active = YES;
    [bikes.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [self buildSheet];
    NSBox *sheetBox = [[NSBox alloc] init];
    sheetBox.title = NSLocalizedString(@"Bike sheet", @"equipment");
    sheetBox.contentView = _sheet;
    NSStackView *bikesRow = [NSStackView stackViewWithViews:@[ bikeList, sheetBox ]];
    bikesRow.alignment = NSLayoutAttributeTop;
    bikesRow.spacing = 14;
    NSStackView *stack = [NSStackView stackViewWithViews:@[
        top, weights, bikesRow,
        [self header:NSLocalizedString(@"All parts", @"equipment") add:@selector(addPart:) remove:@selector(removePart:)
          identifier:@"part"], parts, help, _status ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    for (NSView *v in @[ bikesRow, parts, help ]) {
        [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32].active = YES;
    }
    [bikes.heightAnchor constraintEqualToAnchor:sheetBox.heightAnchor constant:-24].active = YES;
    [parts.heightAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
    [parts setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    self.window.contentView = stack;
}

#pragma mark - the bike sheet

- (NSTextField *)sheetField:(NSString *)identifier width:(CGFloat)width
{
    NSTextField *f = [NSTextField textFieldWithString:@""];
    f.identifier = identifier;
    f.target = self;
    f.action = @selector(sheetEdited:);
    [f.widthAnchor constraintEqualToConstant:width].active = YES;
    _sheetControls[identifier] = f;
    return f;
}

- (NSPopUpButton *)sheetPopup:(NSString *)identifier titles:(NSArray<NSString *> *)titles
{
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSUInteger i = 0; i < titles.count; i++) {
        [p addItemWithTitle:titles[i]];
        p.lastItem.representedObject = @(i);
    }
    p.identifier = identifier;
    p.target = self;
    p.action = @selector(sheetEdited:);
    _sheetControls[identifier] = p;
    return p;
}

- (NSComboBox *)tyreCombo:(NSString *)identifier
{
    NSComboBox *box = [[NSComboBox alloc] init];
    box.completes = YES;
    box.numberOfVisibleItems = 15;
    [box addItemsWithObjectValues:[[RATyreDatabase shared].tyres valueForKey:@"displayName"]];
    box.placeholderString = NSLocalizedString(@"Tyre (database or any)", @"bike sheet");
    box.identifier = identifier;
    box.target = self;
    box.action = @selector(sheetEdited:);
    [box.widthAnchor constraintEqualToConstant:280].active = YES;
    _sheetControls[identifier] = box;
    return box;
}

- (NSStackView *)row:(NSArray<NSView *> *)views
{
    NSStackView *r = [NSStackView stackViewWithViews:views];
    r.spacing = 6;
    return r;
}

- (NSTextField *)unit:(NSString *)text
{
    NSTextField *t = [NSTextField labelWithString:text];
    t.textColor = [NSColor secondaryLabelColor];
    return t;
}

- (NSView *)tyreRow:(NSString *)prefix wheel:(RAWheel)wheel crr:(NSTextField *)crr
{
    NSButton *change = [NSButton buttonWithTitle:NSLocalizedString(@"Change Tyre…", @"bike sheet") target:self
                                          action:@selector(changeTyre:)];
    change.identifier = [prefix stringByAppendingString:@"TyreChange"];
    change.tag = wheel;
    crr.identifier = [prefix stringByAppendingString:@"TyreCrr"];
    crr.textColor = [NSColor secondaryLabelColor];
    crr.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    NSStackView *line = [self row:@[ [self tyreCombo:[prefix stringByAppendingString:@"TyreModel"]],
                                     [self sheetField:[prefix stringByAppendingString:@"TyreWidth"] width:44], [self unit:@"mm"],
                                     [self sheetField:[prefix stringByAppendingString:@"TyrePressure"] width:44], [self unit:@"bar"],
                                     change ]];
    NSStackView *v = [NSStackView stackViewWithViews:@[ line, crr ]];
    v.orientation = NSUserInterfaceLayoutOrientationVertical;
    v.alignment = NSLayoutAttributeLeading;
    v.spacing = 2;
    return v;
}

- (void)buildSheet
{
    _sheetControls = [NSMutableDictionary dictionary];
    NSMutableArray *kinds = [NSMutableArray array], *positions = [NSMutableArray array], *surfaces = [NSMutableArray array];
    for (NSInteger k = RABikeRoad; k <= RABikeElectric; k++) [kinds addObject:[RABike nameOfKind:k]];
    for (NSInteger k = RAPositionUpright; k <= RAPositionDrops; k++) [positions addObject:[RABike nameOfPosition:k]];
    for (NSInteger k = RASurfaceSmoothAsphalt; k <= RASurfaceGravel; k++) {
        [surfaces addObject:[NSString localizedStringWithFormat:@"%@ (Crr × %.2f)", [RABike nameOfSurface:k],
                             [RABike rollingFactorOfSurface:k]]];
    }
    NSTextField *model = [self sheetField:@"bikeModel" width:220];
    model.placeholderString = NSLocalizedString(@"e.g. Giant Rapid 4", @"bike sheet");
    _frontCrr = [NSTextField labelWithString:@""];
    _rearCrr = [NSTextField labelWithString:@""];
    _figures = [NSTextField labelWithString:@""];
    _figures.identifier = @"bikeFigures";
    _figures.font = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
    NSScrollView *history = [self scroll:_historyTable];
    [history.heightAnchor constraintEqualToConstant:96].active = YES;
    [history.widthAnchor constraintEqualToConstant:640].active = YES;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[ [NSTextField labelWithString:NSLocalizedString(@"Name:", @"bike sheet")], [self sheetField:@"bikeName" width:220] ],
        @[ [NSTextField labelWithString:NSLocalizedString(@"Model:", @"bike sheet")], model ],
        @[ [NSTextField labelWithString:NSLocalizedString(@"Kind:", @"bike sheet")],
           [self row:@[ [self sheetPopup:@"bikeKind" titles:kinds],
                        [NSTextField labelWithString:NSLocalizedString(@"Weight:", @"bike sheet")],
                        [self sheetField:@"bikeWeight" width:50], [self unit:NSLocalizedString(@"kg, with bags and bottles", @"bike sheet")] ]] ],
        @[ [NSTextField labelWithString:NSLocalizedString(@"Position:", @"bike sheet")],
           [self row:@[ [self sheetPopup:@"bikePosition" titles:positions],
                        [NSTextField labelWithString:NSLocalizedString(@"CdA:", @"bike sheet")],
                        [self sheetField:@"bikeCdA" width:50], [self unit:@"m²"] ]] ],
        @[ [NSTextField labelWithString:NSLocalizedString(@"Usual roads (where the map has no surface):", @"bike sheet")], [self sheetPopup:@"bikeSurface" titles:surfaces] ],
        @[ [NSTextField labelWithString:NSLocalizedString(@"Front tyre:", @"bike sheet")], [self tyreRow:@"front" wheel:RAWheelFront crr:_frontCrr] ],
        @[ [NSTextField labelWithString:NSLocalizedString(@"Rear tyre:", @"bike sheet")], [self tyreRow:@"rear" wheel:RAWheelRear crr:_rearCrr] ],
        @[ [NSTextField labelWithString:NSLocalizedString(@"Tyres over time:", @"bike sheet")], history ],
        @[ [NSTextField labelWithString:NSLocalizedString(@"Estimate:", @"bike sheet")], _figures ] ]];
    grid.rowSpacing = 6;
    grid.columnSpacing = 8;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    for (NSInteger r = 0; r < grid.numberOfRows; r++) [grid rowAtIndex:r].yPlacement = NSGridCellPlacementCenter;
    [grid rowAtIndex:5].yPlacement = NSGridCellPlacementTop;
    [grid rowAtIndex:6].yPlacement = NSGridCellPlacementTop;
    [grid rowAtIndex:7].yPlacement = NSGridCellPlacementTop;
    _noBike = [NSTextField wrappingLabelWithString:NSLocalizedString(@"No bike: add one with +.", @"bike sheet")];
    _noBike.textColor = [NSColor secondaryLabelColor];
    _noBike.identifier = @"bikeSheetEmpty";
    NSStackView *v = [NSStackView stackViewWithViews:@[ _noBike, grid ]];
    v.orientation = NSUserInterfaceLayoutOrientationVertical;
    v.alignment = NSLayoutAttributeLeading;
    v.edgeInsets = NSEdgeInsetsMake(6, 8, 8, 8);
    _sheet = v;
}

- (NSTableView *)tyreHistoryTable
{
    return _historyTable;
}

- (NSDictionary<NSString *, NSControl *> *)sheetControls
{
    return _sheetControls;
}

- (NSTextField *)sheetFigures
{
    return _figures;
}

- (nullable RABike *)selectedBike
{
    RAEquipment *e = [self equipment];
    NSInteger row = _bikesTable.selectedRow;
    return row >= 0 && (NSUInteger)row < e.bikes.count ? e.bikes[(NSUInteger)row] : nil;
}

- (void)selectBikeWithID:(NSString *)bikeID
{
    (void)self.window;
    NSUInteger index = [[[self equipment].bikes valueForKey:@"identifier"] indexOfObject:bikeID];
    if (index == NSNotFound) return;
    [_bikesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [_bikesTable scrollRowToVisible:(NSInteger)index];
    [self refreshSheet];
}

- (void)tableViewSelectionDidChange:(NSNotification *)n
{
    if (n.object == _bikesTable) [self refreshSheet];
}

- (void)setSheetText:(NSString *)text placeholder:(nullable NSString *)placeholder of:(NSString *)identifier
{
    NSControl *c = _sheetControls[identifier];
    // not while the user is typing in it
    if (c.currentEditor && [c.stringValue isEqualToString:text]) return;
    c.stringValue = text;
    if ([c isKindOfClass:[NSTextField class]]) ((NSTextField *)c).placeholderString = placeholder;
}

- (void)refreshTyre:(nullable RAPart *)tyre prefix:(NSString *)prefix crr:(NSTextField *)crr
{
    [self setSheetText:tyre.model ?: @"" placeholder:nil of:[prefix stringByAppendingString:@"TyreModel"]];
    [self setSheetText:tyre ? [self format:tyre.width] : @"" placeholder:@"28" of:[prefix stringByAppendingString:@"TyreWidth"]];
    RATyre *known = tyre ? [[RATyreDatabase shared] tyreMatchingModel:tyre.model width:tyre.width] : nil;
    [self setSheetText:tyre ? [self format:tyre.pressure] : @""
           placeholder:known.pressureBar > 0 ? [self format:known.pressureBar] : nil
                    of:[prefix stringByAppendingString:@"TyrePressure"]];
    if (!tyre) {
        crr.stringValue = NSLocalizedString(@"No tyre entered: Crr 0.0050", @"bike sheet");
    } else if (tyre.crr > 0) {
        crr.stringValue = [NSString localizedStringWithFormat:NSLocalizedString(@"Crr %.4f (entered)", @"bike sheet"), tyre.crr];
    } else {
        crr.stringValue = [NSString localizedStringWithFormat:NSLocalizedString(@"Crr %.4f — %@", @"bike sheet"),
                           tyre.effectiveCrr, tyre.crrSource];
    }
}

- (void)refreshSheet
{
    RAEquipment *e = [self equipment];
    RABike *b = [self selectedBike];
    _noBike.hidden = b != nil;
    for (NSControl *c in _sheetControls.allValues) c.enabled = b != nil;
    for (NSView *v in _sheet.subviews) if (v != _noBike) v.hidden = b == nil;
    [_historyTable reloadData];
    if (!b) return;
    [self setSheetText:b.name placeholder:nil of:@"bikeName"];
    [self setSheetText:b.model placeholder:NSLocalizedString(@"e.g. Giant Rapid 4", @"bike sheet") of:@"bikeModel"];
    [self setSheetText:[self format:b.weight]
           placeholder:[NSString localizedStringWithFormat:@"%.0f", [RABike typicalWeightForKind:b.kind]] of:@"bikeWeight"];
    [self setSheetText:[self format:b.cdA] placeholder:[self format:[RABike defaultCdAForPosition:b.position]] of:@"bikeCdA"];
    [(NSPopUpButton *)_sheetControls[@"bikeKind"] selectItemAtIndex:b.kind];
    [(NSPopUpButton *)_sheetControls[@"bikePosition"] selectItemAtIndex:b.position];
    [(NSPopUpButton *)_sheetControls[@"bikeSurface"] selectItemAtIndex:b.surface];
    NSDate *now = [NSDate date];
    RAPart *front = [e tyreOfBike:b.identifier wheel:RAWheelFront atDate:now];
    RAPart *rear = [e tyreOfBike:b.identifier wheel:RAWheelRear atDate:now];
    [self refreshTyre:front prefix:@"front" crr:_frontCrr];
    [self refreshTyre:rear prefix:@"rear" crr:_rearCrr];
    // what the estimated power uses today with this bike
    double crr = [e crrOfBike:b.identifier atDate:now] * [RABike rollingFactorOfSurface:b.surface];
    _figures.stringValue = [NSString localizedStringWithFormat:
        NSLocalizedString(@"%.0f kg with the rider · Crr %.4f on these roads · CdA %.2f m²", @"bike sheet"),
        [e riderWeightAtDate:now] + b.effectiveWeight, crr, b.effectiveCdA];
}

/// the edit of a control of the sheet
- (void)sheetEdited:(NSControl *)sender
{
    id value = [sender isKindOfClass:[NSPopUpButton class]] ? ((NSPopUpButton *)sender).selectedItem.representedObject
                                                             : sender.stringValue;
    NSString *identifier = sender.identifier;
    if ([identifier hasPrefix:@"front"] || [identifier hasPrefix:@"rear"]) {
        BOOL front = [identifier hasPrefix:@"front"];
        NSString *field = [[identifier substringFromIndex:front ? 9 : 8] lowercaseString];   // "frontTyre" / "rearTyre"
        [self setValue:value forTyreField:field wheel:front ? RAWheelFront : RAWheelRear];
    } else if ([identifier hasPrefix:@"bike"]) {
        [self setValue:value forBikeField:[[identifier substringFromIndex:4] lowercaseString]];
    }
}

- (void)setValue:(id)value forBikeField:(NSString *)field
{
    NSInteger row = _bikesTable.selectedRow;
    if (row < 0) return;
    NSString *column = [field isEqualToString:@"cda"] ? @"cdA" : field;
    [self setValue:value forColumn:column ofBikeAtRow:row];
}

- (void)setValue:(nullable id)value forTyreField:(NSString *)field wheel:(RAWheel)wheel
{
    RALibraryDocument *library = _library;
    RABike *bike = [self selectedBike];
    if (!library || !bike) return;
    NSString *bikeID = bike.identifier;
    NSString *text = [value description] ?: @"";
    double number = [self numberOf:value];
    if (![[self equipment] tyreOfBike:bikeID wheel:wheel atDate:[NSDate date]] && text.length == 0) return;  // nothing
    [library changeEquipment:^(RAEquipment *e) {
        NSDate *now = [NSDate date];
        RAPart *tyre = [e tyreOfBike:bikeID wheel:wheel atDate:now];
        if (!tyre) {
            // the first tyre entered on this wheel counts since always; after others, from today
            BOOL before = NO;
            for (RAPart *t in [e tyreHistoryOfBike:bikeID]) before = before || t.wheel == wheel || t.wheel == RAWheelBoth;
            tyre = [e mountTyreOnBike:bikeID wheel:wheel fromDate:before ? now : nil];
        } else if (tyre.wheel == RAWheelBoth && ([field isEqualToString:@"model"] || [field isEqualToString:@"width"])) {
            // a pair corrected on one wheel only: two tyres with the same history
            RAPart *other = [tyre copy];
            other.identifier = [[RAPart alloc] init].identifier;
            other.wheel = wheel;
            tyre.wheel = wheel == RAWheelFront ? RAWheelRear : RAWheelFront;
            e.parts = [e.parts arrayByAddingObject:other];
            tyre = other;
        }
        if ([field isEqualToString:@"model"]) [RAEquipmentWindowController setModel:text ofPart:tyre];
        else if ([field isEqualToString:@"width"]) tyre.width = number;
        else if ([field isEqualToString:@"pressure"]) tyre.pressure = number;
        else if ([field isEqualToString:@"crr"]) tyre.crr = number;
    } actionName:NSLocalizedString(@"Edit Tyre", @"undo action name")];
    [self refreshSheet];
}

- (void)changeTyreOnWheel:(RAWheel)wheel model:(NSString *)model width:(double)width date:(NSDate *)date
{
    RALibraryDocument *library = _library;
    RABike *bike = [self selectedBike];
    if (!library || !bike) return;
    NSString *bikeID = bike.identifier;
    [library changeEquipment:^(RAEquipment *e) {
        RAPart *before = [e tyreOfBike:bikeID wheel:wheel atDate:date];
        RAPart *tyre = [e mountTyreOnBike:bikeID wheel:wheel fromDate:date];
        [RAEquipmentWindowController setModel:model ofPart:tyre];
        if (width > 0) tyre.width = width;
        tyre.pressure = before.pressure;                 // the same rim, the same habit
        tyre.wearLimit = before.wearLimit;
    } actionName:NSLocalizedString(@"Change Tyre", @"undo action name")];
    [self refreshSheet];
}

/// asks the new tyre and the day it was mounted (a sheet on the window)
- (IBAction)changeTyre:(nullable id)sender
{
    RABike *bike = [self selectedBike];
    if (!bike) return;
    RAWheel wheel = [sender isKindOfClass:[NSButton class]] ? (RAWheel)[(NSButton *)sender tag] : RAWheelFront;
    RAPart *current = [[self equipment] tyreOfBike:bike.identifier wheel:wheel atDate:[NSDate date]];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"New %@ tyre on “%@”", @"change tyre"),
                         [[RAPart nameOfWheel:wheel] lowercaseString], bike.name];
    alert.informativeText = current
        ? [NSString stringWithFormat:NSLocalizedString(@"“%@” is taken off the day before and stays in the history: the rides "
                                                       @"before keep it.", @"change tyre"), current.model.length ? current.model : current.name]
        : NSLocalizedString(@"The rides from that day use it.", @"change tyre");
    NSComboBox *box = [[NSComboBox alloc] initWithFrame:NSMakeRect(0, 58, 300, 26)];
    box.completes = YES;
    box.numberOfVisibleItems = 15;
    [box addItemsWithObjectValues:[[RATyreDatabase shared].tyres valueForKey:@"displayName"]];
    box.placeholderString = NSLocalizedString(@"Tyre (database or any)", @"bike sheet");
    box.stringValue = current.model ?: @"";
    NSTextField *width = [NSTextField textFieldWithString:current.width > 0 ? [self format:current.width] : @""];
    width.frame = NSMakeRect(0, 30, 50, 22);
    width.placeholderString = NSLocalizedString(@"mm", @"change tyre: width");
    NSDatePicker *day = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 160, 24)];
    day.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    day.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    day.dateValue = [NSDate date];
    NSTextField *from = [NSTextField labelWithString:NSLocalizedString(@"mounted on", @"change tyre")];
    from.frame = NSMakeRect(170, 3, 130, 18);
    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 86)];
    for (NSView *v in @[ box, width, day, from ]) [accessory addSubview:v];
    alert.accessoryView = accessory;
    [alert addButtonWithTitle:NSLocalizedString(@"Change", @"change tyre")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"button")];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn || box.stringValue.length == 0) return;
        [self changeTyreOnWheel:wheel model:box.stringValue width:[self numberOf:width.stringValue] date:day.dateValue];
    }];
}

#pragma mark - data

- (RAEquipment *)equipment
{
    return _library.equipment ?: [[RAEquipment alloc] init];
}

- (void)libraryDidChange:(NSNotification *)n
{
    [self reload];
}

- (void)reload
{
    RAEquipment *e = [self equipment];
    _riderWeightField.objectValue = e.riderWeight > 0 ? @(e.riderWeight) : nil;
    RAWeighing *last = e.weighings.lastObject;
    _usesWeighings.title = last
        ? [NSString localizedStringWithFormat:NSLocalizedString(@"Weight of the day of each ride, from the %lu weighings of Garmin "
                                                                @"Connect (last: %.1f kg on %@); else the weight entered", @"equipment"),
           (unsigned long)e.weighings.count, last.kilograms,
           [NSDateFormatter localizedStringFromDate:last.date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle]]
        : NSLocalizedString(@"Weight of the day of each ride, from the weighings of Garmin Connect (none yet)", @"equipment");
    _usesWeighings.state = e.usesWeighings ? NSControlStateValueOn : NSControlStateValueOff;
    _usesWeighings.enabled = last != nil;
    [_defaultBikePopup removeAllItems];
    [_defaultBikePopup addItemWithTitle:NSLocalizedString(@"None", @"equipment: no default bike")];
    _defaultBikePopup.lastItem.representedObject = @"";
    for (RABike *b in e.bikes) {
        [_defaultBikePopup addItemWithTitle:b.name];
        _defaultBikePopup.lastItem.representedObject = b.identifier;
    }
    NSInteger index = [_defaultBikePopup indexOfItemWithRepresentedObject:e.defaultBikeID];
    [_defaultBikePopup selectItemAtIndex:MAX(0, index)];
    NSIndexSet *bikeRows = _bikesTable.selectedRowIndexes, *partRows = _partsTable.selectedRowIndexes;
    [_bikesTable reloadData];
    [_partsTable reloadData];
    if (bikeRows.count == 0 && e.bikes.count) bikeRows = [NSIndexSet indexSetWithIndex:0];
    if (bikeRows.lastIndex != NSNotFound && bikeRows.lastIndex >= e.bikes.count) {
        bikeRows = [NSIndexSet indexSetWithIndex:e.bikes.count - 1];
    }
    [_bikesTable selectRowIndexes:bikeRows byExtendingSelection:NO];
    [_partsTable selectRowIndexes:partRows byExtendingSelection:NO];
    [self refreshSheet];
    NSArray<RAPart *> *worn = [e wornPartsWithRides:_library.rides ?: @[]];
    _status.stringValue = worn.count ? [NSString stringWithFormat:NSLocalizedString(@"Worn: %@", @"equipment"),
                                        [[worn valueForKey:@"name"] componentsJoinedByString:@", "]] : @"";
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    RAEquipment *e = [self equipment];
    if (tableView == _historyTable) {
        RABike *bike = [self selectedBike];
        return bike ? (NSInteger)[e tyreHistoryOfBike:bike.identifier].count : 0;
    }
    return (NSInteger)(tableView == _bikesTable ? e.bikes.count : e.parts.count);
}

- (NSString *)format:(double)v
{
    return v > 0 ? [_number stringFromNumber:@(v)] ?: @"" : @"";
}

- (NSTextField *)field:(NSString *)text placeholder:(nullable NSString *)placeholder editable:(BOOL)editable
{
    NSTextField *f = editable ? [NSTextField textFieldWithString:text] : [NSTextField labelWithString:text];
    f.placeholderString = placeholder;
    f.bordered = NO;
    f.drawsBackground = NO;
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    if (editable) {
        f.target = self;
        f.action = @selector(cellEdited:);
    }
    return f;
}

- (NSPopUpButton *)popup:(NSArray<NSString *> *)titles values:(NSArray *)values selected:(id)selected
{
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    p.bordered = NO;
    p.controlSize = NSControlSizeSmall;
    p.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    for (NSUInteger i = 0; i < titles.count; i++) {
        [p addItemWithTitle:titles[i]];
        p.lastItem.representedObject = values[i];
    }
    [p selectItemAtIndex:MAX(0, [p indexOfItemWithRepresentedObject:selected])];
    p.target = self;
    p.action = @selector(cellEdited:);
    return p;
}

- (NSArray *)bikeTitles:(BOOL)withNone values:(NSMutableArray *)values
{
    NSMutableArray *titles = [NSMutableArray array];
    if (withNone) {
        [titles addObject:NSLocalizedString(@"Not mounted", @"equipment")];
        [values addObject:@""];
    }
    for (RABike *b in [self equipment].bikes) {
        [titles addObject:b.name];
        [values addObject:b.identifier];
    }
    return titles;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    RAEquipment *e = [self equipment];
    NSString *c = tableColumn.identifier;
    NSArray<RARide *> *rides = _library.rides ?: @[];
    NSView *view = nil;
    if (tableView == _historyTable) {
        RABike *bike = [self selectedBike];
        NSArray<RAPart *> *history = bike ? [e tyreHistoryOfBike:bike.identifier] : @[];
        if ((NSUInteger)row >= history.count) return nil;
        RAPart *p = history[(NSUInteger)row];
        RAMounting *m = [e lastMountingOfPart:p onBike:(NSString *)bike.identifier];
        NSString *text = @"";
        if ([c isEqualToString:@"wheel"]) text = [RAPart nameOfWheel:p.wheel];
        else if ([c isEqualToString:@"tyre"]) {
            text = p.model.length ? p.model : p.name;
            if (p.width > 0) text = [NSString localizedStringWithFormat:@"%@ %.0f mm", text, p.width];
        } else if ([c isEqualToString:@"pressure"]) text = [self format:p.pressure];
        else if ([c isEqualToString:@"from"]) text = m.from.timeIntervalSinceReferenceDate > 86400 ? [_day stringFromDate:m.from] : @"…";
        else if ([c isEqualToString:@"to"]) text = m.to ? [_day stringFromDate:(NSDate *)m.to] : NSLocalizedString(@"mounted", @"equipment");
        else if ([c isEqualToString:@"distance"]) {
            text = [NSString localizedStringWithFormat:@"%.0f", [e distanceOfPart:p rides:rides] / 1000];
        }
        view = [self field:text placeholder:nil editable:NO];
        ((NSTextField *)view).font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    } else if (tableView == _bikesTable) {
        RABike *b = e.bikes[(NSUInteger)row];
        if ([c isEqualToString:@"name"]) view = [self field:b.name placeholder:nil editable:YES];
        else if ([c isEqualToString:@"distance"]) {
            view = [self field:[NSString localizedStringWithFormat:@"%.0f", [e distanceOfBike:b.identifier rides:rides] / 1000]
                   placeholder:nil editable:NO];
        }
    } else {
        RAPart *p = e.parts[(NSUInteger)row];
        RAMounting *m = p.mountings.lastObject;
        BOOL tyre = p.kind == RAPartTyre;
        if ([c isEqualToString:@"name"]) view = [self field:p.name placeholder:nil editable:YES];
        else if ([c isEqualToString:@"kind"]) {
            NSMutableArray *t = [NSMutableArray array], *v = [NSMutableArray array];
            for (NSInteger k = RAPartTyre; k <= RAPartOther; k++) { [t addObject:[RAPart nameOfKind:k]]; [v addObject:@(k)]; }
            view = [self popup:t values:v selected:@(p.kind)];
        } else if ([c isEqualToString:@"model"]) {
            if (tyre) {
                // the tyres of the database to choose from, or any text
                NSComboBox *box = [[NSComboBox alloc] init];
                box.bordered = NO;
                box.drawsBackground = NO;
                box.completes = YES;
                box.numberOfVisibleItems = 15;
                box.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
                [box addItemsWithObjectValues:[[RATyreDatabase shared].tyres valueForKey:@"displayName"]];
                box.stringValue = p.model;
                box.placeholderString = NSLocalizedString(@"Model (database or any)", @"equipment");
                box.target = self;
                box.action = @selector(cellEdited:);
                view = box;
            } else {
                view = [self field:p.model placeholder:nil editable:YES];
            }
        }
        else if ([c isEqualToString:@"width"]) view = tyre ? [self field:[self format:p.width] placeholder:nil editable:YES] : nil;
        else if ([c isEqualToString:@"wheel"]) {
            if (tyre) {
                NSMutableArray *t = [NSMutableArray array], *v = [NSMutableArray array];
                for (NSInteger k = RAWheelFront; k <= RAWheelBoth; k++) { [t addObject:[RAPart nameOfWheel:k]]; [v addObject:@(k)]; }
                view = [self popup:t values:v selected:@(p.wheel)];
            }
        } else if ([c isEqualToString:@"crr"]) {
            if (tyre) {
                NSTextField *f = [self field:[self format:p.crr]
                                 placeholder:[self format:[RAPart defaultCrrForModel:p.model width:p.width]] editable:YES];
                RATyre *known = [[RATyreDatabase shared] tyreMatchingModel:p.model width:p.width];
                f.toolTip = known ? [NSString stringWithFormat:NSLocalizedString(@"Default: %@, %@ (%@)", @"equipment: Crr source"),
                                     known.displayName, known.pressure, known.source]
                                  : NSLocalizedString(@"Default: estimate from the width", @"equipment: Crr source");
                view = f;
            }
        } else if ([c isEqualToString:@"bike"]) {
            NSMutableArray *values = [NSMutableArray array];
            NSArray *titles = [self bikeTitles:YES values:values];
            NSString *current = (m && !m.to) ? m.bikeID : @"";
            view = [self popup:titles values:values selected:current];
        } else if ([c isEqualToString:@"from"]) {
            view = [self field:m ? [_day stringFromDate:m.from] : @"" placeholder:nil editable:m != nil];
        } else if ([c isEqualToString:@"to"]) {
            view = [self field:m.to ? [_day stringFromDate:(NSDate *)m.to] : @""
                   placeholder:m ? NSLocalizedString(@"mounted", @"equipment") : nil editable:m != nil];
        } else if ([c isEqualToString:@"distance"]) {
            view = [self field:[NSString localizedStringWithFormat:@"%.0f", [e distanceOfPart:p rides:rides] / 1000]
                   placeholder:nil editable:NO];
        } else if ([c isEqualToString:@"wearLimit"]) {
            view = [self field:[self format:p.wearLimit] placeholder:nil editable:YES];
        }
    }
    view.identifier = c;
    return view;
}

#pragma mark - editing

/// a model typed or chosen: a tyre of the database gives its name and width, its Crr by default
+ (void)setModel:(NSString *)text ofPart:(RAPart *)p
{
    RATyre *chosen = nil;
    for (RATyre *t in [RATyreDatabase shared].tyres) if ([t.displayName isEqualToString:text]) chosen = t;
    if (!chosen) {
        p.model = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        return;
    }
    BOOL defaultName = [p.name isEqualToString:[RAPart nameOfKind:RAPartTyre]] || [p.name hasPrefix:[[RAPart nameOfKind:RAPartTyre] stringByAppendingString:@" ("]]
                       || [p.name isEqualToString:p.model];
    p.model = chosen.variant.length ? [NSString stringWithFormat:@"%@ %@", chosen.name, chosen.variant] : chosen.name;
    p.width = chosen.width;
    p.crr = 0;
    if (defaultName) p.name = chosen.model;
}

- (void)cellEdited:(NSControl *)sender
{
    NSInteger row = [_bikesTable rowForView:sender];
    id value = [sender isKindOfClass:[NSPopUpButton class]] ? ((NSPopUpButton *)sender).selectedItem.representedObject
                                                             : sender.stringValue;
    if (row >= 0) {
        [self setValue:value forColumn:sender.identifier ofBikeAtRow:row];
        return;
    }
    row = [_partsTable rowForView:sender];
    if (row >= 0) [self setValue:value forColumn:sender.identifier ofPartAtRow:row];
}

- (double)numberOf:(id)value
{
    if ([value isKindOfClass:[NSNumber class]]) return [value doubleValue];
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return 0;
    NSNumber *n = [_number numberFromString:value];
    if (n == nil) n = @([[value stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue]);
    return MAX(0, n.doubleValue);
}

- (void)setValue:(id)value forColumn:(NSString *)column ofBikeAtRow:(NSInteger)row
{
    RALibraryDocument *library = _library;
    if (!library || row < 0 || (NSUInteger)row >= library.equipment.bikes.count) return;
    NSString *bikeID = library.equipment.bikes[(NSUInteger)row].identifier;
    [library changeEquipment:^(RAEquipment *e) {
        RABike *b = [e bikeWithID:bikeID];
        if ([column isEqualToString:@"name"]) {
            NSString *s = [[value description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (s.length) b.name = s;
        } else if ([column isEqualToString:@"kind"]) {
            RABikeKind kind = (RABikeKind)[value integerValue];
            if (kind != b.kind) {
                b.kind = kind;
                b.position = [RABike defaultPositionForKind:kind];
            }
        } else if ([column isEqualToString:@"weight"]) b.weight = [self numberOf:value];
        else if ([column isEqualToString:@"position"]) b.position = (RARidingPosition)[value integerValue];
        else if ([column isEqualToString:@"cdA"]) b.cdA = [self numberOf:value];
        else if ([column isEqualToString:@"surface"]) b.surface = (RASurface)[value integerValue];
        else if ([column isEqualToString:@"model"]) {
            b.model = [[value description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] ?: @"";
        }
    } actionName:NSLocalizedString(@"Edit Bike", @"undo action name")];
}

- (void)setValue:(nullable id)value forColumn:(NSString *)column ofPartAtRow:(NSInteger)row
{
    RALibraryDocument *library = _library;
    if (!library || row < 0 || (NSUInteger)row >= library.equipment.parts.count) return;
    RAPart *original = library.equipment.parts[(NSUInteger)row];
    NSString *partID = original.identifier;
    double ridden = [library.equipment distanceOfPart:original rides:library.rides];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today = [cal startOfDayForDate:[NSDate date]];
    [library changeEquipment:^(RAEquipment *e) {
        RAPart *p = [e partWithID:partID];
        NSMutableArray<RAMounting *> *mountings = [p.mountings mutableCopy];
        RAMounting *last = mountings.lastObject;
        if ([column isEqualToString:@"name"]) {
            NSString *s = [[value description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (s.length) p.name = s;
        } else if ([column isEqualToString:@"kind"]) p.kind = (RAPartKind)[value integerValue];
        else if ([column isEqualToString:@"model"]) [RAEquipmentWindowController setModel:[value description] ?: @"" ofPart:p];
        else if ([column isEqualToString:@"width"]) p.width = [self numberOf:value];
        else if ([column isEqualToString:@"wheel"]) p.wheel = (RAWheel)[value integerValue];
        else if ([column isEqualToString:@"crr"]) p.crr = [self numberOf:value];
        else if ([column isEqualToString:@"wearLimit"]) {
            p.wearLimit = [self numberOf:value];
            p.wearWarned = NO;
        } else if ([column isEqualToString:@"bike"]) {
            NSString *bike = [value isKindOfClass:[NSString class]] ? value : @"";
            BOOL mounted = last && !last.to;
            if (bike.length == 0) {
                if (mounted) last.to = today;                                    // unmounted today
            } else if (!mounted) {
                RAMounting *m = [[RAMounting alloc] init];                       // mounted from today
                m.bikeID = bike;
                m.from = today;
                [mountings addObject:m];
            } else if (![last.bikeID isEqualToString:bike]) {
                if (ridden > 0) {                                                // moved today to another bike
                    last.to = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:today options:0] ?: today;
                    RAMounting *m = [[RAMounting alloc] init];
                    m.bikeID = bike;
                    m.from = today;
                    [mountings addObject:m];
                } else {
                    last.bikeID = bike;                                          // a correction: never ridden
                }
            }
        } else if ([column isEqualToString:@"from"] || [column isEqualToString:@"to"]) {
            NSString *s = [[value description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSDate *d = s.length ? [self->_day dateFromString:s] : nil;
            if (last && [column isEqualToString:@"from"] && d) last.from = [cal startOfDayForDate:d];
            if (last && [column isEqualToString:@"to"] && (d || s.length == 0)) last.to = d ? [cal startOfDayForDate:d] : nil;
        }
        p.mountings = mountings;
    } actionName:NSLocalizedString(@"Edit Part", @"undo action name")];
    [self reload];  // a value refused (e.g. a date that does not parse) shows again as it was
}

- (void)riderWeightChanged:(id)sender
{
    double w = [self numberOf:_riderWeightField.objectValue ?: _riderWeightField.stringValue];
    [_library changeEquipment:^(RAEquipment *e) { e.riderWeight = w; }
                   actionName:NSLocalizedString(@"Rider Weight", @"undo action name")];
}

/// the library window does it (its key, its alerts)
- (IBAction)updateWeighingsFromGarmin:(nullable id)sender
{
    for (NSWindowController *wc in _library.windowControllers) {
        if ([wc isKindOfClass:[RALibraryWindowController class]]) {
            [(RALibraryWindowController *)wc updateWeighingsFromGarmin:sender];
            return;
        }
    }
}

- (void)usesWeighingsChanged:(id)sender
{
    BOOL uses = _usesWeighings.state == NSControlStateValueOn;
    [_library changeEquipment:^(RAEquipment *e) { e.usesWeighings = uses; }
                   actionName:NSLocalizedString(@"Weight of the Day", @"undo action name")];
}

- (void)defaultBikeChosen:(id)sender
{
    NSString *bike = _defaultBikePopup.selectedItem.representedObject ?: @"";
    [_library changeEquipment:^(RAEquipment *e) { e.defaultBikeID = bike; }
                   actionName:NSLocalizedString(@"Default Bike", @"undo action name")];
}

- (IBAction)showTyreDatabase:(nullable id)sender
{
    if (!_tyreDatabase) {
        _tyreDatabase = [[RATyreDatabaseWindowController alloc] initWithDatabase:[RATyreDatabase shared]];
        __weak RAEquipmentWindowController *weakSelf = self;
        _tyreDatabase.useHandler = ^(RATyre *tyre) { [weakSelf useTyre:tyre]; };
        [_tyreDatabase.window center];
    }
    [_tyreDatabase showWindow:self];
}

/// the tyre of the database for the part selected in the parts table (a new tyre part if none is selected)
- (void)useTyre:(RATyre *)tyre
{
    NSInteger row = _partsTable.selectedRow;
    RAEquipment *e = [self equipment];
    if (row < 0 || (NSUInteger)row >= e.parts.count || e.parts[(NSUInteger)row].kind != RAPartTyre) {
        [self addPart:self];
        row = (NSInteger)[self equipment].parts.count - 1;
        [_partsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    }
    [self setValue:tyre.displayName forColumn:@"model" ofPartAtRow:row];
}

- (IBAction)addBike:(nullable id)sender
{
    [_library changeEquipment:^(RAEquipment *e) {
        RABike *b = [[RABike alloc] init];
        b.name = [NSString localizedStringWithFormat:NSLocalizedString(@"Bike %lu", @"equipment: new bike"),
                  (unsigned long)e.bikes.count + 1];
        e.bikes = [e.bikes arrayByAddingObject:b];
        if (e.defaultBikeID.length == 0) e.defaultBikeID = b.identifier;   // the first bike: the default one
    } actionName:NSLocalizedString(@"Add Bike", @"undo action name")];
}

- (IBAction)removeBike:(nullable id)sender
{
    NSInteger row = _bikesTable.selectedRow;
    RAEquipment *current = [self equipment];
    if (row < 0 || (NSUInteger)row >= current.bikes.count) return;
    NSString *bikeID = current.bikes[(NSUInteger)row].identifier;
    [_library changeEquipment:^(RAEquipment *e) {
        NSMutableArray *bikes = [e.bikes mutableCopy];
        [bikes removeObject:[e bikeWithID:bikeID]];
        e.bikes = bikes;
        if ([e.defaultBikeID isEqualToString:bikeID]) e.defaultBikeID = [bikes.firstObject identifier] ?: @"";
    } actionName:NSLocalizedString(@"Delete Bike", @"undo action name")];
}

- (IBAction)addPart:(nullable id)sender
{
    RAEquipment *current = [self equipment];
    NSInteger row = _bikesTable.selectedRow;
    NSString *bike = row >= 0 && (NSUInteger)row < current.bikes.count ? current.bikes[(NSUInteger)row].identifier
                                                                       : current.defaultBikeID;
    [_library changeEquipment:^(RAEquipment *e) {
        RAPart *p = [[RAPart alloc] init];
        if (bike.length) {
            RAMounting *m = [[RAMounting alloc] init];
            m.bikeID = bike;
            p.mountings = @[ m ];
        }
        e.parts = [e.parts arrayByAddingObject:p];
    } actionName:NSLocalizedString(@"Add Part", @"undo action name")];
}

- (IBAction)removePart:(nullable id)sender
{
    NSInteger row = _partsTable.selectedRow;
    RAEquipment *current = [self equipment];
    if (row < 0 || (NSUInteger)row >= current.parts.count) return;
    NSString *partID = current.parts[(NSUInteger)row].identifier;
    [_library changeEquipment:^(RAEquipment *e) {
        NSMutableArray *parts = [e.parts mutableCopy];
        [parts removeObject:[e partWithID:partID]];
        e.parts = parts;
    } actionName:NSLocalizedString(@"Delete Part", @"undo action name")];
}

@end
