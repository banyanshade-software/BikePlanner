//
//  POICalloutView.m
//  BikePlanner
//
//  Created by Daniel Braun on 20/08/2025.
//

#import "POICalloutView.h"
#import "BPPOIDescription.h"

static const CGFloat kBPCalloutWidth = 300;

@implementation POICalloutView {
    NSStackView *_stack;
    NSTextField *_positionLabel;
    NSBox *_separator1, *_separator2;
    NSGridView *_grid;
    NSStackView *_allTagsRow;
    NSButton *_allTagsToggle;
    NSTextField *_allTagsTitle;
    NSTextField *_allTagsLabel;
    NSButton *_includeCheckbox;
    NSButton *_osmButton, *_streetViewButton, *_coordinatesButton, *_editButton;
}


static NSTextField *BPLabel(NSFont *font, NSColor *color)
{
    NSTextField *l = [NSTextField wrappingLabelWithString:@""];
    l.font = font;
    l.textColor = color;
    l.preferredMaxLayoutWidth = kBPCalloutWidth - 8;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}

static NSButton *BPSmallButton(NSString *title, NSString *identifier)
{
    NSButton *b = [NSButton buttonWithTitle:title target:nil action:nil];
    b.controlSize = NSControlSizeSmall;
    b.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
    b.accessibilityIdentifier = identifier;
    return b;
}

static NSBox *BPSeparator(void)
{
    NSBox *b = [[NSBox alloc] init];
    b.boxType = NSBoxSeparator;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    return b;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _included = YES;
    }
    return self;
}

// the content is built when the callout is filled (it opens), not for every POI marker: ~6 ms per callout (#78)
- (void) buildContentIfNeeded
{
    if (_stack) return;
    {
        NSFont *small = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        _positionLabel = BPLabel(small, [NSColor secondaryLabelColor]);
        _positionLabel.accessibilityIdentifier = @"poiPosition";

        _grid = [NSGridView gridViewWithNumberOfColumns:2 rows:0];
        _grid.rowSpacing = 2;
        _grid.columnSpacing = 8;
        _grid.accessibilityIdentifier = @"poiTags";

        // All OSM tags: collapsed
        _allTagsToggle = [[NSButton alloc] init];
        _allTagsToggle.bezelStyle = NSBezelStyleDisclosure;
        [_allTagsToggle setButtonType:NSButtonTypePushOnPushOff];
        _allTagsToggle.title = @"";
        _allTagsToggle.target = self;
        _allTagsToggle.action = @selector(toggleAllTags:);
        _allTagsToggle.accessibilityIdentifier = @"poiAllTagsToggle";
        _allTagsTitle = BPLabel(small, [NSColor labelColor]);
        _allTagsRow = [NSStackView stackViewWithViews:@[_allTagsToggle, _allTagsTitle]];
        _allTagsRow.spacing = 2;
        _allTagsLabel = BPLabel([NSFont monospacedSystemFontOfSize:[NSFont smallSystemFontSize] - 1 weight:NSFontWeightRegular],
                                [NSColor labelColor]);
        _allTagsLabel.selectable = YES;
        _allTagsLabel.accessibilityIdentifier = @"poiAllTags";
        _allTagsLabel.hidden = YES;

        _osmButton = BPSmallButton(NSLocalizedString(@"OpenStreetMap", @"POI callout button"), @"poiOpenOSM");
        _osmButton.toolTip = NSLocalizedString(@"Open this point of interest on openstreetmap.org", @"POI callout");
        _streetViewButton = BPSmallButton(NSLocalizedString(@"Street View", @"POI callout button"), @"poiStreetView");
        _streetViewButton.toolTip = NSLocalizedString(@"Look at this point of interest from the route in Street View", @"POI callout");
        _coordinatesButton = BPSmallButton(NSLocalizedString(@"Copy", @"POI callout button"), @"poiCopy");
        _coordinatesButton.toolTip = NSLocalizedString(@"Copy the coordinates (latitude, longitude)", @"POI callout");
        NSStackView *buttons = [NSStackView stackViewWithViews:@[_osmButton, _streetViewButton, _coordinatesButton]];
        buttons.spacing = 4;

        id<POICalloutActions> target = self.actionTarget;
        _osmButton.target = _streetViewButton.target = _coordinatesButton.target = target;
        _osmButton.action = @selector(openPOIInOSM:);
        _streetViewButton.action = @selector(streetViewAtPOI:);
        _coordinatesButton.action = @selector(copyPOICoordinates:);

        _includeCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Include in track", @"POI callout")
                                                target:target action:@selector(includeCheckboxChanged:)];
        _includeCheckbox.controlSize = NSControlSizeSmall;
        _includeCheckbox.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
        _includeCheckbox.state = _included ? NSControlStateValueOn : NSControlStateValueOff;
        _includeCheckbox.toolTip = NSLocalizedString(@"Exported with the track to GPX (when POIs are exported)", @"POI callout");
        _includeCheckbox.accessibilityIdentifier = @"poiInclude";
        _editButton = BPSmallButton(NSLocalizedString(@"Edit…", @"POI callout button"), @"poiEdit");
        _editButton.target = target;
        _editButton.action = @selector(editPOIFromCallout:);
        NSStackView *bottom = [NSStackView stackViewWithViews:@[_includeCheckbox, _editButton]];
        bottom.spacing = 8;

        _separator1 = BPSeparator();
        _separator2 = BPSeparator();
        _stack = [NSStackView stackViewWithViews:@[ _positionLabel, _separator1, _grid, _allTagsRow, _allTagsLabel,
                                                    _separator2, buttons, bottom ]];
        _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _stack.alignment = NSLayoutAttributeLeading;
        _stack.spacing = 6;
        _stack.detachesHiddenViews = YES;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];

        [NSLayoutConstraint activateConstraints:@[
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
            [self.widthAnchor constraintEqualToConstant:kBPCalloutWidth],
            [_separator1.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
            [_separator2.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
        ]];
    }
}

