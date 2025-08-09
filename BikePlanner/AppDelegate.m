//
//  AppDelegate.m
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import "AppDelegate.h"
#import "SafeTileRenderer.h"
#import "SafeOSMTileOverlay.h"

@implementation AppDelegate


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    if ((0)) {
        NSRect frame = NSMakeRect(0, 0, 900, 600);
        self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
        [self.window center];
        [self.window setTitle:@"BRouter + OpenStreetMap (Objective-C Demo)"];
    }
    NSView *content = [_mapView superview];// self.window.contentView;

    // Map view
    /*
     if (!_mapView) {
        self.mapView = [[MKMapView alloc] initWithFrame:content.bounds];
        self.mapView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [content addSubview:self.mapView];
    }*/
    self.mapView.delegate = self;

    // Add OpenStreetMap tile overlay
    NSString *template = @"https://tile.openstreetmap.org/{z}/{x}/{y}.png";
    SafeOSMTileOverlay *osm = [[SafeOSMTileOverlay alloc] initWithURLTemplate:template];
    osm.canReplaceMapContent = NO; // replace Apple's map
    [self.mapView addOverlay:osm level:MKOverlayLevelAboveRoads];

    // Buttons
    NSButton *clearBtn = [[NSButton alloc] initWithFrame:NSMakeRect(10, 10, 80, 28)];
    clearBtn.title = @"Clear";
    clearBtn.bezelStyle = NSBezelStyleRounded;
    clearBtn.target = self;
    clearBtn.action = @selector(clearAction:);
    [content addSubview:clearBtn];

    NSTextField *help = [[NSTextField alloc] initWithFrame:NSMakeRect(100, 6, 420, 36)];
    help.bezeled = NO; help.drawsBackground = NO; help.editable = NO; help.selectable = NO;
    help.stringValue = @"Click once to set START, click again to set END. Route is requested automatically.";
    [content addSubview:help];

    // BRouter client (default points to local server at port 17777)
    //NSString *brouter=@"http://127.0.0.1:17777";
    //NSString *brouter=@"https://brouter.de/brouter";
    NSString *brouter=@"https://brouter.de";
    NSURL *server = [NSURL URLWithString:brouter]; // change if using remote brouter
    self.brouter = [[BRouterClient alloc] initWithServerURL:server];

    // Center map to a default location
    //CLLocationCoordinate2D center = CLLocationCoordinate2DMake(48.8566, 2.3522); // Paris
    // 44.1249234 ,0.4961707,10920
    CLLocationCoordinate2D center = CLLocationCoordinate2DMake(44.1249234, 0.4961707); // Laplume
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(center, 20000, 20000) animated:NO];

    // Add click handler
    NSClickGestureRecognizer *clicker = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapClick:)];
    clicker.buttonMask = 0x1; // left mouse
    [self.mapView addGestureRecognizer:clicker];

    NSString *s = @"https://www.google.com/maps/@44.1042884,0.5239076,3a,75y,166.01h,82.2t/data=!3m7!1e1!3m5!1sUAywig97gsSiSgRpXM4R_g!2e0!6shttps:%2F%2Fstreetviewpixels-pa.googleapis.com%2Fv1%2Fthumbnail%3Fcb_client%3Dmaps_sv.tactile%26w%3D900%26h%3D600%26pitch%3D7.796108031354706%26panoid%3DUAywig97gsSiSgRpXM4R_g%26yaw%3D166.01471008172715!7i16384!8i8192?entry=ttu&g_ep=EgoyMDI1MDgwNi4wIKXMDSoASAFQAw%3D%3D";
    NSURL *url = [NSURL URLWithString:s];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:req];
    
    
    [self.window makeKeyAndOrderFront:nil];
}

- (void)clearAction:(id)sender
{
    self.hasStart = NO; self.hasEnd = NO;
    [self.mapView removeAnnotations:self.mapView.annotations];
    [self.mapView removeOverlays:self.mapView.overlays];
}

- (void)handleMapClick:(NSGestureRecognizer *)gesture
{
    NSPoint locInView = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:locInView toCoordinateFromView:self.mapView];

    if (!self.hasStart) {
        self.startCoord = coord; self.hasStart = YES;
        MKPointAnnotation *a = [MKPointAnnotation new]; a.coordinate = coord; a.title = @"Start";
        [self.mapView addAnnotation:a];
        return;
    }

    if (!self.hasEnd) {
        self.endCoord = coord; self.hasEnd = YES;
        MKPointAnnotation *a = [MKPointAnnotation new]; a.coordinate = coord; a.title = @"End";
        [self.mapView addAnnotation:a];

        // Request route automatically
        [self requestRoute];
        return;
    }

    // If both set, replace start with new start (two-click cycle)
    self.hasStart = YES; self.hasEnd = NO;
    self.startCoord = coord;
    [self.mapView removeAnnotations:self.mapView.annotations];
    MKPointAnnotation *a = [MKPointAnnotation new]; a.coordinate = coord; a.title = @"Start";
    [self.mapView addAnnotation:a];
}

- (void)requestRoute {
    // profile can be changed, e.g. "trekking", "fastbike", etc.
    NSString *profile = @"trekking";
    [self.brouter routeFrom:self.startCoord to:self.endCoord profile:profile completion:^(NSArray<CLLocation *> *points, NSError *error) {
        if (error) {
            NSLog(@"BRouter error: %@", error);
            return;
        }
        if (points.count == 0) { NSLog(@"No points returned"); return; }

        // Build polyline
        NSUInteger n = points.count;
        CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * n);
        for (NSUInteger i=0;i<n;i++) coords[i] = points[i].coordinate;
        MKPolyline *poly = [MKPolyline polylineWithCoordinates:coords count:n];
        free(coords);

        dispatch_async(dispatch_get_main_queue(), ^{
            // Remove old route overlays (except tile overlays)
            for (id<MKOverlay> ov in [self.mapView.overlays copy]) {
                if (![ov isKindOfClass:[MKTileOverlay class]]) [self.mapView removeOverlay:ov];
            }
            [self.mapView addOverlay:poly level:MKOverlayLevelAboveLabels];
            [self.mapView setVisibleMapRect:[poly boundingMapRect] edgePadding:NSEdgeInsetsMake(40, 40, 40, 40) animated:YES];
            
            if ((0)) {
                NSArray *overlays = self.mapView.overlays;
                [self.mapView removeOverlays:overlays];
                for (id<MKOverlay> overlay in overlays) {
                    if ([overlay isKindOfClass:[MKPolyline class]]) {
                        [self.mapView addOverlay:overlay level:MKOverlayLevelAboveLabels];
                    } else {
                        [self.mapView addOverlay:overlay level:MKOverlayLevelAboveRoads];
                    }
                }
            }
        });
    }];
}

#pragma mark - MKMapViewDelegate

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay
{
    if ([overlay isKindOfClass:[SafeOSMTileOverlay class]]) {
        return [[SafeTileRenderer alloc] initWithTileOverlay:overlay];
    }
    if ([overlay isKindOfClass:[MKTileOverlay class]]) {
        return [[MKTileOverlayRenderer alloc] initWithTileOverlay:(MKTileOverlay *)overlay];
    }
    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        r.lineWidth = 8.0;
        r.alpha = 0.5;
        r.strokeColor = [NSColor blueColor];
        return r;
    }
    return nil;
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

