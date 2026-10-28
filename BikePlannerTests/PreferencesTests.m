//
//  PreferencesTests.m
//  BikePlannerTests
//
//  BPPreferences and the Preferences window (#27). The preferences under test use a private suite (never the
//  owner's defaults); the place search is replaced (offline).
//

#import <XCTest/XCTest.h>
#import "BPPreferences.h"
#import "BPPreferencesWindowController.h"
#import "BPPlaceSearch.h"
#import "AppDelegate.h"
#import "TestFixtures.h"

@interface BPPreferencesWindowController (Testing)
@property (strong) NSTextField *latitudeField;
@property (strong) NSTextField *longitudeField;
@property (strong) NSTextField *radiusField;
@property (strong) NSSearchField *searchField;
@property (strong) NSTextField *messageLabel;
- (void)positionChanged:(id)sender;
- (void)radiusChanged:(id)sender;
- (void)useMapCenter:(id)sender;
- (void)search:(NSSearchField *)sender;
@end

@interface AppDelegate (Testing)
@property (nonatomic, strong) BPPreferencesWindowController *preferencesWindowController;
@end

static MKMapItem *BPItem(NSString *name, double lat, double lon)
{
    MKMapItem *item = [[MKMapItem alloc] initWithPlacemark:
                       [[MKPlacemark alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)]];
    item.name = name;
    return item;
}

@interface PreferencesTests : XCTestCase
@end

@implementation PreferencesTests {
    NSString *suite;
    NSUserDefaults *defaults;
    BPPreferences *prefs;
    BPPreferencesWindowController *wc;
}

- (void)setUp
{
    suite = [NSString stringWithFormat:@"PreferencesTests.%@", NSUUID.UUID.UUIDString];
    defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    prefs = [[BPPreferences alloc] initWithUserDefaults:defaults];
}

- (void)tearDown
{
    [wc close];
    [BPPlaceSearch setSearchHandlerForTesting:nil];
    [defaults removePersistentDomainForName:suite];
}

- (BPPreferencesWindowController *)window
{
    wc = [[BPPreferencesWindowController alloc] initWithPreferences:prefs];
    (void)wc.window;
    return wc;
}

#pragma mark - BPPreferences

- (void)testRegisteredDefaults
{
    [BPPreferences registerDefaults];
    NSDictionary *reg = [[NSUserDefaults standardUserDefaults] volatileDomainForName:NSRegistrationDomain];
    XCTAssertEqualObjects(reg[BPDefaultPositionKey], @"44.124923,0.496171");
    XCTAssertEqualObjects(reg[BPInitialRadiusKmKey], @80);
    XCTAssertEqualObjects(BPDefaultPositionKey, @"BPDefaultPosition", @"the key read by BPEnvironment");
    XCTAssertEqualObjects(BPInitialRadiusKmKey, @"BPInitialRadiusKm");
}

- (void)testAccessors
{
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.latitude, 44.1249234, 1e-6, @"default when unset");
    XCTAssertEqual(prefs.initialRadiusKm, 80);
    prefs.defaultPosition = CLLocationCoordinate2DMake(45.5, 1.25);
    prefs.initialRadiusKm = 30;
    XCTAssertEqualObjects([defaults stringForKey:@"BPDefaultPosition"], @"45.500000,1.250000", @"format read by BPEnvironment");
    XCTAssertEqual([defaults doubleForKey:@"BPInitialRadiusKm"], 30);
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.longitude, 1.25, 1e-9);
    // invalid values are ignored
    prefs.defaultPosition = CLLocationCoordinate2DMake(100, 0);
    prefs.initialRadiusKm = 0;
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.latitude, 45.5, 1e-9);
    XCTAssertEqual(prefs.initialRadiusKm, 30);
}

#pragma mark - window

- (void)testFieldsShowAndChangePreferences
{
    prefs.defaultPosition = CLLocationCoordinate2DMake(45.5, 1.25);
    [self window];
    XCTAssertEqualWithAccuracy(wc.latitudeField.doubleValue, 45.5, 1e-9);
    XCTAssertEqualWithAccuracy(wc.longitudeField.doubleValue, 1.25, 1e-9);
    XCTAssertEqual(wc.radiusField.doubleValue, 80);

    wc.latitudeField.objectValue = @43.6;
    [wc positionChanged:wc.latitudeField];
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.latitude, 43.6, 1e-9, @"applied at once");
    wc.radiusField.objectValue = @25;
    [wc radiusChanged:wc.radiusField];
    XCTAssertEqual(prefs.initialRadiusKm, 25);

    // an invalid latitude gives back the saved one
    wc.latitudeField.objectValue = @123;
    [wc positionChanged:wc.latitudeField];
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.latitude, 43.6, 1e-9);
    XCTAssertEqualWithAccuracy(wc.latitudeField.doubleValue, 43.6, 1e-9);
}

