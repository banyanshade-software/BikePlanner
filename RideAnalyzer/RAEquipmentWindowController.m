//
//  RAEquipmentWindowController.m
//  RideAnalyzer
//

#import "RAEquipmentWindowController.h"
#import "RAEquipment.h"
#import "RALibraryDocument.h"
#import "RARide.h"

@interface RAEquipmentWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation RAEquipmentWindowController
{
    __weak RALibraryDocument *_library;
    NSNumberFormatter *_number;
    NSDateFormatter *_day;
    NSTextField *_status;
}

- (instancetype)initWithLibrary:(RALibraryDocument *)library
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1060, 620)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                  | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:YES];
    window.minSize = NSMakeSize(860, 460);
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
        [NSTextField labelWithString:NSLocalizedString(@"Default bike:", @"equipment")], _defaultBikePopup ]];
    top.spacing = 6;
    [top setCustomSpacing:24 afterView:top.views[2]];

    _bikesTable = [self tableWithIdentifier:@"bikes" columns:@[
        @[ @"name", NSLocalizedString(@"Bike", @"column"), @180 ],
        @[ @"kind", NSLocalizedString(@"Kind", @"column"), @110 ],
        @[ @"weight", NSLocalizedString(@"Weight (kg)", @"column"), @80 ],
        @[ @"position", NSLocalizedString(@"Position", @"column"), @110 ],
        @[ @"cdA", NSLocalizedString(@"CdA (m²)", @"column"), @80 ],
        @[ @"distance", NSLocalizedString(@"Ridden (km)", @"column"), @90 ] ]];
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
        @"Crr: rolling resistance of a tyre; empty, the value shown in gray is estimated from the model or the width. "
        @"CdA: air drag of bike and rider; empty, from the riding position. To: empty while the part is mounted. "
        @"Choosing another bike for a part already ridden moves it from today.", @"equipment")];
    help.textColor = [NSColor secondaryLabelColor];
    help.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _status = [NSTextField labelWithString:@""];
    _status.textColor = [NSColor systemOrangeColor];
    _status.identifier = @"equipmentStatus";

    NSScrollView *bikes = [self scroll:_bikesTable];
    NSScrollView *parts = [self scroll:_partsTable];
    NSStackView *stack = [NSStackView stackViewWithViews:@[
        top, [self header:NSLocalizedString(@"Bikes", @"equipment") add:@selector(addBike:) remove:@selector(removeBike:)
               identifier:@"bike"], bikes,
        [self header:NSLocalizedString(@"Parts", @"equipment") add:@selector(addPart:) remove:@selector(removePart:)
          identifier:@"part"], parts, help, _status ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    for (NSView *v in @[ bikes, parts, help ]) {
        [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32].active = YES;
    }
    [bikes.heightAnchor constraintEqualToConstant:150].active = YES;
    [parts.heightAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
    [parts setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    self.window.contentView = stack;
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
    [_bikesTable selectRowIndexes:bikeRows byExtendingSelection:NO];
    [_partsTable selectRowIndexes:partRows byExtendingSelection:NO];
    NSArray<RAPart *> *worn = [e wornPartsWithRides:_library.rides ?: @[]];
    _status.stringValue = worn.count ? [NSString stringWithFormat:NSLocalizedString(@"Worn: %@", @"equipment"),
                                        [[worn valueForKey:@"name"] componentsJoinedByString:@", "]] : @"";
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    RAEquipment *e = [self equipment];
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
    if (tableView == _bikesTable) {
        RABike *b = e.bikes[(NSUInteger)row];
        if ([c isEqualToString:@"name"]) view = [self field:b.name placeholder:nil editable:YES];
        else if ([c isEqualToString:@"kind"]) {
            NSMutableArray *t = [NSMutableArray array], *v = [NSMutableArray array];
            for (NSInteger k = RABikeRoad; k <= RABikeElectric; k++) { [t addObject:[RABike nameOfKind:k]]; [v addObject:@(k)]; }
            view = [self popup:t values:v selected:@(b.kind)];
        } else if ([c isEqualToString:@"weight"]) view = [self field:[self format:b.weight] placeholder:@"12" editable:YES];
        else if ([c isEqualToString:@"position"]) {
            NSMutableArray *t = [NSMutableArray array], *v = [NSMutableArray array];
            for (NSInteger k = RAPositionUpright; k <= RAPositionDrops; k++) { [t addObject:[RABike nameOfPosition:k]]; [v addObject:@(k)]; }
            view = [self popup:t values:v selected:@(b.position)];
        } else if ([c isEqualToString:@"cdA"]) {
            view = [self field:[self format:b.cdA] placeholder:[self format:[RABike defaultCdAForPosition:b.position]] editable:YES];
        } else if ([c isEqualToString:@"distance"]) {
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
        } else if ([c isEqualToString:@"model"]) view = [self field:p.model placeholder:nil editable:YES];
        else if ([c isEqualToString:@"width"]) view = tyre ? [self field:[self format:p.width] placeholder:nil editable:YES] : nil;
        else if ([c isEqualToString:@"wheel"]) {
            if (tyre) {
                NSMutableArray *t = [NSMutableArray array], *v = [NSMutableArray array];
                for (NSInteger k = RAWheelFront; k <= RAWheelBoth; k++) { [t addObject:[RAPart nameOfWheel:k]]; [v addObject:@(k)]; }
                view = [self popup:t values:v selected:@(p.wheel)];
            }
        } else if ([c isEqualToString:@"crr"]) {
            view = tyre ? [self field:[self format:p.crr]
                          placeholder:[self format:[RAPart defaultCrrForModel:p.model width:p.width]] editable:YES] : nil;
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
        else if ([column isEqualToString:@"model"]) p.model = [value description] ?: @"";
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

- (void)defaultBikeChosen:(id)sender
{
    NSString *bike = _defaultBikePopup.selectedItem.representedObject ?: @"";
    [_library changeEquipment:^(RAEquipment *e) { e.defaultBikeID = bike; }
                   actionName:NSLocalizedString(@"Default Bike", @"undo action name")];
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
