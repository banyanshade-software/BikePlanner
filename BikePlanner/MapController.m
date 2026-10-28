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
#import "RouteAnnotation.h"
#import "POIAnnotation.h"
#import "BikePlan.h"
#import "TaggedPoly.h"
#import "POICalloutView.h"
#import "POIAnnotationView.h"
#import "ExportAccessoryViewController.h"
#import "Secret.h"
#import "BPEnvironment.h"

// Secret.h is not commited, see Secret.h.example


@implementation MapController {
    //NSMutableArray <CLLocation *>*waypointsLocations;
    NSMutableArray <RouteAnnotation *>*waypointsRouteAnnotations;
    //NSArray<CLLocation *> *routePoints;
    //MKPolyline *poly; // route being built
    //MKPolyline *gpxpoly; // loaded gpx, just displayed
    MKPointAnnotation *scrubberMarker;
    int mapType;
    SafeOSMTileOverlay *osmOverlay;
    SafeOSMTileOverlay *osmCycleOverlay;
    
    NSTextField *helpTxtField;
    BPClickMode clickmode;
    NSSegmentedControl *clickmodeseg;
    NSVisualEffectView *helpBackdrop;
    
    POIAnnotation *_highlightedPOI;
    BOOL animateDropPins;
    BOOL initialRegionPending;              // new plan: recenter on the first user location (#26)
    CLLocationCoordinate2D initialCenter;   // center set by showInitialRegion, to detect a map moved by the user
}

- (void) initializeMapview
{
    NSAssert(_document.plan, @"no plan");
    animateDropPins = NO; //YES;
    NSView *content = [_mapView superview];// self.window.contentView;
    //_document.plan.waypointsLocations = [[NSMutableArray alloc]initWithCapacity:32];
    waypointsRouteAnnotations = [[NSMutableArray alloc]initWithCapacity:32];
   
    
    self.mapView.delegate = self;
    self.mapView.accessibilityIdentifier = @"map";
    self.viewPOI = YES;

    // Add OpenStreetMap tile overlay
    NSString *template = @"https://tile.openstreetmap.org/{z}/{x}/{y}.png";
    osmOverlay = [[SafeOSMTileOverlay alloc] initWithURLTemplate:template];
    osmOverlay.canReplaceMapContent = YES; // replace Apple's map
    if (![BPEnvironment tilesDisabled]) [self.mapView addOverlay:osmOverlay level:MKOverlayLevelAboveRoads];
    mapType = 0;
    
    // thunderforest
    // https://manage.thunderforest.com/dashboard
    NSString *ctemplate = @"https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=" THUNDERFOREST_API_KEY;

    osmCycleOverlay =  [[SafeOSMTileOverlay alloc] initWithURLTemplate:ctemplate];
    osmCycleOverlay.canReplaceMapContent = YES; // replace Apple's map
    
    
    // BRouter client (default points to local server at port 17777)
    //NSString *brouter=@"http://127.0.0.1:17777";
    //NSString *brouter=@"https://brouter.de/brouter";
    //NSString *brouter=@"https://brouter.de";
    NSURL *server = [BPEnvironment brouterServerURL]; // https://brouter.de unless overridden (BPEnvironment)
    self.brouter = [[BRouterClient alloc] initWithServerURL:server];
    
    
    [self addMapviewButtonsIn:content];
    
    // Add click handler
    NSClickGestureRecognizer *clicker = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapClick:)];
    clicker.delegate = self;
    clicker.buttonMask = 0x1; // left mouse
    clicker.numberOfClicksRequired = 1;
    [self.mapView addGestureRecognizer:clicker];
    self.mapView.showsZoomControls = NO;
   
    scrubberMarker = [[MKPointAnnotation alloc] init];
    [self.mapView addAnnotation:scrubberMarker];
    self.elevationView.delegate = self;
    
    [self installPlanCallbacks];
    if ((0)) {
        // move to defined place
        // 44.1249234 ,0.4961707,10920
        CLLocationCoordinate2D center = CLLocationCoordinate2DMake(44.1249234, 0.4961707); // Laplume
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(center, 20000, 20000) animated:NO];
            
        });
    }
    if ((1)) [self addTrackingAreas];
}

#pragma  mark - tracking area

- (void) mouseEntered:(id)x
{
    
}
- (void) mouseExited:(id)x
{
    
}
- (void) addTrackingAreas
{
    [self.mapView addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.mapView.bounds
                                                               options:(NSTrackingActiveAlways |
                                                                        NSTrackingMouseMoved |
                                                                        NSTrackingInVisibleRect)
                                                                 owner:self
                                                              userInfo:nil]];
}
- (BOOL)acceptsFirstResponder {
    return YES;
}

#if 0
- (void) highlightPoi:(POIAnnotation *)poi
{
    MKAnnotationView *newView = [self.mapView viewForAnnotation:_highlightedPOI];
    newView.wantsLayer = YES;
    newView.layer.borderWidth = 2.0;
    newView.layer.borderColor = [NSColor systemRedColor].CGColor;
    newView.layer.cornerRadius = newView.frame.size.width / 2.0;

}
- (void) unHighlightPoi:(POIAnnotation *)poi
{
    if (!poi) return;
    MKAnnotationView *oldView = [self.mapView viewForAnnotation:poi];
    oldView.layer.borderWidth = 0;
    oldView.layer.borderColor = nil;
}
#else
- (void) highlightPoi:(POIAnnotation *)poi
{
    POIAnnotationView *v = (POIAnnotationView *)[self.mapView viewForAnnotation:_highlightedPOI];
    v.savedColor = v.glyphTintColor;
    v.glyphTintColor =[NSColor yellowColor];
}
- (void) unHighlightPoi:(POIAnnotation *)poi
{
    POIAnnotationView *v = (POIAnnotationView *)[self.mapView viewForAnnotation:_highlightedPOI];
    v.glyphTintColor = v.savedColor;
}
#endif


#define MOUSE_RADIUS ((clickmode == BPClickModeView) ? 30. : 36.0)


- (void)mouseMoved:(NSEvent *)event
{
    CGPoint point = [self.mapView convertPoint:event.locationInWindow fromView:nil];
    CGFloat radius = MOUSE_RADIUS;
    id<MKAnnotation> nearest = [self nearestPOIToScreenPoint:point maxPixelRadius:radius];

    if (nearest != _highlightedPOI) {
        // Remove highlight from old one
        if (_highlightedPOI) [self unHighlightPoi:_highlightedPOI];
       
        NSAssert(!nearest || [nearest isKindOfClass:[POIAnnotation class]], @"bad class");
        _highlightedPOI = (POIAnnotation *) nearest;

        // Apply highlight to new one
        if (_highlightedPOI) [self highlightPoi:_highlightedPOI];
           
    }
}


#pragma  mark - mapview buttons

// selected segment of the map controls: light gray in light mode (original look), dark gray in dark mode
static NSColor *selectedSegmentColor(void)
{
    return [NSColor colorWithName:@"BPSelectedSegment" dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
                     isEqualToString:NSAppearanceNameDarkAqua];
        return dark ? [NSColor darkGrayColor] : [NSColor lightGrayColor];
    }];
}

// controls drawn over the map: a translucent blurred backdrop (follows light/dark) keeps them readable
// on any map content while the map stays visible through it (#23)
static const CGFloat kBackdropMargin = 3;