- (void)testUseMapCenter
{
    [self window];
    wc.mapCenterProvider = ^BOOL(CLLocationCoordinate2D *c) { *c = CLLocationCoordinate2DMake(46.2, 2.3); return YES; };
    [wc useMapCenter:nil];
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.latitude, 46.2, 1e-9);
    XCTAssertEqualWithAccuracy(wc.longitudeField.doubleValue, 2.3, 1e-9);

    wc.mapCenterProvider = ^BOOL(CLLocationCoordinate2D *c) { return NO; };
    [wc useMapCenter:nil];
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.latitude, 46.2, 1e-9, @"unchanged without a map");
    XCTAssertTrue([wc.messageLabel.stringValue containsString:@"No map"]);
}

// runs a search answered with results; waits until the result is handled (completion on the main queue)
- (void)searchFor:(NSString *)query results:(NSArray<MKMapItem *> *)results until:(BOOL (^)(void))handled
{
    [BPPlaceSearch setSearchHandlerForTesting:^(NSString *q, MKCoordinateRegion region, BPPlaceSearchCompletion done) {
        XCTAssertEqualObjects(q, query);
        done(results, nil);
    }];
    wc.searchField.stringValue = query;
    [wc search:wc.searchField];
    XCTAssertTrue(BPWaitUntil(3, handled), @"search %@ handled", query);
}

// search: one result is used at once, several are proposed in a menu, none gives a message
- (void)testSearchPlace
{
    [self window];
    __block NSMenu *shown = nil;
    wc.presentResultsMenu = ^(NSMenu *menu, NSView *view) { shown = menu; };

    [self searchFor:@"Agen" results:@[ BPItem(@"Agen", 44.2033, 0.6163) ]
              until:^BOOL{ return fabs(self->prefs.defaultPosition.latitude - 44.2033) < 1e-6; }];
    XCTAssertNil(shown);
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.latitude, 44.2033, 1e-6);

    [self searchFor:@"Valence" results:@[ BPItem(@"Valence (Drôme)", 44.93, 4.89), BPItem(@"Valence (Tarn-et-Garonne)", 44.11, 0.89),
                                          BPItem(@"Valence-d'Albigeois", 44.02, 2.40) ]
              until:^BOOL{ return shown != nil; }];
    XCTAssertEqual(shown.itemArray.count, 3u);
    XCTAssertTrue([shown.itemArray[1].title hasPrefix:@"Valence (Tarn-et-Garonne)"]);
    NSMenuItem *choice = shown.itemArray[1];
    [NSApp sendAction:choice.action to:choice.target from:choice];
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.latitude, 44.11, 1e-6);

    [self searchFor:@"Nowhere" results:@[]
              until:^BOOL{ return [self->wc.messageLabel.stringValue containsString:@"Nowhere"]; }];
    XCTAssertTrue([wc.messageLabel.stringValue containsString:@"Nowhere"]);
    XCTAssertEqualWithAccuracy(prefs.defaultPosition.latitude, 44.11, 1e-6);
}

// BikePlanner ▸ Preferences… opens a single window
- (void)testMenuOpensSingleWindow
{
    AppDelegate *app = (AppDelegate *)NSApp.delegate;
    XCTAssertTrue([app respondsToSelector:@selector(showPreferences:)]);
    [app showPreferences:nil];
    BPPreferencesWindowController *first = app.preferencesWindowController;
    XCTAssertNotNil(first);
    XCTAssertTrue(first.window.isVisible);
    [app showPreferences:nil];
    XCTAssertEqual(app.preferencesWindowController, first);
    [first close];

    NSMenuItem *item = nil;
    for (NSMenuItem *i in NSApp.mainMenu.itemArray.firstObject.submenu.itemArray) if ([i.keyEquivalent isEqualToString:@","]) item = i;
    XCTAssertEqual(item.action, @selector(showPreferences:), @"menu item connected (MainMenu.xib)");
}

@end
