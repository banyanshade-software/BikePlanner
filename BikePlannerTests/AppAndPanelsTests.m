//
//  AppAndPanelsTests.m
//  BikePlannerTests
//
//  AppDelegate, About window, export accessory view, POI annotation views.
//

#import <XCTest/XCTest.h>
#import <MapKit/MapKit.h>
#import "AppDelegate.h"
#import "ExportAccessoryViewController.h"
#import "POIAnnotation.h"
#import "POIAnnotationView.h"
#import "POICalloutView.h"
#import "TestFixtures.h"

@interface AppDelegate (Testing)
- (NSWindowController *)aboutWindowController;
- (IBAction)showAboutWindow:(id)sender;
+ (NSString *)versionStringWithInfo:(NSDictionary *)info;
@end

@interface AppAndPanelsTests : XCTestCase
@end

@implementation AppAndPanelsTests

#pragma mark - AppDelegate

- (void)testAppDelegateIsInstalled
{
    XCTAssertTrue([NSApp.delegate isKindOfClass:[AppDelegate class]]);
}

- (void)testNoUntitledDocumentInUnitTestHost
{
    AppDelegate *ad = (AppDelegate *)NSApp.delegate;
    XCTAssertFalse([ad applicationShouldOpenUntitledFile:NSApp]);
    XCTAssertTrue([ad applicationSupportsSecureRestorableState:NSApp]);
}

- (void)testAboutWindow
{
    AppDelegate *ad = (AppDelegate *)NSApp.delegate;
    [ad showAboutWindow:nil];
    NSWindow *w = ad.aboutWindowController.window;
    XCTAssertNotNil(w);
    XCTAssertTrue(w.isVisible);
    ad.useTextView = YES;
    XCTAssertTrue(ad.useTextView);
    [w close];
}

// build number and git commit written into the built Info.plist by scripts/set_build_info.sh (#34)
- (void)testBuildInfoInBundle
{
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    XCTAssertGreaterThan([info[@"BPGitCommit"] length], 0u);
    XCTAssertGreaterThan([info[@"BPGitBranch"] length], 0u);
    XCTAssertGreaterThan([info[@"CFBundleVersion"] integerValue], 1, @"number of commits");
}

- (void)testAboutVersionString
{
    NSDictionary *info = @{ @"CFBundleShortVersionString": @"0.4.0", @"CFBundleVersion": @"123",
                            @"BPGitCommit": @"5a33d4f-dirty", @"BPGitBranch": @"small-features" };
    XCTAssertEqualObjects([AppDelegate versionStringWithInfo:info], @"Version 0.4.0 (Build 123, 5a33d4f-dirty, small-features)");
    info = @{ @"CFBundleShortVersionString": @"0.4.0", @"CFBundleVersion": @"1" };
    XCTAssertEqualObjects([AppDelegate versionStringWithInfo:info], @"Version 0.4.0 (Build 1)", @"no git info");

    AppDelegate *ad = (AppDelegate *)NSApp.delegate;
    NSString *v = [ad.aboutWindowController valueForKey:@"appVersion"];
    XCTAssertTrue([v containsString:NSBundle.mainBundle.infoDictionary[@"BPGitCommit"]], @"%@", v);
}

#pragma mark - export accessory

- (void)testExportAccessoryFormatSwitch
{
    ExportAccessoryViewController *vc = [[ExportAccessoryViewController alloc] initWithNibName:@"ExportAccessoryView" bundle:nil];
    (void)vc.view;
    XCTAssertNotNil(vc.poiCheckbox);
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"plan.gpx";
    vc.savePanel = panel;

    vc.outputFormatNum = 1;
    XCTAssertEqualObjects(panel.nameFieldStringValue, @"plan.fit");
    vc.outputFormatNum = 0;
    XCTAssertEqualObjects(panel.nameFieldStringValue, @"plan.gpx");
}

- (void)testExportAccessoryWithoutPanel
{
    ExportAccessoryViewController *vc = [[ExportAccessoryViewController alloc] initWithNibName:@"ExportAccessoryView" bundle:nil];
    vc.outputFormatNum = 1;
    XCTAssertEqual(vc.outputFormatNum, 1);
}

#pragma mark - POI annotation views

- (void)testIconsPerType
{
    PoiType_t types[] = { POI_drinking_water, POI_toilets, POI_cemetery, POI_bicycle_repair_station, POI_warning };
    for (int i = 0; i < 5; i++) {
        POIAnnotation *a = [[POIAnnotation alloc] init];
        a.poiType = types[i];
        a.coordinate = CLLocationCoordinate2DMake(44, 0.5);
        POIAnnotationView *v = [[POIAnnotationView alloc] initWithAnnotation:a reuseIdentifier:@"poi"];
        [a configureAnnotViewIcon:v];
        XCTAssertNotNil(v.glyphImage, @"type %d", types[i]);
        XCTAssertNotNil(v.markerTintColor, @"type %d", types[i]);
    }
}

- (void)testUnknownTypeHasNoIcon
{
    POIAnnotation *a = [[POIAnnotation alloc] init];
    a.poiType = POI_unknown;
    POIAnnotationView *v = [[POIAnnotationView alloc] initWithAnnotation:a reuseIdentifier:@"poi"];
    [a configureAnnotViewIcon:v];
    XCTAssertNil(v.glyphImage);
}

- (void)testCalloutShowsInfo
{
    POICalloutView *c = [[POICalloutView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    XCTAssertNotNil(c.excludeControl);
    XCTAssertEqual(c.excludeControl.segmentCount, 2);
    c.infodic = @{ @"amenity": @"toilets" };
    NSTextField *label = nil;
    for (NSView *v in c.subviews) if ([v isKindOfClass:[NSTextField class]]) label = (NSTextField *)v;
    XCTAssertTrue([label.stringValue containsString:@"toilets"]);
}

@end