// frame: what it covers (controls frames), inserted below `below`
static NSVisualEffectView *addBackdrop(NSRect frame, NSString *ident, NSView *below, NSView *content)
{
    const CGFloat radius = 8;
    NSVisualEffectView *bg = [[NSVisualEffectView alloc] initWithFrame:NSInsetRect(frame, -kBackdropMargin, -kBackdropMargin)];
    bg.material = NSVisualEffectMaterialPopover;
    bg.blendingMode = NSVisualEffectBlendingModeWithinWindow; // blurs the map, not the desktop
    bg.state = NSVisualEffectStateActive;
    bg.alphaValue = 0.7; // a bit more of the map shows through
    bg.autoresizingMask = below.autoresizingMask;
    bg.maskImage = [NSImage imageWithSize:NSMakeSize(2*radius+1, 2*radius+1) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [[NSColor blackColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius] fill];
        return YES;
    }];
    bg.maskImage.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    bg.accessibilityIdentifier = ident;
    [content addSubview:bg positioned:NSWindowBelow relativeTo:below];
    return bg;
}

static NSVisualEffectView *addBackdropBehind(NSView *ctrl, NSView *content)
{
    return addBackdrop(ctrl.frame, [ctrl.accessibilityIdentifier stringByAppendingString:@"Backdrop"], ctrl, content);
}

- (void) addMapviewButtonsIn:(NSView *)content
{
    NSBezelStyle bzstyle = NSBezelStyleRoundRect; // NSBezelStyleRoundRect;

    NSImage *zoomOutImage = [NSImage imageWithSystemSymbolName:@"minus.magnifyingglass"
                                        accessibilityDescription:@"Zoom Out"];
    NSButton *btnZoomOut =  [[NSButton alloc]initWithFrame:NSMakeRect(14, 8, 32, 32)];

    btnZoomOut.image = zoomOutImage;
    //btnZoomOut.imageScaling = NSImageScaleProportionallyDown;
    btnZoomOut.bezelStyle = bzstyle;
    btnZoomOut.action = @selector(zoomOut:);
    btnZoomOut.target = self;
    btnZoomOut.accessibilityIdentifier = @"zoomOut";
    //btnZoomOut.contentTintColor = [NSColor labelColor];
    [content addSubview:btnZoomOut];
    
    
    NSImage *zoomInImage = [NSImage imageWithSystemSymbolName:@"plus.magnifyingglass"
                                        accessibilityDescription:@"Zoom In"];
    NSButton *btnZoomIn =  [[NSButton alloc]initWithFrame:NSMakeRect(14+32, 8, 32, 32)];
    btnZoomIn.image = zoomInImage;
    //btnZoomIn.imageScaling = NSImageScaleProportionallyDown;
    btnZoomIn.bezelStyle = bzstyle;
    btnZoomIn.action = @selector(zoomIn:);
    btnZoomIn.target = self;
    btnZoomIn.accessibilityIdentifier = @"zoomIn";
    [content addSubview:btnZoomIn];
    addBackdrop(NSUnionRect(btnZoomOut.frame, btnZoomIn.frame), @"zoomBackdrop", btnZoomOut, content); // they touch: one backdrop
    
  
    
    NSImage *locImage = [NSImage imageWithSystemSymbolName:@"location.fill"
                                       accessibilityDescription:@"Show User Location"];

    NSButton *btnCurloc = [[NSButton alloc]initWithFrame:NSMakeRect(14+32*2+10, 8, 32, 32)];
    btnCurloc.image = locImage;
    btnCurloc.target = self;
    btnCurloc.action = @selector(centerOnUserLocation:);
    btnCurloc.bezelStyle = bzstyle;
    btnCurloc.accessibilityIdentifier = @"userLocation";
    
    //btnCurloc.contentTintColor = [NSColor orangeColor];
    [content addSubview:btnCurloc];
    addBackdropBehind(btnCurloc, content);

    
   
    
    
    NSSegmentedControl *maptype = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(14, 64, 280, 26)];
    maptype.segmentCount = 5;
    maptype.selectedSegment = 0;
    [maptype setLabel:@"OSM" forSegment:0];
    [maptype setLabel:@"OSM+cycle" forSegment:1];
    [maptype setLabel:@"Apple" forSegment:2];
    [maptype setLabel:@"Sat+Rd" forSegment:3];
    [maptype setLabel:@"Sat" forSegment:4];
    maptype.selectedSegmentBezelColor = selectedSegmentColor();
    //maptype.backgroundColor = [NSColor grayColor];
    maptype.segmentStyle = NSSegmentStyleRoundRect;
    //maptype.bezelColor = [NSColor redColor];
    maptype.action = @selector(changeMapType:);
    maptype.target = self;
    maptype.accessibilityIdentifier = @"mapType";
    [content addSubview:maptype];
    addBackdropBehind(maptype, content);
    
    
    helpTxtField = [[NSTextField alloc] initWithFrame:NSMakeRect(14+230+14, 32, 500, 26)];
    helpTxtField.bezeled = NO; helpTxtField.editable = NO; helpTxtField.selectable = NO;
    // drawn over the map (OSM tiles stay light in dark mode): same backdrop as the controls, sized to the text
    helpTxtField.drawsBackground = NO;
    helpTxtField.stringValue = @"...";
    helpTxtField.accessibilityIdentifier = @"clickModeHelp";
    [content addSubview:helpTxtField];
    helpBackdrop = addBackdropBehind(helpTxtField, content);
    
    clickmode = BPClickModeEdit;
    clickmodeseg = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(14, 38, 230, 26)];
    clickmodeseg.segmentCount = 4;
    clickmodeseg.selectedSegment = clickmode;
    [self setHelpStringForClickMode:clickmode];
    [clickmodeseg setLabel:@"Edit" forSegment:BPClickModeEdit];
    [clickmodeseg setLabel:@"Add interm." forSegment:BPClickModeInterm];
    [clickmodeseg setLabel:@"Add POI" forSegment:BPClickModeAddPOI];
    [clickmodeseg setLabel:@"View" forSegment:BPClickModeView];
    clickmodeseg.selectedSegmentBezelColor = selectedSegmentColor();
    clickmodeseg.segmentStyle = NSSegmentStyleRoundRect;
    //clickmode.bezelColor = [NSColor redColor];
    clickmodeseg.action = @selector(changeClickMode:);
    clickmodeseg.target = self;
    clickmodeseg.accessibilityIdentifier = @"clickMode";
    [content addSubview:clickmodeseg];
    addBackdropBehind(clickmodeseg, content);
    
}

// Plan without route (#26): ~80 km around the user location, or around the default position until the
// location comes (or if it is refused); the first location recenters, unless the user moved the map meanwhile
- (MKCoordinateRegion) initialRegionAround:(CLLocationCoordinate2D)center
{
    double d = 2 * 1000 * [BPEnvironment initialRadiusKm];
    return MKCoordinateRegionMakeWithDistance(center, d, d);
}

- (void) showInitialRegion
{
    CLLocation *loc = [BPEnvironment locationDisabled] ? nil : self.mapView.userLocation.location;
    initialRegionPending = (loc == nil);
    if (initialRegionPending && ![BPEnvironment locationDisabled]) {
        CLLocationManager *locationManager = [[CLLocationManager alloc] init];
        [locationManager requestWhenInUseAuthorization];
        self.mapView.showsUserLocation = YES;
    }
    [self.mapView setRegion:[self initialRegionAround:loc ? loc.coordinate : [BPEnvironment defaultPosition]] animated:NO];
    initialCenter = self.mapView.centerCoordinate;
}

- (void) userLocationAvailable:(nullable CLLocation *)loc
{
    if (!initialRegionPending || !loc) return;
    initialRegionPending = NO;
    CLLocationCoordinate2D c = self.mapView.centerCoordinate;
    BOOL moved = fabs(c.latitude - initialCenter.latitude) > 1e-3 || fabs(c.longitude - initialCenter.longitude) > 1e-3;
    if (moved || [_document.plan.waypointsLocations count]) return; // keep what the user is looking at
    [self.mapView setRegion:[self initialRegionAround:loc.coordinate] animated:YES];
}

- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation
{
    [self userLocationAvailable:userLocation.location];
}

