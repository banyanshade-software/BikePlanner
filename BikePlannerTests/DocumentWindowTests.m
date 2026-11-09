//
//  DocumentWindowTests.m
//  BikePlannerTests
//
//  Integration tests: a real document window (Document.xib) with MapController, driven
//  programmatically, against the local stub server (BRouter + Overpass), without tiles nor Street View.
//  Map clicks go through the real -handleMapClick: with a fake gesture recognizer.
//

#import <XCTest/XCTest.h>
#import <MapKit/MapKit.h>
#import "Document.h"
#import "MapController.h"
#import "BikePlan.h"
#import "RouteAnnotation.h"
#import "POIAnnotation.h"
#import "POIAnnotationView.h"
#import "POICalloutView.h"
#import "TaggedPoly.h"
#import "ElevationProfileView.h"
#import "BPStubServer.h"
#import "BRFProfileEditor.h"
#import "SafeOSMTileOverlay.h"
#import "BPRoadTypesLabel.h"
#import "SafeTileRenderer.h"
#import "StreetViewController.h"
#import "GPXParser.h"
#import "BPPlaceSearch.h"
#import "TestFixtures.h"
#import "BPRemarkableSites.h"
#import "BPEnvironment.h"

@interface MapController (WindowTesting)
- (void)setSearchCompletionTitles:(NSArray<NSString *> *)titles;
- (NSArray<NSString *> *)completionsForText:(NSString *)text partialWordRange:(NSRange)range;
- (void)handleMapClick:(NSGestureRecognizer *)gesture;
- (void)addCustomPoiAt:(CLLocationCoordinate2D)coord;
- (void)userLocationAvailable:(nullable CLLocation *)loc;
- (void)changeMapType:(id)sender;
- (void)changeClickMode:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (void)removeWaypointMenuAction:(id)sender;
- (CGFloat)projectPoint:(CGPoint)p ontoSegmentFrom:(CGPoint)a to:(CGPoint)b projection:(CGPoint *)projection;
- (NSMenu *)waypointMenuForAnnotation:(RouteAnnotation *)annotation;
- (BOOL)exportStagesToDirectory:(NSURL *)dir baseName:(NSString *)baseName withPOI:(BOOL)inclPOI error:(NSError **)error;
- (void)mouseMoved:(NSEvent *)event;
- (NSData *)exportGpxDataWithPOI:(BOOL)inclPOI trackName:(NSString *)trackName;
- (void)loadGPXFromURL:(NSURL *)url;
- (void)loadGPXAsRouteFromURL:(NSURL *)url;
- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer shouldAttemptToRecognizeWithEvent:(NSEvent *)event;
- (CLLocationDistance)distanceAtCoordinate:(CLLocationCoordinate2D)coord segstart:(NSUInteger *)psegstart;
@end

@interface PlannerWindowController : NSWindowController
@property (strong, nonatomic) id brfEditor;
@end

@interface Document (WindowTesting)
- (IBAction)setClickModeToEdit:(id)sender;
- (IBAction)setClickModeToInterm:(id)sender;
- (IBAction)setClickModeToView:(id)sender;
- (IBAction)setClickModeToAddPoi:(id)sender;
- (IBAction)reverseRoute:(id)sender;
- (IBAction)recalculateRoute:(id)sender;
- (IBAction)removeGPXTraceForDisplay:(id)sender;
- (IBAction)clearRoute:(id)sender;
@end

// Returns a fixed location, in map view coordinates
@interface BPFakeClick : NSClickGestureRecognizer
@property (nonatomic) NSPoint point;
@end
@implementation BPFakeClick
- (NSPoint)locationInView:(NSView *)view { return self.point; }
@end


@interface DocumentWindowTests : XCTestCase
@end

// counts the actions sent by a control (stands for MapController, so that no Apple search is run)
@interface BPActionCounter : NSObject
@property NSInteger count;
- (void)act:(id)sender;
@end
@implementation BPActionCounter
- (void)act:(id)sender { self.count++; }
@end

@implementation DocumentWindowTests {
    BPStubServer *server;
    Document *doc;
    MapController *mc;
    MKMapView *map;
}

- (void)setUp
{
    server = [[BPStubServer alloc] init];
    XCTAssertTrue([server startInProcess]);
    BPOverrideDefaults(@{ @"BPBRouterServer": server.baseURL.absoluteString,
                          @"BPOverpassURL": server.overpassURL.absoluteString,
                          @"BPDisableStreetView": @YES,
                          @"BPDisableTiles": @YES,
                          @"BPInitialRegion": @"44.05,0.55,0.2",
                          @"BPProfileOverrides": @{} }); // not the owner's default BRouter parameters
    doc = [[Document alloc] init];
    [self openWindow];
}

- (void)openWindow
{
    [doc makeWindowControllers];
    NSWindow *w = doc.windowControllers.firstObject.window; // loads Document.xib, windowDidLoad
    XCTAssertNotNil(w);
    mc = doc.mapController;
    map = mc.mapView;
    [map setRegion:MKCoordinateRegionMake(CLLocationCoordinate2DMake(44.05, 0.55), MKCoordinateSpanMake(0.2, 0.2)) animated:NO];
    BPSpin(0.2);
}

- (void)tearDown
{
    doc.plan.fetchPOI = NO;
    [doc.undoManager removeAllActions];
    [doc close];
    BPSpin(0.2);
    [server stop];
    BPRestoreDefaults();
}

#pragma mark - helpers

- (NSView *)viewWithIdentifier:(NSString *)ident in:(NSView *)root
{
    if ([root.accessibilityIdentifier isEqualToString:ident]) return root;
    for (NSView *v in root.subviews) {
        NSView *f = [self viewWithIdentifier:ident in:v];
        if (f) return f;
    }
    return nil;
}

- (NSView *)content { return doc.windowControllers.firstObject.window.contentView; }

- (NSTabView *)tabViewIn:(NSView *)root
{
    if ([root isKindOfClass:[NSTabView class]]) return (NSTabView *)root;
    for (NSView *v in root.subviews) {
        NSTabView *t = [self tabViewIn:v];
        if (t) return t;
    }
    return nil;
}

// a control of the Info/Params tabs, by the accessibility identifier set in the XIB (on the control's cell)
- (NSView *)controlWithIdentifier:(NSString *)ident in:(NSView *)root
{
    if ([root isKindOfClass:[NSControl class]] && [[((NSControl *)root).cell accessibilityIdentifier] isEqualToString:ident]) return root;
    for (NSView *v in root.subviews) {
        NSView *f = [self controlWithIdentifier:ident in:v];
        if (f) return f;
    }
    return nil;
}

// a control of the side panel (Info section, Street View / Params tabs) by its XIB accessibility identifier
- (NSView *)panelControlWithIdentifier:(NSString *)ident
{
    NSView *f = [self controlWithIdentifier:ident in:self.content];
    if (f) return f;
    for (NSTabViewItem *item in [self tabViewIn:self.content].tabViewItems) { // views of the hidden tabs
        f = [self controlWithIdentifier:ident in:item.view];
        if (f) return f;
    }
    return nil;
}

- (void)clickAt:(NSPoint)p
{
    BPFakeClick *g = [[BPFakeClick alloc] initWithTarget:nil action:nil];
    g.point = p;
    [mc handleMapClick:g];
}

- (void)clickAtCoordinate:(CLLocationCoordinate2D)c
{
    [self clickAt:[map convertCoordinate:c toPointToView:map]];
}

- (NSArray *)annotationsOfClass:(Class)cls
{
    return [map.annotations filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id a, NSDictionary *b) { return [a isKindOfClass:cls]; }]];
}

- (NSArray<TaggedPoly *> *)polysWithTag:(NSUInteger)tag
{
    return (NSArray<TaggedPoly *> *)[map.overlays filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
        return [o isKindOfClass:[TaggedPoly class]] && ((TaggedPoly *)o).tag == tag;
    }]];
}

- (BOOL)waitForRouteWithPoints:(NSUInteger)n
{
    return BPWaitUntil(5, ^{ return (BOOL)(self->doc.plan.routePoints.count == n); });
}

// two waypoints at known coordinates, route computed by the stub (11 points)
- (void)makeRoute
{
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.5)];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.1, 0.6)];
    XCTAssertTrue([self waitForRouteWithPoints:11]);
    BPSpin(0.1);
}

#pragma mark - window setup

- (void)testWindowSetup
{
    XCTAssertNotNil(mc.svCtrl);
    XCTAssertEqual(mc.elevationView.delegate, (id)mc);
    XCTAssertEqual(map.delegate, (id)mc);
    XCTAssertFalse(map.showsZoomControls);
    XCTAssertEqualObjects(map.accessibilityIdentifier, @"map");
    // no tile overlay when tiles are disabled
    for (id o in map.overlays) XCTAssertFalse([o isKindOfClass:[MKTileOverlay class]]);
    // controls created in code
    XCTAssertNotNil([self viewWithIdentifier:@"zoomIn" in:self.content]);
    XCTAssertNotNil([self viewWithIdentifier:@"zoomOut" in:self.content]);
    XCTAssertNotNil([self viewWithIdentifier:@"userLocation" in:self.content]);
    XCTAssertNotNil([self viewWithIdentifier:@"mapType" in:self.content]);
    NSTextField *help = (NSTextField *)[self viewWithIdentifier:@"clickModeHelp" in:self.content];
    XCTAssertEqualObjects(help.stringValue, @"Click on map to add start and end waypoints");
    // BRF editor installed in the Params tab, profile fetched from the stub
    XCTAssertEqual(doc.brfParamsPlaceholder.subviews.count, 1u);
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self->server requestsWithPath:@"/brouter/profiles2/trekking.brf"].count == 1); }));
}

- (void)testClickModes
{
    NSTextField *help = (NSTextField *)[self viewWithIdentifier:@"clickModeHelp" in:self.content];
    NSSegmentedControl *seg = (NSSegmentedControl *)[self viewWithIdentifier:@"clickMode" in:self.content];

    [mc setClickModeToInterm:self];
    XCTAssertEqual(seg.selectedSegment, 1);
    XCTAssertEqualObjects(help.stringValue, @"Click on path to add intermediate waypoints");
    [mc setClickModeToAddPoi:self];
    XCTAssertEqual(seg.selectedSegment, 2);
    XCTAssertEqualObjects(help.stringValue, @"Add POI");
    [mc setClickModeToView:self];
    XCTAssertEqual(seg.selectedSegment, 3);
    XCTAssertEqualObjects(help.stringValue, @"Drag waypoints");
    [mc setClickModeToEdit:self];
    XCTAssertEqual(seg.selectedSegment, 0);

    // through the segmented control itself
    seg.selectedSegment = 3;
    [mc changeClickMode:seg];
    XCTAssertEqualObjects(help.stringValue, @"Drag waypoints");

    // menu relays in Document
    [doc setClickModeToInterm:nil];
    XCTAssertEqual(seg.selectedSegment, 1);
}

// Edit ▸ Mode items: ⌘1…⌘4 in the main menu, current mode checked, also when changed with the segmented control (#22)
- (void)testClickModeMenuShortcuts
{
    NSArray *actions = @[@"setClickModeToEdit:", @"setClickModeToInterm:", @"setClickModeToAddPoi:", @"setClickModeToView:"];
    NSMenu *edit = [NSApp.mainMenu itemWithTitle:@"Edit"].submenu;
    XCTAssertNotNil(edit);
    NSSegmentedControl *seg = (NSSegmentedControl *)[self viewWithIdentifier:@"clickMode" in:self.content];
    for (NSUInteger m = 0; m < actions.count; m++) {
        NSInteger i = [edit indexOfItemWithTarget:nil andAction:NSSelectorFromString(actions[m])];
        XCTAssertNotEqual(i, -1, @"%@", actions[m]);
        if (i < 0) continue;
        NSMenuItem *item = [edit itemAtIndex:i];
        // macOS localizes key equivalents to the keyboard layout (⌘1 is reported as ⌘& on AZERTY): compare the raw one
        BOOL loc = item.allowsAutomaticKeyEquivalentLocalization;
        item.allowsAutomaticKeyEquivalentLocalization = NO;
        XCTAssertEqualObjects(item.keyEquivalent, ([NSString stringWithFormat:@"%lu", m + 1]), @"%@", actions[m]);
        item.allowsAutomaticKeyEquivalentLocalization = loc;
        XCTAssertEqual(item.keyEquivalentModifierMask & NSEventModifierFlagDeviceIndependentFlagsMask,
                       NSEventModifierFlagCommand, @"%@", actions[m]);
    }
    for (NSUInteger m = 0; m < actions.count; m++) {
        seg.selectedSegment = m;
        [mc changeClickMode:seg];
        for (NSUInteger k = 0; k < actions.count; k++) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:NSSelectorFromString(actions[k]) keyEquivalent:@""];
            XCTAssertTrue([doc validateMenuItem:item]);
            XCTAssertEqual(item.state, (k == m) ? NSControlStateValueOn : NSControlStateValueOff, @"mode %lu, %@", m, actions[k]);
        }
    }
}

