//
//  AppDelegate.m
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    //[self installRunLoopLogger];
    [self installRunLoopModeLogger];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    // Only create a new untitled doc if there are no open windows
    if ([NSApp windows].count == 0) {
        return YES; // make one
    }
    return NO; // don’t
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
