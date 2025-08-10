//
//  MapController.m
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import "MapController.h"
#import "SafeTileRenderer.h"
#import "SafeOSMTileOverlay.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation MapController 

- (void) initializeMapview
{
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

    NSPopUpButton *profileMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(14, 36, 200, 26)];
    [profileMenu addItemsWithTitles:@[@"trekking", @"fastbike", @"car-fast", @"car-eco"]];
    [content addSubview:profileMenu];
    
    NSSegmentedControl *maptype = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(14, 64, 200, 26)];
    maptype.segmentCount = 3;
    maptype.selectedSegment = 0;
    [maptype setLabel:@"OSM" forSegment:0];
    [maptype setLabel:@"Apple" forSegment:1];
    [maptype setLabel:@"Sat" forSegment:2];
    maptype.segmentStyle = NSSegmentStyleRoundRect;
    [content addSubview:maptype];
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
}



- (void)clearAction:(id)sender
{
    self.hasStart = NO; self.hasEnd = NO;
    self.gpxData = nil;
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
        [self.svCtrl viewCoord:coord];
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
    [self.svCtrl viewCoord:coord];
}

- (void)requestRoute
{
    // profile can be changed, e.g. "trekking", "fastbike", etc.
    self.gpxData = nil;
    NSString *profile = @"trekking";
    [self.brouter routeFrom:self.startCoord to:self.endCoord profile:profile completion:^(NSArray<CLLocation *> *points, NSData *gpx, NSError *error) {
        if (error) {
            NSLog(@"BRouter error: %@", error);
            return;
        }
        if (points.count == 0) { NSLog(@"No points returned"); return; }

        self.gpxData = gpx;
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



- (IBAction) exportGPX:(id)sender
{
    if (!_gpxData) return;
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.title = @"Export GPX route";
    //savePanel.allowedFileTypes = @[@"gpx"]; // Change or remove as needed
    savePanel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"gpx"]];
    savePanel.nameFieldStringValue = @"plan.gpx"; // Suggested filename
    
    [savePanel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
                NSURL *destinationURL = savePanel.URL;
                NSError *error = nil;
                
                if (![self.gpxData writeToURL:destinationURL options:NSDataWritingAtomic error:&error]) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Export failed";
                    alert.informativeText = error.localizedDescription;
                    [alert runModal];
                }
            }
        }];
}
@end