- (void)testMapTypes
{
    NSSegmentedControl *seg = (NSSegmentedControl *)[self viewWithIdentifier:@"mapType" in:self.content];
    seg.selectedSegment = 2; [mc changeMapType:seg];
    XCTAssertEqual(map.mapType, MKMapTypeStandard);
    seg.selectedSegment = 3; [mc changeMapType:seg];
    XCTAssertEqual(map.mapType, MKMapTypeHybrid);
    seg.selectedSegment = 4; [mc changeMapType:seg];
    XCTAssertEqual(map.mapType, MKMapTypeSatellite);
    seg.selectedSegment = 1; [mc changeMapType:seg];
    seg.selectedSegment = 0; [mc changeMapType:seg];
    for (id o in map.overlays) XCTAssertFalse([o isKindOfClass:[MKTileOverlay class]]);
}

- (void)testZoomButtons
{
    double span = map.region.span.latitudeDelta;
    [mc zoomIn:nil];
    BPSpin(1.0);
    XCTAssertLessThan(map.region.span.latitudeDelta, span * 0.75);
    span = map.region.span.latitudeDelta;
    [mc zoomOut:nil];
    BPSpin(1.0);
    XCTAssertGreaterThan(map.region.span.latitudeDelta, span * 1.5);
}

#pragma mark - route building

- (void)testClickAddsWaypointsAndComputesRoute
{
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.5)];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 1u);
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 1u);
    XCTAssertEqual([server requestsWithPath:@"/brouter"].count, 0u, @"no route with a single waypoint");

    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.1, 0.6)];
    XCTAssertTrue([self waitForRouteWithPoints:11]);
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u);
    XCTAssertEqualWithAccuracy(doc.plan.waypointsLocations[1].coordinate.latitude, 44.1, 0.001);
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 2u);
    XCTAssertNotNil(mc.gpxData);
    XCTAssertGreaterThan(doc.plan.brouterInfo.kmlen, 10);
    XCTAssertGreaterThan(doc.plan.brouterInfo.mup, 0);
    // riding time from BRouter (stub: time=10m 0s), shown in the Info section with the average speed (#30)
    XCTAssertEqual(doc.plan.brouterInfo.seconds, 600);
    XCTAssertGreaterThan(doc.plan.brouterInfo.meters, 10000);
    NSTextField *time = (NSTextField *)[self panelControlWithIdentifier:@"routeTime"];
    NSTextField *speed = (NSTextField *)[self panelControlWithIdentifier:@"routeSpeed"];
    XCTAssertNotNil(time);
    XCTAssertNotNil(speed);
    XCTAssertEqualObjects(time.stringValue, @"10 min");
    XCTAssertEqualObjects(speed.stringValue, doc.plan.brouterInfo.averageSpeedText);
    XCTAssertGreaterThan(doc.plan.brouterInfo.averageSpeed, 60, @"stub: > 10 km in 10 min");
    XCTAssertEqual(mc.elevationView.distances.count, 11u);
    XCTAssertEqual([self polysWithTag:0].firstObject.pointCount, 11u);
    XCTAssertTrue(doc.isDocumentEdited || doc.undoManager.canUndo);

    RouteAnnotation *start = [self annotationsOfClass:[RouteAnnotation class]].firstObject;
    XCTAssertTrue(([@[@"Start", @"1"] containsObject:start.title]));
}

- (void)testThirdClickAppendsDestination
{
    [self makeRoute];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.65)];
    XCTAssertTrue([self waitForRouteWithPoints:21]);
    XCTAssertEqual(doc.plan.waypointsLocations.count, 3u);
}

- (void)testClickOnRouteInsertsIntermediateWaypoint
{
    [self makeRoute];
    [mc setClickModeToInterm:self];
    [self clickAtCoordinate:doc.plan.routePoints[5].coordinate];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 3u);
    XCTAssertEqualWithAccuracy(doc.plan.waypointsLocations[1].coordinate.latitude, 44.05, 0.002);
    XCTAssertTrue([self waitForRouteWithPoints:21]);
    NSArray *titles = [[self annotationsOfClass:[RouteAnnotation class]] valueForKey:@"title"];
    XCTAssertEqual(titles.count, 3u);
}

- (void)testClickAwayFromRouteInIntermModeDoesNothing
{
    [self makeRoute];
    [mc setClickModeToInterm:self];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.6)];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u);
}

- (void)testViewModeClickOnRoute
{
    [self makeRoute];
    [mc setClickModeToView:self];
    CLLocationCoordinate2D c = doc.plan.routePoints[3].coordinate;
    [self clickAtCoordinate:c];
    BPSpin(0.2);
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u);
    XCTAssertGreaterThan(mc.elevationView.highlightDistance, 0);
    XCTAssertTrue([mc.elevationView.highlightText containsString:@"%"], @"slope shown at the selected point (#48): %@", mc.elevationView.highlightText);
    XCTAssertEqualWithAccuracy(map.centerCoordinate.latitude, c.latitude, 0.005);
}

// a sheet of the window (alert) with its accessory controls
- (NSWindow *)waitForSheet
{
    NSWindow *window = doc.windowControllers.firstObject.window;
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet != nil); }), @"sheet");
    return window.attachedSheet;
}

- (void)endSheet:(NSModalResponse)response
{
    NSWindow *window = doc.windowControllers.firstObject.window;
    [window endSheet:window.attachedSheet returnCode:response];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet == nil); }));
}

// Add POI mode: a click on the route asks the type and an optional name (#3); Cancel adds nothing
- (void)testAddPOIModeAddsCustomPOI
{
    [self makeRoute];
    doc.plan.fetchPOI = NO;
    [mc setClickModeToAddPoi:self];
    [self clickAtCoordinate:doc.plan.routePoints[4].coordinate];
    NSWindow *sheet = [self waitForSheet];
    NSPopUpButton *type = (NSPopUpButton *)[self viewWithIdentifier:@"poiType" in:sheet.contentView];
    NSTextField *name = (NSTextField *)[self viewWithIdentifier:@"poiName" in:sheet.contentView];
    XCTAssertNotNil(type);
    XCTAssertNotNil(name);
    XCTAssertEqual(type.selectedTag, POI_warning, @"default type");
    [self endSheet:NSAlertSecondButtonReturn]; // Cancel
    XCTAssertEqual(doc.plan.customPoiloc.count, 0u);

    [self clickAtCoordinate:doc.plan.routePoints[4].coordinate];
    sheet = [self waitForSheet];
    type = (NSPopUpButton *)[self viewWithIdentifier:@"poiType" in:sheet.contentView];
    name = (NSTextField *)[self viewWithIdentifier:@"poiName" in:sheet.contentView];
    [type selectItemWithTag:POI_drinking_water];
    name.stringValue = @"Fontaine";
    [self endSheet:NSAlertFirstButtonReturn];
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);
    XCTAssertEqual(doc.plan.customPoiloc[0].poiType, POI_drinking_water);
    XCTAssertEqualObjects(doc.plan.customPoiloc[0].title, @"Fontaine");
    XCTAssertGreaterThanOrEqual([self annotationsOfClass:[POIAnnotation class]].count, 1u);
    // away from the route: nothing
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.6)];
    BPSpin(0.3);
    XCTAssertNil(doc.windowControllers.firstObject.window.attachedSheet);
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);
}

// right-click menu of a custom POI: Edit POI… and Remove POI, undoable (#3)
- (void)testEditAndRemoveCustomPOI
{
    doc.plan.fetchPOI = NO;
    // nested run loops in tests do not close automatic undo groups: group explicitly (see UndoTests)
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [mc addCustomPoiAt:CLLocationCoordinate2DMake(44.05, 0.55)];
    [um endUndoGrouping];
    POIAnnotation *ann = [self annotationsOfClass:[POIAnnotation class]].firstObject;
    MKAnnotationView *view = [mc mapView:map viewForAnnotation:ann];
    NSArray *titles = [view.menu.itemArray valueForKey:@"title"];
    XCTAssertEqualObjects(titles, (@[@"Edit POI…", @"Remove POI"]));

    NSMenuItem *edit = view.menu.itemArray[0];
    [NSApp sendAction:edit.action to:edit.target from:edit];
    NSWindow *sheet = [self waitForSheet];
    NSPopUpButton *type = (NSPopUpButton *)[self viewWithIdentifier:@"poiType" in:sheet.contentView];
    XCTAssertEqual(type.selectedTag, POI_warning, @"current type");
    [type selectItemWithTag:POI_shelter];
    ((NSTextField *)[self viewWithIdentifier:@"poiName" in:sheet.contentView]).stringValue = @"Abri";
    [um beginUndoGrouping];
    [self endSheet:NSAlertFirstButtonReturn];
    [um endUndoGrouping];
    XCTAssertEqual(doc.plan.customPoiloc[0].poiType, POI_shelter);
    XCTAssertEqualObjects(doc.plan.customPoiloc[0].title, @"Abri");
    XCTAssertEqualObjects(um.undoActionName, @"edit POI");
    [um undo];
    XCTAssertEqual(doc.plan.customPoiloc[0].poiType, POI_warning);

    ann = [self annotationsOfClass:[POIAnnotation class]].firstObject;
    view = [mc mapView:map viewForAnnotation:ann];
    NSMenuItem *remove = view.menu.itemArray[1];
    [um beginUndoGrouping];
    [NSApp sendAction:remove.action to:remove.target from:remove];
    [um endUndoGrouping];
    XCTAssertEqual(doc.plan.customPoiloc.count, 0u);
    XCTAssertEqual([self annotationsOfClass:[POIAnnotation class]].count, 0u);
    XCTAssertEqualObjects(um.undoActionName, @"remove POI");
    [um undo];
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);
}

// fetched (OSM) POIs have no edit menu
- (void)testFetchedPOIHasNoEditMenu
{
    [self makeRoute];
    XCTAssertTrue(BPWaitUntil(6, ^{ return (BOOL)(self->doc.plan.poiloc.count == 3); }));
    BPSpin(0.1);
    POIAnnotation *ann = [self annotationsOfClass:[POIAnnotation class]].firstObject;
    XCTAssertNil([mc mapView:map viewForAnnotation:ann].menu);
}

#pragma mark - POIs

- (void)waitForPOIs
{
    XCTAssertTrue(BPWaitUntil(6, ^{ return (BOOL)(self->doc.plan.poiloc.count == 3); }));
    BPSpin(0.1);
}

