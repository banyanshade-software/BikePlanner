//
//  MapController.m
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import "MapController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "SafeTileRenderer.h"
#import "SafeOSMTileOverlay.h"
#import "GPXParser.h"

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
    NSMutableArray <CLLocation *>*waypointsLocations;
    NSMutableArray <RouteAnnotation *>*waypointsRouteAnnotations;
    NSArray<CLLocation *> *routePoints;
    MKPolyline *poly; // route being built
    MKPolyline *gpxpoly; // loaded gpx, just displayed
    MKPointAnnotation *scrubberMarker;
}

- (void) initializeMapview
{
    NSView *content = [_mapView superview];// self.window.contentView;
    waypointsLocations = [[NSMutableArray alloc]initWithCapacity:32];
    waypointsRouteAnnotations = [[NSMutableArray alloc]initWithCapacity:32];
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
    
   
    scrubberMarker = [[MKPointAnnotation alloc] init];
    [self.mapView addAnnotation:scrubberMarker];
    self.elevationView.delegate = self;
    
}



- (void)clearAction:(id)sender
{
    [waypointsLocations removeAllObjects];
    //self.hasStart = NO; self.hasEnd = NO;
    self.gpxData = nil;
    [waypointsLocations removeAllObjects];
    [waypointsRouteAnnotations removeAllObjects];
    poly = nil;
    scrubberMarker = nil;
    [self.mapView removeAnnotations:self.mapView.annotations];
    //[self.mapView removeOverlays:self.mapView.overlays];
    for (id<MKOverlay> ov in [self.mapView.overlays copy]) {
        if (![ov isKindOfClass:[MKTileOverlay class]]) {
            [self.mapView removeOverlay:ov];
        }
    }
}

- (NSColor *) pinColorForWaypointIdx:(NSUInteger)idx
{
    NSColor *c;
    if (0==idx) c = [NSColor redColor];
    else if (idx >= [waypointsRouteAnnotations count]-1) c = [NSColor greenColor];
    else c = [NSColor yellowColor];
    return c;
}
- (NSString *) stringForWaypointIdx:(NSUInteger)idx
{
    if (!idx) return @"Start";
    //if (idx == [waypoints count]-1) return @"end";
    return [NSString stringWithFormat:@"%d", idx];
}



- (void)handleMapClick:(NSGestureRecognizer *)gesture
{
    NSPoint locInView = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:locInView toCoordinateFromView:self.mapView];
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
    
    
    
    if ([self clickNearPolylineAt:coord]) {
        NSUInteger idx = [self insertionIndexForCoordinate:coord polyline:poly waypoints:waypointsLocations];
        [self insertWaypoint:coord atIdx:idx];
        NSString *title = [self stringForWaypointIdx:idx];
        RouteAnnotation *a = [[RouteAnnotation alloc] initWithCoordinate:coord title:title subtitle:nil];
        a.idx = idx;
        [waypointsRouteAnnotations insertObject:a atIndex:idx];
        [self recalcAnnotIndexesFrom:idx];
        [self.mapView addAnnotation:a];
        // update all idx
        return;
    }
    NSString *title = nil;
    NSUInteger  idx = [waypointsLocations count];
    title = [self stringForWaypointIdx:idx];
    
    RouteAnnotation *a = [[RouteAnnotation alloc] initWithCoordinate:coord title:title subtitle:nil];
    a.idx = idx;
    [waypointsLocations addObject:loc];
    [waypointsRouteAnnotations addObject:a];
    [self recalcAnnotIndexesFrom:idx];
    
    [self.mapView addAnnotation:a];
    [self.svCtrl viewCoord:coord lookingAt:0. coalesce:YES];
    
    [self shouldRecalcRoute];
    
}

- (void) recalcAnnotIndexesFrom:(NSUInteger)ri
{
    // for now ignore ri and recalc all
    NSUInteger n = [waypointsRouteAnnotations count];
    for (NSUInteger i = 0; i<n; i++) {
        RouteAnnotation *ra = waypointsRouteAnnotations[i];
        ra.idx = i;
        ra.title = [self stringForWaypointIdx:i];
        //continue;
        MKAnnotationView* aView = [_mapView viewForAnnotation:ra];
        if ([aView isKindOfClass:[MKMarkerAnnotationView class]]) {
            MKMarkerAnnotationView *m = (MKMarkerAnnotationView *)aView;
            m.glyphText = ra.title;
        } else if ([aView isKindOfClass:[MKPinAnnotationView class]]) {
            MKPinAnnotationView *p = (MKPinAnnotationView *)aView;
            p.pinTintColor = [self pinColorForWaypointIdx:i];
        }
        
    }/*
      for (MKAnnotationView *v in _mapView.annotations) {
      if ([v isKindOfClass:[RouteAnnotation class]]) {
      [v]
      }
      }*/
}


