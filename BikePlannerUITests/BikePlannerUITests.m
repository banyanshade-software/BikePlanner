//
//  BikePlannerUITests.m
//  BikePlannerUITests
//
//  End-to-end tests of the document window, offline (see BPUITestCase).
//

#import "BPUITestCase.h"

@interface BikePlannerUITests : BPUITestCase
@end

static BOOL BPWaitWindows(XCUIApplication *app, NSUInteger n)
{
    for (int i = 0; i < 30 && app.windows.count < n; i++) [NSThread sleepForTimeInterval:0.1];
    return app.windows.count >= n;
}

@implementation BikePlannerUITests

#pragma mark - window

- (void)testLaunchShowsDocumentWindow
{
    XCTAssertTrue(self.map.exists);
    XCTAssertTrue([self elementWithIdentifier:@"clickMode"].exists);
    XCTAssertTrue([self elementWithIdentifier:@"mapType"].exists);
    XCTAssertTrue([self elementWithIdentifier:@"zoomIn"].exists);
    XCTAssertTrue([self elementWithIdentifier:@"zoomOut"].exists);
    XCTAssertEqualObjects([self elementWithIdentifier:@"clickModeHelp"].value,
                          @"Click on map to add start and end waypoints");
    // BRF profile downloaded for the Params tab, from the stub server
    XCTAssertTrue([self waitForRequests:@"/brouter/profiles2/trekking.brf" count:1 timeout:10]);
}

- (void)testClickModeControlAndMenu
{
    XCUIElement *help = [self elementWithIdentifier:@"clickModeHelp"];
    [self clickSegment:@"Add interm." of:@"clickMode"];
    XCTAssertEqualObjects(help.value, @"Click on path to add intermediate waypoints");
    [self clickSegment:@"Add POI" of:@"clickMode"];
    XCTAssertEqualObjects(help.value, @"Add POI");
    [self clickMenu:@"Edit" item:@"Mode: View/Drag"];
    XCTAssertEqualObjects(help.value, @"Drag waypoints");
    [self clickMenu:@"Edit" item:@"Mode: Edit"];
    XCTAssertEqualObjects(help.value, @"Click on map to add start and end waypoints");
}

- (void)testMapTypeControl
{
    for (NSString *label in @[@"Apple", @"Sat+Rd", @"Sat", @"OSM+cycle", @"OSM"]) {
        [self clickSegment:label of:@"mapType"];
    }
    XCTAssertTrue(self.map.exists);
}

- (void)testAboutWindow
{
    NSUInteger before = self.app.windows.count;
    [self clickMenu:@"BikePlanner" item:@"About BikePlanner"];
    XCTAssertTrue(BPWaitWindows(self.app, before + 1));
}

#pragma mark - route building

- (void)testBuildRouteByClicking
{
    [self clickMapAt:CGVectorMake(0.30, 0.30)];
    [NSThread sleepForTimeInterval:1.0];
    XCTAssertEqual([self.server requestsWithPath:@"/brouter"].count, 0u, @"no route with one waypoint");

    [self clickMapAt:CGVectorMake(0.70, 0.45)];
    XCTAssertTrue([self waitForRequests:@"/brouter" count:1 timeout:10]);
    XCTAssertEqual([self lastRouteWaypointCount], 2u);
    XCUIElement *km = [self elementWithIdentifier:@"routeLength"];
    XCTAssertTrue([self waitForElement:km valueNot:@"...." timeout:10]);
    XCTAssertGreaterThan([km.value integerValue], 0);
    XCTAssertTrue([self waitForElement:[self elementWithIdentifier:@"routeAscent"] valueNot:@"...." timeout:5]);

    // POIs are fetched along the new route
    XCTAssertTrue([self waitForRequests:@"/api/interpreter" count:1 timeout:10]);
}

- (void)testAppendDestination
{
    [self buildRoute];
    [self clickMapAt:CGVectorMake(0.75, 0.25)];
    XCTAssertTrue([self waitForRequests:@"/brouter" count:2 timeout:10]);
    XCTAssertEqual([self lastRouteWaypointCount], 3u);
}

