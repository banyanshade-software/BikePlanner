//
//  PlannerWindowController.m
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import "PlannerWindowController.h"
#import "Document.h"
#import "MapController.h"
#import "BRFProfileEditor.h"
#import "BikePlan.h"
#import "BPRoadTypesView.h"
#import "BPGuidedTour.h"
#import "BPSightsView.h"
#import "BPSights.h"
#import "POILocation.h"
#import "BPEnvironment.h"

@interface PlannerWindowController ()

@end

// document view of the Info scroll view: content from the top
@interface BPInfoDocumentView : NSView
@end
@implementation BPInfoDocumentView
- (BOOL)isFlipped { return YES; }
@end

@implementation PlannerWindowController

- (nullable NSTabView *) tabViewIn:(NSView *)root
{
    if ([root isKindOfClass:[NSTabView class]]) return (NSTabView *)root;
    for (NSView *v in root.subviews) {
        NSTabView *t = [self tabViewIn:v];
        if (t) return t;
    }
    return nil;
}

// Info section (#53): its content (box of Document.xib) goes into a scroll view, with the distance by road type
// below (bound to plan.brouterInfo.roadTypesRows; the road type or surface selected with its radio button is
// highlighted on the map, #54, #66). Built here so that Document.xib is unchanged.
- (void) setupInfoSection
{
    Document *d = (Document *)self.document;
    NSTabView *tabs = [self tabViewIn:self.window.contentView]; // (a hidden tab's view is not in the hierarchy)
    NSSplitView *split = (NSSplitView *)tabs.superview.superview;   // Info | Street View / Params tabs (#43)
    if (![split isKindOfClass:[NSSplitView class]] || split.subviews.count < 2) return;
    NSView *infoPane = split.subviews[0];
    NSArray<NSView *> *content = [infoPane.subviews copy];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:infoPane.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    NSView *doc = [[BPInfoDocumentView alloc] init];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *c in content) {
        NSSize size = c.frame.size;
        [c removeFromSuperview];
        c.translatesAutoresizingMaskIntoConstraints = NO;
        [c.widthAnchor constraintEqualToConstant:size.width].active = YES;
        [c.heightAnchor constraintEqualToConstant:size.height].active = YES;
        [stack addArrangedSubview:c];
    }
    BPRoadTypesView *roads = [[BPRoadTypesView alloc] init];
    roads.accessibilityIdentifier = @"routeRoadTypes";
    [roads bind:@"rows" toObject:d withKeyPath:@"plan.brouterInfo.roadTypesRows" options:nil];
    // the selected road type or surface is highlighted on the map (#54, #66)
    __weak Document *weakDoc = d;
    roads.selectionHandler = ^(NSString *kind) {
        [weakDoc.mapController highlightKind:kind];
    };
    [stack addArrangedSubview:roads];
    // sights near the route (#81)
    BPSightsView *sights = [[BPSightsView alloc] init];
    sights.accessibilityIdentifier = @"sightsSection";
    self.sightsView = sights;
    __weak MapController *mc = d.mapController;
    sights.categoriesHandler = ^(NSArray<NSString *> *categories) { [mc setSightCategories:categories]; };
    sights.includeDistanceHandler = ^(NSInteger meters) { [mc setSightIncludeDistance:meters]; };
    sights.inclusionHandler = ^(NSString *key, BOOL included) { [mc setPOIKey:key excluded:!included]; };
    sights.selectionHandler = ^(NSString *key) { [mc showPOIWithKey:key]; };
    __weak PlannerWindowController *weakSelf = self;
    d.mapController.poisChangedHandler = ^{ [weakSelf updateSightsView]; };
    [stack addArrangedSubview:sights];
    [stack setCustomSpacing:16 afterView:roads];
    [stack setCustomSpacing:2 afterView:stack.arrangedSubviews.firstObject];
    [doc addSubview:stack];
    scroll.documentView = doc;
    [infoPane addSubview:scroll];
    scroll.accessibilityIdentifier = @"infoSection"; // guided tour (#63)
    tabs.accessibilityIdentifier = @"sideTabs";
    [self setTooltipsIn:doc];
    NSClipView *clip = scroll.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [doc.leadingAnchor constraintEqualToAnchor:clip.leadingAnchor],
        [doc.trailingAnchor constraintEqualToAnchor:clip.trailingAnchor],
        [doc.topAnchor constraintEqualToAnchor:clip.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:doc.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:doc.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-8],
        [roads.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:12],
        [roads.widthAnchor constraintEqualToConstant:240],
        [sights.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:12],
        [sights.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-12], // the table takes the width
    ]];
    [self updateSightsView];
}

