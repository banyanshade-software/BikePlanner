//
//  BPGuidedTour.m
//  BikePlanner
//
//  Guided tour of a document window (#63).
//

#import "BPGuidedTour.h"

static NSString *const BPGuidedTourShownKey = @"BPGuidedTourShown";


@implementation BPGuidedTour {
    __weak NSWindow *_window;
    NSArray<NSDictionary<NSString *, NSString *> *> *_steps;
}

+ (BOOL)shouldOfferAutomaticallyWithDefaults:(NSUserDefaults *)defaults
{
    return ![defaults boolForKey:BPGuidedTourShownKey];
}

+ (void)markOfferedInDefaults:(NSUserDefaults *)defaults
{
    [defaults setBool:YES forKey:BPGuidedTourShownKey];
}

+ (void)installMenuItem
{
    NSMenu *help = NSApp.helpMenu ?: [NSApp.mainMenu itemWithTitle:@"Help"].submenu;
    if (!help || [help indexOfItemWithTarget:nil andAction:NSSelectorFromString(@"showGuidedTour:")] >= 0) return;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Guided Tour", @"Help menu")
                                                  action:NSSelectorFromString(@"showGuidedTour:") keyEquivalent:@""];
    [help insertItem:item atIndex:0];
}

// anchor: accessibility identifier of the control; "search": the toolbar search field; "toolbar": the top of the
// window content (toolbar items have no view of their own)
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)steps
{
    return @[
        @{ @"anchor": @"map", @"title": NSLocalizedString(@"Welcome to BikePlanner", @"tour"),
           @"text": NSLocalizedString(@"Plan bicycle routes on the map: BRouter computes the route between your waypoints, "
                                      @"with its length, elevation and the points of interest along it. This tour shows the "
                                      @"main controls on a sample route; Help ▸ Guided Tour shows it again.", @"tour") },
        @{ @"anchor": @"clickMode", @"title": NSLocalizedString(@"Click modes", @"tour"),
           @"text": NSLocalizedString(@"Edit (⌘1): a click on the map places the start, then each destination; a click on the "
                                      @"route inserts a waypoint. Add interm. (⌘2): a click on the route inserts an "
                                      @"intermediate waypoint. View (⌘3): a click on the route moves Street View and the "
                                      @"profile cursor there. An opened document starts in View mode.", @"tour") },
        @{ @"anchor": @"waypoint", @"title": NSLocalizedString(@"Waypoints", @"tour"),
           @"text": NSLocalizedString(@"The route goes through its waypoints. Drag a waypoint to move it; right-click it to "
                                      @"remove it or to end a stage there. Every change can be undone (⌘Z).", @"tour") },
        @{ @"anchor": @"routeLine", @"title": NSLocalizedString(@"Right-click on the map", @"tour"),
           @"text": NSLocalizedString(@"Add POI… (water, danger, shelter…, with a name), Insert Waypoint Here on the route "
                                      @"line, Street View Here, Copy Coordinates.", @"tour") },
        @{ @"anchor": @"waterPOI", @"title": NSLocalizedString(@"Points of interest", @"tour"),
           @"text": NSLocalizedString(@"Drinking water, toilets and repair stations found along the route. Click one for its "
                                      @"details: include it in the GPX, look at it in Street View or open it on "
                                      @"OpenStreetMap.", @"tour") },
        @{ @"anchor": @"mapType", @"title": NSLocalizedString(@"Maps", @"tour"),
           @"text": NSLocalizedString(@"OSM, OSM+cycle (with the cycle routes), Apple, satellite with roads, satellite. "
                                      @"The colors of the route are chosen in the Preferences.", @"tour") },
        @{ @"anchor": @"search", @"title": NSLocalizedString(@"Search", @"tour"),
           @"text": NSLocalizedString(@"Find a place by name and show it on the map.", @"tour") },
        @{ @"anchor": @"infoSection", @"title": NSLocalizedString(@"Route information", @"tour"),
           @"text": NSLocalizedString(@"Length, elevation gain, riding time and average speed estimated by BRouter, and the "
                                      @"distance by road type and surface: select one to highlight it on the map. Fetch POI "
                                      @"looks for points of interest along the route; View POI shows them.", @"tour") },
        @{ @"anchor": @"elevationProfile", @"title": NSLocalizedString(@"Elevation profile", @"tour"),
           @"text": NSLocalizedString(@"Move the mouse over the profile to follow the route on the map; zoom with the "
                                      @"buttons. Stage ends are marked.", @"tour") },
        @{ @"anchor": @"sideTabs", @"title": NSLocalizedString(@"Street View and parameters", @"tour"),
           @"text": NSLocalizedString(@"Street View shows the road at the cursor. The Params tab sets the BRouter profile "
                                      @"parameters of this document (avoid busy roads, hills…); Apply computes the route "
                                      @"again.", @"tour") },
        @{ @"anchor": @"toolbar", @"title": NSLocalizedString(@"Files and GPS", @"tour"),
           @"text": NSLocalizedString(@"Export GPX for your GPS (the whole route or one file per stage). Import trace shows a "
                                      @"track to compare with the route; File ▸ Import Track as Route… turns a GPX, TCX or "
                                      @"FIT file into a plan. Reverse and Clear act on the route.", @"tour") },
    ];
}

