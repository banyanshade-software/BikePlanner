//
//  BPRoadTypesView.m
//  BikePlanner
//

#import "BPRoadTypesView.h"
#import "BikePlan.h"

@implementation BPRoadTypesView {
    NSGridView *_grid;
    NSMutableDictionary<NSString *, NSButton *> *_radios; // by kind, @"" for None
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setRows:(nullable NSArray<NSDictionary<NSString *, NSString *> *> *)rows
{
    rows = rows ?: @[];
    if ([rows isEqualToArray:_rows ?: @[]] && _grid) return;
    _rows = [rows copy];
    NSString *kind = _selectedKind;
    if (kind && ![[rows valueForKey:BPRoadTypeKindKey] containsObject:kind]) kind = nil;
    [self rebuild];
    [self selectKind:kind];
}

- (NSTextField *)label:(NSString *)text bold:(BOOL)bold
{
    NSTextField *t = [NSTextField labelWithString:text];
    CGFloat size = NSFont.smallSystemFontSize;
    t.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont monospacedDigitSystemFontOfSize:size weight:NSFontWeightRegular];
    t.alignment = NSTextAlignmentRight;
    return t;
}

- (NSButton *)radio:(NSString *)title kind:(NSString *)kind
{
    NSButton *b = [NSButton radioButtonWithTitle:title target:self action:@selector(radioClicked:)];
    b.controlSize = NSControlSizeSmall;
    b.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    b.identifier = kind;
    b.accessibilityIdentifier = [@"roadType." stringByAppendingString:kind.length ? kind : @"none"];
    _radios[kind] = b;
    return b;
}

- (void)rebuild
{
    [_grid removeFromSuperview];
    _grid = nil;
    _radios = [NSMutableDictionary dictionary];
    if (!_rows.count) {
        [self invalidateIntrinsicContentSize];
        return;
    }
    NSGridView *g = [NSGridView gridViewWithNumberOfColumns:3 rows:0];
    g.rowSpacing = 1;
    g.columnSpacing = 8;
    g.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray<NSView *> *(^title)(NSString *) = ^(NSString *s) {
        NSTextField *t = [self label:s bold:YES];
        t.alignment = NSTextAlignmentLeft;
        return @[t, NSGridCell.emptyContentView, NSGridCell.emptyContentView];
    };
    void (^merge)(NSGridRow *) = ^(NSGridRow *r) {
        [r mergeCellsInRange:NSMakeRange(0, 3)];
        r.topPadding = 4;
    };
    merge([g addRowWithViews:title(NSLocalizedString(@"Distance by road type", @"Info section"))]);
    BOOL surfaces = NO;
    for (NSDictionary<NSString *, NSString *> *row in _rows) {
        NSString *kind = row[BPRoadTypeKindKey];
        if (!surfaces && [kind hasPrefix:@"surface:"]) {
            surfaces = YES;
            merge([g addRowWithViews:title(NSLocalizedString(@"Surface", @"Info section"))]);
        }
        [g addRowWithViews:@[[self radio:row[BPRoadTypeNameKey] kind:kind],
                             [self label:row[BPRoadTypeDistanceKey] bold:NO], [self label:row[BPRoadTypePercentKey] bold:NO]]];
    }
    NSGridRow *none = [g addRowWithViews:@[[self radio:NSLocalizedString(@"None (no highlight on the map)", @"Info section") kind:@""],
                                           NSGridCell.emptyContentView, NSGridCell.emptyContentView]];
    [none mergeCellsInRange:NSMakeRange(0, 3)];
    none.topPadding = 4;
    [g columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
    [g columnAtIndex:1].xPlacement = NSGridCellPlacementTrailing;
    [g columnAtIndex:2].xPlacement = NSGridCellPlacementTrailing;
    [self addSubview:g];
    [NSLayoutConstraint activateConstraints:@[
        [g.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [g.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
        [g.topAnchor constraintEqualToAnchor:self.topAnchor],
        [g.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    _grid = g;
    [self invalidateIntrinsicContentSize];
}

- (NSSize)intrinsicContentSize
{
    return _grid ? NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric) : NSMakeSize(NSViewNoIntrinsicMetric, 0);
}

- (void)radioClicked:(NSButton *)sender
{
    [self selectKind:sender.identifier.length ? sender.identifier : nil];
}

- (nullable NSButton *)radioForKind:(nullable NSString *)kind
{
    return _radios[kind ?: @""];
}

- (void)selectKind:(nullable NSString *)kind
{
    if (!_radios[kind ?: @""]) kind = nil;
    for (NSString *k in _radios) _radios[k].state = [k isEqualToString:kind ?: @""] ? NSControlStateValueOn : NSControlStateValueOff;
    if ((kind == nil && _selectedKind == nil) || [kind isEqualToString:_selectedKind]) return;
    _selectedKind = [kind copy];
    if (self.selectionHandler) self.selectionHandler(_selectedKind);
}

@end
