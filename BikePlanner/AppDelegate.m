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

    NSString *s = @"https://www.google.com/maps/@44.1042884,0.5239076,3a,75y,166.01h,82.2t/data=!3m7!1e1!3m5!1sUAywig97gsSiSgRpXM4R_g!2e0!6shttps:%2F%2Fstreetviewpixels-pa.googleapis.com%2Fv1%2Fthumbnail%3Fcb_client%3Dmaps_sv.tactile%26w%3D900%26h%3D600%26pitch%3D7.796108031354706%26panoid%3DUAywig97gsSiSgRpXM4R_g%26yaw%3D166.01471008172715!7i16384!8i8192?entry=ttu&g_ep=EgoyMDI1MDgwNi4wIKXMDSoASAFQAw%3D%3D";
    // https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=44.1042884,0.5239076
    // &heading 0-360
    NSURL *url = [NSURL URLWithString:s];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:req];
    
    
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