- (IBAction)centerOnUserLocation:(id)sender
{
    MKUserLocation *userloc = self.mapView.userLocation;
    if (!userloc.location) {
        CLLocationManager *locationManager = [[CLLocationManager alloc] init];
        [locationManager requestWhenInUseAuthorization];
        self.mapView.showsUserLocation = YES;
        
    }
    if (userloc.location) {
        CLLocationCoordinate2D coord = self.mapView.userLocation.coordinate;
        MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord, 1000, 1000);
        [self.mapView setRegion:region animated:YES];
    }
}



// When a pin is selected/deselected:
- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view {
    self.activeCalloutView = view.detailCalloutAccessoryView;
}

- (void)mapView:(MKMapView *)mapView didDeselectAnnotationView:(MKAnnotationView *)view {
    if (self.activeCalloutView == view.detailCalloutAccessoryView) {
        self.activeCalloutView = nil;
    }
}


- (void) setHelpStringForClickMode:(BPClickMode)mt
{
    NSString *hlp;
    switch (mt) {
        default:
        case BPClickModeView:
            hlp = NSLocalizedString( @"Drag waypoints", @"CLICK_MODE_3");
            break;
        case BPClickModeAddPOI:
            hlp = NSLocalizedString( @"Add POI", @"CLICK_MODE_2");
            break;
        case BPClickModeInterm:
            hlp = NSLocalizedString(@"Click on path to add intermediate waypoints", @"CLICK_MODE_1");
            break;
        case BPClickModeEdit:
            hlp = NSLocalizedString(@"Click on map to add start and end waypoints",@"CLICK_MODE_0");
            break;
    }
    helpTxtField.stringValue = hlp;
    // the backdrop follows the text width
    NSRect f = helpTxtField.frame;
    f.size.width = ceil(helpTxtField.attributedStringValue.size.width) + 8;
    helpTxtField.frame = f;
    if (helpBackdrop) helpBackdrop.frame = NSInsetRect(f, -kBackdropMargin, -kBackdropMargin);
}
- (void) changeClickMode:(id)sender
{
    NSAssert([sender isKindOfClass:[NSSegmentedControl class]], @"bad ctrl class");
    NSSegmentedControl *seg = (NSSegmentedControl *) sender;
    BPClickMode mt = (BPClickMode) seg.selectedSegment;
    NSLog(@"cm %d", mt);
    if (mt != clickmode) {
        [self setHelpStringForClickMode:mt];
        clickmode = mt;
    }
}



- (IBAction) setClickModeToEdit:(id)sender
{
    [self setClickModeTo:BPClickModeEdit];
}

- (IBAction) setClickModeToInterm:(id)sender
{
    [self setClickModeTo:BPClickModeInterm];
}

- (IBAction) setClickModeToView:(id)sender
{
    [self setClickModeTo:BPClickModeView];
}

- (IBAction) setClickModeToAddPoi:(id)sender
{
    [self setClickModeTo:BPClickModeAddPOI];
}

- (BPClickMode) clickMode
{
    return clickmode;
}

- (void) setClickModeTo:(BPClickMode)mt
{
    if (mt != clickmode) {
        [self setHelpStringForClickMode:mt];
        clickmode = mt;
        clickmodeseg.selectedSegment = mt;
    }
}

- (IBAction)zoomIn:(id)sender
{
    MKCoordinateRegion region = self.mapView.region;
    region.span.latitudeDelta /= 2.0;
    region.span.longitudeDelta /= 2.0;
    [self.mapView setRegion:region animated:YES];
}

- (IBAction)zoomOut:(id)sender
{
    MKCoordinateRegion region = self.mapView.region;
    region.span.latitudeDelta *= 2.0;
    region.span.longitudeDelta *= 2.0;
    [self.mapView setRegion:region animated:YES];
}


- (void) changeMapType:(id)sender
{
    NSAssert([sender isKindOfClass:[NSSegmentedControl class]], @"bad ctrl class");
    NSSegmentedControl *seg = (NSSegmentedControl *) sender;
    int mt = (int) seg.selectedSegment;
    NSLog(@"mt %d", mt);
    if (mt==mapType) return;
    switch (mapType) {
        default:
            break;
        case 0:// remove osm
            [self.mapView removeOverlay:osmOverlay];
            break;
        case 1: //remove cyle osm
            [self.mapView removeOverlay:osmCycleOverlay];
            break;
    }
    mapType = mt;
    switch (mapType) {
        default: // FALLTHRU
        case 0:
            if (![BPEnvironment tilesDisabled]) [self.mapView addOverlay:osmOverlay level:MKOverlayLevelAboveRoads];
            break;
        case 1:
            if (![BPEnvironment tilesDisabled]) [self.mapView addOverlay:osmCycleOverlay level:MKOverlayLevelAboveRoads];
            break;
        case 2:
            self.mapView.mapType = MKMapTypeStandard;
            break;
        case 3:
            self.mapView.mapType = MKMapTypeHybrid;
            break;
        case 4:
            self.mapView.mapType = MKMapTypeSatellite;
            break;
    }
    
}


// Clear Route (#33): after confirmation, everything but the reference trace; undo restores the route as is (no new BRouter request)
- (BOOL) canClearRoute
{
    return [_document.plan.waypointsLocations count] > 0;
}

- (IBAction) clearRoute:(id)sender
{
    if (![self canClearRoute]) return;
    NSWindow *window = _mapView.window;
    if (!window) {
        [self setRouteState:nil desc:@"clear route"];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Clear the route?", @"");
    alert.informativeText = NSLocalizedString(@"Waypoints, route and POIs will be erased; the displayed GPX trace is kept. This can be undone.", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"Clear", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    alert.buttons.firstObject.hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        if (![self canClearRoute]) return;
        [self setRouteState:nil desc:@"clear route"];
    }];
}

// state: from -[BikePlan clearRoute] (includes the BRouter GPX for export), nil to clear
- (void) setRouteState:(nullable NSDictionary *)state desc:(nullable NSString *)d
{
    NSDictionary *cur = [_document.plan clearRoute];
    NSUndoManager *um = _document.undoManager;
    [um registerUndoWithTarget:self selector:@selector(undoRouteState:) object:cur];
    if (d) [um setActionName:d];
    if (state) [_document.plan restoreRoute:state];
    self.gpxData = _document.plan.exportableGPX;
    self.elevationView.highlightDistance = 0;
    [self fullRefresh:NO];
}

- (void) undoRouteState:(NSDictionary *)state
{
    [self setRouteState:state desc:nil];
}

- (NSColor *) pinColorForWaypointIdx:(NSUInteger)idx
{
    NSColor *c;
    if (0==idx) c = [NSColor grayColor];
    else if (idx >= [waypointsRouteAnnotations count]-1) c = [NSColor whiteColor];
    else c = [NSColor yellowColor];
    return c;
}
- (NSString *) stringForWaypointIdx:(NSUInteger)idx
{
    if (!idx) return @"Start";
    //if (idx == [waypoints count]-1) return @"end";
    return [NSString stringWithFormat:@"%lu", idx];
}


- (BOOL )gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer
 shouldAttemptToRecognizeWithEvent:(NSEvent *)event
{
    if (self.activeCalloutView) {
         NSPoint pInCallout = [self.activeCalloutView convertPoint:event.locationInWindow
                                                          fromView:nil];
         NSView *hit = [self.activeCalloutView hitTest:pInCallout];
         if (hit) {
             // Click landed on the callout (e.g., the NSSegmentedControl or label) — let it handle the event.
             return NO;
         }
     }
    return YES;
}
 

