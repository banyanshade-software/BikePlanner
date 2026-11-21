//
//  RATyreDatabaseWindowController.m
//  RideAnalyzer
//

#import "RATyreDatabaseWindowController.h"
#import "RATyreDatabase.h"

@interface RATyreDatabaseWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@end

@implementation RATyreDatabaseWindowController
{
    RATyreDatabase *_database;
    NSButton *_useButton;
}

- (instancetype)initWithDatabase:(RATyreDatabase *)database
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 480)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:YES];
    window.title = NSLocalizedString(@"Tyre Database", @"window title");
    window.identifier = @"tyreDatabase";
    window.minSize = NSMakeSize(600, 300);
    self = [super initWithWindow:window];
    if (!self) return nil;
    _database = database;
    _shownTyres = database.tyres;

    _search = [[NSSearchField alloc] init];
    _search.placeholderString = NSLocalizedString(@"Brand, model, category", @"tyre database");
    _search.delegate = self;
    _search.identifier = @"tyreSearch";
    _table = [[NSTableView alloc] init];
    _table.identifier = @"tyres";
    _table.dataSource = self;
    _table.delegate = self;
    _table.usesAlternatingRowBackgroundColors = YES;
    _table.target = self;
    _table.doubleAction = @selector(useSelectedTyre:);
    NSArray *columns = @[ @[ @"brand", NSLocalizedString(@"Brand", @"column"), @100 ],
                          @[ @"model", NSLocalizedString(@"Model", @"column"), @200 ],
                          @[ @"width", NSLocalizedString(@"Width (mm)", @"column"), @70 ],
                          @[ @"crr", NSLocalizedString(@"Crr", @"column"), @65 ],
                          @[ @"pressure", NSLocalizedString(@"Test pressure", @"column"), @170 ],
                          @[ @"category", NSLocalizedString(@"Category", @"column"), @80 ] ];
    for (NSArray *c in columns) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        [_table addTableColumn:col];
    }
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    NSTextField *note = [NSTextField wrappingLabelWithString:database.note];
    note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    note.textColor = [NSColor secondaryLabelColor];
    _useButton = [NSButton buttonWithTitle:NSLocalizedString(@"Use for Selected Part", @"tyre database")
                                    target:self action:@selector(useSelectedTyre:)];
    _useButton.identifier = @"useTyre";
    NSStackView *stack = [NSStackView stackViewWithViews:@[ _search, scroll, note, _useButton ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
    for (NSView *v in @[ _search, scroll, note ]) {
        [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-28].active = YES;
    }
    [scroll setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    window.contentView = stack;
    [self updateButton];
    return self;
}

- (void)setUseHandler:(nullable void (^)(RATyre *))useHandler
{
    _useHandler = [useHandler copy];
    [self updateButton];
}

- (void)updateButton
{
    _useButton.enabled = _useHandler != nil && _table.selectedRow >= 0;
}

- (void)controlTextDidChange:(NSNotification *)obj
{
    _shownTyres = [_database tyresMatchingText:_search.stringValue];
    [_table reloadData];
    [self updateButton];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)_shownTyres.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    RATyre *t = _shownTyres[(NSUInteger)row];
    NSString *c = tableColumn.identifier, *text = @"";
    BOOL numeric = NO;
    if ([c isEqualToString:@"brand"]) text = t.brand;
    else if ([c isEqualToString:@"model"]) text = t.variant.length ? [NSString stringWithFormat:@"%@ (%@)", t.model, t.variant] : t.model;
    else if ([c isEqualToString:@"width"]) { text = [NSString localizedStringWithFormat:@"%.0f", t.width]; numeric = YES; }
    else if ([c isEqualToString:@"crr"]) { text = [NSString localizedStringWithFormat:@"%.4f", t.crr]; numeric = YES; }
    else if ([c isEqualToString:@"pressure"]) text = t.pressure;
    else if ([c isEqualToString:@"category"]) text = t.category;
    NSTextField *f = [NSTextField labelWithString:text];
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    if (numeric) f.alignment = NSTextAlignmentRight;
    f.toolTip = t.source;
    return f;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateButton];
}

- (IBAction)useSelectedTyre:(nullable id)sender
{
    NSInteger row = _table.clickedRow >= 0 ? _table.clickedRow : _table.selectedRow;
    if (row < 0 || (NSUInteger)row >= _shownTyres.count || !_useHandler) return;
    _useHandler(_shownTyres[(NSUInteger)row]);
}

@end