+ (nullable NSURL *)sampleURL
{
    return [[NSBundle mainBundle] URLForResource:@"TourSample" withExtension:@"bikeplan"];
}

+ (void)openSampleWithCompletion:(void (^)(NSDocument * _Nullable document, NSError * _Nullable error))completion
{
    NSURL *copy = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"BikePlanner Tour.bikeplan"]];
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    NSDocument *open = [dc documentForURL:copy];
    if (open) {
        [open showWindows];
        completion(open, nil);
        return;
    }
    NSURL *sample = [self sampleURL];
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtURL:copy error:NULL];
    if (!sample || ![[NSFileManager defaultManager] copyItemAtURL:sample toURL:copy error:&error]) {
        completion(nil, error);
        return;
    }
    [dc openDocumentWithContentsOfURL:copy display:YES
                    completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *openError) {
        completion(document, openError);
    }];
}

- (instancetype)initWithWindow:(NSWindow *)window
{
    if (self = [super init]) {
        _window = window;
        _steps = [BPGuidedTour steps];
    }
    return self;
}

- (NSUInteger)stepCount
{
    return _steps.count;
}

- (BOOL)isShowing
{
    return _popover != nil;
}

static NSView *BPFindView(NSView *root, NSString *identifier)
{
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (NSView *v in root.subviews) {
        NSView *found = BPFindView(v, identifier);
        if (found) return found;
    }
    return nil;
}

- (NSString *)anchorKeyForStep:(NSUInteger)step
{
    return step < _steps.count ? _steps[step][@"anchor"] : @"";
}

+ (NSSet<NSString *> *)routeAnchorKeys
{
    return [NSSet setWithObjects:@"waypoint", @"routeLine", @"waterPOI", nil];
}

- (nullable NSView *)anchorViewForStep:(NSUInteger)step
{
    NSRect rect;
    return [self anchorViewForStep:step rect:&rect];
}

// the view and the rect in it; route elements from the provider, else the center of the map
- (nullable NSView *)anchorViewForStep:(NSUInteger)step rect:(NSRect *)rect
{
    NSWindow *w = _window;
    if (step >= _steps.count || !w) return nil;
    NSString *anchor = _steps[step][@"anchor"];
    if ([[BPGuidedTour routeAnchorKeys] containsObject:anchor]) {
        NSView *v = self.routeAnchorProvider ? self.routeAnchorProvider(anchor, rect) : nil;
        if (v.window == w) return v;
        anchor = @"map";
    }
    NSView *v = [self anchorViewWithKey:anchor];
    if (v) *rect = [self anchorRectForKey:anchor inView:v];
    return v;
}

- (nullable NSView *)anchorViewWithKey:(NSString *)anchor
{
    NSWindow *w = _window;
    if ([anchor isEqualToString:@"search"]) {
        for (NSToolbarItem *item in w.toolbar.items) {
            if ([item isKindOfClass:[NSSearchToolbarItem class]]) {
                NSView *field = ((NSSearchToolbarItem *)item).searchField;
                if (field.window == w) return field;
            }
        }
        return w.contentView;
    }
    if ([anchor isEqualToString:@"toolbar"]) {
        // the Export GPX button of the toolbar (a view of the window frame, not of the content)
        NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:w.contentView.superview ?: w.contentView];
        while (views.count) {
            NSView *v = views.lastObject;
            [views removeLastObject];
            if ([v isKindOfClass:[NSControl class]] && ((NSControl *)v).action == NSSelectorFromString(@"exportGPX:") && !v.isHiddenOrHasHiddenAncestor) return v;
            [views addObjectsFromArray:v.subviews];
        }
        return w.contentView;
    }
    return BPFindView(w.contentView, anchor) ?: w.contentView;
}