- (void)handleMapClick:(NSGestureRecognizer *)gesture
{
    //NSView *gview =gesture.view;

    NSPoint locInView = [gesture locationInView:self.mapView];
    
    /*if (![self gestureRecognizerShouldHandleMapClick:gr]) {
        // should not happen
        return;
    }*/
    // check if POI is selected (standard mechanism require tricky click right on the bottom of annotation view)
    if (!self.activeCalloutView) {
        float radius = MOUSE_RADIUS;
        id<MKAnnotation> poi = [self nearestPOIToScreenPoint:locInView
                                              maxPixelRadius:radius];
        if (poi) {
            NSAssert([poi isKindOfClass:[POIAnnotation class]], @"bad poi class");
            [self.mapView selectAnnotation:poi animated:YES];
            return; // don’t treat as route edit
        } else {
            NSLog(@"out of poi");
        }
    }
    
    CLLocationCoordinate2D coord = [self.mapView convertPoint:locInView toCoordinateFromView:self.mapView];
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
   
    if (clickmode == BPClickModeView) {
        CLLocationCoordinate2D rcoord;
        // in View mode, a click on route moves view
        if ([self clickNearPolylineAt:locInView tolerence:40. nearestPoint:&rcoord]) {
            scrubberMarker.coordinate = rcoord;
            [self.mapView setCenterCoordinate:rcoord animated:NO];
            // for elevation view, compute distance from begin
            NSUInteger segstart = 0;
            double distance = [self distanceAtCoordinate:rcoord segstart:&segstart];
            // for streetview compute orientation
            double bearing = [self bearingAtDistance:distance];
            [self.svCtrl viewCoord:rcoord lookingAt:bearing coalesce:NO];
            self.elevationView.highlightDistance = distance;
            [self.elevationView setNeedsDisplay:YES];
        }
        return;
    }
    if (clickmode == BPClickModeAddPOI) {
        // Add POI on the track
        CLLocationCoordinate2D rcoord;
        if ([self clickNearPolylineAt:locInView tolerence:50. nearestPoint:&rcoord]) {
            [self addCustomPoiAt:rcoord];
        }
        NSLog(@"..");
        return;
    }
    if (clickmode == BPClickModeEdit || clickmode == BPClickModeInterm) {
        CLLocationCoordinate2D rcoord;
        CGFloat tolerence = 16.;
        if (clickmode == BPClickModeInterm) tolerence = 50.;
        // in Edit and Interm modes, a click on route adds intermediate point
        if ([self clickNearPolylineAt:locInView tolerence:tolerence nearestPoint:&rcoord]) {
            MKPolyline *poly = [_document.plan routePoly];
            NSUInteger idx = [self insertionIndexForCoordinate:rcoord polyline:poly waypoints:_document.plan.waypointsLocations];
            [self insertWaypoint:rcoord atIdx:idx];
            NSString *title = [self stringForWaypointIdx:idx];
            RouteAnnotation *a = [[RouteAnnotation alloc] initWithCoordinate:rcoord title:title subtitle:nil];
            a.idx = idx;
            [waypointsRouteAnnotations insertObject:a atIndex:idx];
            [self recalcAnnotIndexesFrom:idx];
            [self.mapView addAnnotation:a];
            // update all idx
            return;
        }
    }
    if (clickmode == BPClickModeEdit) {
        // in Edit mode, a click on map adds end point
        NSString *title = nil;
        NSUInteger  idx = [_document.plan.waypointsLocations count];
        title = [self stringForWaypointIdx:idx];
        
        RouteAnnotation *a = [[RouteAnnotation alloc] initWithCoordinate:coord title:title subtitle:nil];
        a.idx = idx;
        [self undoableWP:[_document.plan appendWaypoint:loc] desc:@"add destination"];
        //[_document.plan.waypointsLocations addObject:loc];
        [waypointsRouteAnnotations addObject:a];
        [self recalcAnnotIndexesFrom:idx];
        
        [self.mapView addAnnotation:a];
        [self.svCtrl viewCoord:coord lookingAt:0. coalesce:YES];
        
        [self shouldRecalcRoute];
    }
}