- (void)testInsertIntermediateWaypointOnRoute
{
    [self buildRoute];
    [self clickSegment:@"Add interm." of:@"clickMode"];
    // the stub route is a straight line between the two clicks: click in the middle
    [self clickMapAt:CGVectorMake(0.50, 0.375)];
    XCTAssertTrue([self waitForRequests:@"/brouter" count:2 timeout:10]);
    XCTAssertEqual([self lastRouteWaypointCount], 3u);
}

- (void)testUndoRedoDestination
{
    [self buildRoute];
    XCTAssertTrue([self menu:@"Edit" hasItem:@"Undo add destination"]);
    [self clickMenu:@"Edit" item:@"Undo add destination"];
    XCTAssertTrue([self menu:@"Edit" hasItem:@"Redo add destination"]);
    [self clickMenu:@"Edit" item:@"Redo add destination"];
    // redo recomputes the route with both waypoints
    XCTAssertTrue([self waitForRequests:@"/brouter" count:2 timeout:10]);
    XCTAssertEqual([self lastRouteWaypointCount], 2u);
}

- (void)testRemoveWaypointWithContextMenu
{
    [self buildRoute];
    [self clickMapAt:CGVectorMake(0.75, 0.25)];
    XCTAssertTrue([self waitForRequests:@"/brouter" count:2 timeout:10]);
    // right-click on the pin of the second waypoint (pin head is above the point)
    [self rightClickMapAt:CGVectorMake(0.70, 0.45) dy:-15];
    XCUIElement *remove = self.app.menuItems[@"Remove Waypoint"];
    XCTAssertTrue([remove waitForExistenceWithTimeout:3]);
    [remove click];
    XCTAssertTrue([self waitForRequests:@"/brouter" count:3 timeout:10]);
    XCTAssertEqual([self lastRouteWaypointCount], 2u);
    XCTAssertTrue([self menu:@"Edit" hasItem:@"Undo remove waypoint"]);
}

- (void)testAddCustomPOI
{
    [self buildRoute];
    [self clickSegment:@"Add POI" of:@"clickMode"];
    [self clickMapAt:CGVectorMake(0.50, 0.375)];
    // the type / name sheet (#3)
    XCUIElement *add = self.window.sheets.firstMatch.buttons[@"Add"];
    XCTAssertTrue([add waitForExistenceWithTimeout:5]);
    [add click];
    XCTAssertTrue([self menu:@"Edit" hasItem:@"Undo add POI"]);
}

// A click on a POI selects it instead of adding a destination (Edit mode).
// The stub places a water POI ~1 km (~24 px at the initial zoom) north of the route start.
- (void)testClickOnPOIDoesNotAddDestination
{
    [self buildRoute];
    XCTAssertTrue([self waitForRequests:@"/api/interpreter" count:1 timeout:10]);
    [NSThread sleepForTimeInterval:1.5];
    [[[self.map coordinateWithNormalizedOffset:CGVectorMake(0.30, 0.30)] coordinateWithOffset:CGVectorMake(0, -24)] click];
    [NSThread sleepForTimeInterval:2.0];
    XCTAssertEqual([self.server requestsWithPath:@"/brouter"].count, 1u, @"click on a POI must not add a destination");

    // control: the same click far from any POI adds a destination
    [self clickMapAt:CGVectorMake(0.75, 0.25)];
    XCTAssertTrue([self waitForRequests:@"/brouter" count:2 timeout:10]);
}

#pragma mark - parameters

- (void)testProfileOverrideRecomputesRoute
{
    [self buildRoute];
    [self.window.tabs[@"Params"] click];
    XCUIElement *cost = self.window.textFields[@"brf.downhillcost"];
    XCTAssertTrue([cost waitForExistenceWithTimeout:5]);
    XCUIElement *apply = self.window.buttons[@"Apply"];
    XCTAssertFalse(apply.isEnabled, @"nothing changed yet (#39)");
    [cost doubleClick];
    [cost typeKey:@"a" modifierFlags:XCUIKeyModifierCommand];
    [cost typeText:@"80"];
    [apply click];
    XCTAssertTrue([self waitForRequests:@"/brouter" count:2 timeout:10]);
    NSString *value = [self.server requestsWithPath:@"/brouter"].lastObject.query[@"profile:downhillcost"];
    XCTAssertEqualObjects(value, @"80", @"one profile:<name> parameter per override (#15, #35)");
}