// Include / Exclude in the POI callout (#5): an excluded POI stays on the map, greyed, is not exported; undoable
- (void)testExcludePOIFromCallout
{
    [self makeRoute];
    [self waitForPOIs];
    POIAnnotation *ann = [self annotationsOfClass:[POIAnnotation class]].firstObject;
    POIAnnotationView *view = (POIAnnotationView *)[mc mapView:map viewForAnnotation:ann];
    POICalloutView *callout = (POICalloutView *)view.detailCalloutAccessoryView;
    XCTAssertEqual(callout.excludeControl.selectedSegment, 0, @"included");
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    callout.excludeControl.selectedSegment = 1;
    [NSApp sendAction:callout.excludeControl.action to:callout.excludeControl.target from:callout.excludeControl];
    [um endUndoGrouping];
    XCTAssertEqual(doc.plan.excludedPOIKeys.count, 1u);
    POIAnnotation *after = nil;
    for (POIAnnotation *a in [self annotationsOfClass:[POIAnnotation class]]) if ([a.poiKey isEqualToString:ann.poiKey]) after = a;
    XCTAssertTrue(after.excluded, @"still on the map, marked excluded");
    POIAnnotationView *v2 = (POIAnnotationView *)[mc mapView:map viewForAnnotation:after];
    XCTAssertEqualObjects(v2.markerTintColor, [NSColor systemGrayColor], @"greyed");
    XCTAssertEqual(((POICalloutView *)v2.detailCalloutAccessoryView).excludeControl.selectedSegment, 1);
    XCTAssertEqualObjects(um.undoActionName, @"exclude POI");
    [um undo];
    XCTAssertEqual(doc.plan.excludedPOIKeys.count, 0u);
}

- (void)testFetchedPOIsAreDisplayed
{
    [self makeRoute];
    [self waitForPOIs];
    XCTAssertEqual([self annotationsOfClass:[POIAnnotation class]].count, 3u);
    mc.viewPOI = NO;
    XCTAssertEqual([self annotationsOfClass:[POIAnnotation class]].count, 0u);
    mc.viewPOI = YES;
    XCTAssertEqual([self annotationsOfClass:[POIAnnotation class]].count, 3u);
}

- (void)testClickNearPOISelectsIt
{
    [self makeRoute];
    [self waitForPOIs];
    POIAnnotation *poi = [self annotationsOfClass:[POIAnnotation class]].firstObject;
    [self clickAtCoordinate:poi.coordinate];
    BPSpin(0.3);
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u, @"a click on a POI does not add a waypoint");
    XCTAssertTrue([map.selectedAnnotations containsObject:poi]);
}

- (void)testMouseOverPOIHighlightsIt
{
    [self makeRoute];
    [self waitForPOIs];
    POIAnnotation *poi = [self annotationsOfClass:[POIAnnotation class]].firstObject;
    POIAnnotationView *v = (POIAnnotationView *)[mc mapView:map viewForAnnotation:poi];
    XCTAssertTrue([v isKindOfClass:[POIAnnotationView class]]);
    NSPoint inMap = [map convertCoordinate:poi.coordinate toPointToView:map];
    NSPoint inWindow = [map convertPoint:inMap toView:nil];
    NSEvent *e = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:inWindow modifierFlags:0 timestamp:0
                                windowNumber:map.window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
    XCTAssertNoThrow([mc mouseMoved:e]);
    NSEvent *away = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:NSMakePoint(1, 1) modifierFlags:0 timestamp:0
                                   windowNumber:map.window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
    XCTAssertNoThrow([mc mouseMoved:away]);
}

#pragma mark - waypoint editing

- (void)testDragWaypoint
{
    [self makeRoute];
    [server clearRequests];
    RouteAnnotation *end = nil;
    for (RouteAnnotation *a in [self annotationsOfClass:[RouteAnnotation class]]) if (a.idx == 1) end = a;
    XCTAssertNotNil(end);
    end.coordinate = CLLocationCoordinate2DMake(44.12, 0.62);
    MKAnnotationView *v = [mc mapView:map viewForAnnotation:end];
    [mc mapView:map annotationView:v didChangeDragState:MKAnnotationViewDragStateEnding fromOldState:MKAnnotationViewDragStateDragging];
    XCTAssertEqualWithAccuracy(doc.plan.waypointsLocations[1].coordinate.latitude, 44.12, 1e-6);
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self->server requestsWithPath:@"/brouter"].count == 1); }));
    XCTAssertTrue([[server requestsWithPath:@"/brouter"].firstObject.query[@"lonlats"] containsString:@"0.620000,44.120000"]);
}

- (void)testRemoveWaypointFromMenu
{
    [self makeRoute];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.65)];
    XCTAssertTrue([self waitForRouteWithPoints:21]);
    RouteAnnotation *middle = nil;
    for (RouteAnnotation *a in [self annotationsOfClass:[RouteAnnotation class]]) if (a.idx == 1) middle = a;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Remove Waypoint" action:nil keyEquivalent:@""];
    item.representedObject = middle;
    [mc removeWaypointMenuAction:item];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u);
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 2u);
    XCTAssertEqualWithAccuracy(doc.plan.waypointsLocations[1].coordinate.longitude, 0.65, 0.001);
}

- (void)testUndoRedoAddWaypoint
{
    // in the app each click is a separate event, hence a separate undo group;
    // nested run loops in tests do not close automatic groups, so group explicitly
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.5)];
    [um endUndoGrouping];
    [um beginUndoGrouping];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.1, 0.6)];
    [um endUndoGrouping];
    XCTAssertTrue([self waitForRouteWithPoints:11]);
    XCTAssertTrue(um.canUndo);
    XCTAssertEqualObjects(um.undoActionName, @"add destination");
    [doc.undoManager undo];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 1u);
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 1u);
    [doc.undoManager redo];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u);
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 2u);
}

// Reverse Route (#25): waypoints reversed, route recomputed by BRouter in the other direction, undoable
- (void)testReverseRoute
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Reverse Route" action:@selector(reverseRoute:) keyEquivalent:@""];
    XCTAssertFalse([doc validateMenuItem:item], @"disabled without a route");
    // nested run loops in tests do not close automatic undo groups: group explicitly (see UndoTests)
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [self makeRoute];
    [um endUndoGrouping];
    XCTAssertTrue([doc validateMenuItem:item]);
    NSArray *wps = doc.plan.waypointsLocations;
    [server clearRequests];
    [doc updateChangeCount:NSChangeCleared];

    [um beginUndoGrouping];
    [doc reverseRoute:item];
    [um endUndoGrouping];
    XCTAssertEqualObjects(doc.plan.waypointsLocations, wps.reverseObjectEnumerator.allObjects);
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self->server requestsWithPath:@"/brouter"].count == 1); }));
    XCTAssertEqualObjects([server requestsWithPath:@"/brouter"].firstObject.query[@"lonlats"],
                          @"0.600000,44.100000|0.500000,44.000000");
    RouteAnnotation *first = nil;
    for (RouteAnnotation *a in [self annotationsOfClass:[RouteAnnotation class]]) if (a.idx == 0) first = a;
    XCTAssertEqualWithAccuracy(first.coordinate.latitude, 44.1, 1e-6, @"start marker is the old end");
    XCTAssertTrue(BPWaitUntil(2, ^{ return self->doc.isDocumentEdited; }), @"document edited (updated asynchronously by NSDocument)");

    XCTAssertEqualObjects(um.undoActionName, @"reverse route");
    [um undo];
    XCTAssertEqualObjects(doc.plan.waypointsLocations, wps);
}

// Edit ▸ Recalculate Route (#55): same waypoints, profile and overrides sent again to BRouter; the new answer
// (here: with road types, missing from a document saved before #54) is one undoable action
- (void)testRecalculateRoute
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Recalculate Route" action:@selector(recalculateRoute:) keyEquivalent:@""];
    XCTAssertFalse([doc validateMenuItem:item], @"disabled without a route");
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.5)];
    [um endUndoGrouping];
    XCTAssertFalse([doc validateMenuItem:item], @"disabled with 1 waypoint");
    [um beginUndoGrouping];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.1, 0.6)];
    [um endUndoGrouping];
    XCTAssertTrue([self waitForRouteWithPoints:11]);
    BPSpin(0.1);
    XCTAssertTrue([doc validateMenuItem:item]);
    doc.plan.profileOverrides = @{ @"avoid_unsafe": @"1" };
    doc.plan.brouterInfo.roadRuns = nil; // as in a document saved before #54
    doc.plan.brouterInfo.roadStats = nil;
    NSArray *wps = doc.plan.waypointsLocations;
    [server clearRequests];
    [doc updateChangeCount:NSChangeCleared];

    [doc recalculateRoute:item];
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->doc.plan.brouterInfo.roadRuns != nil); }), @"new BRouter answer");
    NSArray<BPStubRequest *> *reqs = [server requestsWithPath:@"/brouter"];
    XCTAssertEqual(reqs.count, 1u);
    XCTAssertEqualObjects(reqs.firstObject.query[@"lonlats"], @"0.500000,44.000000|0.600000,44.100000");
    XCTAssertEqualObjects(reqs.firstObject.query[@"profile:avoid_unsafe"], @"1");
    XCTAssertEqualObjects(doc.plan.waypointsLocations, wps, @"waypoints unchanged");
    XCTAssertNotNil(doc.plan.brouterInfo.roadStats);
    XCTAssertTrue(BPWaitUntil(2, ^{ return self->doc.isDocumentEdited; }), @"document edited");

    XCTAssertEqualObjects(um.undoActionName, @"recalculate route");
    [um undo];
    XCTAssertNil(doc.plan.brouterInfo.roadRuns, @"undo gives back the previous route");
    XCTAssertEqual(doc.plan.routePoints.count, 11u);
    XCTAssertEqualObjects(doc.plan.waypointsLocations, wps);
    [um redo];
    XCTAssertNotNil(doc.plan.brouterInfo.roadRuns);
    BPSpin(0.2);
    XCTAssertEqual([server requestsWithPath:@"/brouter"].count, 1u, @"undo/redo do not ask BRouter again");
}

// a failed recalculation keeps the route and registers nothing to undo
- (void)testRecalculateRouteFailureKeepsRoute
{
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [self makeRoute];
    [um endUndoGrouping];
    NSArray *route = doc.plan.routePoints;
    server.failCount = 1;
    server.failStatus = 500;
    [server clearRequests];
    [doc recalculateRoute:nil];
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self->server requestsWithPath:@"/brouter"].count == 1); }));
    BPSpin(0.3);
    XCTAssertEqualObjects(doc.plan.routePoints, route);
    XCTAssertEqualObjects(um.undoActionName, @"add destination");
}

// Edit ▸ Clear Route and its toolbar button (#33): after confirmation, erases waypoints, route, length/ascent and POIs, keeps the
// reference trace; undo restores everything without a new BRouter request
- (void)testClearRoute
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(clearRoute:) keyEquivalent:@""];
    XCTAssertFalse([doc validateMenuItem:item], @"disabled on an empty plan");
    NSToolbarItem *button = nil;
    for (NSToolbarItem *it in doc.windowControllers.firstObject.window.toolbar.items) if (it.action == @selector(clearRoute:)) button = it;
    XCTAssertNotNil(button, @"Clear button in the default toolbar");
    XCTAssertFalse([mc validateToolbarItem:button]);

    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [self makeRoute];
    [self waitForPOIs];
    [mc addCustomPoiAt:CLLocationCoordinate2DMake(44.05, 0.55)];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-ref-clear.gpx"]];
    XCTAssertTrue([BPData(kBRouterGPX) writeToURL:url atomically:YES]);
    [mc loadGPXFromURL:url];
    [um endUndoGrouping];
    NSInteger km = doc.plan.brouterInfo.kmlen;
    XCTAssertGreaterThan(km, 0);
    XCTAssertGreaterThan(doc.plan.poiloc.count, 0u);
    XCTAssertTrue([doc validateMenuItem:item]);
    XCTAssertTrue([mc validateToolbarItem:button]);
    [server clearRequests];

    // a confirmation sheet first (#33): Cancel keeps everything
    NSWindow *window = doc.windowControllers.firstObject.window;
    [doc clearRoute:item];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet != nil); }), @"confirmation sheet");
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u, @"nothing cleared before confirmation");
    [window endSheet:window.attachedSheet returnCode:NSAlertSecondButtonReturn];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet == nil); }));
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u, @"cancelled");
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);

    [doc clearRoute:item];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet != nil); }));
    [um beginUndoGrouping];
    [window endSheet:window.attachedSheet returnCode:NSAlertFirstButtonReturn];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet == nil); }));
    [um endUndoGrouping];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 0u);
    XCTAssertEqual(doc.plan.routePoints.count, 0u);
    XCTAssertEqual(doc.plan.brouterInfo.kmlen, 0);
    XCTAssertEqual(doc.plan.brouterInfo.mup, 0);
    XCTAssertEqual(doc.plan.poiloc.count, 0u);
    XCTAssertEqual(doc.plan.customPoiloc.count, 0u);
    XCTAssertNil(mc.gpxData, @"nothing to export");
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 0u);
    XCTAssertEqual([self annotationsOfClass:[POIAnnotation class]].count, 0u);
    XCTAssertEqual([self polysWithTag:0].firstObject.pointCount, 0u);
    XCTAssertEqual(mc.elevationView.distances.count, 0u);
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 3u, @"reference trace kept");
    XCTAssertEqual([self polysWithTag:2].count, 1u);
    XCTAssertFalse([doc validateMenuItem:item]);

    XCTAssertEqualObjects(um.undoActionName, @"clear route");
    [um undo];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u);
    XCTAssertEqual(doc.plan.routePoints.count, 11u);
    XCTAssertEqual(doc.plan.brouterInfo.kmlen, km);
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);
    XCTAssertGreaterThan(doc.plan.poiloc.count, 0u);
    XCTAssertNotNil(mc.gpxData, @"export available again");
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 2u);
    XCTAssertEqual(mc.elevationView.distances.count, 11u);
    BPSpin(0.2);
    XCTAssertEqual([server requestsWithPath:@"/brouter"].count, 0u, @"restored, not recomputed");
    [um redo];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 0u);
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 3u);
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

