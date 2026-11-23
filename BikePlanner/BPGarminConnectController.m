//
//  BPGarminConnectController.m
//  BikePlanner
//
//  File ▸ Send to Garmin Connect… (#79).
//

#import "BPFeatures.h"
#if BP_GARMIN_CONNECT // the whole file (#79, BPFeatures.h)
#import "BPGarminConnectController.h"
#import "BPEnvironment.h"
#import <os/log.h>

// helpers injected in every page: find a visible button by its text (lowercase, the whole text or its first line),
// click it; click the file input (WebKit then asks the UI delegate for the file: -webView:runOpenPanelWithParameters:)
static NSString *const BPGarminHelpers =
    @"window.__bpg = (function () {"
    @"  function norm(t) { return (t || '').replace(/\\s+/g, ' ').trim().toLowerCase(); }"
    @"  function visible(e) { var r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0"
    @"      && getComputedStyle(e).visibility !== 'hidden'; }"
    @"  function find(texts) {"
    @"    var els = document.querySelectorAll('button, a, [role=button], [role=radio], [role=tab], label');"
    @"    for (var i = 0; i < els.length; i++) {"
    @"      var e = els[i];"
    @"      if (e.disabled || !visible(e)) continue;"
    @"      var all = norm(e.innerText || e.textContent), first = norm((e.innerText || '').split('\\n')[0]);"
    @"      if (texts.indexOf(all) >= 0 || texts.indexOf(first) >= 0) return e;"
    @"    }"
    @"    return null;"
    @"  }"
    // the login fields (#79, Keychain): the password field, and the account field before it
    // (in the page, its frames and its shadow roots: the login page may build its fields in web components)
    @"  function deep(sel, root) {"
    @"    root = root || document;"
    @"    var r = root.querySelector(sel); if (r) return r;"
    @"    var all = root.querySelectorAll('*');"
    @"    for (var i = 0; i < all.length; i++) if (all[i].shadowRoot) { r = deep(sel, all[i].shadowRoot); if (r) return r; }"
    @"    return null;"
    @"  }"
    @"  function fields() {"
    @"    var p = deep('input[type=password]');"
    @"    var u = deep('input[type=email], input[autocomplete=username], input[name*=user i], input[name*=email i],"
    @"        input[name*=login i], input[type=text]');"
    @"    return { user: u, password: p };"
    @"  }"
    @"  function grab() {"
    @"    var f = fields();"
    @"    if (!f.user || !f.password || !f.user.value || !f.password.value || !window.webkit) return;"
    @"    window.webkit.messageHandlers.bpgLogin.postMessage({ account: f.user.value, password: f.password.value });"
    @"  }"
    @"  document.addEventListener('submit', grab, true);"
    @"  document.addEventListener('click', function (e) { if (e.target.closest && e.target.closest('button, input[type=submit]')) grab(); }, true);"
    @"  document.addEventListener('keydown', function (e) { if (e.key === 'Enter') grab(); }, true);"
    @"  function setValue(el, v) {"
    @"    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, v);"
    @"    el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true }));"
    @"  }"
    @"  return {"
    @"    click: function (texts) { var e = find(texts); if (!e) return false; e.click(); return true; },"
    @"    clickFile: function () { var i = document.querySelector('input[type=file]'); if (!i) return false; i.click(); return true; },"
    // force: the login chosen in the native fields replaces what the page has
    @"    fill: function (a, p, force) { var f = fields(); if (!f.user || !f.password) return false;"
    @"      if (force || !f.user.value) setValue(f.user, a); if (force || !f.password.value) setValue(f.password, p); return true; }"
    @"  };"
    @"})();";

// the login typed on the Garmin page, to the controller (weakly: the content controller keeps its handlers)
@interface BPGarminMessageProxy : NSObject <WKScriptMessageHandler>
@property (weak) id<WKScriptMessageHandler> target;
@end
@implementation BPGarminMessageProxy
- (void)userContentController:(WKUserContentController *)c didReceiveScriptMessage:(WKScriptMessage *)message
{
    [self.target userContentController:c didReceiveScriptMessage:message];
}
@end

@interface BPGarminConnectController () <WKScriptMessageHandler>
@end

