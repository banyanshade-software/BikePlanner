//
//  BPGarminConnectTests.m
//  BikePlannerTests
//
//  Sending a course to Garmin Connect (#79): the activity type rule, and the automation of the import against fake
//  Garmin Connect pages served to the web view by a URL scheme handler (never the real site).
//

#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import "BPGarminCourse.h"
#import "BPGarminConnectController.h"
#import "BRouterGeoJSON.h"
#import "BPGarminCredentials.h"
#import "TestFixtures.h"

#pragma mark - fake Garmin Connect

// pages like the real ones (2026-11-18, French interface): login on another path, the courses page with "Importer", a
// popup with a hidden file input and "Mise en route", the editor (activity buttons, then the name and "Enregistrer",
// then a popup with the privacy and "Enregistrer" again, left to the user)
@interface BPFakeGarmin : NSObject <WKURLSchemeHandler>
@property (nonatomic) BOOL loggedIn;
@property (nonatomic) BOOL withoutImportButton;   // a changed site: the degraded mode
@property (nonatomic, strong) NSMutableArray<NSString *> *paths;
@end

@implementation BPFakeGarmin

- (instancetype)init
{
    if (self = [super init]) _paths = [NSMutableArray array];
    return self;
}

- (NSString *)pageForPath:(NSString *)path
{
    if (!self.loggedIn && ![path hasPrefix:@"/sso"]) {
        return @"<script>location.href='bpgarmin://connect.test/sso/sign-in?service=app'</script>";
    }
    if ([path hasPrefix:@"/sso"]) {
        return @"<h1>Se connecter</h1><form onsubmit=\"event.preventDefault(); location.href='bpgarmin://connect.test/app?login=1'\">"
               @"<input type=email id=email><input type=password id=password><button type=submit id=login>Se connecter</button></form>";
    }
    if ([path isEqualToString:@"/app"]) return @"<h1>Accueil</h1>";
    if ([path isEqualToString:@"/app/courses"]) {
        NSString *importButton = self.withoutImportButton ? @"" : @"<button id=imp onclick=\"document.getElementById('pop').style.display='block'\">Importer</button>";
        return [NSString stringWithFormat:@"<h1>Parcours</h1>%@"
            @"<div id=pop role=dialog style='display:none'><h2>Importer des parcours</h2>"
            @"<div id=zone onclick=\"document.getElementById('f').click()\">Déposez vos fichiers ici</div>"
            @"<p>Les fichiers doivent être au format .tcx, .fit ou .gpx.</p>"
            @"<input type=file id=f multiple style='display:none' onchange=\"window.gotFiles=Array.from(this.files).map(f=>f.name);"
            @"  var r=new FileReader(); r.onload=()=>{window.gotText=r.result; document.getElementById('list').textContent=window.gotFiles.join(',')}; r.readAsText(this.files[0])\">"
            @"<ul id=list></ul>"
            @"<button id=start onclick=\"sessionStorage.setItem('file', window.gotFiles[0]); sessionStorage.setItem('gpx', window.gotText);"
            @"  location.href='bpgarmin://connect.test/app/course/create'\">Mise en route</button></div>", importButton];
    }
    if ([path isEqualToString:@"/app/course/create"]) {
        return @"<h1>Créer un parcours</h1>"
            @"<div id=types><h3>Cyclisme</h3>"
            @"<button onclick=\"pick('road')\">Cyclisme sur route</button><button onclick=\"pick('gravel')\">Gravel bike</button>"
            @"<button onclick=\"pick('mtb')\">VTT</button><h3>Autres</h3><button onclick=\"pick('run')\">Course à pied</button></div>"
            @"<div id=name style='display:none'><input id=n><button id=save1 onclick=\"document.getElementById('final').style.display='block';"
            @"  sessionStorage.setItem('saved1','yes')\">Enregistrer</button></div>"
            @"<div id=final role=dialog style='display:none'><input id=n2><label><input type=radio name=p checked>Privé</label>"
            @"<button id=save2 onclick=\"location.href='bpgarmin://connect.test/app/course/4242'\">Enregistrer</button></div>"
            @"<script>function pick(t){sessionStorage.setItem('type',t); document.getElementById('types').style.display='none';"
            @"  document.getElementById('name').style.display='block'; var m=(sessionStorage.getItem('gpx')||'').match(/<name>([^<]*)<\\/name>/);"
            @"  document.getElementById('n').value=m?m[1]:''; document.getElementById('n2').value=m?m[1]:''}</script>";
    }
    if ([path hasPrefix:@"/app/course/"]) return @"<h1>Parcours enregistré</h1><button>Envoyer vers l'appareil</button>";
    return @"<h1>?</h1>";
}

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task
{
    NSURL *url = task.request.URL;
    if ([url.query containsString:@"login=1"]) self.loggedIn = YES;
    [self.paths addObject:url.path ?: @"/"];
    NSString *html = [NSString stringWithFormat:@"<!doctype html><html><head><meta charset=utf-8></head><body>%@</body></html>",
                      [self pageForPath:url.path ?: @"/"]];
    NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding];
    [task didReceiveResponse:[[NSURLResponse alloc] initWithURL:url MIMEType:@"text/html" expectedContentLength:(NSInteger)data.length
                                               textEncodingName:@"utf-8"]];
    [task didReceiveData:data];
    [task didFinish];
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task
{
}