- (id<MKAnnotation>)nearestPOIToScreenPoint:(CGPoint)p maxPixelRadius:(CGFloat)radius
{
    id<MKAnnotation> best = nil;
    CGFloat bestDist = CGFLOAT_MAX;

    for (id<MKAnnotation> ann in self.mapView.annotations) {
        if (![ann isKindOfClass:[POIAnnotation class]]) continue;
    
        CGPoint q = [self.mapView convertCoordinate:ann.coordinate toPointToView:self.mapView];
        CGFloat dx = q.x - p.x, dy = q.y - p.y;
        CGFloat d = sqrt(dx*dx + dy*dy);
        if (d < bestDist) { bestDist = d; best = ann; }
    }

    return (bestDist <= radius) ? best : nil;
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

- (void) installPlanCallbacks
{
    _document.plan.poiAvailableCallback = ^() {
        //NSLog(@"hop");
        [self refreshPOI];
    };
}

- (void) planReplaced
{
    [self installPlanCallbacks];
    [self fullRefresh:YES];
}

- (void) fullRefresh:(BOOL)fromLoad
{
    for (id<MKOverlay> ov in [self.mapView.overlays copy]) {
        if (![ov isKindOfClass:[MKTileOverlay class]]) {
            [self.mapView removeOverlay:ov];
        }
    }
    if (fromLoad) self.gpxData = _document.plan.exportableGPX; // export available after reopening (#10)
    [self refreshAnnot:!fromLoad];
    [self refreshPOI];
    [self refreshPoly:fromLoad]; // change view rect when loading, not when undoing
    [self refreshGpxDisplayed];
    [self refreshSideView];
}

- (void) refreshGpxDisplayed
{
    for (id<MKOverlay> ov in [self.mapView.overlays copy]) {
        if ([ov isKindOfClass:[TaggedPoly class]] && (2 == ((TaggedPoly *)ov).tag)) {
            [self.mapView removeOverlay:ov];
        }
    }
    if (![_document.plan.gpxDisplayed count]) return; // no trace: no empty overlay
    TaggedPoly *gpxpoly = _document.plan.gpxDisplayedPoly;
    [self.mapView addOverlay:gpxpoly level:MKOverlayLevelAboveLabels];
 
}
- (void) refreshSideView
{
    [self.elevationView setGpxPoints:_document.plan.routePoints];
    
}

- (void) refreshAnnot:(BOOL)anim
{
    for (RouteAnnotation *annot in self.mapView.annotations) {
        if (![annot isKindOfClass:[RouteAnnotation class]]) {
            continue;
        }
        [self.mapView removeAnnotation:annot];
    }
    [waypointsRouteAnnotations removeAllObjects];
    NSUInteger idx = 0;
    /*
    for (CLLocation *loc in _document.plan.waypointsLocations) {
        CLLocationCoordinate2D coord = loc.coordinate;
        NSString *title = [self stringForWaypointIdx:idx];
        RouteAnnotation *a = [[RouteAnnotation alloc] initWithCoordinate:coord title:title subtitle:nil];
        a.idx = idx;
        [waypointsRouteAnnotations addObject:a];
        [self.mapView addAnnotation:a];
        idx++;
    }
    */
    NSMutableArray *ans = [[NSMutableArray alloc]initWithCapacity:4];
    for (CLLocation *loc in _document.plan.waypointsLocations) {
        CLLocationCoordinate2D coord = loc.coordinate;
        NSString *title = [self stringForWaypointIdx:idx];
        RouteAnnotation *a = [[RouteAnnotation alloc] initWithCoordinate:coord title:title subtitle:nil];
        a.idx = idx;
        [waypointsRouteAnnotations addObject:a];
        idx++;
    }
    [self.mapView addAnnotations:waypointsRouteAnnotations];
}

- (void) addAnnotationViewForPoi:(POILocation *)loc
{
    POIAnnotation *ann = [[POIAnnotation alloc] init];
    ann.info = loc.info;
    ann.coordinate = loc.coordinate;
    ann.title = loc.title;
    ann.poiType = loc.poiType;
    ann.poiKey = loc.poiKey;
    ann.excluded = [_document.plan isPOIExcluded:loc];
    //ann.xxpoiType = loc.title; // FIXME
    [self.mapView addAnnotation:ann];
}

- (void) refreshPOI
{
    for (RouteAnnotation *annot in self.mapView.annotations) {
        if (![annot isKindOfClass:[POIAnnotation class]]) {
            continue;
        }
        [self.mapView removeAnnotation:annot];
    }
    for (POILocation *loc in _document.plan.customPoiloc) {
        [self addAnnotationViewForPoi:loc];
    }
    if (!_viewPOI) return;
    for (POILocation *loc in _document.plan.poiloc) {
        [self addAnnotationViewForPoi:loc];
        /*
        POIAnnotation *ann = [[POIAnnotation alloc] init];
        ann.info = loc.info;
        ann.coordinate = loc.coordinate;
        ann.title = loc.title;
        ann.poiType = loc.poiType;
        //ann.xxpoiType = loc.title; // FIXME
        [self.mapView addAnnotation:ann];*/
    }
}

- (void) setViewPOI:(BOOL)v
{
    if (v == _viewPOI) return;
    _viewPOI = v;
    [self refreshPOI];
}
- (void) refreshPoly:(BOOL)changeVisibleRect
{
    // Remove old route overlays (except tile overlays)
    for (id<MKOverlay> ov in [self.mapView.overlays copy]) {
        // if (![ov isKindOfClass:[MKTileOverlay class]]) {
        if ([ov isKindOfClass:[TaggedPoly class]]) {
            TaggedPoly *tp = (TaggedPoly *)ov;
            if (0 == tp.tag) {
                [self.mapView removeOverlay:ov];
            }
        }
    }
    MKPolyline *poly = _document.plan.routePoly;
    
    [self.mapView addOverlay:poly level:MKOverlayLevelAboveLabels];
    if (changeVisibleRect) {
        if (poly.pointCount>0) {
            MKMapRect rect = [poly boundingMapRect];
            [self.mapView setVisibleMapRect:rect edgePadding:NSEdgeInsetsMake(40, 40, 40, 40) animated:YES];
        } else {
            MKCoordinateRegion region;
            if ([BPEnvironment getInitialRegion:&region]) {
                [self.mapView setRegion:region animated:NO]; // tests
            } else {
                [self showInitialRegion];
            }
        }
    }
}


- (void) shouldRecalcRoute
{
    if ([_document.plan.waypointsLocations count]>=2) {
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
    NSString *profile = _document.plan.profileName;
    [self.brouter routeWithWaypoints:_document.plan.waypointsLocations profile:profile overrides:_document.plan.profileOverrides completion:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *brouterInfo, NSError *error) {
        if (error) {
            NSLog(@"BRouter error: %@", error);
            return;
        }
        if (points.count == 0) {
            NSLog(@"No points returned");
            return;
        }
        // process it on main thread, otherwise setNeedDisplay does not operate ok
        dispatch_async(dispatch_get_main_queue(), ^{
            if (brouterInfo) {
                unsigned int kmlen = ([brouterInfo[@"n-track-length-m"] unsignedIntValue] + 500)/1000;
                NSAssert(self.document.plan.brouterInfo, @"no brouterInfo");
                self.document.plan.brouterInfo.kmlen = kmlen;
                int mup = [brouterInfo[@"filtered-ascend"] intValue];
                self.document.plan.brouterInfo.mup = mup;
                self.document.plan.brouterInfo.meters = [brouterInfo[@"n-track-length-m"] integerValue];
                self.document.plan.brouterInfo.seconds = [brouterInfo[@"n-time-seconds"] integerValue];
            }
            self.document.plan.routeGPX = gpx; // saved with the document (#10)
            self.gpxData = gpx;
            self.document.plan.routePoints = points;
            [self.elevationView setGpxPoints:points];
            [self refreshPoly:NO];
            
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
    if ([overlay isKindOfClass:[TaggedPoly class]]) {
        TaggedPoly *pl = (TaggedPoly *) overlay;
        MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:pl];
        
        if (pl.tag == 0) {
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

static NSString *xmlEscaped(NSString * _Nullable s)
{
    if (!s) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

- (NSData *) exportGpxDataWithPOI:(BOOL)inclPOI trackName:(NSString *)trackName
{
    if (0 && !inclPOI) {
        return _gpxData;
    }
    if (!trackName) trackName = @"track";
    //NSMutableString *xml = [[NSMutableString alloc]initWithCapacity:4000];
    NSString *gpxstr = [[NSString alloc] initWithData:_gpxData encoding:NSUTF8StringEncoding];
    
    //gpxstr = [gpxstr stringByAppendingString:@"<name>plop</name>"];
    NSRange nameTag = [gpxstr rangeOfString:@"<name>.*</name>" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch];
    if (nameTag.location != NSNotFound) {
        NSString *nname = [NSString stringWithFormat:@"<name>%@</name>", xmlEscaped(trackName)];
        gpxstr = [gpxstr stringByReplacingCharactersInRange:nameTag withString:nname];
    }
    
    NSRange closingTag = [gpxstr rangeOfString:@"</gpx>" options:NSBackwardsSearch|NSCaseInsensitiveSearch];
    if (closingTag.location == NSNotFound) {
        NSLog(@"Invalid GPX: missing </gpx>");
        return _gpxData;
    }
    NSMutableString *xml = [NSMutableString stringWithString:
                               [gpxstr substringToIndex:closingTag.location]];
  
    
    if (inclPOI) {
        for (POILocation *poi in _document.plan.customPoiloc) {
            if ([_document.plan isPOIExcluded:poi]) continue; // #5
            [xml appendFormat:@"<wpt lat=\"%f\" lon=\"%f\">\n", poi.coordinate.latitude, poi.coordinate.longitude];
            [xml appendFormat:@"  <name>%@</name>\n", xmlEscaped(poi.title ?: poi.gpxType)]; // custom POIs have no title
            //if (poi.subtitle) {
            //    [xml appendFormat:@"  <desc>%@</desc>\n", poi.subtitle];
            //}
            [xml appendFormat:@"  <sym>%@</sym>\n", xmlEscaped(poi.gpxSymbol ?: @"Flag")];
            [xml appendFormat:@"  <type>%@</type>\n", xmlEscaped(poi.gpxType ?: @"Flag")];
            [xml appendString:@"</wpt>\n"];
        }
    }
    if (inclPOI) {
        for (POILocation *poi in _document.plan.poiloc) {
            if ([_document.plan isPOIExcluded:poi]) continue; // #5
            [xml appendFormat:@"<wpt lat=\"%f\" lon=\"%f\">\n", poi.coordinate.latitude, poi.coordinate.longitude];
            [xml appendFormat:@"  <name>%@</name>\n", xmlEscaped(poi.title ?: poi.gpxType)]; // custom POIs have no title
            //if (poi.subtitle) {
            //    [xml appendFormat:@"  <desc>%@</desc>\n", poi.subtitle];
            //}
            [xml appendFormat:@"  <sym>%@</sym>\n", xmlEscaped(poi.gpxSymbol ?: @"Flag")];
            [xml appendFormat:@"  <type>%@</type>\n", xmlEscaped(poi.gpxType ?: @"Flag")];
            [xml appendString:@"</wpt>\n"];
        }
    }
    if ((0)) {
        [xml appendString:@"<rte>\n"];
        for (POILocation *poi in _document.plan.poiloc) {
            [xml appendFormat:@"<rtept lat=\"%f\" lon=\"%f\">\n", poi.coordinate.latitude, poi.coordinate.longitude];
            [xml appendFormat:@"  <name>%@</name>\n", poi.title];
            [xml appendFormat:@"  <sym>%@</sym>\n", poi.gpxSymbol ?: @"Flag"];
            if ((0)) {
                
                [xml appendString:@"  <extensions>\n"];
                [xml appendString:@"    <gpxx:RoutePointExtension>\n"];
                [xml appendFormat:@"      <gpxx:Subclass>%@</gpxx:Subclass>\n", /*poi.subclass ?: */ poi.title];
                [xml appendString:@"    </gpxx:RoutePointExtension>\n"];
                [xml appendString:@"  </extensions>\n"];
            }
            [xml appendString:@"</rtept>\n"];
        }
        [xml appendString:@"</rte>\n"];
    }
    [xml appendString:@"</gpx>\n"];
    
    NSData *d = [xml dataUsingEncoding:NSUTF8StringEncoding];
    
    return d;
}
- (IBAction) exportGPX:(id)sender
{
    if (!_gpxData) return;
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.title = @"Export GPX route";
    //savePanel.allowedFileTypes = @[@"gpx"]; // Change or remove as needed
    savePanel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"gpx"]];
    savePanel.nameFieldStringValue = @"plan.gpx"; // Suggested filename
    
    // Load XIB
    ExportAccessoryViewController *accessoryVC = [[ExportAccessoryViewController alloc] initWithNibName:@"ExportAccessoryView" bundle:nil];
    savePanel.accessoryView = accessoryVC.view;
    accessoryVC.savePanel = savePanel;
    
    [savePanel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *destinationURL = savePanel.URL;
            NSString *trackname = [[destinationURL lastPathComponent] stringByDeletingPathExtension];
            NSError *error = nil;
            BOOL includePOI = (accessoryVC.poiCheckbox.state == NSControlStateValueOn);

            NSData *gpxdta = [self exportGpxDataWithPOI:includePOI trackName:trackname];
            if (![gpxdta writeToURL:destinationURL options:NSDataWritingAtomic error:&error]) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Export failed";
                alert.informativeText = error.localizedDescription;
                [alert runModal];
            }
        }
    }];
}

#pragma mark -

#if 0
- (BOOL)clickNearPolylineAt:(CLLocationCoordinate2D)coord
{
    MKPolyline *poly = _document.plan.routePoly;
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
#endif

- (CGFloat)distanceFromPoint:(CGPoint)p toSegmentFrom:(CGPoint)a to:(CGPoint)b
{
    CGFloat dx = b.x - a.x;
    CGFloat dy = b.y - a.y;
    
    if (dx == 0 && dy == 0) {
        // a == b case
        dx = p.x - a.x;
        dy = p.y - a.y;
        return sqrt(dx*dx + dy*dy);
    }
    
    CGFloat t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx*dx + dy*dy);
    if (t < 0) {
        dx = p.x - a.x;
        dy = p.y - a.y;
    } else if (t > 1) {
        dx = p.x - b.x;
        dy = p.y - b.y;
    } else {
        CGFloat projX = a.x + t * dx;
        CGFloat projY = a.y + t * dy;
        dx = p.x - projX;
        dy = p.y - projY;
    }
    
    return sqrt(dx*dx + dy*dy);
}
- (CLLocationCoordinate2D)nearestCoordinateOnPolyline:(MKPolyline *)polyline
                                           toPoint:(CGPoint)tapPoint
                                     pixelTolerance:(CGFloat)pixelTolerance
                                      found:(BOOL *)found
{
    CGFloat minDistance = CGFLOAT_MAX;
    CLLocationCoordinate2D nearestCoord = kCLLocationCoordinate2DInvalid;
    if (!polyline.points) return nearestCoord;

    for (NSInteger i = 0; i < polyline.pointCount - 1; i++) {
        MKMapPoint p1 = polyline.points[i];
        MKMapPoint p2 = polyline.points[i+1];
        
        CGPoint pt1 = [self.mapView convertCoordinate:MKCoordinateForMapPoint(p1)
                                        toPointToView:self.mapView];
        CGPoint pt2 = [self.mapView convertCoordinate:MKCoordinateForMapPoint(p2)
                                        toPointToView:self.mapView];
        
        CGPoint proj;
        CGFloat distance = [self projectPoint:tapPoint
                                    ontoSegmentFrom:pt1
                                                 to:pt2
                                         projection:&proj];
        
        if (distance < minDistance) {
            minDistance = distance;
            // convert projection point back to map coordinate
            nearestCoord = [self.mapView convertPoint:proj toCoordinateFromView:self.mapView];
        }
    }
    
    if (minDistance <= pixelTolerance) {
        if (found) *found = YES;
        return nearestCoord;
    } else {
        if (found) *found = NO;
        return kCLLocationCoordinate2DInvalid;
    }
}

- (CGFloat)projectPoint:(CGPoint)p
       ontoSegmentFrom:(CGPoint)a
                    to:(CGPoint)b
            projection:(CGPoint *)projection {
    CGFloat dx = b.x - a.x;
    CGFloat dy = b.y - a.y;
    
    if (dx == 0 && dy == 0) {
        // a == b case
        if (projection) *projection = a;
        dx = p.x - a.x;
        dy = p.y - a.y;
        return sqrt(dx*dx + dy*dy);
    }
    
    CGFloat t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx*dx + dy*dy);
    
    if (t < 0) {
        if (projection) *projection = a;
    } else if (t > 1) {
        if (projection) *projection = b;
    } else {
        if (projection) *projection = CGPointMake(a.x + t * dx, a.y + t * dy);
    }
    
    CGFloat px = p.x - projection->x;
    CGFloat py = p.y - projection->y;
    return sqrt(px*px + py*py);
}
/*
- (NSInteger)nearestPolylineSegmentToPoint:(CGPoint)tapPoint
                                polyline:(MKPolyline *)polyline
                          pixelTolerance:(CGFloat)pixelTolerance {
    NSInteger nearestIndex = -1;
    CGFloat minDistance = CGFLOAT_MAX;
    if (!polyline.points) return -1;
    
    for (NSInteger i = 0; i < polyline.pointCount - 1; i++) {
        MKMapPoint p1 = polyline.points[i];
        MKMapPoint p2 = polyline.points[i+1];

        CGPoint pt1 = [self.mapView convertCoordinate:MKCoordinateForMapPoint(p1)
                                            toPointToView:self.mapView];
        CGPoint pt2 = [self.mapView convertCoordinate:MKCoordinateForMapPoint(p2)
                                            toPointToView:self.mapView];
        
        CGFloat distance = [self distanceFromPoint:tapPoint toSegmentFrom:pt1 to:pt2];
        
        if (distance < minDistance) {
            minDistance = distance;
            nearestIndex = i;
        }
    }
    
    if (minDistance <= pixelTolerance) {
        return nearestIndex;
    } else {
        return -1; // not close enough
    }
}
 */

- (BOOL)clickNearPolylineAt:(CGPoint)clickPoint tolerence:(CGFloat)tol nearestPoint:(CLLocationCoordinate2D *)ppt
{
    MKPolyline *poly = [_document.plan routePoly];
    BOOL found = NO;
    CLLocationCoordinate2D loc = [self nearestCoordinateOnPolyline:poly toPoint:clickPoint pixelTolerance:tol found:&found];
    if (found && ppt) {
        *ppt = loc;
    }
    return found;
}

#pragma mark -

- (void)insertWaypoint:(CLLocationCoordinate2D)coord atIdx:(NSUInteger)idx
{
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
    [self undoableWP:[_document.plan insertWaypoint:loc atIndex:idx] desc:@"insert waypoint"];
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
    return [self projectedDistanceAlongPolyline:polyline forCoordinate:coord segment:NULL];
}

// same, and returns in *psegment the index of the start point of the nearest segment
- (double)projectedDistanceAlongPolyline:(MKPolyline *)polyline
                           forCoordinate:(CLLocationCoordinate2D)coord
                                 segment:(nullable NSUInteger *)psegment
{
    if (psegment) *psegment = 0;
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
            if (psegment) *psegment = i;
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
        view.displayPriority = MKFeatureDisplayPriorityRequired;
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
            pview.animatesDrop = animateDropPins;
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
    
    
    if ([annotation isKindOfClass:[POIAnnotation class]]) {
        static NSString *identifier = @"POIAnnotationView";
        POIAnnotationView *view = (POIAnnotationView *) [mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        //MKMarkerAnnotationView *view = (MKMarkerAnnotationView *) [mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        view.displayPriority = MKFeatureDisplayPriorityDefaultLow;
        if (!view) {
            view = [[POIAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
            view.canShowCallout = YES;
            view.calloutOffset = CGPointMake(0, 4);
            POICalloutView *detailView = [[POICalloutView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
            view.detailCalloutAccessoryView = detailView;
            detailView.excludeControl.target = self;
            detailView.excludeControl.action = @selector(excludeControlChanged:);
            detailView.annotview = view;
        } else {
            view.annotation = annotation;
        }
        
        POIAnnotation *poi = (POIAnnotation *)annotation;
        [poi configureAnnotViewIcon:view];
        ((POICalloutView *)view.detailCalloutAccessoryView).infodic = poi.info; //XXX TODO
        ((POICalloutView *)view.detailCalloutAccessoryView).excludeControl.selectedSegment = poi.excluded ? 1 : 0;
        
        return view;
    }
        
    return nil;
}

// Include / Exclude in the POI callout (#5): an excluded POI is not exported, and shown greyed
- (void)excludeControlChanged:(NSSegmentedControl *)sender
{
    NSView *v = sender;
    while (v && ![v isKindOfClass:[POICalloutView class]]) v = v.superview;
    id<MKAnnotation> annotation = ((POICalloutView *)v).annotview.annotation;
    if (![annotation isKindOfClass:[POIAnnotation class]]) return;
    NSString *key = ((POIAnnotation *)annotation).poiKey;
    if (!key) return;
    [self setPOIKey:key excluded:(sender.selectedSegment == 1)];
}

- (void)setPOIKey:(NSString *)key excluded:(BOOL)excluded
{
    BikePlan *plan = _document.plan;
    if ([plan.excludedPOIKeys containsObject:key] == excluded) return;
    NSUndoManager *um = _document.undoManager;
    [um registerUndoWithTarget:self handler:^(MapController *target) {
        [target setPOIKey:key excluded:!excluded];
    }];
    [um setActionName:excluded ? NSLocalizedString(@"exclude POI", @"undo action") : NSLocalizedString(@"include POI", @"undo action")];
    [plan setPOIKey:key excluded:excluded];
    [self refreshPOI];
}


- (void)handleRightClickOnAnnotation:(NSClickGestureRecognizer *)gesture
{
    if (gesture.state == NSGestureRecognizerStateEnded) {
        MKAnnotationView *annotView = (MKAnnotationView *)gesture.view;
        if (!annotView.annotation) return;
        
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Waypoint Menu"];
        NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:@"Remove Waypoint"
                                                            action:@selector(removeWaypointMenuAction:)
                                                     keyEquivalent:@""];
        removeItem.target = self;
        removeItem.representedObject = annotView.annotation;
        [menu addItem:removeItem];
        
        NSPoint clickLocation = [gesture locationInView:annotView];
        NSPoint windowLocation = [annotView convertPoint:clickLocation toView:nil];
        //NSPoint screenLocation = [_mapView.window convertPointToScreen:windowLocation];
        //NSPoint clickLocation = [gesture locationInView:_mapView];
        NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
                                            location:windowLocation //screenLocation
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:annotView.window.windowNumber
                                             context:nil
                                         eventNumber:0
                                          clickCount:1
                                            pressure:1.0];
        
        [NSMenu popUpContextMenu:menu withEvent:event forView:annotView];
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
        CLLocation *loc = [[CLLocation alloc] initWithLatitude:newCoord.latitude longitude:newCoord.longitude];
        [self undoableWP:[_document.plan replaceWaypointAtIndex:idx by:loc] desc:@"move waypoint"];
        
        [self requestRoute];
    }
}

#pragma mark -

#pragma mark -


- (void)elevationProfileView:(id)view didSelectDistance:(double)distance
{
    CLLocationCoordinate2D coord = [self coordinateAtDistance:distance];
    double bearing = [self bearingAtDistance:distance];
    scrubberMarker.coordinate = coord;
    [self.mapView setCenterCoordinate:coord animated:NO];
    
    [self.svCtrl viewCoord:coord lookingAt:bearing coalesce:NO];
}
// distance along the route of the projection of coord on the NEAREST route segment (#14)
// *psegstart: index of the start point of that segment, or the last point index if coord is beyond the end
- (CLLocationDistance)distanceAtCoordinate:(CLLocationCoordinate2D)coord segstart:(NSUInteger *)psegstart
{
    *psegstart = 0;
    NSArray <CLLocation *>  *lp = _document.plan.routePoints;
    NSUInteger c = lp.count;
    if (c < 2) return 0;

    CLLocationCoordinate2D coords[c];
    CLLocationDistance total = 0.0;
    for (NSUInteger i = 0; i < c; i++) {
        coords[i] = lp[i].coordinate;
        if (i) total += [lp[i] distanceFromLocation:lp[i-1]];
    }
    MKPolyline *polyline = [MKPolyline polylineWithCoordinates:coords count:c];
    CLLocationDistance result = [self projectedDistanceAlongPolyline:polyline forCoordinate:coord segment:psegstart];
    if (result >= total) {
        // coord is beyond the end
        *psegstart = c-1;
        return total;
    }
    return result;
}

- (CLLocationCoordinate2D)coordinateAtDistance:(double)targetDist {
    double cumDist = 0.0;
    for (NSUInteger i = 1; i < _document.plan.routePoints.count; i++) {
        CLLocation *prev = _document.plan.routePoints[i - 1];
        CLLocation *curr = _document.plan.routePoints[i];
        double segDist = [curr distanceFromLocation:prev];
        
        if (cumDist + segDist >= targetDist) {
            double t = (targetDist - cumDist) / segDist;
            double lat = prev.coordinate.latitude + t * (curr.coordinate.latitude - prev.coordinate.latitude);
            double lon = prev.coordinate.longitude + t * (curr.coordinate.longitude - prev.coordinate.longitude);
            return CLLocationCoordinate2DMake(lat, lon);
        }
        cumDist += segDist;
    }
    return [[_document.plan.routePoints lastObject] coordinate];
}




- (double)bearingAtDistance:(double)distanceAlongRoute {
    double cumDist = 0.0;
    NSUInteger npt = _document.plan.routePoints.count;
    for (NSUInteger i = 1; i < npt; i++) {
        CLLocation *p1 = _document.plan.routePoints[i - 1];
        CLLocation *p2 = _document.plan.routePoints[i];
        double segDist = [p2 distanceFromLocation:p1];
        
        if ((0)) NSLog(@"segdist %lu-%lu  : %g (tot %g, target %g)", (unsigned long)i-1, (unsigned long)i,  segDist, cumDist+segDist, distanceAlongRoute); // one line per segment: too verbose (#18)
        if (cumDist + segDist >= distanceAlongRoute) {
            double b = [self bearingFrom:p1.coordinate to:p2.coordinate];
            if ((0)) NSLog(@"  bearing b=%g", b);
            return b;
        }
        cumDist += segDist;
    }

    // If distance exceeds total length, return bearing of last segment
    if (_document.plan.routePoints.count >= 2) {
        CLLocation *last1 = _document.plan.routePoints[_document.plan.routePoints.count - 2];
        CLLocation *last2 = _document.plan.routePoints[_document.plan.routePoints.count - 1];
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
    RouteAnnotation *annotation = item.representedObject;
    if (annotation) {
        NSAssert([annotation isKindOfClass:[RouteAnnotation class]], @"bad class");
        [self.mapView removeAnnotation:annotation];
        
        // If you store waypoints in an array, remove it there too:
        NSUInteger idx = [waypointsRouteAnnotations indexOfObject:annotation];
        if (idx != NSNotFound) {
            [waypointsRouteAnnotations removeObjectAtIndex:idx];
            //[_document.plan removeWaypoints];
            //[_document.plan removeWaypointAtIndex:idx];
            [self undoableWP:[_document.plan removeWaypointAtIndex:idx] desc:@"remove waypoint"];
            [self recalcAnnotIndexesFrom:idx];
            [self shouldRecalcRoute];
        }
    }
}

// start <-> end; the route is recomputed (one-way streets, climbs differ in the other direction)
- (BOOL) canReverseRoute
{
    return [_document.plan.waypointsLocations count] >= 2;
}

- (IBAction) reverseRoute:(id)sender
{
    if (![self canReverseRoute]) return;
    [self undoableWP:[_document.plan reverseWaypoints] desc:@"reverse route"];
    [self fullRefresh:NO];
    [self shouldRecalcRoute];
}

// toolbar items targeting the map controller (Document.xib)
- (BOOL) validateToolbarItem:(NSToolbarItem *)item
{
    if (item.action == @selector(reverseRoute:)) return [self canReverseRoute];
    if (item.action == @selector(clearRoute:)) return [self canClearRoute];
    return YES;
}

- (BOOL) canRemoveGPXTraceForDisplay
{
    return [_document.plan.gpxDisplayed count] > 0;
}

// the reference trace is saved with the document: removing it is the only way to get rid of it (#24)
- (IBAction) removeGPXTraceForDisplay:(id)sender
{
    if (![self canRemoveGPXTraceForDisplay]) return;
    [self setGpxDisplayed:nil desc:@"remove trace"];
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

// Import GPX as route (#29): the track becomes waypoints (simplified) and the route is requested from BRouter;
// the original track stays as the reference trace to compare; <wpt> become custom POIs, except those of the types
// BikePlanner exports for fetched POIs (fetched again along the new route). One undoable action.
- (IBAction) importGPXAsRoute:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"gpx"]];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.title = NSLocalizedString(@"Choose a GPX file to convert into a route", @"");
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) [self loadGPXAsRouteFromURL:panel.URL];
    }];
}

- (void) loadGPXAsRouteFromURL:(NSURL *)url
{
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (!data) {
        NSLog(@"Failed to read GPX file: %@", error);
        return;
    }
    GPXParser *pgpx = [[GPXParser alloc] init];
    NSArray<CLLocation *> *trace = [pgpx parseGPXData:data error:&error];
    if ([trace count] < 2) {
        NSLog(@"parse gpx err : %@", error);
        return;
    }
    // route points (or a file of waypoints only) are already waypoints
    BOOL isTrack = [pgpx.traceSource isEqualToString:@"trk"];
    NSArray<CLLocation *> *wps = isTrack || [trace count] > kBPImportMaxWaypoints ? [BikePlan waypointsForTrace:trace] : trace;
    NSMutableArray<CLLocation *> *pois = [NSMutableArray array];
    if (![pgpx.traceSource isEqualToString:@"wpt"]) {
        NSSet *fetchedTypes = [NSSet setWithObjects:@"WATER", @"TOILET", @"SERVICE", @"GENERIC", nil];
        [pgpx.waypoints enumerateObjectsUsingBlock:^(CLLocation *w, NSUInteger i, BOOL *stop) {
            if (![fetchedTypes containsObject:pgpx.waypointTypes[i]]) [pois addObject:w];
        }];
    }
    NSWindow *window = _mapView.window;
    if (![_document.plan.waypointsLocations count] || !window) {
        [self setRouteFromTrace:trace waypoints:wps pois:pois];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Replace the current route?", @"");
    alert.informativeText = NSLocalizedString(@"The imported GPX replaces the waypoints, route and POIs. This can be undone.", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"Replace", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) [self setRouteFromTrace:trace waypoints:wps pois:pois];
    }];
}

