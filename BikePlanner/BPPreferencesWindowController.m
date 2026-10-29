//
//  BPPreferencesWindowController.m
//  BikePlanner
//

#import "BPPreferencesWindowController.h"
#import "BPPlaceSearch.h"
#import "Document.h"
#import "MapController.h"

@interface BPPreferencesWindowController () <NSWindowDelegate>
@property (strong) NSTextField *latitudeField;
@property (strong) NSTextField *longitudeField;
@property (strong) NSTextField *radiusField;
@property (strong) NSButton *mapCenterButton;
@property (strong) NSSearchField *searchField;
@property (strong) NSTextField *messageLabel;
@property (strong, nullable) NSMenu *resultsMenu;
@end

@implementation BPPreferencesWindowController

- (instancetype)initWithPreferences:(BPPreferences *)preferences
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 230)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing:NSBackingStoreBuffered defer:YES];
    w.title = NSLocalizedString(@"Preferences", @"Preferences window");
    w.releasedWhenClosed = NO;
    if (self = [super initWithWindow:w]) {
        _preferences = preferences;
        _mapCenterProvider = ^BOOL(CLLocationCoordinate2D *center) {
            for (NSWindow *win in NSApp.orderedWindows) {
                Document *d = win.windowController.document;
                if ([d isKindOfClass:[Document class]] && d.mapController.mapView) {
                    if (center) *center = d.mapController.mapView.centerCoordinate;
                    return YES;
                }
            }
            return NO;
        };
        _presentResultsMenu = ^(NSMenu *menu, NSView *view) {
            NSPoint p = view.isFlipped ? NSMakePoint(0, NSHeight(view.bounds) + 4) : NSMakePoint(0, -4);
            [menu popUpMenuPositioningItem:nil atLocation:p inView:view];
        };
        [self buildContent];
        [self refreshFields];
        [w center];
        w.frameAutosaveName = @"BPPreferences";
    }
    return self;
}

- (NSTextField *)numberFieldMin:(double)min max:(double)max digits:(NSUInteger)digits
{
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    f.usesGroupingSeparator = NO;
    f.maximumFractionDigits = digits;
    f.minimum = @(min);
    f.maximum = @(max);
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.formatter = f;
    field.alignment = NSTextAlignmentRight;
    field.target = self;
    [field.widthAnchor constraintEqualToConstant:110].active = YES;
    return field;
}

- (NSTextField *)label:(NSString *)s
{
    NSTextField *l = [NSTextField labelWithString:s];
    l.alignment = NSTextAlignmentRight;
    return l;
}

- (void)buildContent
{
    self.latitudeField = [self numberFieldMin:-90 max:90 digits:6];
    self.latitudeField.action = @selector(positionChanged:);
    self.latitudeField.placeholderString = NSLocalizedString(@"latitude", @"Preferences");
    self.latitudeField.accessibilityIdentifier = @"prefLatitude";
    self.longitudeField = [self numberFieldMin:-180 max:180 digits:6];
    self.longitudeField.action = @selector(positionChanged:);
    self.longitudeField.placeholderString = NSLocalizedString(@"longitude", @"Preferences");
    self.longitudeField.accessibilityIdentifier = @"prefLongitude";
    self.radiusField = [self numberFieldMin:1 max:2000 digits:0];
    self.radiusField.action = @selector(radiusChanged:);
    self.radiusField.accessibilityIdentifier = @"prefRadius";

    self.mapCenterButton = [NSButton buttonWithTitle:NSLocalizedString(@"Use Current Map Center", @"Preferences")
                                              target:self action:@selector(useMapCenter:)];
    self.searchField = [[NSSearchField alloc] init];
    self.searchField.placeholderString = NSLocalizedString(@"Find a place", @"Preferences");
    self.searchField.sendsWholeSearchString = YES; // search on Return only
    self.searchField.target = self;
    self.searchField.action = @selector(search:);
    self.searchField.accessibilityIdentifier = @"prefSearch";
    self.messageLabel = [NSTextField wrappingLabelWithString:
        NSLocalizedString(@"Used when your location is unknown, and as the initial map center.", @"Preferences")];
    self.messageLabel.textColor = [NSColor secondaryLabelColor];
    self.messageLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSStackView *position = [NSStackView stackViewWithViews:@[ self.latitudeField, self.longitudeField ]];
    NSStackView *radius = [NSStackView stackViewWithViews:@[ self.radiusField,
                                                             [NSTextField labelWithString:NSLocalizedString(@"km", @"Preferences")] ]];
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[ [self label:NSLocalizedString(@"Default position:", @"Preferences")], position ],
        @[ [NSGridCell emptyContentView], self.mapCenterButton ],
        @[ [self label:NSLocalizedString(@"Find a place:", @"Preferences")], self.searchField ],
        @[ [NSGridCell emptyContentView], self.messageLabel ],
        @[ [self label:NSLocalizedString(@"Initial radius:", @"Preferences")], radius ],
    ]];
    grid.rowSpacing = 10;
    grid.columnSpacing = 8;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *content = self.window.contentView;
    [content addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-20],
        [grid.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [grid.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-20],
        [self.searchField.widthAnchor constraintEqualToConstant:228],
        [self.messageLabel.widthAnchor constraintEqualToConstant:228],
    ]];
}