@end

// counts the Keychain reads
@interface BPGarminCountingCredentials : BPGarminMemoryCredentials
@property NSInteger reads;
@end
@implementation BPGarminCountingCredentials
- (nullable NSDictionary<NSString *, NSString *> *)savedLogin { self.reads++; return [super savedLogin]; }
@end

@interface BPGarminConnectTests : XCTestCase
@end

@implementation BPGarminConnectTests {
    BPFakeGarmin *garmin;
    NSURL *dir;
}

- (void)setUp
{
    garmin = [[BPFakeGarmin alloc] init];
    BPOverrideDefaults(@{ @"BPGarminConnectURL": @"bpgarmin://connect.test" });
    dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"bp-garmin-" stringByAppendingString:NSUUID.UUID.UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:dir error:NULL];
    BPRestoreDefaults();
}

#pragma mark - activity type

- (void)testActivityRule
{
    XCTAssertEqual([BPGarminCourse activityForSurfaceStats:nil], BPGarminActivityGravel, @"no statistics");
    XCTAssertEqual([BPGarminCourse activityForSurfaceStats:(@{ BPSurfacePaved: @95, BPSurfaceUnpaved: @5 })], BPGarminActivityRoad);
    XCTAssertEqual([BPGarminCourse activityForSurfaceStats:(@{ BPSurfacePaved: @90, BPSurfaceUnpaved: @10 })], BPGarminActivityRoad, @"90 %%: road");
    XCTAssertEqual([BPGarminCourse activityForSurfaceStats:(@{ BPSurfacePaved: @89, BPSurfaceUnpaved: @11 })], BPGarminActivityGravel);
    XCTAssertEqual([BPGarminCourse activityForSurfaceStats:(@{ BPSurfacePaved: @21, BPSurfaceUnpaved: @79 })], BPGarminActivityGravel);
    XCTAssertEqual([BPGarminCourse activityForSurfaceStats:(@{ BPSurfacePaved: @20, BPSurfaceUnpaved: @80 })], BPGarminActivityMountain, @"20 %%: VTT");
    XCTAssertEqual([BPGarminCourse activityForSurfaceStats:(@{ BPSurfaceUnpaved: @100 })], BPGarminActivityMountain);
    // unknown excluded from the ratio, unless it is the majority
    XCTAssertEqual([BPGarminCourse activityForSurfaceStats:(@{ BPSurfacePaved: @45, BPSurfaceUnpaved: @5, BPSurfaceUnknown: @50 })],
                   BPGarminActivityRoad, @"unknown at 50 %%: not the majority");
    XCTAssertEqual([BPGarminCourse activityForSurfaceStats:(@{ BPSurfacePaved: @40, BPSurfaceUnknown: @60 })], BPGarminActivityGravel,
                   @"unknown the majority");
    NSArray *road = @[ @"cyclisme sur route", @"road cycling" ];
    XCTAssertEqualObjects([BPGarminCourse buttonTextsForActivity:BPGarminActivityRoad], road);
    XCTAssertTrue([[BPGarminCourse buttonTextsForActivity:BPGarminActivityMountain] containsObject:@"vtt"]);
    XCTAssertTrue([[BPGarminCourse buttonTextsForActivity:BPGarminActivityGravel] containsObject:@"gravel bike"]);
}

#pragma mark - the automation

