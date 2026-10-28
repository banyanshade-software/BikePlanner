//
//  BRFProfileEditorTests.m
//  BikePlannerTests
//
//  BRF profile download (stub server), parameter rows, override output.
//

#import <XCTest/XCTest.h>
#import "BRFProfileEditor.h"
#import "BPStubServer.h"
#import "TestFixtures.h"

@interface BRFProfileEditor (Testing)
@property (strong) NSStackView *stackView;
@property (strong) NSMutableArray<BRFParam *> *parameters;
- (void)parseProfile:(NSString *)brf;
- (void)doneClicked:(id)sender;
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

- (NSArray<NSStackView *> *)rows
{
    return [editor.stackView.arrangedSubviews filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id v, NSDictionary *b) { return [v isKindOfClass:[NSStackView class]]; }]];
}

- (void)loadUI
{
    (void)editor.view; // viewDidLoad -> fetch -> buildUI on main queue
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([self rows].count == 3); }));
}

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
}

- (void)testDownloadsProfileFromServer
{
    [self loadUI];
    BPStubRequest *r = [server requestsWithPath:@"/brouter/profiles2/trekking.brf"].firstObject;
    XCTAssertNotNil(r);
    NSStackView *row = [self rows][0];
    XCTAssertEqualObjects(((NSTextField *)row.arrangedSubviews[1]).stringValue, @"downhillcost");
    XCTAssertEqualObjects(((NSTextField *)row.arrangedSubviews[2]).stringValue, @"60");
    XCTAssertTrue([editor.stackView.arrangedSubviews.lastObject isKindOfClass:[NSButton class]]); // Done/Save
}

- (void)testDoneReturnsOnlyOverriddenParams
{
    [self loadUI];
    __block NSDictionary *result = nil;
    editor.completionHandler = ^(NSDictionary *overrides) { result = overrides; };

    NSStackView *row0 = [self rows][0];
    NSStackView *row2 = [self rows][2];
    ((NSButton *)row0.arrangedSubviews[0]).state = NSControlStateValueOn;
    ((NSTextField *)row0.arrangedSubviews[2]).stringValue = @"80";
    ((NSButton *)row2.arrangedSubviews[0]).state = NSControlStateValueOn;

    [editor doneClicked:nil];
    XCTAssertEqualObjects(result, (@{ @"downhillcost": @"80", @"avoid_unsafe": @"false" }), @"names without the profile: prefix (added by BRouterClient)");
}

- (void)testDoneWithoutOverrides
{
    [self loadUI];
    __block NSDictionary *result = nil;
    editor.completionHandler = ^(NSDictionary *overrides) { result = overrides; };
    [editor doneClicked:nil];
    XCTAssertEqualObjects(result, @{});
}

- (void)testServerErrorGivesNoRows
{
    server.failCount = 1;
    (void)editor.view;
    BPSpin(1.0);
    // current behavior: the 500 body is parsed as a profile (no assign -> no row), only the Done button
    XCTAssertEqual([self rows].count, 0u);
}

@end