- (NSButton *) includeCheckbox    { [self buildContentIfNeeded]; return _includeCheckbox; }
- (NSButton *) osmButton          { [self buildContentIfNeeded]; return _osmButton; }
- (NSButton *) streetViewButton   { [self buildContentIfNeeded]; return _streetViewButton; }
- (NSButton *) coordinatesButton  { [self buildContentIfNeeded]; return _coordinatesButton; }
- (NSButton *) editButton         { [self buildContentIfNeeded]; return _editButton; }

- (void) setIncluded:(BOOL)included
{
    _included = included;
    _includeCheckbox.state = included ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void) configureWithDescription:(BPPOIDescription *)d position:(nullable NSString *)position
{
    [self buildContentIfNeeded];
    _positionLabel.stringValue = position ?: @"";
    _positionLabel.hidden = (position.length == 0);

    while (_grid.numberOfRows) [_grid removeRowAtIndex:0];
    for (NSView *v in [_grid.subviews copy]) [v removeFromSuperview];
    NSFont *small = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    for (NSArray<NSString *> *row in d.rows) {
        NSTextField *label = [NSTextField labelWithString:row[0]];
        label.font = small;
        label.textColor = [NSColor secondaryLabelColor];
        NSTextField *value = BPLabel(small, [NSColor labelColor]);
        value.selectable = YES;
        value.allowsEditingTextAttributes = YES; // links are clickable
        value.attributedStringValue = [self linkedString:row[1] font:small];
        value.preferredMaxLayoutWidth = kBPCalloutWidth / 2;
        [_grid addRowWithViews:@[label, value]];
    }
    _grid.hidden = (d.rows.count == 0);

    NSFont *mono = _allTagsLabel.font;
    NSMutableAttributedString *all = [[NSMutableAttributedString alloc] init];
    for (NSArray<NSString *> *t in d.allTags) {
        if (all.length) [all appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{ NSFontAttributeName: mono }]];
        NSString *key = [NSString stringWithFormat:@"%@ = ", t[0]];
        [all appendAttributedString:[[NSAttributedString alloc] initWithString:key attributes:@{ NSFontAttributeName: mono,
                                                                                                 NSForegroundColorAttributeName: [NSColor labelColor] }]];
        [all appendAttributedString:[self linkedString:t[1] font:mono]];
    }
    _allTagsLabel.allowsEditingTextAttributes = YES;
    _allTagsLabel.attributedStringValue = all;
    _allTagsTitle.stringValue = [NSString localizedStringWithFormat:NSLocalizedString(@"All OSM tags (%lu)", @"POI callout"),
                                 (unsigned long)d.allTags.count];
    _allTagsRow.hidden = (d.allTags.count == 0);
    _allTagsLabel.hidden = _allTagsRow.hidden || !self.showsAllTags;

    _separator1.hidden = _grid.hidden && _allTagsRow.hidden;
    _separator2.hidden = _positionLabel.hidden && _separator1.hidden;
    _osmButton.hidden = (d.osmURL == nil);
    _editButton.hidden = !d.custom;
    [self fitToContent];
}