- (NSURL *)gpxNamed:(NSString *)name
{
    NSURL *u = [dir URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"gpx"]];
    NSString *gpx = [NSString stringWithFormat:@"<?xml version=\"1.0\"?><gpx><trk><name>%@</name><trkseg>"
                     @"<trkpt lat=\"44\" lon=\"0.5\"/><trkpt lat=\"44.1\" lon=\"0.6\"/></trkseg></trk></gpx>", name];
    XCTAssertTrue([gpx writeToURL:u atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    return u;
}

- (BPGarminConnectController *)controllerWithFiles:(NSArray<NSURL *> *)files activity:(BPGarminActivity)activity
{
    return [self controllerWithFiles:files activity:activity credentials:[[BPGarminMemoryCredentials alloc] init]];
}

- (BPGarminConnectController *)controllerWithFiles:(NSArray<NSURL *> *)files activity:(BPGarminActivity)activity
                                       credentials:(id<BPGarminCredentialStore>)credentials
{
    BPGarminConnectController *c = [[BPGarminConnectController alloc] initWithFiles:files activity:activity
                                                                      schemeHandler:garmin forScheme:@"bpgarmin"];
    c.credentials = credentials; // never the user's Keychain
    c.stepTimeout = 2;
    [c showWindow:nil];
    [c start];
    return c;
}

- (nullable NSString *)evaluate:(NSString *)js in:(BPGarminConnectController *)c
{
    __block id result = nil;
    __block BOOL done = NO;
    [c.webView evaluateJavaScript:js completionHandler:^(id r, NSError *e) { result = r; done = YES; }];
    BPWaitUntil(3, ^{ return done; });
    return [result isKindOfClass:[NSString class]] ? result : [result description];
}

// logged out: the user logs in on the Garmin page; then Importer, the GPX given to the file chooser, Mise en route,
// the activity, Enregistrer; the last Enregistrer (name, privacy) is left to the user
- (void)testImportFlow
{
    BPGarminConnectController *c = [self controllerWithFiles:@[ [self gpxNamed:@"Tour du Lot"] ] activity:BPGarminActivityGravel];
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(c.step == BPGarminStepLogin); }));
    XCTAssertTrue([c.statusText containsString:@"Log in"], @"%@", c.statusText);
    // the user logs in
    [self evaluate:@"document.getElementById('login').click(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(c.step == BPGarminStepUserSave); }), @"step %ld: %@", (long)c.step, c.statusText);
    XCTAssertEqualObjects([self evaluate:@"sessionStorage.getItem('file')" in:c], @"Tour du Lot.gpx", @"the GPX given to the file chooser");
    XCTAssertEqualObjects([self evaluate:@"sessionStorage.getItem('type')" in:c], @"gravel", @"the activity clicked");
    XCTAssertEqualObjects([self evaluate:@"sessionStorage.getItem('saved1')" in:c], @"yes", @"the first Enregistrer clicked");
    XCTAssertEqualObjects([self evaluate:@"document.getElementById('n2').value" in:c], @"Tour du Lot", @"the name of the document");
    XCTAssertTrue([c.statusText containsString:@"Enregistrer"], @"the user saves: %@", c.statusText);
    BPSpin(1.5);
    XCTAssertEqual(c.step, BPGarminStepUserSave, @"the automation never clicks the last Enregistrer");
    XCTAssertTrue([garmin.paths containsObject:@"/app/course/create"]);
    XCTAssertFalse([garmin.paths containsObject:@"/app/course/4242"]);
    // the user saves
    [self evaluate:@"document.getElementById('save2').click(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(c.step == BPGarminStepDone); }));
    XCTAssertTrue([c.statusText containsString:@"Send to Device"], @"%@", c.statusText);
    [c close];
}

// one course per stage: the import again for each file, after the user saved the previous one
- (void)testStages
{
    garmin.loggedIn = YES;
    BPGarminConnectController *c = [self controllerWithFiles:@[ [self gpxNamed:@"Trip - stage 1"], [self gpxNamed:@"Trip - stage 2"] ]
                                                    activity:BPGarminActivityRoad];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(c.step == BPGarminStepUserSave); }));
    XCTAssertEqualObjects([self evaluate:@"sessionStorage.getItem('file')" in:c], @"Trip - stage 1.gpx");
    XCTAssertEqualObjects([self evaluate:@"sessionStorage.getItem('type')" in:c], @"road");
    XCTAssertTrue([c.statusText containsString:@"1/2"], @"%@", c.statusText);
    [self evaluate:@"document.getElementById('save2').click(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(c.step == BPGarminStepUserSave && c.fileIndex == 1); }), @"step %ld", (long)c.step);
    XCTAssertEqualObjects([self evaluate:@"sessionStorage.getItem('file')" in:c], @"Trip - stage 2.gpx");
    XCTAssertTrue([c.statusText containsString:@"2/2"], @"%@", c.statusText);
    [self evaluate:@"document.getElementById('save2').click(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(c.step == BPGarminStepDone); }));
    [c close];
}

// a step not recognized (the site changed): the page as is, and what to do by hand; the automation goes on when the
// page moves on
- (void)testDegradedMode
{
    garmin.loggedIn = YES;
    garmin.withoutImportButton = YES;
    BPGarminConnectController *c = [self controllerWithFiles:@[ [self gpxNamed:@"Tour"] ] activity:BPGarminActivityMountain];
    XCTAssertTrue(BPWaitUntil(8, ^{ return (BOOL)[c.statusText containsString:@"Importer"]; }), @"%@", c.statusText);
    XCTAssertEqual(c.step, BPGarminStepCourses);
    // the user opens the popup by hand (here: the script of the page); the automation continues with the file
    [self evaluate:@"document.getElementById('pop').style.display='block'; 'ok'" in:c];
    garmin.withoutImportButton = NO;
    [self evaluate:@"location.reload(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(c.step == BPGarminStepUserSave); }), @"step %ld: %@", (long)c.step, c.statusText);
    XCTAssertEqualObjects([self evaluate:@"sessionStorage.getItem('type')" in:c], @"mtb");
    [c close];
}

#pragma mark - the login in the Keychain (owner's choice 2026-11-19)

// the user logs in on the Garmin page: BikePlanner asks whether to remember the login, and keeps it if yes
- (void)testLoginCapturedAndRemembered
{
    BPGarminMemoryCredentials *store = [[BPGarminMemoryCredentials alloc] init];
    __block NSString *asked = nil;
    BPGarminConnectController *c = [self controllerWithFiles:@[ [self gpxNamed:@"Tour"] ] activity:BPGarminActivityRoad credentials:store];
    c.rememberPrompt = ^(NSString *account, void (^answer)(BPGarminRemember)) { asked = account; answer(BPGarminRememberYes); };
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(c.step == BPGarminStepLogin); }));
    [self evaluate:@"document.getElementById('email').value='rider@example.org'; document.getElementById('password').value='s3cret';"
                   @"document.getElementById('login').click(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(c.step == BPGarminStepUserSave); }), @"step %ld", (long)c.step);
    XCTAssertEqualObjects(asked, @"rider@example.org", @"asked once logged in");
    NSDictionary *expected = @{ @"account": @"rider@example.org", @"password": @"s3cret" };
    XCTAssertEqualObjects(store.savedLogin, expected);
    [c close];
}

