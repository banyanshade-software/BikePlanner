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
@end