@implementation BPGarminConnectController {
    NSArray<NSURL *> *_files;
    BPGarminActivity _activity;
    NSTextField *_status;
    NSStackView *_loginBar;                             // native login fields (macOS Passwords AutoFill), login step only
    NSTextField *_accountField;
    NSSecureTextField *_passwordField;
    NSTimer *_timer;
    BOOL _evaluating;
    BOOL _fileGiven;
    NSDate *_stepStarted;
    NSURL *_base;
    NSDictionary<NSString *, NSString *> *_typedLogin;  // typed on the login page, until the login succeeds
    NSURL *_filledPage;                                 // the login page filled from the Keychain
    BOOL _askedToRemember;
    NSString *_loggedMiss;                              // diagnostics: a button not found, logged once
    NSDictionary<NSString *, NSString *> *_savedLogin;  // the Keychain item, read once per sheet
    BOOL _savedLoginRead;
    NSDate *_lastStartClick;                            // "Mise en route" clicked again if the editor does not open
    NSMutableArray<NSString *> *_report;                // the diagnostics of the session (Report a Problem…)
    NSAlert *_reportAlert;
    NSDate *_lateNoted;                                 // the step noted as not recognized in the report
}

- (instancetype)initWithFiles:(NSArray<NSURL *> *)files activity:(BPGarminActivity)activity
{
    return [self initWithFiles:files activity:activity schemeHandler:nil forScheme:nil];
}