// the next times: the fields filled from the Keychain; the user clicks "Se connecter" (not submitted by the app)
- (void)testLoginFilledFromKeychain
{
    BPGarminMemoryCredentials *store = [[BPGarminMemoryCredentials alloc] init];
    [store saveAccount:@"rider@example.org" password:@"s3cret"];
    __block NSInteger prompts = 0;
    BPGarminConnectController *c = [self controllerWithFiles:@[ [self gpxNamed:@"Tour"] ] activity:BPGarminActivityRoad credentials:store];
    c.rememberPrompt = ^(NSString *account, void (^answer)(BPGarminRemember)) { prompts++; answer(BPGarminRememberNotNow); };
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([[self evaluate:@"document.getElementById('password') ? document.getElementById('password').value : ''" in:c] isEqualToString:@"s3cret"]); }),
                  @"the password filled");
    XCTAssertEqualObjects([self evaluate:@"document.getElementById('email').value" in:c], @"rider@example.org");
    XCTAssertTrue([c.statusText containsString:@"Keychain"], @"%@", c.statusText);
    BPSpin(1.5);
    XCTAssertEqual(c.step, BPGarminStepLogin, @"not submitted by the app");
    [self evaluate:@"document.getElementById('login').click(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(c.step == BPGarminStepUserSave); }));
    XCTAssertEqual(prompts, 0, @"the same login: nothing to ask");
    [c close];
}

