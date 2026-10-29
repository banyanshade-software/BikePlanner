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
- (void)parseProfile:(NSString *)brf;
- (void)buildUI;
- (void)applyClicked:(id)sender;
- (void)resetAllClicked:(id)sender;
- (void)resetParam:(NSButton *)sender;
- (void)useMyDefaults:(id)sender;
- (void)saveAsMyDefaults:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
@property (strong) NSView *defaultsNotice;
@end

@interface BRFParam (Testing)
@property (nonatomic, strong, nullable) NSButton *resetButton;
@end

@interface BRFProfileEditorTests : XCTestCase
@end

@implementation BRFProfileEditorTests {
    BPStubServer *server;
    BRFProfileEditor *editor;
    NSUserDefaults *defaults; // "my defaults" of the tests, not the owner's
    NSString *suite;
}

- (void)setUp
{
    server = [[BPStubServer alloc] init];
    XCTAssertTrue([server startInProcess]);
    BPOverrideDefaults(@{ @"BPBRouterServer": server.baseURL.absoluteString });
    editor = [[BRFProfileEditor alloc] initWithNibName:@"BRFProfileEditor" bundle:nil];
    suite = [NSString stringWithFormat:@"BRFProfileEditorTests.%@", NSUUID.UUID.UUIDString];
    defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    editor.userDefaults = defaults;
    [editor loadProfileName:@"trekking"];
}

- (void)tearDown
{
    [defaults removePersistentDomainForName:suite];
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

- (BOOL)menuEnabled:(SEL)action
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""];
    return [editor validateMenuItem:item];
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