#pragma mark - import GPX as route (#29)

// a track from (44.02, 0.52) to (44.08, 0.58) with 3 waypoints: a custom POI (DANGER), a fetched POI (WATER,
// fetched again along the new route) and an untyped one (custom)
- (NSURL *)writeTrackToImport
{
    NSMutableString *gpx = [NSMutableString stringWithString:@"<gpx><trk><trkseg>"];
    for (int i = 0; i <= 20; i++) [gpx appendFormat:@"<trkpt lat=\"%f\" lon=\"%f\"/>", 44.02 + i * 0.003, 0.52 + i * 0.003];
    [gpx appendString:@"</trkseg></trk>"
                      @"<wpt lat=\"44.05\" lon=\"0.55\"><name>DANGER</name><type>DANGER</type></wpt>"
                      @"<wpt lat=\"44.06\" lon=\"0.56\"><name>water</name><type>WATER</type></wpt>"
                      @"<wpt lat=\"44.07\" lon=\"0.57\"><name>mine</name></wpt></gpx>"];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-import-route.gpx"]];
    XCTAssertTrue([[gpx dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url atomically:YES]);
    return url;
}

- (void)testImportGPXAsRoute
{
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    NSURL *url = [self writeTrackToImport];
    [um beginUndoGrouping];
    [mc loadGPXAsRouteFromURL:url];
    [um endUndoGrouping];
    NSWindow *window = doc.windowControllers.firstObject.window;
    XCTAssertNil(window.attachedSheet, @"empty plan: no confirmation");

    NSArray<CLLocation *> *wps = doc.plan.waypointsLocations;
    XCTAssertGreaterThanOrEqual(wps.count, 2u);
    XCTAssertEqualWithAccuracy(wps.firstObject.coordinate.latitude, 44.02, 1e-6);
    XCTAssertEqualWithAccuracy(wps.lastObject.coordinate.longitude, 0.58, 1e-6);
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 21u, @"original track kept as the reference trace");
    XCTAssertEqual(doc.plan.customPoiloc.count, 2u, @"DANGER and untyped waypoints become custom POIs");
    XCTAssertTrue([self waitForRouteWithPoints:10 * (wps.count - 1) + 1], @"route requested from BRouter (stub: 10 steps per leg)");
    XCTAssertTrue([[server requestsWithPath:@"/brouter"].lastObject.query[@"lonlats"] hasPrefix:@"0.520000,44.020000|"]);
    XCTAssertEqualObjects(um.undoActionName, @"import GPX as route");

    [um undo];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 0u);
    XCTAssertEqual(doc.plan.routePoints.count, 0u);
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 0u);
    XCTAssertEqual(doc.plan.customPoiloc.count, 0u);
    [um redo];
    XCTAssertEqual(doc.plan.waypointsLocations.count, wps.count);
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 21u);
    XCTAssertEqual(doc.plan.customPoiloc.count, 2u);
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

// the current route is replaced only after confirmation, and comes back with undo
- (void)testImportGPXAsRouteReplacesCurrentPlan
{
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [self makeRoute];
    [um endUndoGrouping];
    NSArray *old = doc.plan.waypointsLocations;
    NSURL *url = [self writeTrackToImport];
    NSWindow *window = doc.windowControllers.firstObject.window;

    [mc loadGPXAsRouteFromURL:url];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet != nil); }), @"confirmation sheet");
    [window endSheet:window.attachedSheet returnCode:NSAlertSecondButtonReturn];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet == nil); }));
    XCTAssertEqualObjects(doc.plan.waypointsLocations, old, @"cancelled");
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 0u);

    [mc loadGPXAsRouteFromURL:url];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet != nil); }));
    [um beginUndoGrouping];
    [window endSheet:window.attachedSheet returnCode:NSAlertFirstButtonReturn];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(window.attachedSheet == nil); }));
    [um endUndoGrouping];
    XCTAssertEqualWithAccuracy(doc.plan.waypointsLocations.firstObject.coordinate.latitude, 44.02, 1e-6);
    XCTAssertTrue([self waitForRouteWithPoints:10 * (doc.plan.waypointsLocations.count - 1) + 1]);

    [um undo];
    XCTAssertEqualObjects(doc.plan.waypointsLocations, old);
    XCTAssertEqual(doc.plan.routePoints.count, 11u);
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 0u);
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

// unreadable file or empty trace: nothing changes
- (void)testImportGPXAsRouteBadFile
{
    NSURL *bad = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-import-bad.gpx"]];
    XCTAssertTrue([BPData(@"<gpx></gpx>") writeToURL:bad atomically:YES]);
    [mc loadGPXAsRouteFromURL:bad];
    [mc loadGPXAsRouteFromURL:[NSURL fileURLWithPath:@"/nonexistent/x.gpx"]];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 0u);
    XCTAssertFalse(doc.undoManager.canUndo);
    [[NSFileManager defaultManager] removeItemAtURL:bad error:NULL];
}

#pragma mark - initial region (#26)

// new document, no test region: ~80 km around the default position, then around the user location when it comes
- (void)reopenWithoutTestRegion
{
    doc.plan.fetchPOI = NO;
    [doc close];
    // all the settings involved, so that the owner's Preferences (#27) do not change the result
    BPOverrideDefaults(@{ @"BPInitialRegion": @"", @"BPDefaultPosition": @"45.0,1.0", @"BPInitialRadiusKm": @80,
                          @"BPDisableLocation": @YES, @"BPDisableStreetView": @YES, @"BPDisableTiles": @YES, @"BPStartPosition": @0 });
    doc = [[Document alloc] init];
    [doc makeWindowControllers];
    XCTAssertNotNil(doc.windowControllers.firstObject.window);
    mc = doc.mapController;
    map = mc.mapView;
    BPSpin(0.2);
}

// smaller dimension of the visible region, in km (MapKit widens one dimension to the view aspect)
- (double)visibleKm
{
    MKCoordinateRegion r = map.region;
    return MIN(r.span.latitudeDelta * 111.0, r.span.longitudeDelta * 111.0 * cos(r.center.latitude * M_PI / 180));
}

- (void)testInitialRegionAroundDefaultPosition
{
    [self reopenWithoutTestRegion];
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 45.0, 0.05);
    XCTAssertEqualWithAccuracy(map.region.center.longitude, 1.0, 0.05);
    XCTAssertTrue([self visibleKm] > 120 && [self visibleKm] < 260, @"~80 km radius, not the whole country (%g km)", [self visibleKm]);
}

- (void)testInitialRegionFollowsFirstUserLocation
{
    [self reopenWithoutTestRegion];
    [mc userLocationAvailable:[[CLLocation alloc] initWithLatitude:44.5 longitude:0.3]];
    // animated from the default position (the owner's Preferences): wait for the end, not a fixed time
    BPWaitUntil(3, ^BOOL{ return fabs(self->map.region.center.latitude - 44.5) < 0.01
                              && fabs(self->map.region.center.longitude - 0.3) < 0.01; });
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 44.5, 0.05);
    XCTAssertEqualWithAccuracy(map.region.center.longitude, 0.3, 0.05);
    XCTAssertTrue([self visibleKm] > 120 && [self visibleKm] < 260, @"%g km", [self visibleKm]);
    // later updates do not move the map
    [mc userLocationAvailable:[[CLLocation alloc] initWithLatitude:43.0 longitude:2.0]];
    BPSpin(0.3);
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 44.5, 0.05);
}

// Preferences ▸ Start position (#65): a remarkable site, ~15 km around it, its name in the map message; the
// location is not used
- (void)testStartOnRemarkableSite
{
    doc.plan.fetchPOI = NO;
    [doc close];
    BPOverrideDefaults(@{ @"BPInitialRegion": @"", @"BPDefaultPosition": @"45.0,1.0", @"BPInitialRadiusKm": @80,
                          @"BPDisableLocation": @YES, @"BPDisableStreetView": @YES, @"BPDisableTiles": @YES, @"BPStartPosition": @2, @"BPRemarkableSiteIndex": @0 });
    doc = [[Document alloc] init];
    [doc makeWindowControllers];
    XCTAssertNotNil(doc.windowControllers.firstObject.window); // loads the window
    mc = doc.mapController;
    map = mc.mapView;
    BPSpin(0.2);
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 44.1739, 0.02, @"Mont Ventoux");
    XCTAssertEqualWithAccuracy(map.region.center.longitude, 5.2789, 0.02);
    XCTAssertTrue([self visibleKm] > 20 && [self visibleKm] < 60, @"%g km", [self visibleKm]);
    NSTextField *help = (NSTextField *)[self viewWithIdentifier:@"clickModeHelp" in:self.content];
    XCTAssertEqualObjects(help.stringValue, @"Mont Ventoux — famous climb");
    XCTAssertEqualWithAccuracy(mc.svCtrl.lastCoord.latitude, 44.1739, 1e-4, @"Street View on the site");
    XCTAssertEqualWithAccuracy(mc.svCtrl.lastCoord.longitude, 5.2789, 1e-4);
    XCTAssertEqual(mc.svCtrl.lastHeading, [BPRemarkableSites sites][0].heading, @"camera heading of the site");
    [mc userLocationAvailable:[[CLLocation alloc] initWithLatitude:44.5 longitude:0.3]];
    BPSpin(0.3);
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 44.1739, 0.02, @"the location does not move the map");
}

// Start position: default position — the location does not move the map either
- (void)testStartOnDefaultPosition
{
    doc.plan.fetchPOI = NO;
    [doc close];
    BPOverrideDefaults(@{ @"BPInitialRegion": @"", @"BPDefaultPosition": @"45.0,1.0", @"BPInitialRadiusKm": @80,
                          @"BPDisableLocation": @YES, @"BPDisableStreetView": @YES, @"BPDisableTiles": @YES, @"BPStartPosition": @1 });
    doc = [[Document alloc] init];
    [doc makeWindowControllers];
    XCTAssertNotNil(doc.windowControllers.firstObject.window); // loads the window
    mc = doc.mapController;
    map = mc.mapView;
    BPSpin(0.2);
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 45.0, 0.05);
    [mc userLocationAvailable:[[CLLocation alloc] initWithLatitude:44.5 longitude:0.3]];
    BPSpin(0.3);
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 45.0, 0.05);
}

