//
//  RASurfaceFactorsWindowController.m
//  RideAnalyzer
//

#import "RASurfaceFactorsWindowController.h"
#import "RASurfaceFactors.h"
#import "RAEquipment.h"
#import "RALibraryDocument.h"

@interface RASurfaceFactorsWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation RASurfaceFactorsWindowController
{
    __weak RALibraryDocument *_library;
    NSNumberFormatter *_number;
}

- (instancetype)initWithLibrary:(RALibraryDocument *)library
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 620)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
          backing:NSBackingStoreBuffered defer:YES];
    window.title = NSLocalizedString(@"Rolling Resistance by Surface", @"surface factors window");
    window.identifier = @"surfaceFactors";
    window.minSize = NSMakeSize(640, 460);
    self = [super initWithWindow:window];
    if (!self) return nil;
    _library = library;
    _number = [[NSNumberFormatter alloc] init];
    _number.numberStyle = NSNumberFormatterDecimalStyle;
    _number.minimumFractionDigits = 2;
    _number.maximumFractionDigits = 2;
    _number.lenient = YES;
    [self buildContent];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryDidChange:)
                                                 name:RALibraryDidChangeNotification object:library];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildContent
{
    NSTextField *intro = [NSTextField wrappingLabelWithString:NSLocalizedString(
        @"The rolling resistance (Crr) of the tyres is measured on a smooth steel drum; a real surface multiplies it by "
        @"its factor. Each way of OpenStreetMap falls into a category by its tags; the usual roads of a bike (where the "
        @"map says nothing) use the same factors. Empty: the default. A change applies at once to the estimated power "
        @"of every ride.", @"surface factors")];
    _tableView = [[NSTableView alloc] init];
    _tableView.identifier = @"surfaceFactorsTable";
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.rowHeight = 22;
    for (NSArray *c in @[ @[ @"name", NSLocalizedString(@"Surface", @"column"), @230 ],
                          @[ @"tags", NSLocalizedString(@"OpenStreetMap tags", @"column"), @300 ],
                          @[ @"default", NSLocalizedString(@"Default", @"column"), @70 ],
                          @[ @"factor", NSLocalizedString(@"Factor", @"column"), @70 ] ]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        [_tableView addTableColumn:col];
    }
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = _tableView;
    scroll.hasVerticalScroller = YES;

    // the sources of the defaults: links
    NSMutableAttributedString *sources = [[NSMutableAttributedString alloc] initWithString:
        [NSLocalizedString(@"Sources of the defaults (rough estimates: the sources agree on the order of the surfaces "
                           @"more than on the ratios):", @"surface factors") stringByAppendingString:@"\n"]
        attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize] }];
    for (NSArray<NSString *> *s in [RASurfaceFactors sources]) {
        NSURL *url = [NSURL URLWithString:s[1]];
        [sources appendAttributedString:[[NSAttributedString alloc] initWithString:@"• " attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize] }]];
        [sources appendAttributedString:[[NSAttributedString alloc] initWithString:s[0] attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize], NSLinkAttributeName: url ? (id)url : (id)s[1] }]];
        [sources appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    }
    NSTextField *links = [NSTextField labelWithAttributedString:sources];
    links.allowsEditingTextAttributes = YES;    // the links can be clicked
    links.selectable = YES;
    links.identifier = @"surfaceFactorsSources";

    NSButton *restore = [NSButton buttonWithTitle:NSLocalizedString(@"Restore Defaults", @"surface factors") target:self
                                           action:@selector(restoreDefaults:)];
    restore.identifier = @"surfaceFactorsRestore";
    NSStackView *stack = [NSStackView stackViewWithViews:@[ intro, scroll, restore, links ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    for (NSView *v in @[ intro, scroll, links ]) [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32].active = YES;
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:260].active = YES;
    [scroll setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    self.window.contentView = stack;
}

- (void)libraryDidChange:(NSNotification *)n
{
    [_tableView reloadData];
}

#pragma mark - table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[RASurfaceFactors categories].count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSString *category = [RASurfaceFactors categories][(NSUInteger)row];
    NSString *c = tableColumn.identifier;
    NSTextField *f = nil;
    if ([c isEqualToString:@"factor"]) {
        NSNumber *changed = _library.equipment.surfaceFactors[category];
        f = [NSTextField textFieldWithString:changed != nil ? [_number stringFromNumber:changed] ?: @"" : @""];
        f.placeholderString = [_number stringFromNumber:@([RASurfaceFactors defaultFactorOfCategory:category])];
        f.bordered = NO;
        f.drawsBackground = NO;
        f.alignment = NSTextAlignmentRight;
        f.target = self;
        f.action = @selector(factorEdited:);
        f.identifier = [@"surfaceFactor." stringByAppendingString:category];
        return f;
    }
    NSString *text = [c isEqualToString:@"name"] ? [RASurfaceFactors nameOfCategory:category]
                   : [c isEqualToString:@"tags"] ? [RASurfaceFactors tagsOfCategory:category]
                   : [_number stringFromNumber:@([RASurfaceFactors defaultFactorOfCategory:category])] ?: @"";
    f = [NSTextField labelWithString:text];
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    f.toolTip = text;
    if ([c isEqualToString:@"tags"]) {
        f.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
        f.textColor = [NSColor secondaryLabelColor];
    }
    if ([c isEqualToString:@"default"]) {
        f.alignment = NSTextAlignmentRight;
        f.textColor = [NSColor secondaryLabelColor];
    }
    return f;
}

- (void)factorEdited:(NSTextField *)sender
{
    NSInteger row = [_tableView rowForView:sender];
    if (row < 0) return;
    NSString *s = [sender.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSNumber *n = s.length ? ([_number numberFromString:s] ?: @([[s stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue]))
                           : nil;
    [self setFactor:n ofCategory:[RASurfaceFactors categories][(NSUInteger)row]];
}

- (void)setFactor:(nullable NSNumber *)factor ofCategory:(NSString *)category
{
    RALibraryDocument *library = _library;
    if (!library || ![[RASurfaceFactors categories] containsObject:category]) return;
    double v = factor != nil ? factor.doubleValue : 0;
    [library changeEquipment:^(RAEquipment *e) {
        NSMutableDictionary<NSString *, NSNumber *> *d = [e.surfaceFactors mutableCopy];
        if (v > 0) d[category] = @(MIN(MAX(v, [RASurfaceFactors minimumFactor]), [RASurfaceFactors maximumFactor]));
        else [d removeObjectForKey:category];
        e.surfaceFactors = d;
    } actionName:NSLocalizedString(@"Surface Factor", @"undo action name")];
    [_tableView reloadData];     // a refused or bounded value shows as it is kept
}

- (IBAction)restoreDefaults:(nullable id)sender
{
    [_library changeEquipment:^(RAEquipment *e) { e.surfaceFactors = @{}; }
                   actionName:NSLocalizedString(@"Restore Surface Factors", @"undo action name")];
    [_tableView reloadData];
}

@end
