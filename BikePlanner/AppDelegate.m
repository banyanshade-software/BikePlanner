//
//  AppDelegate.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "AppDelegate.h"

@implementation AppDelegate


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self.mapController initializeMapview];
    [self.streetViewController initializeStreetView];
    
    [self.window makeKeyAndOrderFront:nil];
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