// where the bubble points: a small control as a whole; the center of a large view (map); the top right of the
// content for the toolbar
- (NSRect)anchorRectForKey:(NSString *)anchor inView:(NSView *)view
{
    NSRect b = view.bounds;
    if (([anchor isEqualToString:@"toolbar"] || [anchor isEqualToString:@"search"]) && view == _window.contentView) {
        CGFloat top = view.isFlipped ? NSMinY(b) : NSMaxY(b) - 2;
        return NSMakeRect(NSMaxX(b) - 160, top, 2, 2);
    }
    if (b.size.width > 400 && b.size.height > 200) return NSMakeRect(NSMidX(b) - 1, NSMidY(b) - 1, 2, 2);
    return b;
}

- (NSViewController *)contentForStep:(NSUInteger)step
{
    NSDictionary *s = _steps[step];
    NSTextField *title = [NSTextField labelWithString:[NSString stringWithFormat:@"%lu/%lu  %@", (unsigned long)step + 1,
                                                       (unsigned long)_steps.count, s[@"title"]]];
    title.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    title.accessibilityIdentifier = @"tourTitle";
    NSTextField *text = [NSTextField wrappingLabelWithString:s[@"text"]];
    text.preferredMaxLayoutWidth = 320;
    text.selectable = NO;
    text.accessibilityIdentifier = @"tourText";

    BOOL last = step + 1 == _steps.count;
    NSButton *previous = [NSButton buttonWithTitle:NSLocalizedString(@"Previous", @"tour") target:self action:@selector(previous)];
    previous.enabled = step > 0;
    previous.accessibilityIdentifier = @"tourPrevious";
    NSButton *end = [NSButton buttonWithTitle:NSLocalizedString(@"End", @"tour") target:self action:@selector(end)];
    end.keyEquivalent = @"\e";
    end.accessibilityIdentifier = @"tourEnd";
    NSButton *next = [NSButton buttonWithTitle:last ? NSLocalizedString(@"Done", @"tour") : NSLocalizedString(@"Next", @"tour")
                                        target:self action:@selector(next)];
    next.keyEquivalent = @"\r";
    next.accessibilityIdentifier = @"tourNext";
    NSStackView *buttons = [NSStackView stackViewWithViews:@[ previous, end, next ]];
    buttons.spacing = 8;

    NSStackView *stack = [NSStackView stackViewWithViews:@[ title, text, buttons ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [text.widthAnchor constraintEqualToConstant:320].active = YES;
    [buttons.trailingAnchor constraintEqualToAnchor:text.trailingAnchor].active = YES;

    // the margins as constraints of a container (the popover sizes itself to the view's frame, not to the
    // edge insets of a stack view)
    const CGFloat h = 26, top = 22, bottom = 20;
    NSView *container = [[NSView alloc] init];
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:h],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-h],
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:top],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-bottom],
    ]];
    NSSize size = container.fittingSize;
    container.frame = NSMakeRect(0, 0, size.width, size.height);

    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = container;
    vc.preferredContentSize = size;
    return vc;
}

- (void)showStep:(NSUInteger)step
{
    NSRect rect = NSZeroRect;
    NSView *anchor = [self anchorViewForStep:step rect:&rect];
    if (!anchor) {
        [self end];
        return;
    }
    BOOL first = _popover == nil;
    [_popover close];
    _currentStep = step;
    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorApplicationDefined; // stays until End / Done
    popover.animates = first;
    popover.contentViewController = [self contentForStep:step];
    _popover = popover;
    [popover showRelativeToRect:rect ofView:anchor preferredEdge:NSRectEdgeMaxY];
}

- (void)start
{
    [self showStep:0];
}

- (void)next
{
    if (!_popover) return;
    if (_currentStep + 1 >= _steps.count) [self end];
    else [self showStep:_currentStep + 1];
}

- (void)previous
{
    if (_popover && _currentStep > 0) [self showStep:_currentStep - 1];
}

- (void)end
{
    [_popover close];
    _popover = nil;
}

@end