- (void)testUserLocationDoesNotMoveAMapTheUserMoved
{
    [self reopenWithoutTestRegion];
    [map setCenterCoordinate:CLLocationCoordinate2DMake(46.0, 2.0) animated:NO];
    [mc userLocationAvailable:[[CLLocation alloc] initWithLatitude:44.5 longitude:0.3]];
    BPSpin(0.3);
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 46.0, 0.05);
}

// toolbar button for Reverse Route (#25), enabled with >= 2 waypoints
- (void)testReverseRouteToolbarButton
{
    NSToolbar *tb = doc.windowControllers.firstObject.window.toolbar;
    NSToolbarItem *item = nil;
    for (NSToolbarItem *it in tb.items) if (it.action == @selector(reverseRoute:)) item = it;
    XCTAssertNotNil(item, @"Reverse button in the default toolbar");
    XCTAssertEqual(item.target, mc);
    XCTAssertFalse([mc validateToolbarItem:item], @"disabled without a route");
    [self makeRoute];
    XCTAssertTrue([mc validateToolbarItem:item]);
}

#pragma mark - views, renderers, scrubbing, export

- (void)testAnnotationViews
{
    [self makeRoute];
    RouteAnnotation *ra = [self annotationsOfClass:[RouteAnnotation class]].firstObject;
    MKAnnotationView *v = [mc mapView:map viewForAnnotation:ra];
    XCTAssertTrue(v.draggable);
    XCTAssertEqualObjects(v.menu.itemArray.firstObject.title, @"Remove Waypoint");
    XCTAssertNil([mc mapView:map viewForAnnotation:[[MKPointAnnotation alloc] init]]);
}

- (void)testOverlayRenderers
{
    [self makeRoute];
    MKPolylineRenderer *r = (MKPolylineRenderer *)[mc mapView:map rendererForOverlay:doc.plan.routePoly];
    XCTAssertEqual(r.lineWidth, 8.0);
    doc.plan.gpxDisplayed = @[BPLoc(44, 0.5), BPLoc(44.1, 0.5)];
    MKPolylineRenderer *g = (MKPolylineRenderer *)[mc mapView:map rendererForOverlay:doc.plan.gpxDisplayedPoly];
    XCTAssertEqual(g.lineWidth, 6.0);
    XCTAssertNotNil([mc mapView:map rendererForOverlay:[[MKTileOverlay alloc] initWithURLTemplate:@"x"]]);
}

- (void)testElevationScrubbingMovesMap
{
    [self makeRoute];
    double total = mc.elevationView.distances.lastObject.doubleValue;
    [mc elevationProfileView:mc.elevationView didSelectDistance:total / 2];
    BPSpin(0.2);
    XCTAssertEqualWithAccuracy(map.centerCoordinate.latitude, 44.05, 0.005);
}

// zooming the elevation profile shows the same part of the route on the map (#62)
- (void)testProfileZoomMovesMap
{
    [self makeRoute]; // 44.0, 0.5 → 44.1, 0.6
    double total = mc.elevationView.distances.lastObject.doubleValue;
    [mc.elevationView showRangeFrom:0 to:total / 4 notify:YES];
    BPSpin(0.2);
    MKCoordinateRegion r = map.region;
    XCTAssertEqualWithAccuracy(r.center.latitude, 44.0125, 0.01, @"first quarter of the route");
    XCTAssertLessThan(r.span.latitudeDelta, 0.08, @"zoomed on it");
    XCTAssertGreaterThan(r.span.latitudeDelta, 0.025, @"all of it");
    // the cursor set from the map moves the profile, not the map back
    mc.elevationView.highlightDistance = total * 0.9;
    XCTAssertTrue(mc.elevationView.visibleTo >= total * 0.9);
    XCTAssertEqualWithAccuracy(map.region.center.latitude, r.center.latitude, 1e-6);
}

- (void)testExportAfterRoute
{
    [self makeRoute];
    NSString *gpx = [[NSString alloc] initWithData:[mc exportGpxDataWithPOI:NO trackName:@"t"] encoding:NSUTF8StringEncoding];
    XCTAssertTrue([gpx containsString:@"<name>t</name>"]);
}

#pragma mark - documents

- (void)testReopenSavedDocument
{
    [self makeRoute];
    NSInteger km = doc.plan.brouterInfo.kmlen;
    NSData *data = [doc dataOfType:@"fr.free.daniel.braun.bikeplan" error:NULL];
    [doc close];

    doc = [[Document alloc] init];
    XCTAssertTrue([doc readFromData:data ofType:@"fr.free.daniel.braun.bikeplan" error:NULL]);
    [self openWindow];
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 2u);
    XCTAssertEqual([self polysWithTag:0].firstObject.pointCount, 11u);
    XCTAssertEqual(mc.elevationView.distances.count, 11u);
    XCTAssertEqual(doc.plan.brouterInfo.kmlen, km);
    // the BRouter GPX is saved with the document: export available after reopening (#10)
    XCTAssertNotNil(mc.gpxData);
    XCTAssertEqualObjects(mc.gpxData, doc.plan.routeGPX);
}

// a document saved before #10 (route points, no GPX): export available, GPX generated from the route points
- (void)testReopenOldDocumentCanExport
{
    [self makeRoute];
    doc.plan.routeGPX = nil;
    NSData *data = [doc dataOfType:@"fr.free.daniel.braun.bikeplan" error:NULL];
    [doc close];
    doc = [[Document alloc] init];
    XCTAssertTrue([doc readFromData:data ofType:@"fr.free.daniel.braun.bikeplan" error:NULL]);
    [self openWindow];
    XCTAssertNotNil(mc.gpxData);
    NSArray *pts = [[[GPXParser alloc] init] parseGPXData:[mc exportGpxDataWithPOI:NO trackName:@"t"] error:NULL];
    XCTAssertEqual(pts.count, 11u);
}

// Revert to Saved replaces doc.plan while the window is open: the map must show the saved plan
// and the POI callback must be installed on the new plan (#16).
- (void)testRevertToSavedRefreshesMap
{
    NSString *type = @"fr.free.daniel.braun.bikeplan";
    [self makeRoute];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-revert.bikeplan"]];
    XCTAssertTrue([[doc dataOfType:type error:NULL] writeToURL:url atomically:YES]);
    doc.fileURL = url;
    doc.fileType = type;

    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.7)]; // third waypoint, not saved
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 3u);
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->doc.plan.routePoints.count != 11); }));

    NSError *err = nil;
    XCTAssertTrue([doc revertToContentsOfURL:url ofType:type error:&err], @"%@", err);
    BPSpin(0.2);
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u);
    XCTAssertEqual([self annotationsOfClass:[RouteAnnotation class]].count, 2u);
    XCTAssertEqual([self polysWithTag:0].firstObject.pointCount, 11u);
    XCTAssertNotNil(doc.plan.poiAvailableCallback);
}

#pragma mark - more paths

- (void)testMenuRelays
{
    NSSegmentedControl *seg = (NSSegmentedControl *)[self viewWithIdentifier:@"clickMode" in:self.content];
    [doc setClickModeToView:nil];   XCTAssertEqual(seg.selectedSegment, 3);
    [doc setClickModeToAddPoi:nil]; XCTAssertEqual(seg.selectedSegment, 2);
    [doc setClickModeToInterm:nil]; XCTAssertEqual(seg.selectedSegment, 1);
    [doc setClickModeToEdit:nil];   XCTAssertEqual(seg.selectedSegment, 0);
}

// "Apply" in the Params tab: overrides are sent to BRouter as profile:<name> parameters (#15, #35), saved in the
// plan (#44)
- (void)testBRFOverridesRecomputeRoute
{
    [self makeRoute];
    [server clearRequests];
    BRFProfileEditor *editor = ((PlannerWindowController *)doc.windowControllers.firstObject).brfEditor;
    XCTAssertNotNil(editor.completionHandler);
    editor.completionHandler(@{ @"downhillcost": @"80" });
    XCTAssertEqualObjects(doc.plan.profileOverrides, @{ @"downhillcost": @"80" });
    XCTAssertEqualObjects(editor.appliedOverrides, @{ @"downhillcost": @"80" });
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self->server requestsWithPath:@"/brouter"].count == 1); }));
    XCTAssertEqualObjects([server requestsWithPath:@"/brouter"].firstObject.query[@"profile:downhillcost"], @"80");

    // same overrides again: no new request
    [server clearRequests];
    editor.completionHandler(@{ @"downhillcost": @"80" });
    BPSpin(0.5);
    XCTAssertEqual([server requestsWithPath:@"/brouter"].count, 0u);

    // no override: back to the profile defaults
    editor.completionHandler(@{});
    XCTAssertEqualObjects(doc.plan.profileOverrides, @{});
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self->server requestsWithPath:@"/brouter"].count == 1); }));
    XCTAssertNil([server requestsWithPath:@"/brouter"].firstObject.query[@"profile:downhillcost"]);
}

// Apply is undoable: undo restores the parameters (plan and Params tab) and recomputes the route (#44)
- (void)testUndoProfileOverrides
{
    // nested run loops in tests do not close automatic undo groups: group explicitly (see UndoTests)
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [self makeRoute];
    [um endUndoGrouping];
    [doc updateChangeCount:NSChangeCleared];
    BRFProfileEditor *editor = ((PlannerWindowController *)doc.windowControllers.firstObject).brfEditor;
    [server clearRequests];
    [um beginUndoGrouping];
    editor.completionHandler(@{ @"downhillcost": @"80" });
    [um endUndoGrouping];
    XCTAssertEqualObjects(um.undoActionName, @"change routing parameters");
    XCTAssertTrue(BPWaitUntil(2, ^{ return self->doc.isDocumentEdited; }), @"document edited (updated asynchronously by NSDocument)");
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self->server requestsWithPath:@"/brouter"].count == 1); }));
    [server clearRequests];
    [um undo];
    XCTAssertEqualObjects(doc.plan.profileOverrides, @{});
    XCTAssertEqualObjects(editor.appliedOverrides, @{});
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self->server requestsWithPath:@"/brouter"].count == 1); }));
    XCTAssertNil([server requestsWithPath:@"/brouter"].firstObject.query[@"profile:downhillcost"]);
    [um redo];
    XCTAssertEqualObjects(doc.plan.profileOverrides, @{ @"downhillcost": @"80" });
    XCTAssertEqualObjects(editor.appliedOverrides, @{ @"downhillcost": @"80" });
}

// a new document starts with my default parameters; an opened one keeps its own (#44)
- (void)testNewDocumentUsesMyDefaults
{
    BPOverrideDefaults(@{ @"BPProfileOverrides": @{ @"trekking": @{ @"bikerPower": @"80" } } });
    Document *d = [[Document alloc] init];
    XCTAssertEqualObjects(d.plan.profileOverrides, @{ @"bikerPower": @"80" });

    NSString *type = @"fr.free.daniel.braun.bikeplan";
    NSData *data = [doc dataOfType:type error:NULL]; // saved with no override
    Document *opened = [[Document alloc] init];
    XCTAssertTrue([opened readFromData:data ofType:type error:NULL]);
    XCTAssertEqualObjects(opened.plan.profileOverrides, @{});
}

#pragma mark - analyzer findings (#58)

// the projection is optional: NULL used to be dereferenced
- (void)testProjectPointWithoutProjection
{
    CGFloat d = [mc projectPoint:CGPointMake(5, 3) ontoSegmentFrom:CGPointMake(0, 0) to:CGPointMake(10, 0) projection:NULL];
    XCTAssertEqualWithAccuracy(d, 3, 1e-9);
    CGPoint proj;
    d = [mc projectPoint:CGPointMake(-4, 3) ontoSegmentFrom:CGPointMake(0, 0) to:CGPointMake(10, 0) projection:&proj];
    XCTAssertEqualWithAccuracy(d, 5, 1e-9, @"before the segment: distance to its start");
    XCTAssertEqual(proj.x, 0);
}

// MapKit expects a renderer for every overlay: one that draws nothing for an unknown kind (was nil)
- (void)testRendererForUnknownOverlay
{
    MKCircle *circle = [MKCircle circleWithCenterCoordinate:CLLocationCoordinate2DMake(44, 0.5) radius:100];
    XCTAssertNotNil([mc mapView:map rendererForOverlay:circle]);
}