- (instancetype)initWithFiles:(NSArray<NSURL *> *)files activity:(BPGarminActivity)activity
                schemeHandler:(nullable id<WKURLSchemeHandler>)handler forScheme:(nullable NSString *)scheme
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 720)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.title = NSLocalizedString(@"Send to Garmin Connect", @"Garmin Connect window");
    window.minSize = NSMakeSize(700, 500);
    if (self = [super initWithWindow:window]) {
        _files = [files copy];
        _activity = activity;
        _stepTimeout = 20;
        _base = [BPEnvironment garminConnectURL];
        _statusText = @"";
        // never the user's Keychain in the unit test host
        _report = [NSMutableArray array];
        _credentials = [BPEnvironment isUnitTestHost] ? [[BPGarminMemoryCredentials alloc] init] : [BPGarminKeychain shared];

        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        // the Garmin session is kept in the app's website data (tests: nothing kept)
        config.websiteDataStore = handler ? [WKWebsiteDataStore nonPersistentDataStore] : [WKWebsiteDataStore defaultDataStore];
        if (handler && scheme) [config setURLSchemeHandler:handler forURLScheme:scheme];
        BPGarminMessageProxy *proxy = [[BPGarminMessageProxy alloc] init];
        proxy.target = self;
        [config.userContentController addScriptMessageHandler:proxy name:@"bpgLogin"];
        [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:BPGarminHelpers
                                                                            injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                                         forMainFrameOnly:NO]]; // the login may be in a frame
        _webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
        _webView.navigationDelegate = self;
        _webView.UIDelegate = self;
        _webView.translatesAutoresizingMaskIntoConstraints = NO;
        _webView.accessibilityIdentifier = @"garminWeb";

        _status = [NSTextField wrappingLabelWithString:@""];
        _status.translatesAutoresizingMaskIntoConstraints = NO;
        _status.accessibilityIdentifier = @"garminStatus";
        _status.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightMedium];
        NSButton *logOut = [NSButton buttonWithTitle:NSLocalizedString(@"Log Out of Garmin Connect", @"Garmin Connect window")
                                              target:self action:@selector(logOut:)];
        logOut.accessibilityIdentifier = @"garminLogOut";
        NSButton *close = [NSButton buttonWithTitle:NSLocalizedString(@"Close", @"Garmin Connect window")
                                             target:self action:@selector(closeSheet:)];
        close.keyEquivalent = @"\e";
        close.accessibilityIdentifier = @"garminClose";
        NSButton *report = [NSButton buttonWithTitle:NSLocalizedString(@"Report a Problem…", @"Garmin Connect window")
                                              target:self action:@selector(reportProblem:)];
        report.accessibilityIdentifier = @"garminReport";
        report.toolTip = NSLocalizedString(@"Shows what BikePlanner did in this window (no password), to copy and send", @"Garmin Connect window");
        for (NSView *v in @[ report, logOut, close ]) v.translatesAutoresizingMaskIntoConstraints = NO;

        // the login bar: native fields, so that macOS offers its Passwords AutoFill (Safari's passwords cannot be
        // read by the app nor offered in a web view of another app)
        NSTextField *loginLabel = [NSTextField labelWithString:NSLocalizedString(@"Garmin login:", @"Garmin Connect window")];
        _accountField = [NSTextField textFieldWithString:@""];
        _accountField.placeholderString = NSLocalizedString(@"E-mail", @"Garmin Connect window");
        _accountField.contentType = NSTextContentTypeUsername;
        _accountField.accessibilityIdentifier = @"garminAccount";
        _passwordField = [[NSSecureTextField alloc] init];
        _passwordField.placeholderString = NSLocalizedString(@"Password", @"Garmin Connect window");
        _passwordField.contentType = NSTextContentTypePassword;
        _passwordField.accessibilityIdentifier = @"garminPassword";
        _passwordField.target = self;
        _passwordField.action = @selector(fillLoginFromFields:);
        NSButton *fill = [NSButton buttonWithTitle:NSLocalizedString(@"Fill Garmin Login", @"Garmin Connect window")
                                            target:self action:@selector(fillLoginFromFields:)];
        fill.accessibilityIdentifier = @"garminFill";
        fill.toolTip = NSLocalizedString(@"Fills the e-mail and the password in the Garmin login page; then click “Se connecter”. "
                                         @"Click in a field to choose a saved password.", @"Garmin Connect window");
        [_accountField.widthAnchor constraintEqualToConstant:220].active = YES;
        [_passwordField.widthAnchor constraintEqualToConstant:160].active = YES;
        _loginBar = [NSStackView stackViewWithViews:@[ loginLabel, _accountField, _passwordField, fill ]];
        _loginBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _loginBar.edgeInsets = NSEdgeInsetsMake(10, 16, 10, 16);
        _loginBar.accessibilityIdentifier = @"garminLoginBar";
        _loginBar.hidden = YES;
        NSStackView *top = [NSStackView stackViewWithViews:@[ _loginBar, _webView ]];
        top.orientation = NSUserInterfaceLayoutOrientationVertical;
        top.alignment = NSLayoutAttributeLeading;
        top.spacing = 0;
        top.translatesAutoresizingMaskIntoConstraints = NO;
        [_webView.widthAnchor constraintEqualToAnchor:top.widthAnchor].active = YES;

        NSView *content = window.contentView;
        for (NSView *v in @[ top, _status, report, logOut, close ]) [content addSubview:v];
        [NSLayoutConstraint activateConstraints:@[
            [top.topAnchor constraintEqualToAnchor:content.topAnchor],
            [top.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [top.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [top.bottomAnchor constraintEqualToAnchor:_status.topAnchor constant:-10],
            [_status.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
            [_status.trailingAnchor constraintEqualToAnchor:report.leadingAnchor constant:-12],
            [report.centerYAnchor constraintEqualToAnchor:_status.centerYAnchor],
            [report.trailingAnchor constraintEqualToAnchor:logOut.leadingAnchor constant:-8],
            [_status.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],
            [logOut.centerYAnchor constraintEqualToAnchor:_status.centerYAnchor],
            [logOut.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-8],
            [close.centerYAnchor constraintEqualToAnchor:_status.centerYAnchor],
            [close.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
            [_status.heightAnchor constraintGreaterThanOrEqualToConstant:34],
        ]];
    }
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
}

#pragma mark - steps

- (NSString *)courseName
{
    return _fileIndex < _files.count ? _files[_fileIndex].URLByDeletingPathExtension.lastPathComponent : @"";
}

- (NSString *)progress
{
    return [NSString stringWithFormat:@"%lu/%lu", (unsigned long)MIN(_fileIndex + 1, _files.count), (unsigned long)_files.count];
}

- (NSString *)activityName
{
    switch (_activity) {
        case BPGarminActivityRoad:     return NSLocalizedString(@"Cyclisme sur route", @"Garmin activity button");
        case BPGarminActivityMountain: return NSLocalizedString(@"VTT", @"Garmin activity button");
        case BPGarminActivityGravel:
        default:                       return NSLocalizedString(@"Gravel bike", @"Garmin activity button");
    }
}

- (void)setStatus:(NSString *)text
{
    if ([text isEqualToString:_statusText]) return;
    _statusText = [text copy];
    _status.stringValue = text;
}

static NSString *BPGarminStepLabel(BPGarminStep s)
{
    switch (s) {
        case BPGarminStepLoading: return @"loading";
        case BPGarminStepLogin: return @"login";
        case BPGarminStepCourses: return @"courses";
        case BPGarminStepImportPopup: return @"import popup";
        case BPGarminStepStart: return @"start";
        case BPGarminStepActivity: return @"activity";
        case BPGarminStepName: return @"name";
        case BPGarminStepUserSave: return @"user save";
        case BPGarminStepDone: return @"done";
    }
    return @"?";
}

- (void)setStep:(BPGarminStep)step
{
    if (step == _step && _stepStarted) return;
    // diagnostics (public: no personal data; never the login)
    [self note:[NSString stringWithFormat:@"step %@ (course %lu/%lu) at %@", BPGarminStepLabel(step),
           (unsigned long)_fileIndex + 1, (unsigned long)_files.count, _webView.URL.path ?: @"-"]];
    _step = step;
    _stepStarted = [NSDate date];
    [self showLoginBar:step == BPGarminStepLogin];
    [self showStatus];
}

- (void)showLoginBar:(BOOL)show
{
    if (show == !_loginBar.hidden) return;
    _loginBar.hidden = !show;
    if (show && !_accountField.stringValue.length) {
        NSDictionary *login = [self savedLogin]; // BikePlanner's own item: the fields ready
        if (login) {
            _accountField.stringValue = login[@"account"];
            _passwordField.stringValue = login[@"password"];
        }
    }
    if (!show) _passwordField.stringValue = @""; // not kept in the window once logged in
}

- (BOOL)loginBarShown
{
    return !_loginBar.hidden;
}

// the login of the native fields (typed, or chosen in the macOS Passwords AutoFill) into the Garmin page
- (IBAction)fillLoginFromFields:(id)sender
{
    NSString *account = _accountField.stringValue, *password = _passwordField.stringValue;
    if (!account.length || !password.length) {
        NSBeep();
        return;
    }
    NSData *args = [NSJSONSerialization dataWithJSONObject:@[ account, password, @YES ] options:0 error:NULL];
    NSString *js = [NSString stringWithFormat:@"window.__bpg ? __bpg.fill.apply(null, %@) : false",
                    [[NSString alloc] initWithData:args encoding:NSUTF8StringEncoding]];
    [self evaluate:js then:^(BOOL ok) {
        [self note:[NSString stringWithFormat:@"login fields %@ from the login bar", ok ? @"filled" : @"not found"]];
        if (ok) {
            self->_filledPage = self->_webView.URL;
            [self setStatus:NSLocalizedString(@"Your login is filled in the Garmin page: click “Se connecter” (Sign In).", @"Garmin Connect status")];
        } else {
            [self setStatus:NSLocalizedString(@"The login fields of the Garmin page were not found: type the login in the page.", @"Garmin Connect status")];
        }
    }];
}

// the normal status of the step, or what to do by hand when the step was not recognized in time
- (void)showStatus
{
    BOOL late = -[_stepStarted timeIntervalSinceNow] > self.stepTimeout;
    if (late && _lateNoted != _stepStarted && _step != BPGarminStepLogin && _step != BPGarminStepUserSave && _step != BPGarminStepDone) {
        _lateNoted = _stepStarted;
        [self note:[NSString stringWithFormat:@"step %@ not recognized after %.0f s at %@", BPGarminStepLabel(_step),
                    self.stepTimeout, _webView.URL.path ?: @"-"]];
    }
    NSString *name = [self courseName], *progress = [self progress];
    NSString *working = [NSString stringWithFormat:NSLocalizedString(@"Importing “%@” (%@)…", @"Garmin Connect status"), name, progress];
    switch (_step) {
        case BPGarminStepLoading:
            [self setStatus:NSLocalizedString(@"Opening Garmin Connect…", @"Garmin Connect status")]; break;
        case BPGarminStepLogin:
            [self setStatus:_filledPage
                ? NSLocalizedString(@"Your Garmin Connect login is filled from the Keychain: click “Se connecter” (Sign In).", @"Garmin Connect status")
                : NSLocalizedString(@"Log in to Garmin Connect: choose a saved password in the fields above (click in a field), then “Fill Garmin Login”, or type in the page.", @"Garmin Connect status")]; break;
        case BPGarminStepCourses:
            [self setStatus:late ? NSLocalizedString(@"Step not recognized: click “Importer” (Import) on the courses page.", @"Garmin Connect status") : working]; break;
        case BPGarminStepImportPopup:
            [self setStatus:late ? [NSString stringWithFormat:NSLocalizedString(@"Step not recognized: click the drop zone, “%@.gpx” is chosen for you.", @"Garmin Connect status"), name] : working]; break;
        case BPGarminStepStart:
            [self setStatus:late ? NSLocalizedString(@"Step not recognized: click “Mise en route” (Get Started).", @"Garmin Connect status") : working]; break;
        case BPGarminStepActivity:
            [self setStatus:late ? [NSString stringWithFormat:NSLocalizedString(@"Step not recognized: choose the activity “%@”.", @"Garmin Connect status"), [self activityName]] : working]; break;
        case BPGarminStepName:
            [self setStatus:late ? NSLocalizedString(@"Step not recognized: click “Enregistrer” (Save).", @"Garmin Connect status") : working]; break;
        case BPGarminStepUserSave:
            [self setStatus:[NSString stringWithFormat:NSLocalizedString(@"Check the name and the privacy of “%@” (%@), then click “Enregistrer”.", @"Garmin Connect status"), name, progress]]; break;
        case BPGarminStepDone:
            [self setStatus:_files.count > 1
                ? [NSString stringWithFormat:NSLocalizedString(@"Done: %lu courses on Garmin Connect. Open each one and send it to your device (Send to Device).", @"Garmin Connect status"), (unsigned long)_files.count]
                : NSLocalizedString(@"Done: the course is on Garmin Connect. Send it to your device from its page (Send to Device).", @"Garmin Connect status")]; break;
    }
}

- (NSURL *)coursesURL
{
    return [_base URLByAppendingPathComponent:@"app/courses"];
}

- (void)start
{
    [self setStep:BPGarminStepLoading];
    [_webView loadRequest:[NSURLRequest requestWithURL:[self coursesURL]]];
    [_timer invalidate];
    __weak BPGarminConnectController *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [weakSelf tick]; }];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

// a click looked for: logged when it succeeds, and once when it starts failing in a step
- (void)logClick:(NSArray<NSString *> *)texts found:(BOOL)found
{
    NSString *what = [texts componentsJoinedByString:@" | "];
    if (found) {
        [self note:[NSString stringWithFormat:@"clicked “%@” at %@", what, _webView.URL.path ?: @"-"]];
        _loggedMiss = nil;
    } else if (![_loggedMiss isEqualToString:what]) {
        [self note:[NSString stringWithFormat:@"“%@” not found yet at %@", what, _webView.URL.path ?: @"-"]];
        _loggedMiss = what;
    }
}

#pragma mark - the report of the session (owner's choice 2026-11-23: a popup, copied to the clipboard)

// a line of the diagnostics: in the system log (public: no personal data, never the login) and in the report
- (void)note:(NSString *)line
{
    os_log(OS_LOG_DEFAULT, "Garmin: %{public}@", line);
    static NSDateFormatter *f;
    if (!f) {
        f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"HH:mm:ss.S";
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    }
    [_report addObject:[NSString stringWithFormat:@"%@ %@", [f stringFromDate:[NSDate date]], line]];
    if (_report.count > 500) [_report removeObjectAtIndex:0];
}

// the report: the app and the system, the current step and page, the texts of the buttons of the page (to see a
// renamed button), then the lines of the session. The page path only (no query); never the login
- (void)reportTextWithCompletion:(void (^)(NSString *text))completion
{
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSMutableString *t = [NSMutableString string];
    [t appendFormat:@"BikePlanner %@ (build %@, %@), macOS %@\n", info[@"CFBundleShortVersionString"] ?: @"?",
     info[@"CFBundleVersion"] ?: @"?", info[@"BPGitCommit"] ?: @"?", NSProcessInfo.processInfo.operatingSystemVersionString];
    [t appendFormat:@"Send to Garmin Connect (#79), %@\n", [NSISO8601DateFormatter stringFromDate:[NSDate date]
                                                            timeZone:NSTimeZone.localTimeZone
                                                       formatOptions:NSISO8601DateFormatWithInternetDateTime]];
    [t appendFormat:@"Course %lu/%lu, activity %@, step %@, page %@%@\n", (unsigned long)_fileIndex + 1, (unsigned long)_files.count,
     [self activityName], BPGarminStepLabel(_step), _webView.URL.host ?: @"-", _webView.URL.path ?: @""];
    [t appendFormat:@"Status: %@\n", _statusText];
    NSString *js = @"(function () { var seen = {}, out = [];"
                   @"  document.querySelectorAll('button, a, [role=button], input[type=submit], input[type=button]').forEach(function (e) {"
                   @"    if (!e.offsetParent && e.getClientRects().length === 0) return;"
                   @"    var s = (e.innerText || e.value || e.getAttribute('aria-label') || '').replace(/\\s+/g, ' ').trim().slice(0, 80);"
                   @"    if (s && !seen[s] && out.length < 120) { seen[s] = 1; out.push(s); } });"
                   @"  return out; })()";
    NSArray<NSString *> *lines = [_report copy];
    [_webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        [t appendString:@"\nButtons on the page:\n"];
        if ([result isKindOfClass:[NSArray class]] && [result count]) {
            for (id b in result) if ([b isKindOfClass:[NSString class]]) [t appendFormat:@"  - %@\n", b];
        } else {
            [t appendString:@"  (none)\n"];
        }
        [t appendString:@"\nSession:\n"];
        for (NSString *l in lines) [t appendFormat:@"  %@\n", l];
        completion(t);
    }];
}