- (void)refreshFields
{
    CLLocationCoordinate2D p = self.preferences.defaultPosition;
    self.latitudeField.objectValue = @(p.latitude);
    self.longitudeField.objectValue = @(p.longitude);
    self.radiusField.objectValue = @(self.preferences.initialRadiusKm);
}

- (void)showMessage:(NSString *)message
{
    self.messageLabel.stringValue = message;
}

#pragma mark - actions

// invalid values (refused by the formatters) give back the saved ones
- (void)positionChanged:(id)sender
{
    NSNumber *lat = self.latitudeField.objectValue, *lon = self.longitudeField.objectValue;
    if ([lat isKindOfClass:[NSNumber class]] && [lon isKindOfClass:[NSNumber class]]) {
        self.preferences.defaultPosition = CLLocationCoordinate2DMake(lat.doubleValue, lon.doubleValue);
    }
    [self refreshFields];
}

- (void)radiusChanged:(id)sender
{
    NSNumber *r = self.radiusField.objectValue;
    if ([r isKindOfClass:[NSNumber class]]) self.preferences.initialRadiusKm = r.doubleValue;
    [self refreshFields];
}

- (void)useMapCenter:(id)sender
{
    CLLocationCoordinate2D c = kCLLocationCoordinate2DInvalid;
    if (self.mapCenterProvider && self.mapCenterProvider(&c)) {
        self.preferences.defaultPosition = c;
        [self refreshFields];
        [self showMessage:NSLocalizedString(@"Default position set to the center of the map.", @"Preferences")];
    } else {
        [self showMessage:NSLocalizedString(@"No map is open.", @"Preferences")];
    }
}

- (void)search:(NSSearchField *)sender
{
    NSString *query = [sender.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!query.length) return;
    MKCoordinateRegion near = MKCoordinateRegionMakeWithDistance(self.preferences.defaultPosition, 200000, 200000);
    [BPPlaceSearch search:query near:near completion:^(NSArray<MKMapItem *> *items, NSError *error) {
        if (error) {
            [self showMessage:[NSString stringWithFormat:NSLocalizedString(@"Search failed: %@", @"Preferences"),
                               error.localizedDescription]];
        } else if (items.count == 0) {
            [self showMessage:[NSString stringWithFormat:NSLocalizedString(@"No place found for “%@”.", @"Preferences"), query]];
        } else if (items.count == 1) {
            [self choosePlace:items.firstObject];
        } else {
            NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Places"];
            for (MKMapItem *item in items) {
                NSMenuItem *mi = [menu addItemWithTitle:[BPPlaceSearch titleForItem:item] action:@selector(placeChosen:)
                                          keyEquivalent:@""];
                mi.target = self;
                mi.representedObject = item;
            }
            self.resultsMenu = menu;
            if (self.presentResultsMenu) self.presentResultsMenu(menu, self.searchField);
        }
    }];
}

- (void)placeChosen:(NSMenuItem *)sender
{
    [self choosePlace:sender.representedObject];
}

- (void)choosePlace:(MKMapItem *)item
{
    self.preferences.defaultPosition = item.placemark.coordinate;
    [self refreshFields];
    [self showMessage:[NSString stringWithFormat:NSLocalizedString(@"Default position: %@", @"Preferences"),
                       [BPPlaceSearch titleForItem:item]]];
}

@end