#pragma mark - stages (#31)

// three waypoints (start, 44.1/0.6, end): stub route of 21 points, the middle waypoint on point 10
- (void)makeThreeWaypointRoute
{
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.5)];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.1, 0.6)];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.2, 0.5)];
    XCTAssertTrue([self waitForRouteWithPoints:21]);
    BPSpin(0.1);
}

- (RouteAnnotation *)waypointAnnotation:(NSUInteger)idx
{
    for (RouteAnnotation *a in [self annotationsOfClass:[RouteAnnotation class]]) if (a.idx == idx) return a;
    return nil;
}

- (NSMenuItem *)stageItemForWaypoint:(NSUInteger)idx
{
    NSMenu *menu = [mc waypointMenuForAnnotation:[self waypointAnnotation:idx]];
    for (NSMenuItem *it in menu.itemArray) if (it.action == NSSelectorFromString(@"toggleStageEndMenuAction:")) return it;
    return nil;
}

// right-click on an intermediate waypoint ▸ End Stage Here: the route is cut there (colors, elevation profile), no
// new BRouter request, undoable
- (void)testEndStageFromWaypointMenu
{
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [self makeThreeWaypointRoute];
    [um endUndoGrouping];
    XCTAssertNil([self stageItemForWaypoint:0], @"not on the start");
    XCTAssertNil([self stageItemForWaypoint:2], @"not on the end");
    NSMenuItem *item = [self stageItemForWaypoint:1];
    XCTAssertNotNil(item);
    XCTAssertEqualObjects(item.title, @"End Stage Here");
    XCTAssertEqual(item.state, NSControlStateValueOff);
    XCTAssertEqual([self polysWithTag:0].count, 1u);
    [server clearRequests];
    [doc updateChangeCount:NSChangeCleared];

    [um beginUndoGrouping];
    [NSApp sendAction:item.action to:item.target from:item];
    [um endUndoGrouping];
    XCTAssertTrue([doc.plan isStageEndAtWaypointIndex:1]);
    NSArray<TaggedPoly *> *polys = [self polysWithTag:0];
    XCTAssertEqual(polys.count, 2u, @"one polyline per stage");
    NSUInteger stage0 = 0, stage1 = 0;
    for (TaggedPoly *p in polys) { if (p.stage == 0) stage0 = p.pointCount; else stage1 = p.pointCount; }
    XCTAssertEqual(stage0, 11u, @"points 0 to 10");
    XCTAssertEqual(stage1, 11u, @"points 10 to 20");
    XCTAssertEqualObjects(mc.elevationView.stageEndIndexes, @[@10]);
    XCTAssertEqual(mc.elevationView.stageEndDistances.count, 1u);
    XCTAssertEqual([self stageItemForWaypoint:1].state, NSControlStateValueOn, @"checked");
    XCTAssertTrue(BPWaitUntil(2, ^{ return self->doc.isDocumentEdited; }), @"document edited");
    XCTAssertEqualObjects(um.undoActionName, @"end stage");
    BPSpin(0.2);
    XCTAssertEqual([server requestsWithPath:@"/brouter"].count, 0u, @"same route: no new request");

    [um undo];
    XCTAssertFalse([doc.plan isStageEndAtWaypointIndex:1]);
    XCTAssertEqual([self polysWithTag:0].count, 1u);
    XCTAssertEqualObjects(mc.elevationView.stageEndIndexes, @[]);
    [um redo];
    XCTAssertTrue([doc.plan isStageEndAtWaypointIndex:1]);
    XCTAssertEqual([self polysWithTag:0].count, 2u);
    BPSpin(0.2);
    XCTAssertEqual([server requestsWithPath:@"/brouter"].count, 0u);
}

// a moved stage end still ends its stage; a stage end that becomes the end of the route (removal) ends nothing
- (void)testStageEndFollowsWaypointChanges
{
    [self makeThreeWaypointRoute];
    [NSApp sendAction:NSSelectorFromString(@"toggleStageEndMenuAction:") to:mc from:[self stageItemForWaypoint:1]];
    XCTAssertTrue([doc.plan isStageEndAtWaypointIndex:1]);
    (void)[doc.plan replaceWaypointAtIndex:1 by:BPLoc(44.11, 0.6)];
    XCTAssertTrue([doc.plan isStageEndAtWaypointIndex:1]);
    NSMenuItem *remove = [mc waypointMenuForAnnotation:[self waypointAnnotation:2]].itemArray.firstObject;
    [mc removeWaypointMenuAction:remove];
    XCTAssertTrue([self waitForRouteWithPoints:11]);
    BPSpin(0.1);
    XCTAssertEqual([self polysWithTag:0].count, 1u, @"no stage any more");
    XCTAssertNil([self stageItemForWaypoint:1], @"now the end of the route");
}

// stage ends survive save + reopen
- (void)testStageEndsSavedWithDocument
{
    [self makeThreeWaypointRoute];
    [NSApp sendAction:NSSelectorFromString(@"toggleStageEndMenuAction:") to:mc from:[self stageItemForWaypoint:1]];
    NSString *type = @"fr.free.daniel.braun.bikeplan";
    Document *opened = [[Document alloc] init];
    XCTAssertTrue([opened readFromData:[doc dataOfType:type error:NULL] ofType:type error:NULL]);
    XCTAssertTrue([opened.plan isStageEndAtWaypointIndex:1]);
    XCTAssertEqual(opened.plan.stagesRoutePoints.count, 2u);
}

// export of a staged route: one GPX per stage, each with the POIs of its stage
- (void)testExportStages
{
    doc.plan.fetchPOI = NO; // only the custom POIs below
    [self makeThreeWaypointRoute];
    [NSApp sendAction:NSSelectorFromString(@"toggleStageEndMenuAction:") to:mc from:[self stageItemForWaypoint:1]];
    [mc addCustomPoiAt:CLLocationCoordinate2DMake(44.03, 0.53)];  // stage 1
    [mc addCustomPoiAt:CLLocationCoordinate2DMake(44.17, 0.53)];  // stage 2
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-stages"] isDirectory:YES];
    [[NSFileManager defaultManager] removeItemAtURL:dir error:NULL];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:nil error:NULL]);
    NSError *err = nil;
    XCTAssertTrue([mc exportStagesToDirectory:dir baseName:@"Trip" withPOI:YES error:&err], @"%@", err);
    NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir.path error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(files, (@[@"Trip - stage 1.gpx", @"Trip - stage 2.gpx"]));
    for (NSUInteger i = 0; i < 2; i++) {
        GPXParser *p = [[GPXParser alloc] init];
        NSData *d = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:files[i]]];
        NSArray<CLLocation *> *pts = [p parseGPXData:d error:NULL];
        XCTAssertEqual(pts.count, 11u);
        XCTAssertEqual(p.waypoints.count, 1u, @"the POI of the stage");
        double lat = i ? 44.17 : 44.03;
        XCTAssertEqualWithAccuracy(p.waypoints.firstObject.coordinate.latitude, lat, 1e-4);
        NSString *xml = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        NSString *name = [NSString stringWithFormat:@"<name>Trip - stage %lu</name>", (unsigned long)(i + 1)];
        XCTAssertTrue([xml containsString:name]);
    }
}

// printing is not implemented (#59): File ▸ Print… / Page Setup… and the Print toolbar button are disabled, and a
// print request (menu shortcut, Finder, AppleScript) does nothing instead of raising in NSDocument
- (void)testPrintDisabled
{
    [self makeRoute];
    NSMenuItem *print = [[NSMenuItem alloc] initWithTitle:@"Print…" action:@selector(printDocument:) keyEquivalent:@"p"];
    NSMenuItem *setup = [[NSMenuItem alloc] initWithTitle:@"Page Setup…" action:@selector(runPageLayout:) keyEquivalent:@"P"];
    XCTAssertFalse([doc validateMenuItem:print]);
    XCTAssertFalse([doc validateMenuItem:setup]);
    NSToolbarItem *button = nil;
    for (NSToolbarItem *it in doc.windowControllers.firstObject.window.toolbar.items) {
        if ([it.itemIdentifier isEqualToString:NSToolbarPrintItemIdentifier]) button = it;
    }
    XCTAssertNotNil(button, @"Print button kept in the toolbar");
    XCTAssertFalse([doc validateUserInterfaceItem:button]);

    NSError *err = nil;
    NSPrintOperation *op = nil;
    XCTAssertNoThrow(op = [doc printOperationWithSettings:@{} error:&err]);
    XCTAssertNil(op);
    XCTAssertNotNil(err);
    NSWindow *window = doc.windowControllers.firstObject.window;
    XCTAssertNoThrow([doc printDocument:print]);
    XCTAssertNoThrow([doc runPageLayout:setup]);
    BPSpin(0.3);
    XCTAssertNil(window.attachedSheet, @"no print panel");
}

// a new document starts in Edit mode (to place the start), an opened one in View mode: a click does not change
// its route by mistake
- (void)testOpenedDocumentStartsInViewMode
{
    XCTAssertEqual(mc.clickMode, BPClickModeEdit, @"new document");
    [self makeRoute];
    NSString *type = @"fr.free.daniel.braun.bikeplan";
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-open-view.bikeplan"]];
    XCTAssertTrue([[doc dataOfType:type error:NULL] writeToURL:url atomically:YES]);
    doc.plan.fetchPOI = NO;
    [doc close];

    NSError *err = nil;
    doc = [[Document alloc] initWithContentsOfURL:url ofType:type error:&err];
    XCTAssertNotNil(doc, @"%@", err);
    [self openWindow];
    XCTAssertEqual(mc.clickMode, BPClickModeView);
    NSSegmentedControl *seg = (NSSegmentedControl *)[self viewWithIdentifier:@"clickMode" in:self.content];
    XCTAssertEqual(seg.selectedSegment, BPClickModeView);
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.2, 0.7)];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u, @"a click does not add a waypoint");
}

// the document's parameters are restored in the Params tab by Revert to Saved (#44)
- (void)testRevertRestoresProfileOverrides
{
    NSString *type = @"fr.free.daniel.braun.bikeplan";
    BRFProfileEditor *editor = ((PlannerWindowController *)doc.windowControllers.firstObject).brfEditor;
    editor.completionHandler(@{ @"downhillcost": @"80" });
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-revert-params.bikeplan"]];
    XCTAssertTrue([[doc dataOfType:type error:NULL] writeToURL:url atomically:YES]);
    doc.fileURL = url;
    doc.fileType = type;
    editor.completionHandler(@{ @"downhillcost": @"100" });

    NSError *err = nil;
    XCTAssertTrue([doc revertToContentsOfURL:url ofType:type error:&err], @"%@", err);
    XCTAssertEqualObjects(doc.plan.profileOverrides, @{ @"downhillcost": @"80" });
    XCTAssertEqualObjects(editor.appliedOverrides, @{ @"downhillcost": @"80" });
}

// side panel: the Info section is always visible, the tabs are Street View / Params, so that the effect of new
// parameters on the route (length, time, speed) can be seen (#43)
- (void)testInfoAlwaysVisibleAboveStreetViewAndParamsTabs
{
    NSTabView *tabs = [self tabViewIn:self.content];
    XCTAssertEqualObjects([tabs.tabViewItems valueForKey:@"label"], (@[@"Street View", @"Params"]));
    XCTAssertNotNil(mc.svCtrl.webView);
    XCTAssertTrue([mc.svCtrl.webView isDescendantOf:tabs.tabViewItems[0].view], @"Street View in the first tab");
    [tabs selectTabViewItemAtIndex:1];
    NSView *time = [self controlWithIdentifier:@"routeTime" in:self.content];
    XCTAssertNotNil(time, @"Info shown with the Params tab");
    XCTAssertFalse([time isDescendantOf:tabs]);
    XCTAssertFalse(time.isHiddenOrHasHiddenAncestor);
    XCTAssertNotNil(time.window);
}