- (void) setRouteFromTrace:(NSArray<CLLocation *> *)trace waypoints:(NSArray<CLLocation *> *)wps pois:(NSArray<CLLocation *> *)pois
{
    NSUndoManager *um = _document.undoManager;
    [um beginUndoGrouping];
    [self setRouteState:nil desc:nil]; // undo restores the whole previous route
    [_document.plan undoSetWayPt:wps];
    for (CLLocation *p in pois) [_document.plan addCustomPoiAt:p.coordinate];
    [self setGpxDisplayed:trace desc:nil];
    [um setActionName:@"import GPX as route"];
    [um endUndoGrouping];
    [self fullRefresh:NO];
    [self shouldRecalcRoute];
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
    [self setGpxDisplayed:points desc:@"import trace"];
    /*
    NSUInteger n = points.count;
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * n);
    for (NSUInteger i=0;i<n;i++) {
        coords[i] = points[i].coordinate;
    }
    gpxpoly = [MKPolyline polylineWithCoordinates:coords count:n];
     */

    //free(coords);
}

#pragma mark -


- (void) undoableWP:(NSArray <CLLocation *>*)oldwp desc:(NSString *)d
{
    NSUndoManager *um = _document.undoManager;
    [um registerUndoWithTarget:self selector:@selector(undoAction:) object:oldwp];
    if (d) [um setActionName:d];
}

