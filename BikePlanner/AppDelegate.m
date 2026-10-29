//
//  AppDelegate.m
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import "AppDelegate.h"
#import "BSSUI_AboutWindowController.h"
#import "BPEnvironment.h"
#import "BPPreferences.h"
#import "BPPreferencesWindowController.h"

@interface AppDelegate ()
@property (nonatomic, strong) BSSUI_AboutWindowController *aboutWindowController;
@property (nonatomic, strong) BPPreferencesWindowController *preferencesWindowController;

@end

@implementation AppDelegate

+ (void)initialize
{
    if (self == [AppDelegate class]) [BPPreferences registerDefaults]; // before any document is created (#27)
}

// single Preferences window (#27)
- (IBAction)showPreferences:(id)sender
{
    if (!self.preferencesWindowController) {
        self.preferencesWindowController = [[BPPreferencesWindowController alloc] initWithPreferences:[BPPreferences shared]];
    }
    [self.preferencesWindowController showWindow:sender];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    //[self installRunLoopLogger];
    //[self installRunLoopModeLogger];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    // no document window when hosting unit tests (avoids network access during tests)
    if ([BPEnvironment isUnitTestHost]) return NO;
    NSArray<NSDocument *> *docs = NSDocumentController.sharedDocumentController.documents;
    return [self shouldOpenUntitledFileWithDocuments:docs];
}

// a new untitled document when no document is open or restored (#46): the number of windows was used, but the app
// may have other windows (About, Preferences, panels…)
- (BOOL)shouldOpenUntitledFileWithDocuments:(NSArray<NSDocument *> *)documents
{
    return documents.count == 0;
}

#pragma mark -

static void RunLoopLogger(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info)
{
    NSString *phase;
    switch (activity) {
        case kCFRunLoopEntry: phase = @"Entry"; break;
        case kCFRunLoopBeforeTimers: phase = @"BeforeTimers"; break;
        case kCFRunLoopBeforeSources: phase = @"BeforeSources"; break;
        case kCFRunLoopBeforeWaiting: phase = @"BeforeWaiting"; break;
        case kCFRunLoopAfterWaiting: phase = @"AfterWaiting"; break;
        case kCFRunLoopExit: phase = @"Exit"; break;
        default: phase = [NSString stringWithFormat:@"Activity %lu", activity]; break;
    }
    NSLog(@"[RunLoop] %@", phase);
}

- (void)installRunLoopLogger
{
    CFRunLoopObserverContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    CFRunLoopObserverRef observer = CFRunLoopObserverCreate(
        kCFAllocatorDefault,
        kCFRunLoopAllActivities,
        YES, // repeat
        0,   // order
        RunLoopLogger,
        &context
    );
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
    CFRelease(observer);
}

- (void)installRunLoopModeLogger
{
    //CFRunLoopObserverContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(
        NULL,
        kCFRunLoopAllActivities,
        YES,
        0,
        ^(CFRunLoopObserverRef obs, CFRunLoopActivity activity) {
            NSString *mode = (__bridge_transfer NSString *)CFRunLoopCopyCurrentMode(CFRunLoopGetMain());
            if (activity == kCFRunLoopBeforeWaiting) {
                NSLog(@"[%@] Run loop idle in mode: %@", [NSDate date], mode);
            }
        }
                                                                       );
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
    CFRelease(observer);
}

/*
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
 */


#pragma mark - DCO about win


- (DCOAboutWindowController *) aboutWindowController {
    if(!_aboutWindowController) {
        _aboutWindowController = [[BSSUI_AboutWindowController alloc] init];
        _aboutWindowController.appVersion = [AppDelegate versionStringWithInfo:[NSBundle mainBundle].infoDictionary];
        NSString *website = [NSBundle mainBundle].infoDictionary[@"BPWebsiteURL"]; // #36
        if (website) _aboutWindowController.appWebsiteURL = [NSURL URLWithString:website];
    }
    return _aboutWindowController;
}




// "Version 0.4.0 (Build 123, 5a33d4f-dirty, small-features)": build number and git info are written into the
// built Info.plist by scripts/set_build_info.sh (#34); without git info: "Version 0.4.0 (Build 1)"
+ (NSString *) versionStringWithInfo:(NSDictionary *)info
{
    NSMutableArray *build = [NSMutableArray arrayWithObject:info[@"CFBundleVersion"] ?: @"?"];
    if ([info[@"BPGitCommit"] length]) [build addObject:info[@"BPGitCommit"]];
    if ([info[@"BPGitBranch"] length]) [build addObject:info[@"BPGitBranch"]];
    return [NSString stringWithFormat:NSLocalizedString(@"Version %@ (Build %@)", @"Version %@ (Build %@), displayed in the about window"),
            info[@"CFBundleShortVersionString"] ?: @"?", [build componentsJoinedByString:@", "]];
}

- (void)setUseTextView:(BOOL)useTextView {
    
    _useTextView = useTextView;
    self.aboutWindowController.useTextViewForAcknowledgments = useTextView;
}



- (IBAction)showAboutWindow:(id)sender {
    
    // Set about window values (override defaults)
    //self.aboutWindowController.appWebsiteURL = [NSURL URLWithString:@"http://www.dangercove.com/tapetrap?source=DCOAbouwWindowExample"];
    //self.aboutWindowController.useTextViewForAcknowledgments = NO;

    // Show the about window
    [self.aboutWindowController showWindow:nil];
    
}

@end