// switching between the Street View and Params tabs must not change the width of the side panel (#43)
- (void)testSidePanelWidthStableAcrossTabs
{
    NSWindow *w = doc.windowControllers.firstObject.window;
    NSTabView *tabs = [self tabViewIn:self.content];
    NSView *pane = tabs.superview; // side pane of the map | panel split view
    while (pane && !([pane.superview isKindOfClass:[NSSplitView class]] && ((NSSplitView *)pane.superview).isVertical)) pane = pane.superview;
    XCTAssertNotNil(pane);
    BRFProfileEditor *editor = ((PlannerWindowController *)doc.windowControllers.firstObject).brfEditor;
    [tabs selectTabViewItemAtIndex:0];
    [w layoutIfNeeded];
    CGFloat infoWidth = pane.frame.size.width;
    [tabs selectTabViewItemAtIndex:1];
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([[editor valueForKey:@"parameters"] count] > 0); }));
    BPSpin(0.3);
    [w layoutIfNeeded];
    XCTAssertEqualWithAccuracy(pane.frame.size.width, infoWidth, 0.5, @"Params tab");
    [tabs selectTabViewItemAtIndex:0];
    [w layoutIfNeeded];
    XCTAssertEqualWithAccuracy(pane.frame.size.width, infoWidth, 0.5, @"back to Street View");

    // the user's width is kept: divider moved, then tabs switched
    NSSplitView *split = (NSSplitView *)pane.superview;
    [split setPosition:NSMaxX(split.subviews[0].frame) - 80 ofDividerAtIndex:0];
    [w layoutIfNeeded];
    CGFloat userWidth = pane.frame.size.width;
    [tabs selectTabViewItemAtIndex:1];
    [w layoutIfNeeded];
    XCTAssertEqualWithAccuracy(pane.frame.size.width, userWidth, 0.5, @"Params tab after moving the divider");
    [tabs selectTabViewItemAtIndex:0];
    [w layoutIfNeeded];
    XCTAssertEqualWithAccuracy(pane.frame.size.width, userWidth, 0.5, @"Street View tab after moving the divider");

    // a wider window: the map takes the extra space
    CGFloat mapWidth = split.subviews[0].frame.size.width;
    NSRect frame = w.frame;
    frame.size.width += 200;
    [w setFrame:frame display:NO];
    [w layoutIfNeeded];
    XCTAssertEqualWithAccuracy(pane.frame.size.width, userWidth, 0.5, @"window resized");
    XCTAssertEqualWithAccuracy(split.subviews[0].frame.size.width, mapWidth + 200, 0.5);
}

// the location search runs only on Return: neither while typing nor when the search field loses the focus, e.g.
// when the user then types a value in the Params tab (#41)
- (void)testLocationSearchOnlyOnReturn
{
    NSWindow *w = doc.windowControllers.firstObject.window;
    NSSearchField *field = nil;
    for (NSToolbarItem *item in w.toolbar.items) {
        if ([item isKindOfClass:[NSSearchToolbarItem class]]) field = ((NSSearchToolbarItem *)item).searchField;
    }
    XCTAssertNotNil(field);
    XCTAssertEqual(field.target, mc);
    XCTAssertEqual(field.action, @selector(sendersearchFieldAction:));
    BPActionCounter *counter = [BPActionCounter new];
    field.target = counter;
    field.action = @selector(act:);

    XCTAssertTrue([w makeFirstResponder:field]);
    for (NSString *c in @[@"A", @"g", @"e", @"n"]) [field.currentEditor insertText:c];
    BPSpin(1.0);
    XCTAssertEqual(counter.count, 0, @"no search while typing");
    [field.currentEditor insertNewline:nil];
    XCTAssertEqual(counter.count, 1, @"search on Return");

    // focus back in the search field, then in another field: no new search
    XCTAssertTrue([w makeFirstResponder:field]);
    BRFProfileEditor *editor = ((PlannerWindowController *)doc.windowControllers.firstObject).brfEditor;
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([[editor valueForKey:@"parameters"] count] > 0); }));
    NSControl *param = ((BRFParam *)[[editor valueForKey:@"parameters"] firstObject]).valueControl;
    [w makeFirstResponder:param];
    BPSpin(0.3);
    XCTAssertEqual(counter.count, 1, @"no search when the search field loses the focus");
    XCTAssertEqualObjects(field.stringValue, @"Agen");
}

// road class along the route (#54), from the stub's way tags: half tertiary, half track
- (void)testRouteHasRoadRuns
{
    [self makeRoute];
    XCTAssertEqualObjects(doc.plan.brouterInfo.roadRuns, (@[ @[@"tertiary", @5], @[@"track", @10] ]));
    XCTAssertEqualObjects(doc.plan.brouterInfo.surfaceRuns, (@[ @[@"paved", @5], @[@"unpaved", @10] ]));
}

// surface classes are highlighted the same way; unknown kinds give nothing
- (void)testHighlightSurfaceClass
{
    [self makeRoute];
    [mc highlightKind:@"surface:unpaved"];
    XCTAssertEqual([self polysWithTag:3].count, 1u);
    XCTAssertEqual([self polysWithTag:3].firstObject.pointCount, 6u, @"points 5 to 10");
    [mc highlightKind:@"surface:unknown"];
    XCTAssertEqual([self polysWithTag:3].count, 0u, @"no unknown surface on the route");
    [mc highlightKind:@"bogus"];
    XCTAssertEqual([self polysWithTag:3].count, 0u);
}

// highlight of a road class on the map (#54): tag 3 polylines over the parts of the route of that class
- (void)testHighlightRoadClass
{
    [self makeRoute];
    [mc highlightKind:@"road:track"];
    NSArray<TaggedPoly *> *h = [self polysWithTag:3];
    XCTAssertEqual(h.count, 1u);
    XCTAssertEqual(h.firstObject.pointCount, 6u, @"points 5 to 10: from the end of the tertiary part");
    XCTAssertEqualWithAccuracy(h.firstObject.points[0].x, MKMapPointForCoordinate(doc.plan.routePoints[5].coordinate).x, 1e-3);
    [mc highlightKind:@"road:tertiary"];
    XCTAssertEqual([self polysWithTag:3].count, 1u, @"replaces the previous highlight");
    XCTAssertEqual([self polysWithTag:3].firstObject.pointCount, 6u, @"points 0 to 5");
    [mc highlightKind:@"road:cycleway"];
    XCTAssertEqual([self polysWithTag:3].count, 0u, @"no cycleway on the route");
    [mc highlightKind:@"road:track"];
    [mc highlightKind:nil];
    XCTAssertEqual([self polysWithTag:3].count, 0u);
    XCTAssertTrue([[mc mapView:map rendererForOverlay:h.firstObject] isKindOfClass:[MKPolylineRenderer class]]);
}

// runs that are not those of the route (other point count: route from a trace, old document): no highlight
- (void)testNoHighlightWithRunsOfAnotherRoute
{
    [self makeRoute];
    doc.plan.brouterInfo.roadRuns = @[ @[@"track", @3] ];
    [mc highlightKind:@"road:track"];
    XCTAssertEqual([self polysWithTag:3].count, 0u);
}

// a new route removes the highlight of the old one
- (void)testNewRouteRemovesHighlight
{
    [self makeRoute];
    [mc highlightKind:@"road:track"];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.65)];
    XCTAssertTrue([self waitForRouteWithPoints:21]);
    BPSpin(0.1);
    XCTAssertEqual([self polysWithTag:3].count, 0u);
}

// hovering a road type line or a part of the surface line of the Info section highlights it on the map, leaving
// the label removes it (#54)
- (void)testHoverRoadTypeHighlightsOnMap
{
    BPRoadTypesLabel *roads = (BPRoadTypesLabel *)[self viewWithIdentifier:@"routeRoadTypes" in:self.content];
    XCTAssertTrue([roads isKindOfClass:[BPRoadTypesLabel class]]);
    [self makeRoute];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(roads.stringValue.length > 0); }));
    [roads.superview layoutSubtreeIfNeeded];
    // kinds met over the label, top to bottom and left to right: the tagged parts of the text, in order
    NSMutableArray<NSString *> *met = [NSMutableArray array];
    NSRect b = roads.bounds;
    for (CGFloat y = 1; y < NSHeight(b); y += 2) {
        for (CGFloat x = 1; x < NSWidth(b); x += 2) {
            NSPoint p = NSMakePoint(x, roads.isFlipped ? y : NSHeight(b) - y);
            NSString *k = [roads kindAtPoint:p];
            if (k && ![met containsObject:k]) {
                [met addObject:k];
                [roads hoverAtPoint:p];
                XCTAssertEqualObjects(roads.hoveredKind, k);
                BOOL onRoute = ![k isEqualToString:@"surface:unknown"]; // the stub route is all tertiary/paved or track/unpaved
                XCTAssertEqual([self polysWithTag:3].count, onRoute ? 1u : 0u, @"%@", k);
            }
        }
    }
    NSArray *expected = [@[ [@"road:" stringByAppendingString:doc.plan.brouterInfo.roadTypesClasses[0]],
                            [@"road:" stringByAppendingString:doc.plan.brouterInfo.roadTypesClasses[1]] ]
                         arrayByAddingObjectsFromArray:@[@"surface:paved", @"surface:unpaved", @"surface:unknown"]];
    XCTAssertEqualObjects(met, expected);
    XCTAssertNil([roads kindAtPoint:NSMakePoint(20, roads.isFlipped ? 1 : NSHeight(b) - 1)], @"title line");
    [roads hoverAtPoint:NSMakePoint(-10, -10)];
    XCTAssertNil(roads.hoveredKind);
    XCTAssertEqual([self polysWithTag:3].count, 0u);
}

// a click on the road types does not start text selection: the field editor would lay the text out differently
// (tab stops) and take the mouse events, so the hover stopped working (#54)
- (void)testRoadTypesLabelNotSelectable
{
    BPRoadTypesLabel *roads = (BPRoadTypesLabel *)[self viewWithIdentifier:@"routeRoadTypes" in:self.content];
    [self makeRoute];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(roads.stringValue.length > 0); }));
    XCTAssertFalse(roads.isSelectable);
    XCTAssertFalse(roads.isEditable);
    [roads.window makeFirstResponder:roads];
    XCTAssertNil(roads.currentEditor, @"no field editor over the label");
}

// Info section: in a scroll view (it grows), with the distance by road type of the route (#53)
- (void)testInfoShowsDistanceByRoadType
{
    NSTextField *roads = (NSTextField *)[self viewWithIdentifier:@"routeRoadTypes" in:self.content];
    XCTAssertNotNil(roads);
    NSView *length = [self panelControlWithIdentifier:@"routeLength"];
    XCTAssertNotNil(roads.enclosingScrollView, @"Info section in a scroll view");
    XCTAssertEqual(length.enclosingScrollView, roads.enclosingScrollView, @"existing Info fields in the same scroll view");
    XCTAssertEqualObjects(roads.stringValue, @"", @"no route");
    [self makeRoute];
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(roads.stringValue.length > 0); }));
    // stub route: half tertiary / asphalt, half track / gravel
    XCTAssertTrue([roads.stringValue containsString:NSLocalizedString(@"Tertiary roads", nil)], @"%@", roads.stringValue);
    XCTAssertTrue([roads.stringValue containsString:NSLocalizedString(@"Tracks", nil)], @"%@", roads.stringValue);
    XCTAssertTrue([roads.stringValue containsString:@"km"]);
}

- (void)testRoutingErrorKeepsPreviousRoute
{
    [self makeRoute];
    server.failCount = 1;
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.65)];
    BPSpin(1.0);
    XCTAssertEqual(doc.plan.waypointsLocations.count, 3u);
    XCTAssertEqual(doc.plan.routePoints.count, 11u, @"route unchanged after a failed request");
    // the user is told (#9): BRouter's message on the map
    NSTextField *help = (NSTextField *)[self viewWithIdentifier:@"clickModeHelp" in:self.content];
    XCTAssertEqualObjects(help.stringValue, @"Routing failed: stub failure");
}