// "Never for this account": not asked again
- (void)testNeverForThisAccount
{
    BPGarminMemoryCredentials *store = [[BPGarminMemoryCredentials alloc] init];
    __block NSInteger prompts = 0;
    BPGarminConnectController *c = [self controllerWithFiles:@[ [self gpxNamed:@"Tour"] ] activity:BPGarminActivityRoad credentials:store];
    c.rememberPrompt = ^(NSString *account, void (^answer)(BPGarminRemember)) { prompts++; answer(BPGarminRememberNever); };
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(c.step == BPGarminStepLogin); }));
    [self evaluate:@"document.getElementById('email').value='Rider@Example.org'; document.getElementById('password').value='x';"
                   @"document.getElementById('login').click(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(c.step == BPGarminStepUserSave); }));
    XCTAssertEqual(prompts, 1);
    XCTAssertNil(store.savedLogin);
    XCTAssertTrue([store isNeverSaved:@"rider@example.org"], @"case-insensitive");
    [c close];

    garmin.loggedIn = NO;
    BPGarminConnectController *again = [self controllerWithFiles:@[ [self gpxNamed:@"Tour"] ] activity:BPGarminActivityRoad credentials:store];
    again.rememberPrompt = ^(NSString *account, void (^answer)(BPGarminRemember)) { prompts++; answer(BPGarminRememberNever); };
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(again.step == BPGarminStepLogin); }));
    [self evaluate:@"document.getElementById('email').value='rider@example.org'; document.getElementById('password').value='x';"
                   @"document.getElementById('login').click(); 'ok'" in:again];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(again.step == BPGarminStepUserSave); }));
    XCTAssertEqual(prompts, 1, @"not asked again");
    [again close];
}

// the native login bar (owner's choice 2026-11-19): shown on the login step only, its fields fill the page (replacing
// what it has), not submitted by the app; then hidden, the password not kept
- (void)testLoginBarFillsThePage
{
    BPGarminConnectController *c = [self controllerWithFiles:@[ [self gpxNamed:@"Tour"] ] activity:BPGarminActivityRoad];
    c.rememberPrompt = ^(NSString *account, void (^answer)(BPGarminRemember)) { answer(BPGarminRememberNotNow); };
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(c.step == BPGarminStepLogin); }));
    XCTAssertTrue(c.loginBarShown);
    NSTextField *account = (NSTextField *)[self viewWithIdentifier:@"garminAccount" in:c.window.contentView];
    NSTextField *password = (NSTextField *)[self viewWithIdentifier:@"garminPassword" in:c.window.contentView];
    XCTAssertEqualObjects(account.contentType, NSTextContentTypeUsername, @"macOS AutoFill");
    XCTAssertEqualObjects(password.contentType, NSTextContentTypePassword);
    [self evaluate:@"document.getElementById('email').value='old@example.org'; 'ok'" in:c];
    account.stringValue = @"rider@example.org";
    password.stringValue = @"s3cret";
    [c fillLoginFromFields:self];
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([[self evaluate:@"document.getElementById('password').value" in:c] isEqualToString:@"s3cret"]); }));
    XCTAssertEqualObjects([self evaluate:@"document.getElementById('email').value" in:c], @"rider@example.org", @"replaced");
    BPSpin(1.5);
    XCTAssertEqual(c.step, BPGarminStepLogin, @"not submitted by the app");
    [self evaluate:@"document.getElementById('login').click(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(c.step == BPGarminStepUserSave); }));
    XCTAssertFalse(c.loginBarShown);
    XCTAssertEqualObjects(password.stringValue, @"", @"the password not kept");
    [c close];
}

- (nullable NSView *)viewWithIdentifier:(NSString *)identifier in:(NSView *)view
{
    if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
    for (NSView *v in view.subviews) {
        NSView *found = [self viewWithIdentifier:identifier in:v];
        if (found) return found;
    }
    return nil;
}

// the Keychain read once per sheet (each read may show a macOS permission prompt); a login filled from it and used is
// not offered to be remembered again
- (void)testKeychainReadOncePerSheet
{
    BPGarminCountingCredentials *store = [[BPGarminCountingCredentials alloc] init];
    [store saveAccount:@"rider@example.org" password:@"s3cret"];
    __block NSInteger prompts = 0;
    BPGarminConnectController *c = [self controllerWithFiles:@[ [self gpxNamed:@"Tour"] ] activity:BPGarminActivityRoad credentials:store];
    c.rememberPrompt = ^(NSString *account, void (^answer)(BPGarminRemember)) { prompts++; answer(BPGarminRememberNotNow); };
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)(c.step == BPGarminStepLogin); }));
    XCTAssertTrue(BPWaitUntil(5, ^{ return (BOOL)([[self evaluate:@"document.getElementById('password').value" in:c] isEqualToString:@"s3cret"]); }));
    [c fillLoginFromFields:self];
    BPSpin(0.5);
    [self evaluate:@"document.getElementById('login').click(); 'ok'" in:c];
    XCTAssertTrue(BPWaitUntil(10, ^{ return (BOOL)(c.step == BPGarminStepUserSave); }));
    XCTAssertEqual(store.reads, 1, @"read once");
    XCTAssertEqual(prompts, 0);
    [c close];
}

@end