- (IBAction)reportProblem:(id)sender
{
    [self note:@"report shown"];
    [self reportTextWithCompletion:^(NSString *text) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"Report a Problem with Garmin Connect", @"Garmin Connect report");
        alert.informativeText = NSLocalizedString(@"What BikePlanner did in this window (no password). Copy it and send it "
                                                  @"with a few words on what went wrong.", @"Garmin Connect report");
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 520, 260)];
        scroll.hasVerticalScroller = YES;
        scroll.borderType = NSBezelBorder;
        NSTextView *view = [[NSTextView alloc] initWithFrame:scroll.bounds];
        view.editable = NO;
        view.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
        view.string = text;
        view.autoresizingMask = NSViewWidthSizable;
        view.accessibilityIdentifier = @"garminReportText";
        scroll.documentView = view;
        alert.accessoryView = scroll;
        [alert addButtonWithTitle:NSLocalizedString(@"Copy to Clipboard", @"Garmin Connect report")];
        [alert addButtonWithTitle:NSLocalizedString(@"Close", @"Garmin Connect report")];
        self->_reportAlert = alert;
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
            self->_reportAlert = nil;
            if (r == NSAlertFirstButtonReturn) [self copyReportText:text];
        }];
    }];
}

- (void)copyReportText:(NSString *)text
{
    NSPasteboard *pb = self.reportPasteboard ?: NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    [self note:@"report copied"];
}