// "Fetch POI" and "View POI" (Info section) are displayed as switches
- (void)testPOISwitches
{
    XCUIElement *fetch = [self.window.switches elementBoundByIndex:0];
    XCUIElement *view = [self.window.switches elementBoundByIndex:1];
    XCTAssertTrue(fetch.exists);
    XCTAssertTrue(view.exists);
    XCTAssertEqualObjects(fetch.value, @1);
    XCTAssertEqualObjects(view.value, @1);

    // no POI request when fetching is off
    [fetch click];
    XCTAssertEqualObjects(fetch.value, @0);
    [self buildRoute];
    [NSThread sleepForTimeInterval:2.0];
    XCTAssertEqual([self.server requestsWithPath:@"/api/interpreter"].count, 0u);
    // switching it back on fetches the POIs
    [fetch click];
    XCTAssertTrue([self waitForRequests:@"/api/interpreter" count:1 timeout:10]);

    [view click];
    XCTAssertEqualObjects(view.value, @0);
    [view click];
    XCTAssertEqualObjects(view.value, @1);
}

#pragma mark - files

- (NSString *)tempDir
{
    // shared with the app: the runner sandbox allows read-write in /private/tmp (see entitlements)
    NSString *d = [@"/private/tmp/bp-uitests" stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL];
    return d;
}

// In an open/save panel: go to a folder or file with Cmd-Shift-G
- (void)goToPath:(NSString *)path
{
    [self.app typeKey:@"g" modifierFlags:XCUIKeyModifierCommand | XCUIKeyModifierShift];
    [NSThread sleepForTimeInterval:0.5];
    [self.app typeText:path];
    [self.app typeKey:XCUIKeyboardKeyReturn modifierFlags:0];
    [NSThread sleepForTimeInterval:0.8];
}

- (void)testExportGPXWithPOI
{
    [self buildRoute];
    XCTAssertTrue([self waitForRequests:@"/api/interpreter" count:1 timeout:10]);
    [NSThread sleepForTimeInterval:1.0];
    NSString *dir = [self tempDir];

    [self clickMenu:@"File" item:@"Export to GPX"];
    XCUIElement *panel = self.app.windows[@"Export GPX route"];
    if (![panel waitForExistenceWithTimeout:5]) panel = self.app.sheets.firstMatch;
    XCUIElement *poi = panel.checkBoxes[@"Include POI"];
    XCTAssertTrue([poi waitForExistenceWithTimeout:5]);
    XCTAssertEqualObjects(poi.value, @1, @"Include POI is checked by default");
    [self goToPath:dir];
    [self.app typeKey:@"a" modifierFlags:XCUIKeyModifierCommand];
    [self.app typeText:@"uitest\n"];

    NSString *file = [dir stringByAppendingPathComponent:@"uitest.gpx"];
    for (int i = 0; i < 50 && ![[NSFileManager defaultManager] fileExistsAtPath:file]; i++) [NSThread sleepForTimeInterval:0.1];
    NSString *gpx = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertTrue([gpx containsString:@"<name>uitest</name>"]);
    XCTAssertTrue([gpx containsString:@"<trkpt"]);
    XCTAssertTrue([gpx containsString:@"<type>WATER</type>"]);
}

- (void)testImportReferenceTrace
{
    NSString *dir = [self tempDir];
    NSString *file = [dir stringByAppendingPathComponent:@"ref.gpx"];
    [[BPStubServer gpxForLonLats:@"0.5,44.0|0.6,44.1"] writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    [self clickMenu:@"File" item:@"Import GPX as display"];
    [NSThread sleepForTimeInterval:1.0];
    [self goToPath:file];
    [self.app typeKey:XCUIKeyboardKeyReturn modifierFlags:0];
    [NSThread sleepForTimeInterval:1.0];
    XCTAssertTrue([self menu:@"Edit" hasItem:@"Undo import trace"]);
}

@end
