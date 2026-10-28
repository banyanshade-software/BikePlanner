//
//  BRFProfileEditorTests.m
//  BikePlannerTests
//
//  BRF profile download (stub server), parameter parsing and controls, override output (#38, #39).
//

#import <XCTest/XCTest.h>
#import "BRFProfileEditor.h"
#import "BPStubServer.h"
#import "TestFixtures.h"

@interface BRFProfileEditor (Testing)
@property (strong) NSStackView *stackView;
@property (strong) NSMutableArray<BRFParam *> *parameters;
@property (strong) NSButton *applyButton;
@property (strong) NSButton *resetAllButton;
- (void)parseProfile:(NSString *)brf;
- (void)applyClicked:(id)sender;
- (void)resetAllClicked:(id)sender;
- (void)resetParam:(NSButton *)sender;
@end

@interface BRFParam (Testing)
@property (nonatomic, strong, nullable) NSButton *resetButton;
@end

@interface BRFProfileEditorTests : XCTestCase
@end

@implementation BRFProfileEditorTests {
    BPStubServer *server;
    BRFProfileEditor *editor;
}

- (void)setUp
{
    server = [[BPStubServer alloc] init];
    XCTAssertTrue([server startInProcess]);
    BPOverrideDefaults(@{ @"BPBRouterServer": server.baseURL.absoluteString });
    editor = [[BRFProfileEditor alloc] initWithNibName:@"BRFProfileEditor" bundle:nil];
    [editor loadProfileName:@"trekking"];
}

- (void)tearDown
{
    [server stop];
    BPRestoreDefaults();
}

- (void)loadUI
{
    (void)editor.view; // viewDidLoad -> fetch -> buildUI on main queue
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(self->editor.parameters.firstObject.valueControl != nil); }));
}

- (BRFParam *)param:(NSString *)name
{
    for (BRFParam *p in editor.parameters) if ([p.name isEqualToString:name]) return p;
    return nil;
}

// as if the user had changed the control
- (void)changed:(NSControl *)control
{
    [NSApp sendAction:control.action to:control.target from:control];
}

- (NSDictionary *)apply
{
    __block NSDictionary *result = nil;
    editor.completionHandler = ^(NSDictionary *overrides) { result = overrides; };
    [editor applyClicked:nil];
    return result;
}

// profile without annotations: every simple assignment is a parameter
- (void)testParseProfile
{
    [editor parseProfile:@"assign downhillcost = 60\n"
                         @"  assign   uphillcutoff=1.5 # comment\n"
                         @"assign avoid_unsafe = false\n"
                         @"assign isbike = true\n"
                         @"assign negative = -2\n"
                         @"assign computed = add 1 2\n"];
    NSArray *names = [editor.parameters valueForKey:@"name"];
    XCTAssertEqualObjects(names, (@[@"downhillcost", @"uphillcutoff", @"avoid_unsafe", @"isbike", @"negative"]));
    XCTAssertEqualObjects(editor.parameters[1].defaultValue, @"1.5");
    XCTAssertEqualObjects(editor.parameters[4].defaultValue, @"-2");
    XCTAssertFalse(editor.parameters[0].isBoolean);
    XCTAssertTrue(editor.parameters[2].isBoolean);
    XCTAssertEqual(editor.parameters[2].kind, BRFParamBoolean);
}

// annotated profile (#39): only the annotated parameters of the global context, not the hidden ones, with their
// description, type and section; a later assignment of the same name is a computation
- (void)testParseAnnotatedProfile
{
    [editor parseProfile:@"# *** header\n"
                         @"---context:global\n"
                         @"assign validForBikes = true\n"
                         @"# Switches\n"
                         @"assign avoid_unsafe = false # %avoid_unsafe% | Set true to avoid standard highways | boolean\n"
                         @"\n"
                         @"# Kinematic model\n"
                         @"assign totalMass  = 90 # %totalMass% | Mass (in kg) of the bike + biker | number\n"
                         @"assign mode = 1 # %mode% | Mode | [0=none, 1=auto, 2=other]\n"
                         @"assign processUnusedTags = false # %processUnusedTags% | Set true to output unused tags | boolean\n"
                         @"assign totalMass  = 100\n"
                         @"---context:way\n"
                         @"assign classifier_none = 1 # %classifier_none% | internal | number\n"];
    NSArray *names = [editor.parameters valueForKey:@"name"];
    XCTAssertEqualObjects(names, (@[@"avoid_unsafe", @"totalMass", @"mode"]));
    BRFParam *avoid = editor.parameters[0], *mass = editor.parameters[1], *mode = editor.parameters[2];
    XCTAssertEqual(avoid.kind, BRFParamBoolean);
    XCTAssertEqualObjects(avoid.help, @"Set true to avoid standard highways");
    XCTAssertEqualObjects(avoid.section, @"Switches");
    XCTAssertEqualObjects(avoid.label, @"Avoid unsafe");
    XCTAssertEqual(mass.kind, BRFParamNumber);
    XCTAssertEqualObjects(mass.defaultValue, @"90");
    XCTAssertEqualObjects(mass.section, @"Kinematic model");
    XCTAssertEqualObjects(mass.label, @"Total mass (kg)");
    XCTAssertEqual(mode.kind, BRFParamChoice);
    XCTAssertEqualObjects(mode.choices, (@[@[@"0", @"none"], @[@"1", @"auto"], @[@"2", @"other"]]));
}