- (void)evaluate:(NSString *)js then:(void (^)(BOOL ok))then
{
    _evaluating = YES;
    __weak BPGarminConnectController *weakSelf = self;
    [_webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        BPGarminConnectController *s = weakSelf;
        if (!s) return;
        s->_evaluating = NO;
        then([result isKindOfClass:[NSNumber class]] && [result boolValue]);
    }];
}

- (NSString *)clickScript:(NSArray<NSString *> *)texts
{
    NSData *json = [NSJSONSerialization dataWithJSONObject:texts options:0 error:NULL];
    return [NSString stringWithFormat:@"window.__bpg ? __bpg.click(%@) : false",
            [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
}

// twice a second: where is the page, what to do next
- (void)tick
{
    if (_evaluating || _webView.isLoading) return;
    [self showStatus]; // a late step shows what to do by hand
    NSURL *url = _webView.URL;
    NSString *path = url.path ?: @"";
    BOOL onGarmin = [url.host isEqualToString:_base.host] && [path hasPrefix:@"/app"];
    if (!onGarmin) {
        // the login page (sso.garmin.com, another domain): the user logs in; the fields filled from the Keychain
        if (_step != BPGarminStepUserSave && _step != BPGarminStepDone && url) {
            [self setStep:BPGarminStepLogin];
            [self fillLoginIfSaved:url];
        }
        return;
    }
    if (_typedLogin) [self offerToRememberLogin];
    BOOL inEditor = [path hasPrefix:@"/app/course/create"];
    switch (_step) {
        case BPGarminStepLoading:
        case BPGarminStepLogin: {
            if ([path hasPrefix:@"/app/courses"]) {
                [self setStep:BPGarminStepCourses];
            } else {
                [self setStep:BPGarminStepLoading];
                [_webView loadRequest:[NSURLRequest requestWithURL:[self coursesURL]]];
            }
            break;
        }
        case BPGarminStepCourses: {
            if (!_fileGiven && [path hasPrefix:@"/app/courses"]) {
                [self evaluate:[self clickScript:[BPGarminCourse importButtonTexts]] then:^(BOOL ok) {
                    [self logClick:[BPGarminCourse importButtonTexts] found:ok];
                    if (ok) [self setStep:BPGarminStepImportPopup];
                }];
            }
            break;
        }
        case BPGarminStepImportPopup: {
            [self evaluate:@"window.__bpg ? __bpg.clickFile() : false" then:^(BOOL ok) {
                [self logClick:@[ @"file input" ] found:ok];
                if (ok) [self setStep:BPGarminStepStart];
            }];
            break;
        }
        case BPGarminStepStart: {
            if (inEditor) {
                [self setStep:BPGarminStepActivity]; // "Mise en route" clicked by hand
            } else if (_fileGiven) {
                [self evaluate:[self clickScript:[BPGarminCourse startButtonTexts]] then:^(BOOL ok) {
                    [self logClick:[BPGarminCourse startButtonTexts] found:ok];
                    if (ok) {
                        self->_lastStartClick = [NSDate date];
                        [self setStep:BPGarminStepActivity];
                    }
                }];
            }
            break;
        }
        case BPGarminStepActivity: {
            if (!inEditor && [path hasPrefix:@"/app/courses"]) {
                // "Mise en route" clicked while Garmin still processed the file (real site, 2026-11-23: the page
                // stayed): clicked again every 2 s while the button is there
                if (-[_lastStartClick timeIntervalSinceNow] < 2) break;
                self->_lastStartClick = [NSDate date];
                [self evaluate:[self clickScript:[BPGarminCourse startButtonTexts]] then:^(BOOL ok) {
                    if (ok) [self note:@"“mise en route” clicked again (the editor did not open)"];
                }];
            } else if (inEditor) {
                [self evaluate:[self clickScript:[BPGarminCourse buttonTextsForActivity:_activity]] then:^(BOOL ok) {
                    [self logClick:[BPGarminCourse buttonTextsForActivity:self->_activity] found:ok];
                    if (ok) [self setStep:BPGarminStepName];
                }];
            }
            break;
        }
        case BPGarminStepName: {
            if (inEditor) {
                [self evaluate:[self clickScript:[BPGarminCourse saveButtonTexts]] then:^(BOOL ok) {
                    [self logClick:[BPGarminCourse saveButtonTexts] found:ok];
                    if (ok) [self setStep:BPGarminStepUserSave];
                }];
            }
            break;
        }
        case BPGarminStepUserSave: {
            // the user saved (or left the editor): the next course
            if (!inEditor) {
                _fileIndex++;
                _fileGiven = NO;
                if (_fileIndex < _files.count) {
                    [self setStep:BPGarminStepLoading];
                    [_webView loadRequest:[NSURLRequest requestWithURL:[self coursesURL]]];
                } else {
                    _fileIndex = _files.count - 1;
                    [self setStep:BPGarminStepDone];
                    [_timer invalidate];
                }
            }
            break;
        }
        case BPGarminStepDone: {
            break;
        }
    }
}

#pragma mark - the login in the Keychain

// read once per sheet: each read may ask the user's permission (a prompt of macOS; an ad hoc signed build is a
// new app for the Keychain after each build); a refused read is not asked again in the sheet
- (nullable NSDictionary<NSString *, NSString *> *)savedLogin
{
    if (!_savedLoginRead) {
        _savedLoginRead = YES;
        _savedLogin = [self.credentials savedLogin];
    }
    return _savedLogin;
}

- (void)fillLoginIfSaved:(NSURL *)page
{
    if ([_filledPage isEqual:page]) return;
    NSDictionary *login = [self savedLogin];
    if (!login) return;
    NSData *args = [NSJSONSerialization dataWithJSONObject:@[ login[@"account"], login[@"password"] ] options:0 error:NULL];
    NSString *list = [[NSString alloc] initWithData:args encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"window.__bpg ? __bpg.fill.apply(null, %@) : false", list];
    [self evaluate:js then:^(BOOL ok) {
        [self note:[NSString stringWithFormat:@"login fields %@ from the Keychain", ok ? @"filled" : @"not found"]];
        if (ok) {
            self->_filledPage = page;
            [self showStatus];
        }
    }];
}

- (void)userContentController:(WKUserContentController *)c didReceiveScriptMessage:(WKScriptMessage *)message
{
    if (![message.name isEqualToString:@"bpgLogin"] || ![message.body isKindOfClass:[NSDictionary class]]) return;
    NSString *account = message.body[@"account"], *password = message.body[@"password"];
    if ([account isKindOfClass:[NSString class]] && [password isKindOfClass:[NSString class]] && account.length && password.length) {
        _typedLogin = @{ @"account": account, @"password": password };
        [self note:@"login typed on the login page (kept until logged in)"];
    }
}

// once logged in: remember the login typed? (not when it is already the saved one, or never for this account)
- (void)offerToRememberLogin
{
    NSDictionary *typed = _typedLogin;
    _typedLogin = nil;
    NSString *account = typed[@"account"];
    if (_askedToRemember || [typed isEqualToDictionary:[self savedLogin] ?: @{}] || [self.credentials isNeverSaved:account]) return;
    _askedToRemember = YES;
    id<BPGarminCredentialStore> store = self.credentials;
    void (^answer)(BPGarminRemember) = ^(BPGarminRemember choice) {
        [self note:[NSString stringWithFormat:@"remember the login? %@", choice == BPGarminRememberYes ? @"yes"
               : choice == BPGarminRememberNever ? @"never for this account" : @"not now"]];
        if (choice == BPGarminRememberYes && [store saveAccount:account password:typed[@"password"]]) self->_savedLogin = typed;
        else if (choice == BPGarminRememberNever) [store setNeverSaved:account];
    };
    if (self.rememberPrompt) {
        self.rememberPrompt(account, answer);
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Remember this Garmin Connect login in the Keychain?", @"Garmin Connect");
    alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"BikePlanner will fill “%@” and its password on the Garmin login page; you still click “Se connecter”.", @"Garmin Connect"), account];
    [alert addButtonWithTitle:NSLocalizedString(@"Remember", @"Garmin Connect")];
    [alert addButtonWithTitle:NSLocalizedString(@"Not Now", @"Garmin Connect")];
    [alert addButtonWithTitle:NSLocalizedString(@"Never for This Account", @"Garmin Connect")];
    // a window of its own (a sheet on the Garmin sheet ended with it, without an answer), after the current event
    dispatch_async(dispatch_get_main_queue(), ^{
        NSModalResponse r = [alert runModal];
        answer(r == NSAlertFirstButtonReturn ? BPGarminRememberYes
               : r == NSAlertSecondButtonReturn ? BPGarminRememberNotNow : BPGarminRememberNever);
    });
}

#pragma mark - web view

// the file chooser of the import popup: the GPX of the current course, without any dialog
- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters
initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL *> * _Nullable))completionHandler
{
    if (_fileIndex >= _files.count || _step == BPGarminStepDone) {
        completionHandler(nil);
        return;
    }
    _fileGiven = YES;
    [self note:[NSString stringWithFormat:@"file chooser answered with “%@”", _files[_fileIndex].lastPathComponent]];
    if (_step == BPGarminStepCourses || _step == BPGarminStepImportPopup) [self setStep:BPGarminStepStart]; // by hand
    completionHandler(@[ _files[_fileIndex] ]);
}