- (void) shouldRecalcRoute
{
    if ([waypointsLocations count]>=2) {
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
    [self.brouter routeWithWaypoints:waypointsLocations profile:profile extraUrl:_extraUrl completion:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *brouterInfo, NSError *error) {
        if (error) {
            NSLog(@"BRouter error: %@", error);
            return;
        }
        if (points.count == 0) {
            NSLog(@"No points returned");
            return;
        }
        if (brouterInfo) {
            unsigned int kmlen = [brouterInfo[@"n-track-length-m"] unsignedIntValue];
            self.kmlen = kmlen;
            int mup = [brouterInfo[@"filtered-ascend"] intValue];
            self.mup = mup;
        }
        self.gpxData = gpx;
        routePoints = points;
        [self.elevationView setGpxPoints:points];
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
        MKPolyline *pl = (MKPolyline *) overlay;
        MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:pl];
        
        if (pl == poly) {
            // route being built
            r.lineWidth = 8.0;
            r.alpha = 0.5;
            r.strokeColor = [NSColor blueColor];
        } else {
            // gpx loaded
            r.lineWidth = 6.0;
            r.alpha = 0.5;
            //r.strokeColor = [NSColor darkGrayColor];
            r.strokeColor = [NSColor orangeColor];
        }
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


- (void)insertWaypoint:(CLLocationCoordinate2D)coord atIdx:(NSUInteger)idx
{
    [waypointsLocations insertObject:[[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude] atIndex:idx];
    // update idx
    
    [self requestRoute];
}

- (NSUInteger)insertionIndexForCoordinate:(CLLocationCoordinate2D)coord
                                 polyline:(MKPolyline *)polyline
                                waypoints:(NSArray<CLLocation*> *)waypoints
{
    if (!polyline || polyline.pointCount < 2) return 1; // default insert after start
    
    double newProj = [self projectedDistanceAlongPolyline:polyline forCoordinate:coord];
    
    // compute projected distances for each existing waypoint
    NSUInteger n = waypoints.count;
    NSMutableArray<NSNumber*> *proj = [NSMutableArray arrayWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) {
        CLLocation *wp = waypoints[i];
        double p = [self projectedDistanceAlongPolyline:polyline forCoordinate:wp.coordinate];
        [proj addObject:@(p)];
    }
    
    // ensure monotonicity (just in case): find place where newProj fits between proj[i] and proj[i+1]
    // we don't allow inserting before index 1 (start must remain first) or after last (end must remain last)
    NSUInteger insertIndex = 1; // default
    for (NSUInteger i = 0; i + 1 < proj.count; i++) {
        double a = proj[i].doubleValue;
        double b = proj[i+1].doubleValue;
        if (newProj >= a && newProj <= b) {
            insertIndex = i + 1;
            break;
        }
    }
    
    // If it wasn't found (newProj outside bounds), clamp:
    double first = proj.firstObject.doubleValue;
    double last = proj.lastObject.doubleValue;
    if (newProj <= first) insertIndex = 1;
    else if (newProj >= last) insertIndex = proj.count - 1;
    
    // safety clamp
    if (insertIndex < 1) insertIndex = 1;
    if (insertIndex > proj.count - 1) insertIndex = proj.count - 1;
    
    return insertIndex;
}

static void XYFromLatLon(double lat, double lon, double refLat, double *outX, double *outY) {
    // approximate meters per degree
    double rad = refLat * M_PI / 180.0;
    double metersPerDegLat = 111132.92 - 559.82 * cos(2 * rad) + 1.175 * cos(4 * rad);
    double metersPerDegLon = 111412.84 * cos(rad) - 93.5 * cos(3 * rad);
    *outX = lon * metersPerDegLon;
    *outY = lat * metersPerDegLat;
}

// returns cumulative distance along polyline to closest point projection of coord (meters)
- (double)projectedDistanceAlongPolyline:(MKPolyline *)polyline
                           forCoordinate:(CLLocationCoordinate2D)coord
{
    NSUInteger count = polyline.pointCount;
    if (count < 2) return 0.0;
    
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
    [polyline getCoordinates:coords range:NSMakeRange(0, count)];
    
    // Precompute segment lengths and cumulative distances
    double *segLen = malloc(sizeof(double) * (count - 1));
    double *cum = malloc(sizeof(double) * count); // cum[0] = 0, cum[i] = distance from start to coords[i]
    cum[0] = 0.0;
    for (NSUInteger i = 0; i < count - 1; i++) {
        CLLocation *a = [[CLLocation alloc] initWithLatitude:coords[i].latitude longitude:coords[i].longitude];
        CLLocation *b = [[CLLocation alloc] initWithLatitude:coords[i+1].latitude longitude:coords[i+1].longitude];
        segLen[i] = [a distanceFromLocation:b];
        cum[i+1] = cum[i] + segLen[i];
    }
    
    // Find closest projection
    double bestDist = DBL_MAX;
    double bestProjectionDist = 0.0;
    
    for (NSUInteger i = 0; i < count - 1; i++) {
        // use local planar coords for this segment
        double refLat = (coords[i].latitude + coords[i+1].latitude) * 0.5;
        double ax, ay, bx, by, px, py;
        XYFromLatLon(coords[i].latitude, coords[i].longitude, refLat, &ax, &ay);
        XYFromLatLon(coords[i+1].latitude, coords[i+1].longitude, refLat, &bx, &by);
        XYFromLatLon(coord.latitude, coord.longitude, refLat, &px, &py);
        
        double vx = bx - ax;
        double vy = by - ay;
        double wx = px - ax;
        double wy = py - ay;
        
        double denom = vx*vx + vy*vy;
        double t = 0.0;
        if (denom > 0.0) t = (vx*wx + vy*wy) / denom;
        if (t < 0.0) t = 0.0;
        if (t > 1.0) t = 1.0;
        
        double cx = ax + t*vx;
        double cy = ay + t*vy;
        
        double dx = px - cx;
        double dy = py - cy;
        double distMeters = hypot(dx, dy);
        
        if (distMeters < bestDist) {
            bestDist = distMeters;
            // projected distance along whole polyline = cumulative distance at segment start + t * segmentLength
            bestProjectionDist = cum[i] + (segLen[i] * t);
        }
    }
    
    free(coords);
    free(segLen);
    free(cum);
    
    return bestProjectionDist;
}

#pragma mark - drag and drop

static const BOOL useMarker = NO;

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation
{
    if ([annotation isKindOfClass:[RouteAnnotation class]]) {
        static NSString *identifier = @"RouteAnnotation";
        RouteAnnotation *ra = (RouteAnnotation *)annotation;
        MKAnnotationView *view = (MKAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        if (useMarker) {
            MKMarkerAnnotationView *mview = (MKMarkerAnnotationView *)view;
            if (!mview) {
                mview = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
                view = mview;
            }
            mview.glyphText = annotation.title;
        } else {
            MKPinAnnotationView *pview = (MKPinAnnotationView *)view;
            if (!pview) {
                pview = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
                view = pview;
            }
            pview.animatesDrop = YES;
            pview.pinTintColor = [self pinColorForWaypointIdx:ra.idx];
        }
        view.draggable = YES;
        // right click menu
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Waypoint Menu"];
        NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:@"Remove Waypoint"
                                                            action:@selector(removeWaypointMenuAction:)
                                                     keyEquivalent:@""];
        removeItem.target = self;
        removeItem.representedObject = annotation; // store the annotation reference
        [menu addItem:removeItem];
        
        view.menu = menu;
        view.annotation = annotation;
        
        // Add right-click recognizer
        NSClickGestureRecognizer *rightClick = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(handleRightClickOnAnnotation:)];
        rightClick.buttonMask = 0x2; // Right mouse button
        [view addGestureRecognizer:rightClick];
        
        return view;
    }
    
    return nil;
}


- (void)handleRightClickOnAnnotation:(NSClickGestureRecognizer *)gesture
{
    if (gesture.state == NSGestureRecognizerStateEnded) {
        MKAnnotationView *view = (MKAnnotationView *)gesture.view;
        if (!view.annotation) return;
        
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Waypoint Menu"];
        NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:@"Remove Waypoint"
                                                            action:@selector(removeWaypointMenuAction:)
                                                     keyEquivalent:@""];
        removeItem.target = self;
        removeItem.representedObject = view.annotation;
        [menu addItem:removeItem];
        
        NSPoint clickLocation = [gesture locationInView:view];
        NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
                                            location:[view.window convertPointToScreen:[view convertPoint:clickLocation toView:nil]]
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:view.window.windowNumber
                                             context:nil
                                         eventNumber:0
                                          clickCount:1
                                            pressure:1.0];
        
        [NSMenu popUpContextMenu:menu withEvent:event forView:view];
    }
}


- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view
didChangeDragState:(MKAnnotationViewDragState)newState
   fromOldState:(MKAnnotationViewDragState)oldState
{
    
    if (newState == MKAnnotationViewDragStateEnding) {
        
        // Update waypoint in array
        RouteAnnotation *ra = (RouteAnnotation *) view.annotation;
        if (![ra isKindOfClass:[RouteAnnotation class]]) {
            return;
        }
        NSUInteger idx = ra.idx;
        CLLocationCoordinate2D newCoord = ra.coordinate;
        waypointsLocations[idx] = [[CLLocation alloc] initWithLatitude:newCoord.latitude longitude:newCoord.longitude];
        
        
        [self requestRoute];
    }
}

#pragma mark -


- (void)elevationProfileView:(id)view didSelectDistance:(double)distance
{
    CLLocationCoordinate2D coord = [self coordinateAtDistance:distance];
    double bearing = [self bearingAtDistance:distance];
    scrubberMarker.coordinate = coord;
    [self.mapView setCenterCoordinate:coord animated:NO];
    
    [self.svCtrl viewCoord:coord lookingAt:bearing coalesce:NO];
}

- (CLLocationCoordinate2D)coordinateAtDistance:(double)targetDist {
    double cumDist = 0.0;
    for (NSUInteger i = 1; i < routePoints.count; i++) {
        CLLocation *prev = routePoints[i - 1];
        CLLocation *curr = routePoints[i];
        double segDist = [curr distanceFromLocation:prev];
        
        if (cumDist + segDist >= targetDist) {
            double t = (targetDist - cumDist) / segDist;
            double lat = prev.coordinate.latitude + t * (curr.coordinate.latitude - prev.coordinate.latitude);
            double lon = prev.coordinate.longitude + t * (curr.coordinate.longitude - prev.coordinate.longitude);
            return CLLocationCoordinate2DMake(lat, lon);
        }
        cumDist += segDist;
    }
    return [[routePoints lastObject] coordinate];
}




