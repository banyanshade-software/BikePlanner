//
//  BPSiteEditorTests.m
//  BikePlannerTests
//
//  Start sites editor (#67). Compiled only with BP_SITE_EDITOR=1: run with scripts/build_site_editor.sh test.
//

#if BP_SITE_EDITOR

#import <XCTest/XCTest.h>
#import "BPSiteEditorController.h"
#import "TestFixtures.h"

// the map and Street View of a document window, recorded
@interface BPFakeSiteTarget : NSObject <BPSiteEditorTarget>
@property CLLocationCoordinate2D mapCenter;
@property (nonatomic) NSMutableArray<BPRemarkableSite *> *shown;
@property (nonatomic) NSMutableArray<NSArray<NSNumber *> *> *previews; // lat, lon, heading
@end

@implementation BPFakeSiteTarget
- (instancetype)init
{
    self = [super init];
    _shown = [NSMutableArray array];
    _previews = [NSMutableArray array];
    return self;
}
- (void)showSite:(BPRemarkableSite *)site { [self.shown addObject:site]; }
- (void)previewStreetViewAt:(CLLocationCoordinate2D)c heading:(double)heading
{
    [self.previews addObject:@[@(c.latitude), @(c.longitude), @(heading)]];
}
@end

@interface BPSiteEditorTests : XCTestCase
@end

@implementation BPSiteEditorTests {
    BPSiteEditorController *editor;
    BPFakeSiteTarget *target;
}

- (void)setUp
{
    editor = [[BPSiteEditorController alloc] initWithPropertyListData:[BPRemarkableSites bundledPropertyListData]];
    target = [[BPFakeSiteTarget alloc] init];
    target.mapCenter = CLLocationCoordinate2DMake(45.123456, 6.654321);
    BPFakeSiteTarget *t = target;
    editor.targetProvider = ^id<BPSiteEditorTarget> { return t; };
    (void)editor.window;
}

- (void)tearDown
{
    [editor.window close];
}

// the editor starts on the list of the app, unchanged: exported as is
- (void)testLoadsBundledList
{
    XCTAssertEqual(editor.entries.count, [BPRemarkableSites sites].count);
    XCTAssertEqualObjects(editor.entries[0][@"name"], @"Mont Ventoux");
    XCTAssertEqual(editor.selectedIndex, 0);
    XCTAssertFalse(editor.edited);
    XCTAssertEqualObjects(editor.problems, @[]);
    XCTAssertEqualObjects(editor.nameField.stringValue, @"Mont Ventoux");
    XCTAssertEqualObjects(editor.window.title, ([NSString stringWithFormat:@"Start Sites (%lu)", (unsigned long)editor.entries.count]));
    NSArray *exported = [NSPropertyListSerialization propertyListWithData:[editor exportData] options:0 format:NULL error:NULL];
    NSArray *bundled = [NSPropertyListSerialization propertyListWithData:[BPRemarkableSites bundledPropertyListData]
                                                                 options:0 format:NULL error:NULL];
    XCTAssertEqualObjects(exported, bundled);
    XCTAssertNotNil([BPRemarkableSites headerCommentOfPropertyListData:[editor exportData]], @"header kept");
}

// Add Here: a new site at the map center, after the selected one; it can be named, typed and shown
- (void)testAddSiteHere
{
    NSUInteger n = editor.entries.count;
    editor.selectedIndex = 2;
    [[editor buttonWithIdentifier:@"siteAdd"] performClick:self];
    XCTAssertEqual(editor.entries.count, n + 1);
    XCTAssertEqual(editor.selectedIndex, 3);
    NSDictionary *e = editor.entries[3];
    XCTAssertEqualWithAccuracy([e[@"latitude"] doubleValue], 45.12346, 1e-9, @"rounded to 1e-5° (~1 m)");
    XCTAssertEqualWithAccuracy([e[@"longitude"] doubleValue], 6.65432, 1e-9);
    XCTAssertEqualObjects(e[@"kind"], @"climb");
    XCTAssertTrue(editor.edited);
    XCTAssertTrue(editor.window.documentEdited);

    editor.nameField.stringValue = @"  Col de la Croix de Fer ";
    [editor.nameField sendAction:editor.nameField.action to:editor.nameField.target];
    [editor.kindPopUp selectItemWithTitle:@"nature"];
    [editor.kindPopUp sendAction:editor.kindPopUp.action to:editor.kindPopUp.target];
    XCTAssertEqualObjects(editor.entries[3][@"name"], @"Col de la Croix de Fer", @"trimmed");
    XCTAssertEqualObjects(editor.entries[3][@"kind"], @"nature");

    [[editor buttonWithIdentifier:@"siteGoTo"] performClick:self];
    XCTAssertEqual(target.shown.count, 1u);
    XCTAssertEqualObjects(target.shown[0].name, @"Col de la Croix de Fer");
    XCTAssertEqual(target.shown[0].kind, BPSiteKindNature);

    // in the exported list
    NSArray<BPRemarkableSite *> *sites = [BPRemarkableSites sitesFromPropertyList:
        [NSPropertyListSerialization propertyListWithData:[editor exportData] options:0 format:NULL error:NULL]];
    XCTAssertEqual(sites.count, n + 1);
    XCTAssertEqualObjects(sites[3].name, @"Col de la Croix de Fer");
}

