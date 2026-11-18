//
//  BPGarminConnectController.m
//  BikePlanner
//
//  File ▸ Send to Garmin Connect… (#79).
//

#import "BPGarminConnectController.h"
#import "BPEnvironment.h"

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
    @"  return {"
    @"    click: function (texts) { var e = find(texts); if (!e) return false; e.click(); return true; },"
    @"    clickFile: function () { var i = document.querySelector('input[type=file]'); if (!i) return false; i.click(); return true; }"
    @"  };"
    @"})();";

@implementation BPGarminConnectController {
    NSArray<NSURL *> *_files;
    BPGarminActivity _activity;
    NSTextField *_status;
    NSTimer *_timer;
    BOOL _evaluating;
    BOOL _fileGiven;
    NSDate *_stepStarted;
    NSURL *_base;
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

        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        // the Garmin session is kept in the app's website data (tests: nothing kept)
        config.websiteDataStore = handler ? [WKWebsiteDataStore nonPersistentDataStore] : [WKWebsiteDataStore defaultDataStore];
        if (handler && scheme) [config setURLSchemeHandler:handler forURLScheme:scheme];
        [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:BPGarminHelpers
                                                                            injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                                         forMainFrameOnly:YES]];
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
        for (NSView *v in @[ logOut, close ]) v.translatesAutoresizingMaskIntoConstraints = NO;

        NSView *content = window.contentView;
        for (NSView *v in @[ _webView, _status, logOut, close ]) [content addSubview:v];
        [NSLayoutConstraint activateConstraints:@[
            [_webView.topAnchor constraintEqualToAnchor:content.topAnchor],
            [_webView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [_webView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [_webView.bottomAnchor constraintEqualToAnchor:_status.topAnchor constant:-10],
            [_status.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
            [_status.trailingAnchor constraintEqualToAnchor:logOut.leadingAnchor constant:-12],
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

- (void)setStep:(BPGarminStep)step
{
    if (step == _step && _stepStarted) return;
    _step = step;
    _stepStarted = [NSDate date];
    [self showStatus];
}

// the normal status of the step, or what to do by hand when the step was not recognized in time
- (void)showStatus
{
    BOOL late = -[_stepStarted timeIntervalSinceNow] > self.stepTimeout;
    NSString *name = [self courseName], *progress = [self progress];
    NSString *working = [NSString stringWithFormat:NSLocalizedString(@"Importing “%@” (%@)…", @"Garmin Connect status"), name, progress];
    switch (_step) {
        case BPGarminStepLoading:
            [self setStatus:NSLocalizedString(@"Opening Garmin Connect…", @"Garmin Connect status")]; break;
        case BPGarminStepLogin:
            [self setStatus:NSLocalizedString(@"Log in to Garmin Connect in this window: the app never sees your password, and the login is kept for the next times.", @"Garmin Connect status")]; break;
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
        // the login page (sso.garmin.com, another domain): the user logs in
        if (_step != BPGarminStepUserSave && _step != BPGarminStepDone && url) [self setStep:BPGarminStepLogin];
        return;
    }
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
                    if (ok) [self setStep:BPGarminStepImportPopup];
                }];
            }
            break;
        }
        case BPGarminStepImportPopup: {
            [self evaluate:@"window.__bpg ? __bpg.clickFile() : false" then:^(BOOL ok) {
                if (ok) [self setStep:BPGarminStepStart];
            }];
            break;
        }
        case BPGarminStepStart: {
            if (inEditor) {
                [self setStep:BPGarminStepActivity]; // "Mise en route" clicked by hand
            } else if (_fileGiven) {
                [self evaluate:[self clickScript:[BPGarminCourse startButtonTexts]] then:^(BOOL ok) {
                    if (ok) [self setStep:BPGarminStepActivity];
                }];
            }
            break;
        }
        case BPGarminStepActivity: {
            if (inEditor) {
                [self evaluate:[self clickScript:[BPGarminCourse buttonTextsForActivity:_activity]] then:^(BOOL ok) {
                    if (ok) [self setStep:BPGarminStepName];
                }];
            }
            break;
        }
        case BPGarminStepName: {
            if (inEditor) {
                [self evaluate:[self clickScript:[BPGarminCourse saveButtonTexts]] then:^(BOOL ok) {
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