// a link opening a new window (help pages…): in the same view
- (nullable WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
            forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    if (navigationAction.request.URL) [webView loadRequest:navigationAction.request];
    return nil;
}

#pragma mark - actions

- (IBAction)logOut:(nullable id)sender
{
    WKWebsiteDataStore *store = _webView.configuration.websiteDataStore;
    NSSet *types = [WKWebsiteDataStore allWebsiteDataTypes];
    [store fetchDataRecordsOfTypes:types completionHandler:^(NSArray<WKWebsiteDataRecord *> *records) {
        NSMutableArray *garmin = [NSMutableArray array];
        for (WKWebsiteDataRecord *r in records) if ([r.displayName containsString:@"garmin"]) [garmin addObject:r];
        [store removeDataOfTypes:types forDataRecords:garmin completionHandler:^{
            self->_fileIndex = 0;
            self->_fileGiven = NO;
            [self start];
        }];
    }];
}

- (void)closeSheet:(nullable id)sender
{
    [_timer invalidate];
    NSWindow *parent = self.window.sheetParent;
    if (parent) [parent endSheet:self.window];
    else [self.window orderOut:sender];
    if (self.closeHandler) self.closeHandler();
}

- (void)close
{
    [_timer invalidate];
    [super close];
}

@end

#endif // BP_GARMIN_CONNECT