// heading: field and slider, whole degrees 0–359, Street View previewed once the changes stop
- (void)testHeadingPreview
{
    editor.selectedIndex = 1;
    editor.headingSlider.doubleValue = 80;
    [editor.headingSlider sendAction:editor.headingSlider.action to:editor.headingSlider.target];
    editor.headingSlider.doubleValue = 92.4;
    [editor.headingSlider sendAction:editor.headingSlider.action to:editor.headingSlider.target];
    XCTAssertEqualObjects(editor.headingField.stringValue, @"92");
    XCTAssertEqualObjects(editor.entries[1][@"heading"], @92);
    XCTAssertTrue(editor.edited);
    XCTAssertEqual(target.previews.count, 0u, @"not at each change");
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(self->target.previews.count == 1); }));
    XCTAssertEqualObjects(target.previews[0][2], @92);
    XCTAssertEqualWithAccuracy(target.previews[0][0].doubleValue, [editor.entries[1][@"latitude"] doubleValue], 1e-9);

    editor.headingField.stringValue = @"-90";
    [editor.headingField sendAction:editor.headingField.action to:editor.headingField.target];
    XCTAssertEqualObjects(editor.entries[1][@"heading"], @270, @"normalized");
    XCTAssertEqual(editor.headingSlider.doubleValue, 270);
    XCTAssertTrue(BPWaitUntil(2, ^{ return (BOOL)(self->target.previews.count == 2); }));
}

// Set Position Here, typed coordinates (decimal comma accepted), problems listed
- (void)testPositionAndProblems
{
    editor.selectedIndex = 1;
    [[editor buttonWithIdentifier:@"siteSetPosition"] performClick:self];
    XCTAssertEqualWithAccuracy([editor.entries[1][@"latitude"] doubleValue], 45.12346, 1e-9);
    XCTAssertEqualObjects(editor.problems, @[]);

    editor.latitudeField.stringValue = @"46,5";
    editor.longitudeField.stringValue = @"10";
    [editor.latitudeField sendAction:editor.latitudeField.action to:editor.latitudeField.target];
    XCTAssertEqualObjects(editor.entries[1][@"latitude"], @46.5);
    XCTAssertEqual(editor.problems.count, 1u);
    XCTAssertTrue([editor.problems[0] containsString:@"outside metropolitan France"], @"%@", editor.problems);
    XCTAssertTrue([editor.statusLabel.stringValue containsString:@"outside"]);

    editor.nameField.stringValue = editor.entries[2][@"name"];
    [editor.nameField sendAction:editor.nameField.action to:editor.nameField.target];
    XCTAssertEqual(editor.problems.count, 3u, @"%@", editor.problems); // same name, twice, + outside

    editor.selectedIndex = 0;
    editor.nameField.stringValue = @"";
    [editor.nameField sendAction:editor.nameField.action to:editor.nameField.target];
    XCTAssertTrue([[editor.problems componentsJoinedByString:@"\n"] containsString:@"must stay Mont Ventoux"]);
    XCTAssertTrue([[editor.problems componentsJoinedByString:@"\n"] containsString:@"no name"]);
}

// reorder and remove, the first site (Mont Ventoux) locked; Revert goes back to the list of the app
- (void)testReorderRemoveRevert
{
    NSUInteger n = editor.entries.count;
    NSString *second = editor.entries[1][@"name"], *third = editor.entries[2][@"name"];
    editor.selectedIndex = 0;
    XCTAssertFalse([editor buttonWithIdentifier:@"siteRemove"].enabled);
    XCTAssertFalse([editor buttonWithIdentifier:@"siteDown"].enabled);
    XCTAssertFalse([editor buttonWithIdentifier:@"siteUp"].enabled);
    editor.selectedIndex = 1;
    XCTAssertFalse([editor buttonWithIdentifier:@"siteUp"].enabled, @"nothing above Mont Ventoux");
    [[editor buttonWithIdentifier:@"siteDown"] performClick:self];
    XCTAssertEqualObjects(editor.entries[2][@"name"], second);
    XCTAssertEqualObjects(editor.entries[1][@"name"], third);
    XCTAssertEqual(editor.selectedIndex, 2);
    [[editor buttonWithIdentifier:@"siteUp"] performClick:self];
    XCTAssertEqualObjects(editor.entries[1][@"name"], second);
    [[editor buttonWithIdentifier:@"siteRemove"] performClick:self];
    XCTAssertEqual(editor.entries.count, n - 1);
    XCTAssertEqualObjects(editor.entries[1][@"name"], third);
    XCTAssertEqual(editor.selectedIndex, 1);
    XCTAssertEqualObjects(editor.entries[0][@"name"], @"Mont Ventoux");
    XCTAssertTrue([editor buttonWithIdentifier:@"siteRevert"].enabled);
}

// without a document window: nothing happens
- (void)testNoTarget
{
    editor.targetProvider = ^id<BPSiteEditorTarget> { return nil; };
    NSUInteger n = editor.entries.count;
    [[editor buttonWithIdentifier:@"siteAdd"] performClick:self];
    XCTAssertEqual(editor.entries.count, n);
    XCTAssertFalse(editor.edited);
}

@end

#endif