// a slow answer to an older request does not overwrite the newer route (#9)
- (void)testStaleRouteAnswerIgnored
{
    [self makeRoute];
    server.responseDelay = 0.6;
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.65)];  // 3 waypoints, slow answer
    server.responseDelay = 0;
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.05, 0.7)];  // 4 waypoints, fast answer
    XCTAssertTrue([self waitForRouteWithPoints:31]);
    BPSpin(1.0);
    XCTAssertEqual(doc.plan.routePoints.count, 31u, @"the route of the last request");
}

- (void)testImportReferenceTrace
{
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-ref.gpx"]];
    XCTAssertTrue([BPData(kBRouterGPX) writeToURL:url atomically:YES]);
    [mc loadGPXFromURL:url];
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 3u);
    XCTAssertEqual([self polysWithTag:2].count, 1u);
    XCTAssertEqual([self polysWithTag:2].firstObject.pointCount, 3u);
    // importing again replaces the trace
    [mc loadGPXFromURL:url];
    XCTAssertEqual([self polysWithTag:2].count, 1u);
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

// File ▸ Remove Displayed GPX Trace (#24): removes the reference trace, undoable, disabled without a trace
- (void)testRemoveReferenceTrace
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(removeGPXTraceForDisplay:) keyEquivalent:@""];
    XCTAssertFalse([doc validateMenuItem:item], @"disabled without a trace");
    XCTAssertEqual([self polysWithTag:2].count, 0u, @"no empty trace overlay");

    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-ref-rm.gpx"]];
    XCTAssertTrue([BPData(kBRouterGPX) writeToURL:url atomically:YES]);
    NSUndoManager *um = doc.undoManager;
    um.groupsByEvent = NO;
    [um beginUndoGrouping];
    [mc loadGPXFromURL:url];
    [um endUndoGrouping];
    XCTAssertTrue([doc validateMenuItem:item]);
    [doc updateChangeCount:NSChangeCleared];

    [um beginUndoGrouping];
    [doc removeGPXTraceForDisplay:item];
    [um endUndoGrouping];
    BPSpin(0.1); // NSDocument updates its edited state asynchronously
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 0u);
    XCTAssertEqual([self polysWithTag:2].count, 0u);
    XCTAssertTrue(BPWaitUntil(2, ^{ return self->doc.isDocumentEdited; }), @"document edited (updated asynchronously by NSDocument)");
    XCTAssertFalse([doc validateMenuItem:item]);

    XCTAssertEqualObjects(um.undoActionName, @"remove trace");
    [um undo];
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 3u);
    XCTAssertEqual([self polysWithTag:2].count, 1u);
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

- (void)testImportInvalidTraceIsIgnored
{
    NSURL *missing = [NSURL fileURLWithPath:@"/nonexistent/bp.gpx"];
    [mc loadGPXFromURL:missing];
    NSURL *bad = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-bad.gpx"]];
    XCTAssertTrue([BPData(@"<gpx><trk>") writeToURL:bad atomically:YES]);
    [mc loadGPXFromURL:bad];
    XCTAssertEqual(doc.plan.gpxDisplayed.count, 0u);
    XCTAssertFalse(doc.undoManager.canUndo);
    [[NSFileManager defaultManager] removeItemAtURL:bad error:NULL];
}

- (void)testExportOfInvalidGPXReturnsRaw
{
    mc.gpxData = BPData(@"<gpx>no end");
    XCTAssertEqualObjects([mc exportGpxDataWithPOI:YES trackName:nil], mc.gpxData);
}

- (void)testGestureIgnoredOnOpenCallout
{
    NSEvent *e = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(5, 5) modifierFlags:0 timestamp:0
                                windowNumber:map.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    XCTAssertTrue([mc gestureRecognizer:nil shouldAttemptToRecognizeWithEvent:e]);
    NSView *callout = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
    [map.window.contentView addSubview:callout];
    mc.activeCalloutView = callout;
    XCTAssertFalse([mc gestureRecognizer:nil shouldAttemptToRecognizeWithEvent:e]);
    mc.activeCalloutView = nil;
    [callout removeFromSuperview];
}

- (void)testSelectDeselectAnnotationTracksCallout
{
    [self makeRoute];
    [self waitForPOIs];
    POIAnnotation *poi = [self annotationsOfClass:[POIAnnotation class]].firstObject;
    MKAnnotationView *v = [mc mapView:map viewForAnnotation:poi];
    [mc mapView:map didSelectAnnotationView:v];
    XCTAssertEqual(mc.activeCalloutView, v.detailCalloutAccessoryView);
    [mc mapView:map didDeselectAnnotationView:v];
    XCTAssertNil(mc.activeCalloutView);
}

- (void)testSafeTileRenderer
{
    SafeOSMTileOverlay *o = [[SafeOSMTileOverlay alloc] initWithURLTemplate:@"http://127.0.0.1:1/{z}/{x}/{y}.png"];
    XCTAssertTrue([[mc mapView:map rendererForOverlay:o] isKindOfClass:[SafeTileRenderer class]]);
}

// tiles are fetched by the overlay with the app's User-Agent (OSM tile usage policy); an HTTP error gives no data
- (void)testTileRequestUserAgent
{
    NSString *template = [server.baseURL.absoluteString stringByAppendingString:@"/tiles/{z}/{x}/{y}.png"];
    SafeOSMTileOverlay *o = [[SafeOSMTileOverlay alloc] initWithURLTemplate:template];
    MKTileOverlayPath path = { .x = 3, .y = 5, .z = 4, .contentScaleFactor = 1 };
    __block BOOL done = NO;
    __block NSData *tile = nil;
    __block NSError *error = nil;
    [o loadTileAtPath:path result:^(NSData *d, NSError *e) { tile = d; error = e; done = YES; }];
    XCTAssertTrue(BPWaitUntil(5, ^BOOL{ return done; }));
    BPStubRequest *r = [server requestsWithPath:@"/tiles/4/3/5.png"].firstObject;
    XCTAssertEqualObjects(r.userAgent, [BPEnvironment userAgent]);
    XCTAssertNil(tile, @"the stub answers 404");
    XCTAssertNotNil(error);
}

- (void)testDistanceBeyondRouteEnd
{
    [self makeRoute];
    NSUInteger seg = 0;
    double d = [mc distanceAtCoordinate:CLLocationCoordinate2DMake(45.0, 1.5) segstart:&seg];
    XCTAssertEqual(seg, 10u);
    XCTAssertGreaterThan(d, 10000);
}

- (void)testDragOfNonWaypointIsIgnored
{
    MKPointAnnotation *a = [[MKPointAnnotation alloc] init];
    MKAnnotationView *v = [[MKAnnotationView alloc] initWithAnnotation:a reuseIdentifier:nil];
    [mc mapView:map annotationView:v didChangeDragState:MKAnnotationViewDragStateEnding fromOldState:MKAnnotationViewDragStateDragging];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 0u);
}

#pragma mark - location search (#40)

- (NSSearchField *)searchField
{
    for (NSToolbarItem *item in doc.windowControllers.firstObject.window.toolbar.items) {
        if ([item isKindOfClass:[NSSearchToolbarItem class]]) return ((NSSearchToolbarItem *)item).searchField;
    }
    return nil;
}

static MKMapItem *BPPlace(NSString *name, double lat, double lon)
{
    MKMapItem *item = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)]];
    item.name = name;
    return item;
}

- (void)search:(NSString *)query results:(NSArray<MKMapItem *> *)results
{
    [BPPlaceSearch setSearchHandlerForTesting:^(NSString *q, MKCoordinateRegion region, BPPlaceSearchCompletion done) {
        done(results, nil);
    }];
    NSSearchField *f = [self searchField];
    f.stringValue = query;
    [mc sendersearchFieldAction:f];
    BPSpin(0.3); // completion on the main queue; the tests then wait for their own effect
}

- (NSArray<MKPointAnnotation *> *)searchPins
{
    return [self annotationsOfClass:[BPSearchPinAnnotation class]];
}

// one result: the map goes there, with a single pin (replaced by the next search, removed by clearing the field)
- (void)testSearchSingleResult
{
    [self search:@"Agen" results:@[ BPPlace(@"Agen", 44.2033, 0.6163) ]];
    XCTAssertTrue(BPWaitUntil(3, ^{ return (BOOL)(fabs(self->map.centerCoordinate.latitude - 44.2033) < 0.01); }));
    XCTAssertEqual([self searchPins].count, 1u);
    XCTAssertEqualObjects([self searchPins].firstObject.title, @"Agen");
    [self search:@"Nérac" results:@[ BPPlace(@"Nérac", 44.136, 0.339) ]];
    XCTAssertEqual([self searchPins].count, 1u, @"one pin at a time");
    XCTAssertEqualObjects([self searchPins].firstObject.title, @"Nérac");
    [self search:@"" results:@[]];
    XCTAssertEqual([self searchPins].count, 0u, @"cleared search field: pin removed");
    [BPPlaceSearch setSearchHandlerForTesting:nil];
}

// several results: proposed in a menu (name, place, distance), the chosen one is shown
- (void)testSearchSeveralResults
{
    __block NSMenu *shown = nil;
    mc.presentSearchResultsMenu = ^(NSMenu *menu, NSView *view) { shown = menu; };
    [self search:@"Valence" results:@[ BPPlace(@"Valence", 44.93, 4.89), BPPlace(@"Valence", 44.11, 0.89) ]];
    XCTAssertEqual(shown.itemArray.count, 2u);
    XCTAssertTrue([shown.itemArray[1].title containsString:@"km"], @"%@", shown.itemArray[1].title);
    XCTAssertEqual([self searchPins].count, 0u, @"nothing chosen yet");
    NSMenuItem *choice = shown.itemArray[1];
    [NSApp sendAction:choice.action to:choice.target from:choice];
    XCTAssertTrue(BPWaitUntil(3, ^{ return (BOOL)(fabs(self->map.centerCoordinate.longitude - 0.89) < 0.01); }));
    XCTAssertEqual([self searchPins].count, 1u);
    [BPPlaceSearch setSearchHandlerForTesting:nil];
}

// no result / error: a message instead of nothing
- (void)testSearchNoResultMessage
{
    NSTextField *help = (NSTextField *)[self viewWithIdentifier:@"clickModeHelp" in:self.content];
    NSString *before = help.stringValue;
    [self search:@"Xyzzy" results:@[]];
    XCTAssertTrue([help.stringValue containsString:@"Xyzzy"], @"%@", help.stringValue);
    XCTAssertTrue(BPWaitUntil(6, ^{ return [help.stringValue isEqualToString:before]; }), @"help text back");
    [BPPlaceSearch setSearchHandlerForTesting:nil];
}

// completions while typing (MKLocalSearchCompleter results), for the field editor's completion list: they replace
// the word being typed
- (void)testSearchCompletions
{
    NSSearchField *f = [self searchField];
    XCTAssertEqual(f.delegate, (id)mc);
    [mc setSearchCompletionTitles:@[ @"Valence, Drôme, France", @"Valence d'Agen, Tarn-et-Garonne, France", @"Vals-les-Bains, France" ]];
    NSArray *c = [mc completionsForText:@"Valence" partialWordRange:NSMakeRange(0, 7)];
    XCTAssertEqualObjects(c, (@[ @"Valence, Drôme, France", @"Valence d'Agen, Tarn-et-Garonne, France" ]));
    c = [mc completionsForText:@"Valence d" partialWordRange:NSMakeRange(8, 1)];
    XCTAssertEqualObjects(c, (@[ @"d'Agen, Tarn-et-Garonne, France" ]), @"replaces the partial word only");
}

- (void)testSearchWithEmptyQueryDoesNothing
{
    NSSearchField *f = [[NSSearchField alloc] init];
    f.stringValue = @"";
    XCTAssertNoThrow([mc sendersearchFieldAction:f]);
}

- (void)testExportWithoutRouteDoesNothing
{
    XCTAssertNil(mc.gpxData);
    XCTAssertNoThrow([mc exportGPX:self]); // returns before opening the panel
}

@end
