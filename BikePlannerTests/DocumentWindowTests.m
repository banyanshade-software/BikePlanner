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
#import "SafeTileRenderer.h"
#import "StreetViewController.h"
#import "GPXParser.h"
#import "TestFixtures.h"

@interface MapController (WindowTesting)
- (void)handleMapClick:(NSGestureRecognizer *)gesture;
- (void)addCustomPoiAt:(CLLocationCoordinate2D)coord;
- (void)userLocationAvailable:(nullable CLLocation *)loc;
- (void)changeMapType:(id)sender;
- (void)changeClickMode:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (void)removeWaypointMenuAction:(id)sender;
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
    return [map.overlays filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) {
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

    [mc setClickModeToInterm:nil];
    XCTAssertEqual(seg.selectedSegment, 1);
    XCTAssertEqualObjects(help.stringValue, @"Click on path to add intermediate waypoints");
    [mc setClickModeToAddPoi:nil];
    XCTAssertEqual(seg.selectedSegment, 2);
    XCTAssertEqualObjects(help.stringValue, @"Add POI");
    [mc setClickModeToView:nil];
    XCTAssertEqual(seg.selectedSegment, 3);
    XCTAssertEqualObjects(help.stringValue, @"Drag waypoints");
    [mc setClickModeToEdit:nil];
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
    [mc setClickModeToInterm:nil];
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
    [mc setClickModeToInterm:nil];
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.6)];
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u);
}

- (void)testViewModeClickOnRoute
{
    [self makeRoute];
    [mc setClickModeToView:nil];
    CLLocationCoordinate2D c = doc.plan.routePoints[3].coordinate;
    [self clickAtCoordinate:c];
    BPSpin(0.2);
    XCTAssertEqual(doc.plan.waypointsLocations.count, 2u);
    XCTAssertGreaterThan(mc.elevationView.highlightDistance, 0);
    XCTAssertEqualWithAccuracy(map.centerCoordinate.latitude, c.latitude, 0.005);
}

- (void)testAddPOIModeAddsCustomPOI
{
    [self makeRoute];
    doc.plan.fetchPOI = NO;
    [mc setClickModeToAddPoi:nil];
    [self clickAtCoordinate:doc.plan.routePoints[4].coordinate];
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);
    XCTAssertGreaterThanOrEqual([self annotationsOfClass:[POIAnnotation class]].count, 1u);
    // away from the route: nothing
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.6)];
    XCTAssertEqual(doc.plan.customPoiloc.count, 1u);
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
    BPOverrideDefaults(@{ @"BPInitialRegion": @"", @"BPDefaultPosition": @"45.0,1.0", @"BPDisableLocation": @YES });
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
    BPSpin(0.5);
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 44.5, 0.05);
    XCTAssertEqualWithAccuracy(map.region.center.longitude, 0.3, 0.05);
    XCTAssertTrue([self visibleKm] > 120 && [self visibleKm] < 260, @"%g km", [self visibleKm]);
    // later updates do not move the map
    [mc userLocationAvailable:[[CLLocation alloc] initWithLatitude:43.0 longitude:2.0]];
    BPSpin(0.3);
    XCTAssertEqualWithAccuracy(map.region.center.latitude, 44.5, 0.05);
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
    XCTAssertNil([mc mapView:map rendererForOverlay:[MKCircle circleWithCenterCoordinate:CLLocationCoordinate2DMake(0, 0) radius:1]]);
}

- (void)testElevationScrubbingMovesMap
{
    [self makeRoute];
    double total = mc.elevationView.distances.lastObject.doubleValue;
    [mc elevationProfileView:mc.elevationView didSelectDistance:total / 2];
    BPSpin(0.2);
    XCTAssertEqualWithAccuracy(map.centerCoordinate.latitude, 44.05, 0.005);
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

- (void)testRoutingErrorKeepsPreviousRoute
{
    [self makeRoute];
    server.failCount = 1;
    [self clickAtCoordinate:CLLocationCoordinate2DMake(44.0, 0.65)];
    BPSpin(1.0);
    XCTAssertEqual(doc.plan.waypointsLocations.count, 3u);
    XCTAssertEqual(doc.plan.routePoints.count, 11u, @"route unchanged after a failed request");
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

- (void)testSearchWithEmptyQueryDoesNothing
{
    NSSearchField *f = [[NSSearchField alloc] init];
    f.stringValue = @"";
    XCTAssertNoThrow([mc sendersearchFieldAction:f]);
}

- (void)testExportWithoutRouteDoesNothing
{
    XCTAssertNil(mc.gpxData);
    XCTAssertNoThrow([mc exportGPX:nil]); // returns before opening the panel
}

@end