// profiles mixing annotated and commented parameters, and the "assign name value" syntax (mtb.brf) (#52)
- (void)testParseMixedProfile
{
    [editor parseProfile:@"---context:global\n"
                         @"assign validForBikes = true\n"
                         @"# Use the following switches to change behaviour\n"
                         @"  assign   add_beeline            false  # %add_beeline% | Enable beeline on distant start/end points | boolean\n"
                         @"  assign   iswet                  0 # 0 as default, *) flag for weather conditions\n"
                         @"  assign   smallpaved_factor      -0.5 # default 0.0, *)\n"
                         @"  assign   isbike_for_mainroads   true # default=true / if false then bike friendly tag hints are ignored\n"
                         @"  assign   valley_nonflat_multiplier = 2.0\n"
                         @"  assign   turnInstructionMode  = 1 # 0=none, 1=auto-choose\n"
                         @"---context:way\n"
                         @"assign   other 1 # way context\n"];
    NSArray *names = [editor.parameters valueForKey:@"name"];
    XCTAssertEqualObjects(names, (@[@"add_beeline", @"iswet", @"smallpaved_factor", @"isbike_for_mainroads"]),
                          @"annotated + commented; not the internal (no comment) nor the hidden ones");
    BRFParam *wet = [self param:@"iswet"];
    XCTAssertEqualObjects(wet.defaultValue, @"0");
    XCTAssertEqual(wet.kind, BRFParamNumber, @"no type information: a number");
    XCTAssertEqualObjects(wet.help, @"0 as default, *) flag for weather conditions");
    XCTAssertEqualObjects(wet.section, @"Use the following switches to change behaviour");
    XCTAssertEqualObjects([self param:@"smallpaved_factor"].defaultValue, @"-0.5");
    XCTAssertEqual([self param:@"isbike_for_mainroads"].kind, BRFParamBoolean);
    XCTAssertEqual([self param:@"add_beeline"].kind, BRFParamBoolean);
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
    XCTAssertFalse([self menuEnabled:@selector(resetAllClicked:)]);
    XCTAssertFalse([self menuEnabled:@selector(useMyDefaults:)], @"no saved defaults");
    XCTAssertFalse([self menuEnabled:@selector(saveAsMyDefaults:)], @"nothing to save");
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
    XCTAssertFalse([self menuEnabled:@selector(resetAllClicked:)]);
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

#pragma mark - document parameters and my defaults (#44)

// the document's parameters are shown when the profile is loaded
- (void)testAppliedOverridesShownAfterLoad
{
    editor.appliedOverrides = @{ @"downhillcost": @"80", @"avoid_unsafe": @"1" };
    [self loadUI];
    XCTAssertEqualObjects(((NSTextField *)[self param:@"downhillcost"].valueControl).stringValue, @"80");
    XCTAssertEqual(((NSSwitch *)[self param:@"avoid_unsafe"].valueControl).state, NSControlStateValueOn);
    XCTAssertFalse(editor.applyButton.enabled, @"already applied");
    XCTAssertFalse([self param:@"downhillcost"].resetButton.hidden);
}

// undo / revert: new document parameters replace the values being edited
- (void)testAppliedOverridesSetAfterLoad
{
    [self loadUI];
    ((NSTextField *)[self param:@"totalMass"].valueControl).stringValue = @"120";
    [self changed:[self param:@"totalMass"].valueControl];
    editor.appliedOverrides = @{ @"downhillcost": @"80" };
    XCTAssertEqualObjects(((NSTextField *)[self param:@"downhillcost"].valueControl).stringValue, @"80");
    XCTAssertEqualObjects(((NSTextField *)[self param:@"totalMass"].valueControl).stringValue, @"90");
    XCTAssertFalse(editor.applyButton.enabled);
}

- (void)testSaveAsMyDefaults
{
    XCTAssertNil([BRFProfileEditor savedOverridesForProfile:@"trekking" userDefaults:defaults]);
    [self loadUI];
    ((NSTextField *)[self param:@"downhillcost"].valueControl).stringValue = @"80";
    [self changed:[self param:@"downhillcost"].valueControl];
    XCTAssertTrue([self menuEnabled:@selector(saveAsMyDefaults:)]);
    [editor saveAsMyDefaults:nil];
    XCTAssertFalse([self menuEnabled:@selector(saveAsMyDefaults:)], @"saved");
    XCTAssertEqualObjects([BRFProfileEditor savedOverridesForProfile:@"trekking" userDefaults:defaults],
                          @{ @"downhillcost": @"80" });
    XCTAssertEqualObjects([defaults dictionaryForKey:@"BPProfileOverrides"], (@{ @"trekking": @{ @"downhillcost": @"80" } }));
    XCTAssertTrue(editor.applyButton.enabled, @"saving the defaults does not apply them");
}

// a document whose parameters differ from my defaults: notice, "Use My Defaults" sets the values, Apply sends them
- (void)testUseMyDefaults
{
    [BRFProfileEditor saveOverrides:@{ @"totalMass": @"110" } asDefaultsForProfile:@"trekking" userDefaults:defaults];
    editor.appliedOverrides = @{ @"downhillcost": @"80" };
    [self loadUI];
    XCTAssertFalse(editor.defaultsNotice.hidden, @"document parameters differ from my defaults");
    XCTAssertTrue([self menuEnabled:@selector(useMyDefaults:)]);

    [editor useMyDefaults:nil];
    XCTAssertEqualObjects(((NSTextField *)[self param:@"totalMass"].valueControl).stringValue, @"110");
    XCTAssertEqualObjects(((NSTextField *)[self param:@"downhillcost"].valueControl).stringValue, @"60");
    XCTAssertTrue(editor.defaultsNotice.hidden);
    XCTAssertTrue(editor.applyButton.enabled);
    XCTAssertEqualObjects([self apply], @{ @"totalMass": @"110" });
    XCTAssertTrue(editor.defaultsNotice.hidden);
}

- (void)testNoNoticeWithoutMyDefaultsOrWhenEqual
{
    editor.appliedOverrides = @{ @"downhillcost": @"80" };
    [self loadUI];
    XCTAssertTrue(editor.defaultsNotice.hidden, @"no saved defaults");
    [BRFProfileEditor saveOverrides:@{ @"downhillcost": @"80" } asDefaultsForProfile:@"trekking" userDefaults:defaults];
    editor.appliedOverrides = @{ @"downhillcost": @"80" };
    XCTAssertTrue(editor.defaultsNotice.hidden, @"same as my defaults");
}

#pragma mark - typing numbers (#45)

// types into the number field through the field editor, one character at a time, like the user
- (NSTextField *)type:(NSString *)text into:(NSString *)name window:(NSWindow *)w
{
    NSTextField *field = (NSTextField *)[self param:name].valueControl;
    XCTAssertTrue([w makeFirstResponder:field]);
    NSText *fieldEditor = field.currentEditor;
    XCTAssertNotNil(fieldEditor);
    [fieldEditor selectAll:nil];
    for (NSUInteger i = 0; i < text.length; i++) {
        [fieldEditor insertText:[text substringWithRange:NSMakeRange(i, 1)]];
    }
    return field;
}

- (NSWindow *)windowWithEditor
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 600) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    editor.view.frame = w.contentView.bounds;
    [w.contentView addSubview:editor.view];
    [self loadUI];
    return w;
}

