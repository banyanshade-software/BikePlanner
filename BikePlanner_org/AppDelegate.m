//
//  AppDelegate.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "AppDelegate.h"
#import "BRFProfileEditor.h"

@implementation AppDelegate {
    BRFProfileEditor *brfEditor;
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    //[self installRunLoopLogger];
    //[self installRunLoopModeLogger];
    [self.mapController initializeMapview];
    [self.streetViewController initializeStreetView];
    
    [self.window makeKeyAndOrderFront:nil];
    
    //NSURL *url = [NSURL URLWithString:@"https://brouter.de/brouter/profiles2/trekking.brf"];
    //BRFProfileEditor *editor = [[BRFProfileEditor alloc] initWithProfileURL:url profileName:@"trekking"];
    brfEditor = [[BRFProfileEditor alloc] initWithProfileName:@"trekking"];
    brfEditor.completionHandler = ^(NSArray * _Nullable overideParams) {
        if (overideParams && [overideParams count]) {
             NSLog(@"User overrides: %@", overideParams);
             // append to request as &extraParams=... (remember to percent-encode later)
            NSString *extraParams = [overideParams componentsJoinedByString:@"&"];
            self.mapController.extraUrl = [@"extraParams=" stringByAppendingString:extraParams];
            [self.mapController shouldRecalcRoute];
         } else {
             NSLog(@"User cancelled");
         }
     };
    [brfEditor showWindow:self];

    //[editor loadWindow];
    //[editor showEditor];
}



static void RunLoopLogger(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
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
#if 0
- (void)installRunLoopLogger {
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
#endif

- (void)installRunLoopModeLogger {
    CFRunLoopObserverContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
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
@end


/*
 Notes / Usage:
 - This is a minimal example meant to be compiled as a macOS Command Line Tool target that links AppKit and MapKit, or adapted into an Xcode Cocoa project.
 - The app uses OpenStreetMap tiles at https://tile.openstreetmap.org/{z}/{x}/{y}.png. Respect tile usage policy if using public tile servers.
 - BRouter server: by default this example points to http://127.0.0.1:17777. You can run a local brouter server or point to a public instance if available.
 - The BRouter endpoint used is /brouter with parameters lonlats and format=gpx (the code requests GPX and parses <trkpt> elements).
 - For production use: add robust GPX parsing, error handling, tile cache, rate-limiting, UI for choosing profiles and server, and follow server usage policies.
*/