- (double)bearingAtDistance:(double)distanceAlongRoute {
    double cumDist = 0.0;

    for (NSUInteger i = 1; i < routePoints.count; i++) {
        CLLocation *p1 = routePoints[i - 1];
        CLLocation *p2 = routePoints[i];
        double segDist = [p2 distanceFromLocation:p1];

        if (cumDist + segDist >= distanceAlongRoute) {
            return [self bearingFrom:p1.coordinate to:p2.coordinate];
        }
        cumDist += segDist;
    }

    // If distance exceeds total length, return bearing of last segment
    if (routePoints.count >= 2) {
        CLLocation *last1 = routePoints[routePoints.count - 2];
        CLLocation *last2 = routePoints[routePoints.count - 1];
        return [self bearingFrom:last1.coordinate to:last2.coordinate];
    }
    return 0.0;
}

- (double)bearingFrom:(CLLocationCoordinate2D)p1 to:(CLLocationCoordinate2D)p2 {
    double lat1 = p1.latitude * M_PI / 180.0;
    double lon1 = p1.longitude * M_PI / 180.0;
    double lat2 = p2.latitude * M_PI / 180.0;
    double lon2 = p2.longitude * M_PI / 180.0;

    double dLon = lon2 - lon1;

    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) -
               sin(lat1) * cos(lat2) * cos(dLon);

    double bearingRad = atan2(y, x);
    double bearingDeg = bearingRad * 180.0 / M_PI;
    return fmod((bearingDeg + 360.0), 360.0); // normalize to 0–360
}


#pragma  mark -

- (void)removeWaypointMenuAction:(id)sender
{
    NSMenuItem *item = (NSMenuItem *)sender;
    id<MKAnnotation> annotation = item.representedObject;
    if (annotation) {
        [self.mapView removeAnnotation:annotation];
        
        // If you store waypoints in an array, remove it there too:
        NSUInteger idx = [waypointsRouteAnnotations indexOfObject:annotation];
        if (idx != NSNotFound) {
            [waypointsRouteAnnotations removeObjectAtIndex:idx];
            [waypointsLocations removeObjectAtIndex:idx];
            [self recalcAnnotIndexesFrom:idx];
            [self shouldRecalcRoute];
        }
    }
}

#pragma mark -
- (IBAction) importGPXTraceForDisplay:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"gpx"]];
    //panel.allowedFileTypes = @[@"gpx"];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.title = @"Choose a GPX file";
    
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *fileURL = panel.URL;
            [self loadGPXFromURL:fileURL];
        }
    }];
}

- (void)loadGPXFromURL:(NSURL *)url {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (!data) {
        NSLog(@"Failed to read GPX file: %@", error);
        return;
    }
    // Pass data to your parser
    
    GPXParser *pgpx = [[GPXParser alloc]init];
    NSError *parseError = nil;
    NSArray<CLLocation *> *points = [pgpx parseGPXData:data error:&parseError];
    if (!points || ![points count]) {
        NSLog(@"parse gpx err : %@", parseError);
        return;
    }
    NSUInteger n = points.count;
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * n);
    for (NSUInteger i=0;i<n;i++) {
        coords[i] = points[i].coordinate;
    }
    gpxpoly = [MKPolyline polylineWithCoordinates:coords count:n];
    [self.mapView addOverlay:gpxpoly level:MKOverlayLevelAboveLabels];

    free(coords);
}
@end