// the decimal separator must not disappear while typing (#45): reading the value of the field during the editing
// made the formatter validate "0," and write "0" back
- (void)testTypeDecimalNumber
{
    NSWindow *w = [self windowWithEditor];
    NSTextField *field = (NSTextField *)[self param:@"uphillcutoff"].valueControl;
    NSString *typed = [NSString stringWithFormat:@"0%@3", ((NSNumberFormatter *)field.formatter).decimalSeparator];
    [self type:typed into:@"uphillcutoff" window:w];
    XCTAssertEqualObjects(field.currentEditor.string, typed, @"text kept while typing");
    XCTAssertTrue(editor.applyButton.enabled);
    XCTAssertEqualObjects([self apply], @{ @"uphillcutoff": @"0.3" }, @"sent with a dot");
    XCTAssertEqualObjects(field.stringValue, typed);
    [w close];
}

// a control keeps its size and place when its parameter changes (title in bold): switches moved left
- (void)testControlsStayInPlaceWhenChanged
{
    NSWindow *w = [self windowWithEditor];
    // narrow panel (as in the document window) and a long label that no longer fits once in bold
    [w setContentSize:NSMakeSize(230, 600)];
    editor.view.frame = w.contentView.bounds;
    [editor parseProfile:@"assign avoid_unsafe = false # %avoid_unsafe% | Avoid | boolean\n"
                         @"assign use_proposed_cycleroutes_and_more = false # %use_proposed_cycleroutes_and_more% | Long | boolean\n"
                         @"assign mode = 1 # %mode% | Mode | [0=none, 1=auto, 2=other]\n"];
    [editor buildUI];
    [w layoutIfNeeded];
    NSSwitch *avoid = (NSSwitch *)[self param:@"use_proposed_cycleroutes_and_more"].valueControl;
    NSRect before = [avoid convertRect:avoid.bounds toView:nil];
    XCTAssertEqualWithAccuracy(before.size.width, avoid.intrinsicContentSize.width, 0.5, @"not stretched");
    avoid.state = NSControlStateValueOn;
    [self changed:avoid];
    [w layoutIfNeeded];
    NSRect after = [avoid convertRect:avoid.bounds toView:nil];
    XCTAssertTrue(NSEqualRects(before, after), @"%@ -> %@", NSStringFromRect(before), NSStringFromRect(after));
    XCTAssertEqualWithAccuracy(after.size.width, avoid.intrinsicContentSize.width, 0.5, @"not stretched");

    NSPopUpButton *mode = (NSPopUpButton *)[self param:@"mode"].valueControl;
    before = [mode convertRect:mode.bounds toView:nil];
    [mode selectItemWithTitle:@"other"];
    [self changed:mode];
    [w layoutIfNeeded];
    XCTAssertEqualWithAccuracy(NSMaxX([mode convertRect:mode.bounds toView:nil]), NSMaxX(before), 0.5, @"right-aligned");
    [w close];
}

@end