// tooltips of the controls of Document.xib (#63), set here so that the XIB is unchanged
- (void) setTooltipsIn:(NSView *)root
{
    NSDictionary<NSString *, NSString *> *byBinding = @{
        @"plan.fetchPOI": NSLocalizedString(@"Look for drinking water, toilets and bicycle repair stations along the route (OpenStreetMap)", @"tooltip"),
        @"mapController.viewPOI": NSLocalizedString(@"Show the points of interest on the map", @"tooltip"),
    };
    NSDictionary<NSString *, NSString *> *byIdentifier = @{
        @"routeLength": NSLocalizedString(@"Length of the route", @"tooltip"),
        @"routeAscent": NSLocalizedString(@"Cumulative elevation gain (filtered by BRouter)", @"tooltip"),
        @"routeTime": NSLocalizedString(@"Riding time estimated by BRouter", @"tooltip"),
        @"routeSpeed": NSLocalizedString(@"Average speed: length / riding time", @"tooltip"),
    };
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:root];
    while (views.count) {
        NSView *v = views.lastObject;
        [views removeLastObject];
        NSString *keyPath = [v infoForBinding:NSValueBinding][NSObservedKeyPathKey];
        // the identifiers of the Info fields are on their cells
        NSString *ident = v.accessibilityIdentifier.length ? v.accessibilityIdentifier
                        : [v isKindOfClass:[NSControl class]] ? ((NSControl *)v).cell.accessibilityIdentifier : nil;
        NSString *tip = (keyPath ? byBinding[keyPath] : nil) ?: (ident ? byIdentifier[ident] : nil);
        if (tip && !v.toolTip.length) v.toolTip = tip;
        [views addObjectsFromArray:v.subviews];
    }
}

- (void) setToolbarTooltips
{
    for (NSToolbarItem *item in self.window.toolbar.items) {
        if (item.toolTip.length) continue;
        if (item.action == @selector(importGPXTraceForDisplay:)) {
            item.toolTip = NSLocalizedString(@"Show a GPX, TCX or FIT track on the map, to compare with the route", @"tooltip");
        } else if (item.action == @selector(exportGPX:)) {
            item.toolTip = NSLocalizedString(@"Export the route to GPX for a GPS (whole route or one file per stage)", @"tooltip");
        } else if ([item isKindOfClass:[NSSearchToolbarItem class]]) {
            item.toolTip = NSLocalizedString(@"Find a place by name", @"tooltip");
        }
    }
}

- (void)startGuidedTour
{
    if (!self.guidedTour) {
        self.guidedTour = [[BPGuidedTour alloc] initWithWindow:self.window];
        __weak MapController *mc = ((Document *)self.document).mapController;
        self.guidedTour.routeAnchorProvider = ^NSView *(NSString *key, NSRect *rect) {
            return [mc tourAnchorForKey:key rect:rect];
        };
    }
    [self.guidedTour end];
    [self.guidedTour start];
}

+ (void)showGuidedTourOnSampleWithCompletion:(nullable void (^)(PlannerWindowController * _Nullable controller))completion
{
    [BPGuidedTour openSampleWithCompletion:^(NSDocument *document, NSError *error) {
        PlannerWindowController *wc = (PlannerWindowController *)document.windowControllers.firstObject;
        if (![wc isKindOfClass:[PlannerWindowController class]]) {
            NSLog(@"guided tour: cannot open the sample route: %@", error);
            if (completion) completion(nil);
            return;
        }
        // after the map has zoomed to the route
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [wc startGuidedTour];
            if (completion) completion(wc);
        });
    }];
}