- (void) undoAction:(NSArray <CLLocation *>*)oldwp
{
    NSLog(@"undo action %d %d", _document.undoManager.isUndoing, _document.undoManager.isRedoing);
    //BOOL oa = animateDropPins;
    //animateDropPins = NO;
    if (1 || _document.undoManager.isUndoing) {
        // register for redo
        [self undoableWP:_document.plan.waypointsLocations desc:nil];
    }
    [_document.plan undoSetWayPt:oldwp];
    [self fullRefresh:NO];
    [self shouldRecalcRoute];
    //animateDropPins = oa;
}

// custom POIs and reference trace: undoable (also marks the document as edited)

- (void) addCustomPoiAt:(CLLocationCoordinate2D)coord
{
    [self undoableCustomPoi:[_document.plan.customPoiloc copy] desc:@"add POI"];
    [_document.plan addCustomPoiAt:coord];
    [self refreshPOI];
}

- (void) undoableCustomPoi:(NSArray <POILocation *>*)oldpois desc:(NSString *)d
{
    NSUndoManager *um = _document.undoManager;
    [um registerUndoWithTarget:self selector:@selector(undoCustomPoi:) object:oldpois];
    if (d) [um setActionName:d];
}

- (void) undoCustomPoi:(NSArray <POILocation *>*)oldpois
{
    // register for redo
    [self undoableCustomPoi:[_document.plan.customPoiloc copy] desc:nil];
    [_document.plan restoreCustomPoi:oldpois];
    [self refreshPOI];
}

- (void) setGpxDisplayed:(NSArray <CLLocation *>*)points desc:(NSString *)d
{
    NSUndoManager *um = _document.undoManager;
    [um registerUndoWithTarget:self selector:@selector(undoGpxDisplayed:) object:_document.plan.gpxDisplayed];
    if (d) [um setActionName:d];
    _document.plan.gpxDisplayed = points;
    [self refreshGpxDisplayed];
}

- (void) undoGpxDisplayed:(NSArray <CLLocation *>*)oldpoints
{
    [self setGpxDisplayed:oldpoints desc:nil];
}
@end