- (void)testLabels
{
    BRFParam *p = [BRFParam new];
    p.name = @"considerTurnRestrictions"; XCTAssertEqualObjects(p.label, @"Consider turn restrictions");
    p.name = @"stick_to_cycleroutes";     XCTAssertEqualObjects(p.label, @"Stick to cycleroutes");
    p.name = @"downhillcost";             XCTAssertEqualObjects(p.label, @"Downhill cost");
    p.name = @"S_C_x";                    XCTAssertEqualObjects(p.label, @"Drag area S·Cx (m²)");
    p.name = @"X_Unknown";                XCTAssertEqualObjects(p.label, @"X_Unknown");
    p.name = @"maxSpeed";
    p.help = @"Absolute maximum speed (in km/h), for travel time computation";
    XCTAssertEqualObjects(p.label, @"Max speed (km/h)");
}

- (void)testDownloadsProfileFromServer
{
    [self loadUI];
    BPStubRequest *r = [server requestsWithPath:@"/brouter/profiles2/trekking.brf"].firstObject;
    XCTAssertNotNil(r);
    XCTAssertEqualObjects([editor.parameters valueForKey:@"name"],
                          (@[@"downhillcost", @"uphillcutoff", @"avoid_unsafe", @"totalMass", @"mode"]));
    NSTextField *cost = (NSTextField *)[self param:@"downhillcost"].valueControl;
    XCTAssertTrue([cost isKindOfClass:[NSTextField class]]);
    XCTAssertEqualObjects(cost.stringValue, @"60");
    XCTAssertEqualObjects(cost.accessibilityIdentifier, @"brf.downhillcost");
    NSSwitch *avoid = (NSSwitch *)[self param:@"avoid_unsafe"].valueControl;
    XCTAssertTrue([avoid isKindOfClass:[NSSwitch class]]);
    XCTAssertEqual(avoid.state, NSControlStateValueOff);
    NSPopUpButton *mode = (NSPopUpButton *)[self param:@"mode"].valueControl;
    XCTAssertTrue([mode isKindOfClass:[NSPopUpButton class]]);
    XCTAssertEqualObjects(mode.titleOfSelectedItem, @"auto");
    XCTAssertFalse(editor.applyButton.enabled, @"nothing changed");
    XCTAssertFalse(editor.resetAllButton.enabled);
}

// overrides = the values that differ from the defaults; booleans as 1/0 (#38); same number = no override
- (void)testApplyReturnsOnlyChangedParams
{
    [self loadUI];
    NSTextField *cost = (NSTextField *)[self param:@"downhillcost"].valueControl;
    cost.stringValue = @"80";
    [self changed:cost];
    NSTextField *cutoff = (NSTextField *)[self param:@"uphillcutoff"].valueControl;
    cutoff.stringValue = @"1.50";
    [self changed:cutoff];
    NSSwitch *avoid = (NSSwitch *)[self param:@"avoid_unsafe"].valueControl;
    avoid.state = NSControlStateValueOn;
    [self changed:avoid];
    NSPopUpButton *mode = (NSPopUpButton *)[self param:@"mode"].valueControl;
    [mode selectItemWithTitle:@"other"];
    [self changed:mode];
    XCTAssertTrue(editor.applyButton.enabled);

    XCTAssertEqualObjects([self apply], (@{ @"downhillcost": @"80", @"avoid_unsafe": @"1", @"mode": @"2" }),
                          @"names without the profile: prefix (added by BRouterClient)");
    XCTAssertFalse(editor.applyButton.enabled, @"applied");
}

- (void)testApplyWithoutChanges
{
    [self loadUI];
    XCTAssertEqualObjects([self apply], @{});
}

- (void)testResetParamAndResetAll
{
    [self loadUI];
    BRFParam *cost = [self param:@"downhillcost"];
    BRFParam *mass = [self param:@"totalMass"];
    XCTAssertTrue(cost.resetButton.hidden);
    ((NSTextField *)cost.valueControl).stringValue = @"80";
    [self changed:cost.valueControl];
    ((NSTextField *)mass.valueControl).stringValue = @"110";
    [self changed:mass.valueControl];
    XCTAssertFalse(cost.resetButton.hidden, @"changed parameter: reset button shown");
    XCTAssertEqualObjects([self apply], (@{ @"downhillcost": @"80", @"totalMass": @"110" }));

    [editor resetParam:cost.resetButton];
    XCTAssertEqualObjects(((NSTextField *)cost.valueControl).stringValue, @"60");
    XCTAssertTrue(cost.resetButton.hidden);
    XCTAssertTrue(editor.applyButton.enabled, @"differs from the last Apply");

    [editor resetAllClicked:nil];
    XCTAssertEqualObjects(((NSTextField *)mass.valueControl).stringValue, @"90");
    XCTAssertFalse(editor.resetAllButton.enabled);
    XCTAssertEqualObjects([self apply], @{}, @"back to the profile defaults");
}

- (void)testServerErrorShowsMessage
{
    server.failCount = 1;
    (void)editor.view;
    BPSpin(1.0);
    XCTAssertEqual(editor.parameters.count, 0u);
    NSTextField *message = (NSTextField *)editor.stackView.arrangedSubviews.firstObject;
    XCTAssertEqualObjects(message.accessibilityIdentifier, @"brfMessage");
    XCTAssertTrue([message.stringValue containsString:@"HTTP 500"], @"%@", message.stringValue);
    XCTAssertFalse(editor.applyButton.enabled);
}

@end