// offered by itself once, after the first document window opens (never in the unit test host)
- (void) offerGuidedTourIfNeeded
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([BPEnvironment isUnitTestHost] || ![BPGuidedTour shouldOfferAutomaticallyWithDefaults:ud]) return;
    [BPGuidedTour markOfferedInDefaults:ud];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [PlannerWindowController showGuidedTourOnSampleWithCompletion:nil];
    });
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    Document *d = (Document *)self.document;
    NSAssert(d, @"nil document");
    NSAssert([d isKindOfClass:[Document class]], @"bad class document");
    NSAssert(d.mapController, @"document no mapctrl");
    NSAssert(d.mapController.svCtrl, @"document no svctrl");
    NSAssert(d.mapController.document, @"document not linked to mapController");
    NSAssert(d==d.mapController.document, @"wrong document  linked to mapController");
    [d.mapController initializeMapview];
    // a new document starts in Edit mode (to place the start), an opened one in View mode: a click does not change
    // its route by mistake
    if (d.fileURL) [d.mapController setClickModeToView:self];
    [d.mapController.svCtrl initializeStreetView];
    
    [d.mapController fullRefresh:YES];
    [self setupBrfEditor];
    [self setupInfoSection];
    [self setToolbarTooltips];
    d.mapController.elevationView.accessibilityIdentifier = @"elevationProfile";
    [self.window makeKeyAndOrderFront:nil];
    [self offerGuidedTourIfNeeded];
}


- (void) setupBrfEditor
{
    Document *d = (Document *)self.document;
    self.brfEditor = [[BRFProfileEditor alloc] initWithNibName:@"BRFProfileEditor" bundle:nil]; //initWithProfileName:@"trekking"];
    [_brfEditor loadProfileName:d.plan.profileName];
    _brfEditor.appliedOverrides = d.plan.profileOverrides; // saved in the document (#44)
    
    // overrides are sent as profile:<name>=<value> parameters by BRouterClient (#15, #35); none = profile defaults
    __weak PlannerWindowController *weakSelf = self;
    _brfEditor.completionHandler = ^(NSDictionary<NSString *, NSString *> *overrideParams) {
        NSLog(@"User overrides: %@", overrideParams);
        [weakSelf setProfileOverrides:overrideParams];
    };
    
    _brfEditor.view.frame = d.brfParamsPlaceholder.bounds;
    _brfEditor.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Add as child view controller
    //[self addChildViewController:vc];

    // Add its view into the container
    [d.brfParamsPlaceholder addSubview:_brfEditor.view];

    //[_brfEditor showWindow:self];

}
// undoable, recomputes the route (#44)
- (void)setProfileOverrides:(NSDictionary<NSString *, NSString *> *)overrides
{
    Document *d = (Document *)self.document;
    NSDictionary *old = d.plan.profileOverrides;
    if ([old isEqualToDictionary:overrides ?: @{}]) return;
    [d.undoManager registerUndoWithTarget:self handler:^(PlannerWindowController *target) {
        [target setProfileOverrides:old];
    }];
    [d.undoManager setActionName:NSLocalizedString(@"change routing parameters", @"undo action")];
    d.plan.profileOverrides = overrides;
    _brfEditor.appliedOverrides = d.plan.profileOverrides;
    [d.mapController shouldRecalcRoute];
}

- (void)planReplaced
{
    _brfEditor.appliedOverrides = ((Document *)self.document).plan.profileOverrides;
    [self updateSightsView];
}

// the settings and the list of the sights from the plan (#81)
- (void)updateSightsView
{
    BikePlan *plan = ((Document *)self.document).plan;
    BPSightsView *view = self.sightsView;
    if (!view || !plan) return;
    view.categories = plan.sightCategories;
    view.includeDistance = plan.sightIncludeDistance;
    NSMutableArray *rows = [NSMutableArray array];
    for (POILocation *p in [plan sightsAlongRoute]) {
        double along = 0, off = 0;
        [plan routePositionOfPOI:p along:&along off:&off];
        [rows addObject:@{ BPSightRowKey: p.poiKey, BPSightRowAlong: @(along), BPSightRowOff: @(off),
                           BPSightRowName: p.title ?: @"", BPSightRowType: [POILocation displayNameForType:p.poiType],
                           BPSightRowIncluded: @(![plan isPOIExcluded:p]) }];
    }
    view.rows = rows;
}

@end