// MapKit sizes the callout from the frame of the accessory view
- (void) fitToContent
{
    [self invalidateIntrinsicContentSize];
    [self layoutSubtreeIfNeeded];
    [self setFrameSize:NSMakeSize(kBPCalloutWidth, _stack.fittingSize.height + 8)];
}

// the value, a link if it is a web address
- (NSAttributedString *) linkedString:(NSString *)value font:(NSFont *)font
{
    NSMutableDictionary *attrs = [@{ NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor labelColor] } mutableCopy];
    NSURL *url = [BPPOIDescription linkURLForValue:value];
    if (url) {
        attrs[NSLinkAttributeName] = url;
        attrs[NSForegroundColorAttributeName] = [NSColor linkColor];
        attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        attrs[NSCursorAttributeName] = [NSCursor pointingHandCursor];
    }
    return [[NSAttributedString alloc] initWithString:value attributes:attrs];
}

- (NSArray<NSURL *> *) displayedLinks
{
    NSMutableArray *links = [NSMutableArray array];
    NSMutableArray<NSTextField *> *fields = [NSMutableArray array];
    for (NSInteger r = 0; r < _grid.numberOfRows; r++) [fields addObject:(NSTextField *)[_grid cellAtColumnIndex:1 rowIndex:r].contentView];
    if (!_allTagsLabel.hidden) [fields addObject:_allTagsLabel];
    for (NSTextField *f in fields) {
        NSAttributedString *s = f.attributedStringValue;
        [s enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, s.length) options:0
                   usingBlock:^(id value, NSRange range, BOOL *stop) {
            if ([value isKindOfClass:[NSURL class]]) [links addObject:value];
        }];
    }
    return links;
}

- (void) setShowsAllTags:(BOOL)show
{
    [self buildContentIfNeeded];
    _showsAllTags = show;
    _allTagsToggle.state = show ? NSControlStateValueOn : NSControlStateValueOff;
    _allTagsLabel.hidden = _allTagsRow.hidden || !show;
    [self fitToContent];
    // an open callout does not follow the size of its accessory view: show it again
    MKAnnotationView *av = self.annotview;
    NSView *v = av.superview;
    while (v && ![v isKindOfClass:[MKMapView class]]) v = v.superview;
    if (av.selected && av.annotation && v) {
        MKMapView *map = (MKMapView *)v;
        id<MKAnnotation> annotation = av.annotation;
        [map deselectAnnotation:annotation animated:NO];
        [map selectAnnotation:annotation animated:NO];
    }
}

- (void) toggleAllTags:(NSButton *)sender
{
    self.showsAllTags = (sender.state == NSControlStateValueOn);
}

- (NSSize) intrinsicContentSize
{
    return NSMakeSize(kBPCalloutWidth, _stack.fittingSize.height + 8);
}

- (NSString *) displayedText
{
    if (!_stack) return @"";
    NSMutableArray *parts = [NSMutableArray array];
    if (!_positionLabel.hidden) [parts addObject:_positionLabel.stringValue];
    for (NSInteger r = 0; r < _grid.numberOfRows; r++) {
        NSTextField *l = (NSTextField *)[_grid cellAtColumnIndex:0 rowIndex:r].contentView;
        NSTextField *v = (NSTextField *)[_grid cellAtColumnIndex:1 rowIndex:r].contentView;
        [parts addObject:[NSString stringWithFormat:@"%@ %@", l.stringValue, v.stringValue]];
    }
    if (!_allTagsRow.hidden) [parts addObject:_allTagsTitle.stringValue];
    if (!_allTagsLabel.hidden) [parts addObject:_allTagsLabel.stringValue];
    return [parts componentsJoinedByString:@"\n"];
}

- (void) setInfodic:(NSDictionary *)dic
{
    _infodic = dic;
}

- (void) mouseDown:(NSEvent *)event
{
    [self.annotview  setSelected:NO animated:YES];
}
@end
