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

/*
@interface DraggableWaypoint : CLLocation
@property (nonatomic, assign) NSUInteger index;
@end

@implementation DraggableWaypoint
@end
*/
@interface RouteAnnotation : MKPointAnnotation
@property (nonatomic,assign) NSUInteger idx;
@end

@implementation RouteAnnotation
@end


@implementation MapController {
    NSMutableArray <CLLocation *>*waypoints;
    MKPolyline *poly;
}

- (void) initializeMapview
{
    NSView *content = [_mapView superview];// self.window.contentView;
    waypoints = [[NSMutableArray alloc]initWithCapacity:32];
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
    clicker.numberOfClicksRequired = 1;
    [self.mapView addGestureRecognizer:clicker];
}



- (void)clearAction:(id)sender
{
    [waypoints removeAllObjects];
    //self.hasStart = NO; self.hasEnd = NO;
    self.gpxData = nil;
    [self.mapView removeAnnotations:self.mapView.annotations];
    [self.mapView removeOverlays:self.mapView.overlays];
}

- (void)handleMapClick:(NSGestureRecognizer *)gesture
{
    NSPoint locInView = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:locInView toCoordinateFromView:self.mapView];
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
    
    
    
    if ([self clickNearPolylineAt:coord]) {
        
        [self insertWaypoint:coord];
        return;
    }
    NSString *title = nil;
    if (![waypoints count])  {
        title = @"Start";
    } else {
        title = @"Point";
    }
    RouteAnnotation *a = [[RouteAnnotation alloc] initWithCoordinate:coord title:title subtitle:nil];
    a.idx = [waypoints count];
    [waypoints addObject:loc];

    [self.mapView addAnnotation:a];
    [self.svCtrl viewCoord:coord coalesce:YES];

    [self shouldRecalcRoute];
  
}

- (void) shouldRecalcRoute
{
    if ([waypoints count]>=2) {
        [self requestRoute];
    }
    /*if (self.hasEnd && self.hasStart) {
        // 0.495477,44.178503
        if ((0)) self.startCoord = CLLocationCoordinate2DMake(44.178503, 0.495477);
        [self requestRoute];
    }*/
}
- (void) requestRoute
{
    // profile can be changed, e.g. "trekking", "fastbike", etc.
    self.gpxData = nil;
    NSString *profile = @"trekking";
    [self.brouter routeWithWaypoints:waypoints profile:profile extraUrl:_extraUrl completion:^(NSArray<CLLocation *> *points, NSData *gpx, NSError *error) {
        if (error) {
            NSLog(@"BRouter error: %@", error);
            return;
        }
        if (points.count == 0) {
            NSLog(@"No points returned");
            return;
        }

        self.gpxData = gpx;
        // Build polyline
        NSUInteger n = points.count;
        CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * n);
        for (NSUInteger i=0;i<n;i++) {
            coords[i] = points[i].coordinate;
        }
        poly = [MKPolyline polylineWithCoordinates:coords count:n];
        free(coords);

        dispatch_async(dispatch_get_main_queue(), ^{
            // Remove old route overlays (except tile overlays)
            for (id<MKOverlay> ov in [self.mapView.overlays copy]) {
                if (![ov isKindOfClass:[MKTileOverlay class]]) {
                    [self.mapView removeOverlay:ov];
                }
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




- (IBAction) sendersearchFieldAction:(id)sender
{
    NSSearchField *field = (NSSearchField *)sender;
    NSString *query = field.stringValue;
    
    if (query.length == 0) return;
    
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;
    request.region = self.mapView.region; // Search near current map
    
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Search error: %@", error.localizedDescription);
            return;
        }
        
        if (response.mapItems.count == 0) {
            NSLog(@"No results found");
            return;
        }
        
        // Take first result, zoom to it
        MKMapItem *item = response.mapItems.firstObject;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(item.placemark.coordinate, 2000, 2000) animated:YES];
            
            // Optional: drop a pin
            MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
            annotation.title = item.name;
            annotation.coordinate = item.placemark.coordinate;
            [self.mapView addAnnotation:annotation];
        });
    }];
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

#pragma mark -

- (BOOL)clickNearPolylineAt:(CLLocationCoordinate2D)coord
{
    NSUInteger count = poly.pointCount;
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
    [poly getCoordinates:coords range:NSMakeRange(0, count)];
    
    if (count<2) return NO;
    
    double thresholdMeters = 30.0;
    CLLocation *tapLocation = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
    
    for (NSUInteger i = 0; i < count - 1; i++) {
        CLLocation *p1 = [[CLLocation alloc] initWithLatitude:coords[i].latitude longitude:coords[i].longitude];
        CLLocation *p2 = [[CLLocation alloc] initWithLatitude:coords[i+1].latitude longitude:coords[i+1].longitude];
        double dist = [self distanceFromPoint:tapLocation toSegmentP1:p1 P2:p2];
        if (dist < thresholdMeters) {
            free(coords);
            return YES;
        }
    }
    free(coords);
    return NO;
}

- (double)distanceFromPoint:(CLLocation *)point
                 toSegmentP1:(CLLocation *)p1
                          P2:(CLLocation *)p2
{
    // If both points are the same, just return distance to one of them
    if ([p1 distanceFromLocation:p2] == 0) {
        return [point distanceFromLocation:p1];
    }
    
    // Convert to 2D vectors in meters using a flat Earth approximation for small distances
    // First, pick a reference latitude for scaling longitude
    double refLat = (p1.coordinate.latitude + p2.coordinate.latitude) / 2.0;
    double metersPerDegLat = 111132.92 - 559.82 * cos(2 * refLat * M_PI / 180.0)
                                           + 1.175 * cos(4 * refLat * M_PI / 180.0);
    double metersPerDegLon = 111412.84 * cos(refLat * M_PI / 180.0)
                                           - 93.5 * cos(3 * refLat * M_PI / 180.0);

    // Convert to x/y in meters
    double x1 = p1.coordinate.longitude * metersPerDegLon;
    double y1 = p1.coordinate.latitude  * metersPerDegLat;
    double x2 = p2.coordinate.longitude * metersPerDegLon;
    double y2 = p2.coordinate.latitude  * metersPerDegLat;
    double px = point.coordinate.longitude * metersPerDegLon;
    double py = point.coordinate.latitude  * metersPerDegLat;

    // Project point onto segment
    double dx = x2 - x1;
    double dy = y2 - y1;
    double t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy);
    t = fmax(0, fmin(1, t)); // clamp between 0 and 1

    // Closest point on segment
    double cx = x1 + t * dx;
    double cy = y1 + t * dy;

    // Distance from P to closest point
    double dist = hypot(px - cx, py - cy);
    return dist;
}


- (void)insertWaypoint:(CLLocationCoordinate2D)coord
{
    [waypoints insertObject:[[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude] atIndex:1];
    [self requestRoute];
}

#pragma mark - drag and drop


- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation
{
    if ([annotation isKindOfClass:[RouteAnnotation class]]) {
        static NSString *identifier = @"RouteAnnotation";
        MKPinAnnotationView *view = (MKPinAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        if (!view) {
            view = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
            view.draggable = YES;
            view.animatesDrop = YES;
#if TARGET_OS_OSX
            view.pinTintColor = [NSColor orangeColor];
#else
            view.pinTintColor = [UIColor orangeColor];
#endif
        }
        return view;
    }
    
    return nil;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view
didChangeDragState:(MKAnnotationViewDragState)newState
   fromOldState:(MKAnnotationViewDragState)oldState
{
    
    if (newState == MKAnnotationViewDragStateEnding) {
        
        // Update waypoint in array
        RouteAnnotation *ra = view.annotation;
        if (![ra isKindOfClass:[RouteAnnotation class]]) {
            return;
        }
        NSUInteger idx = ra.idx;
        CLLocationCoordinate2D newCoord = ra.coordinate;
        waypoints[idx] = [[CLLocation alloc] initWithLatitude:newCoord.latitude longitude:newCoord.longitude];
        
        
        [self requestRoute];
    }
}



@end
