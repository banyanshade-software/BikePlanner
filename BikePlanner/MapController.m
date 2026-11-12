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
#import "BPPOIEditor.h"
#import "BPPOIDescription.h"
#import "BPPlaceSearch.h"
#import "BPSecrets.h"
#import "BPEnvironment.h"
#import "BPRemarkableSites.h"
#import "BPColorScheme.h"

// Secret.h is not commited, see Secret.h.example

// GPX export of a route in stages (#31, #69), tag of the "Stages:" pop-up
typedef NS_ENUM(NSInteger, BPStagesExportMode) {
    BPStagesExportFolder = 0,   // one file per stage, in a new folder
    BPStagesExportWhole  = 1,   // the whole route in one file, as without stages
    BPStagesExportFiles  = 2,   // one file per stage, next to each other in the chosen folder
};
static NSString * const BPExportStagesModeKey = @"BPExportStagesMode";
static NSString * const BPExportFolderBookmarksKey = @"BPExportFolderBookmarks";


@interface MapController () <POICalloutActions>
@end

@implementation BPSearchPinAnnotation
@end

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
    NSString *_highlightedKind;     // road type / surface highlighted on the map (#54), drawn again on a new route (#66)
    NSSearchField *searchField;                      // toolbar (#40)
    MKLocalSearchCompleter *searchCompleter;
    NSArray<NSString *> *searchCompletionTitles;
    BPSearchPinAnnotation *searchPin;
    NSTimer *mapMessageTimer;
    NSSegmentedControl *clickmodeseg;
    NSVisualEffectView *helpBackdrop;
    
    POIAnnotation *_highlightedPOI;
    BOOL animateDropPins;
    BOOL initialRegionPending;              // new plan: recenter on the first user location (#26)
    CLLocationCoordinate2D initialCenter;   // center set by showInitialRegion, to detect a map moved by the user
    NSURLSessionDataTask *routeTask;        // route request in flight
    __weak NSSavePanel *exportPanel;         // while the export panel is open (#31, #69: stages pop-up)
    NSUserDefaults *exportDefaults;         // last stages export choice, folder bookmarks (#69); nil: standard, set by tests
    NSUInteger routeGeneration;             // incremented by each request and cancel: older answers are ignored (#9)
    NSPasteboard *poiPasteboard;            // POI callout Copy (#72); nil: general pasteboard, set by tests
    void (^poiURLOpener)(NSURL *url);       // POI callout OpenStreetMap (#72); nil: NSWorkspace, set by tests
    NSTimeInterval calloutOpenedAt;         // the click that opens a callout must not close it (#72)
}

- (void) initializeMapview
{
    NSAssert(_document.plan, @"no plan");
    animateDropPins = NO; //YES;
    // route colors changed in the Preferences (#71)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(colorSchemeChanged:)
                                                 name:BPColorSchemeDidChangeNotification object:nil];
    self.elevationView.stageEndColor = [BPColorScheme currentScheme].stageEndColor;
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
    NSString *ctemplate = [BPSecrets thunderforestTileURLTemplate]; // key obfuscated in the binary (#51)

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
    [self installSearchField];
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

// radius around a remarkable site (#65): close enough to recognize it
static const double kBPSiteRadiusKm = 15;

// a remarkable site as a new document starts on it (#65): map around it, its name, Street View with its heading
- (void) showSite:(BPRemarkableSite *)site
{
    double d = 2 * 1000 * kBPSiteRadiusKm;
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(site.coordinate, d, d) animated:NO];
    [self showMapMessage:site.displayText];
    [self.svCtrl viewCoord:site.coordinate lookingAt:site.heading coalesce:NO]; // not the default position
}

- (void) showInitialRegion
{
    BPStartPosition start = [BPEnvironment startPosition];
    if (start != BPStartPositionLocation) { // the location is not asked (#65)
        initialRegionPending = NO;
        BPRemarkableSite *site = (start == BPStartPositionRemarkableSite) ? [BPRemarkableSites randomSite] : nil;
        if (site) {
            [self showSite:site];
        } else {
            [self.mapView setRegion:[self initialRegionAround:[BPEnvironment defaultPosition]] animated:NO];
        }
        initialCenter = self.mapView.centerCoordinate;
        return;
    }
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
    [self.svCtrl viewCoord:loc.coordinate lookingAt:0 coalesce:NO];
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
    // the position on the route is computed when the callout opens: the route may have changed since (#72)
    if ([view.annotation isKindOfClass:[POIAnnotation class]] && [view.detailCalloutAccessoryView isKindOfClass:[POICalloutView class]]) {
        [self configurePOICallout:(POICalloutView *)view.detailCalloutAccessoryView forAnnotation:(POIAnnotation *)view.annotation];
    }
    self.activeCalloutView = view.detailCalloutAccessoryView;
    calloutOpenedAt = [NSDate timeIntervalSinceReferenceDate];
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
    if ([_document.plan isStageEndAtWaypointIndex:idx]) c = [BPColorScheme currentScheme].stageEndColor; // #31, #71
    else if (0==idx) c = [NSColor grayColor];
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
    // a click outside the open callout closes it and does nothing else (#72), except on another POI: that one opens.
    // A click inside the callout does not get here (gestureRecognizer:shouldAttemptToRecognizeWithEvent:)
    if (self.activeCalloutView) {
        // the click that opened it, seen again (MapKit selected the POI, then this recognizer), or a double click
        if ([NSDate timeIntervalSinceReferenceDate] - calloutOpenedAt < 0.4) return;
        id<MKAnnotation> poi = [self nearestPOIToScreenPoint:locInView maxPixelRadius:MOUSE_RADIUS];
        BOOL other = poi && ![self.mapView.selectedAnnotations containsObject:poi];
        for (id<MKAnnotation> a in [self.mapView.selectedAnnotations copy]) [self.mapView deselectAnnotation:a animated:YES];
        self.activeCalloutView = nil;
        if (other) [self.mapView selectAnnotation:poi animated:YES];
        return;
    }
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
            // type and optional name asked first (#3)
            [BPPOIEditor editType:[POILocation defaultCustomPoiType] name:nil
                            title:NSLocalizedString(@"Add a point of interest", @"custom POI editor")
                         okButton:NSLocalizedString(@"Add", @"custom POI editor") window:self.mapView.window
                       completion:^(PoiType_t type, NSString *name) {
                [self addCustomPoiAt:rcoord type:type name:name];
            }];
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
    [self cancelRouteRequest]; // its answer is for the replaced plan (#16)
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

// the Preferences changed the route colors (#71): MapKit keeps a renderer per overlay, so the overlays are added
// again; the pins are created again (stage-end color)
- (void) colorSchemeChanged:(NSNotification *)note
{
    self.elevationView.stageEndColor = [BPColorScheme currentScheme].stageEndColor;
    [self refreshAnnot:NO];
    [self refreshPoly:NO];
    [self refreshGpxDisplayed];
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
    // under the route (#71: the Compare color scheme draws an opaque route over a wider trace)
    TaggedPoly *firstRoute = nil;
    for (id<MKOverlay> ov in self.mapView.overlays) {
        if ([ov isKindOfClass:[TaggedPoly class]] && 0 == ((TaggedPoly *)ov).tag) { firstRoute = (TaggedPoly *)ov; break; }
    }
    if (firstRoute) {
        [self.mapView insertOverlay:gpxpoly belowOverlay:firstRoute];
    } else {
        [self.mapView addOverlay:gpxpoly level:MKOverlayLevelAboveLabels];
    }
 
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
    // callout (#72): the name under the type; a custom POI with a name has it as title: its type under it
    BPPOIDescription *d = [[BPPOIDescription alloc] initWithType:loc.poiType info:loc.info custom:[loc.poiKey hasPrefix:@"custom:"]];
    ann.subtitle = d.custom ? (d.name ? d.typeName : nil) : d.name;
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
            if (0 == tp.tag || 3 == tp.tag) { // with the road class highlight of the old route (#54), drawn again below
                [self.mapView removeOverlay:ov];
            }
        }
    }
    MKPolyline *poly = _document.plan.routePoly;
    
    // a route cut in stages (#31): one polyline per stage, alternating colors
    NSArray<NSArray<CLLocation *> *> *stages = _document.plan.stagesRoutePoints;
    if (stages.count > 1) {
        [stages enumerateObjectsUsingBlock:^(NSArray<CLLocation *> *pts, NSUInteger i, BOOL *stop) {
            CLLocationCoordinate2D *coords = malloc(pts.count * sizeof(CLLocationCoordinate2D));
            for (NSUInteger k = 0; k < pts.count; k++) coords[k] = pts[k].coordinate;
            TaggedPoly *p = [TaggedPoly polylineWithCoordinates:coords count:pts.count];
            free(coords);
            p.tag = 0;
            p.stage = i;
            [self.mapView addOverlay:p level:MKOverlayLevelAboveLabels];
        }];
    } else {
        [self.mapView addOverlay:poly level:MKOverlayLevelAboveLabels];
    }
    self.elevationView.stageEndIndexes = _document.plan.stageEndRouteIndexes;
    if (_highlightedKind) [self highlightKind:_highlightedKind]; // on the new route (#66)
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
    } else {
        [self cancelRouteRequest];
    }
    /*if (self.hasEnd && self.hasStart) {
     // 0.495477,44.178503
     if ((0)) self.startCoord = CLLocationCoordinate2DMake(44.178503, 0.495477);
     [self requestRoute];
     }*/
}
// the answer of the request in flight, if any, will be ignored
- (void) cancelRouteRequest
{
    [routeTask cancel];
    routeTask = nil;
    routeGeneration++;
}

// one request at a time: a new one cancels the previous one, whose answer could otherwise overwrite the newer
// route (#9); errors are shown on the map, the previous route is kept
- (void) requestRoute
{
    [self requestRouteUndoable:nil];
}

// undoDesc: the answer replaces the route as an undoable action of that name (the waypoints did not change, #55);
// nil when the change of waypoints that caused the request is the undoable action
- (void) requestRouteUndoable:(nullable NSString *)undoDesc
{
    // profile can be changed, e.g. "trekking", "fastbike", etc.
    if (!undoDesc) self.gpxData = nil; // the route no longer matches the waypoints
    [self cancelRouteRequest];
    NSUInteger generation = routeGeneration;
    NSString *profile = _document.plan.profileName;
    routeTask = [self.brouter routeWithWaypoints:_document.plan.waypointsLocations profile:profile overrides:_document.plan.profileOverrides completion:^(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *brouterInfo, NSError *error) {
        // process it on main thread, otherwise setNeedDisplay does not operate ok
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->routeGeneration) return; // cancelled or replaced by a newer request
            self->routeTask = nil;
            if (error || points.count == 0) {
                NSLog(@"BRouter error: %@", error);
                [self showMapMessage:[NSString stringWithFormat:NSLocalizedString(@"Routing failed: %@", @"BRouter error"),
                                      error.localizedDescription ?: NSLocalizedString(@"No route found", @"BRouter error")]];
                return;
            }
            if (undoDesc) {
                NSUndoManager *um = self.document.undoManager;
                [um beginUndoGrouping];
                [um registerUndoWithTarget:self selector:@selector(undoRouteState:) object:[self.document.plan routeState]];
                [um setActionName:undoDesc];
                [um endUndoGrouping];
            }
            if (brouterInfo) {
                unsigned int kmlen = ([brouterInfo[@"n-track-length-m"] unsignedIntValue] + 500)/1000;
                NSAssert(self.document.plan.brouterInfo, @"no brouterInfo");
                self.document.plan.brouterInfo.kmlen = kmlen;
                int mup = [brouterInfo[@"filtered-ascend"] intValue];
                self.document.plan.brouterInfo.mup = mup;
                self.document.plan.brouterInfo.meters = [brouterInfo[@"n-track-length-m"] integerValue];
                self.document.plan.brouterInfo.seconds = [brouterInfo[@"n-time-seconds"] integerValue];
                self.document.plan.brouterInfo.roadStats = brouterInfo[@"road-stats"];       // #53
                self.document.plan.brouterInfo.surfaceStats = brouterInfo[@"surface-stats"];
                self.document.plan.brouterInfo.roadRuns = brouterInfo[@"road-runs"];        // #54
                self.document.plan.brouterInfo.surfaceRuns = brouterInfo[@"surface-runs"];
            }
            self.document.plan.routeGPX = gpx; // saved with the document (#10)
            self.gpxData = gpx;
            self.document.plan.routePoints = points;
            [self.elevationView setGpxPoints:points];
            [self refreshPoly:NO];
            
        });
    
    }];
}

// tag 3 polylines over the route, one per run of the class; nothing when the runs are not those of the route
// (route imported from a trace, document saved before #54). Kept for the next routes (#66)
- (void) highlightKind:(nullable NSString *)kind
{
    _highlightedKind = [kind copy];
    for (id<MKOverlay> ov in [self.mapView.overlays copy]) {
        if ([ov isKindOfClass:[TaggedPoly class]] && 3 == ((TaggedPoly *)ov).tag) [self.mapView removeOverlay:ov];
    }
    NSArray<CLLocation *> *pts = _document.plan.routePoints;
    NSArray<NSArray *> *runs = nil;
    NSString *cls = nil;
    if ([kind hasPrefix:@"road:"]) {
        runs = _document.plan.brouterInfo.roadRuns;
        cls = [kind substringFromIndex:5];
    } else if ([kind hasPrefix:@"surface:"]) {
        runs = _document.plan.brouterInfo.surfaceRuns;
        cls = [kind substringFromIndex:8];
    }
    if (!cls || pts.count < 2 || [runs.lastObject[1] unsignedIntegerValue] != pts.count - 1) return;
    NSUInteger from = 0; // a run starts at the last point of the previous one
    for (NSArray *run in runs) {
        NSUInteger end = MIN([run[1] unsignedIntegerValue], pts.count - 1);
        if ([run[0] isEqualToString:cls] && end > from) {
            NSUInteger n = end - from + 1;
            CLLocationCoordinate2D *coords = malloc(n * sizeof(CLLocationCoordinate2D));
            for (NSUInteger i = 0; i < n; i++) coords[i] = pts[from + i].coordinate;
            TaggedPoly *p = [TaggedPoly polylineWithCoordinates:coords count:n];
            free(coords);
            p.tag = 3;
            [self.mapView addOverlay:p level:MKOverlayLevelAboveLabels];
        }
        from = MAX(from, end);
    }
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
        BPColorScheme *scheme = [BPColorScheme currentScheme]; // #71
        
        if (pl.tag == 0) {
            // route being built
            r.lineWidth = scheme.routeWidth;
            r.alpha = scheme.routeAlpha;
            r.strokeColor = [scheme colorForStage:pl.stage]; // stages (#31)
        } else if (pl.tag == 3) {
            // road class hovered in the Info section (#54)
            r.lineWidth = 9.0;
            r.alpha = 0.9;
            r.strokeColor = scheme.highlightColor;
        } else {
            // gpx loaded
            r.lineWidth = scheme.traceWidth;
            r.alpha = scheme.traceAlpha;
            //r.strokeColor = [NSColor darkGrayColor];
            r.strokeColor = scheme.referenceTraceColor;
        }
        return r;
    }
    return [[MKOverlayRenderer alloc] initWithOverlay:overlay]; // draws nothing; MapKit expects a renderer
}




#pragma mark - location search (#40)

- (void) installSearchField
{
    for (NSToolbarItem *item in self.mapView.window.toolbar.items) {
        if ([item isKindOfClass:[NSSearchToolbarItem class]]) {
            searchField = ((NSSearchToolbarItem *)item).searchField;
            searchField.delegate = self;
        }
    }
}

// Return in the search field (only then, #41): one result is shown, several are proposed in a menu, none or an
// error gives a message; an empty field removes the search pin
- (IBAction) sendersearchFieldAction:(id)sender
{
    NSSearchField *field = (NSSearchField *)sender;
    NSString *query = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        [self removeSearchPin];
        return;
    }
    CLLocation *center = [[CLLocation alloc] initWithLatitude:self.mapView.centerCoordinate.latitude
                                                    longitude:self.mapView.centerCoordinate.longitude];
    [BPPlaceSearch search:query near:self.mapView.region completion:^(NSArray<MKMapItem *> *items, NSError *error) {
        if (error) {
            [self showMapMessage:[NSString stringWithFormat:NSLocalizedString(@"Search failed: %@", @"location search"),
                                  error.localizedDescription]];
        } else if (items.count == 0) {
            [self showMapMessage:[NSString stringWithFormat:NSLocalizedString(@"No place found for “%@”", @"location search"), query]];
        } else if (items.count == 1) {
            [self showSearchResult:items.firstObject];
        } else {
            NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Places"];
            for (MKMapItem *item in items) {
                CLLocation *loc = [[CLLocation alloc] initWithLatitude:item.placemark.coordinate.latitude
                                                             longitude:item.placemark.coordinate.longitude];
                NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%@ (%.0f km)", @"search result: place (distance)"),
                                   [BPPlaceSearch titleForItem:item], [loc distanceFromLocation:center] / 1000];
                NSMenuItem *mi = [menu addItemWithTitle:title action:@selector(searchResultChosen:) keyEquivalent:@""];
                mi.target = self;
                mi.representedObject = item;
            }
            void (^present)(NSMenu *, NSView *) = self.presentSearchResultsMenu ?: ^(NSMenu *m, NSView *v) {
                NSPoint p = v.isFlipped ? NSMakePoint(0, NSHeight(v.bounds) + 4) : NSMakePoint(0, -4);
                [m popUpMenuPositioningItem:nil atLocation:p inView:v];
            };
            present(menu, field);
        }
    }];
}

- (void) searchResultChosen:(NSMenuItem *)sender
{
    [self showSearchResult:sender.representedObject];
}

- (void) showSearchResult:(MKMapItem *)item
{
    [self removeSearchPin];
    searchPin = [[BPSearchPinAnnotation alloc] init];
    searchPin.coordinate = item.placemark.coordinate;
    searchPin.title = item.name;
    searchPin.subtitle = [BPPlaceSearch subtitleForItem:item];
    [self.mapView addAnnotation:searchPin];
    [self.mapView setRegion:[BPPlaceSearch regionForItem:item] animated:YES];
}

- (void) removeSearchPin
{
    if (searchPin) [self.mapView removeAnnotation:searchPin];
    searchPin = nil;
}

// temporary message in place of the click mode help (search feedback)
- (void) showMapMessage:(NSString *)message
{
    helpTxtField.stringValue = message;
    NSRect f = helpTxtField.frame;
    f.size.width = ceil(helpTxtField.attributedStringValue.size.width) + 8;
    helpTxtField.frame = f;
    if (helpBackdrop) helpBackdrop.frame = NSInsetRect(f, -kBackdropMargin, -kBackdropMargin);
    [mapMessageTimer invalidate];
    mapMessageTimer = [NSTimer scheduledTimerWithTimeInterval:4 repeats:NO block:^(NSTimer *t) {
        [self setHelpStringForClickMode:self->clickmode];
    }];
}

// completions while typing (MKLocalSearchCompleter), shown by the field editor's completion list
- (void) controlTextDidChange:(NSNotification *)notification
{
    if (notification.object != searchField) return;
    NSString *text = searchField.stringValue;
    for (NSString *t in searchCompletionTitles) {
        if ([t caseInsensitiveCompare:text] == NSOrderedSame) return; // a completion being browsed, not typing
    }
    if (text.length < 2) {
        searchCompletionTitles = @[];
        return;
    }
    if (!searchCompleter) {
        searchCompleter = [[MKLocalSearchCompleter alloc] init];
        searchCompleter.delegate = self;
    }
    searchCompleter.region = self.mapView.region;
    searchCompleter.queryFragment = text;
}

- (void) completerDidUpdateResults:(MKLocalSearchCompleter *)completer
{
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (MKLocalSearchCompletion *c in completer.results) {
        [titles addObject:c.subtitle.length ? [NSString stringWithFormat:@"%@, %@", c.title, c.subtitle] : c.title];
    }
    searchCompletionTitles = titles;
    NSText *editor = searchField.currentEditor;
    if (titles.count && [editor isKindOfClass:[NSTextView class]]) [(NSTextView *)editor complete:nil];
}

- (void) completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error
{
    searchCompletionTitles = @[];
}

- (void) setSearchCompletionTitles:(NSArray<NSString *> *)titles
{
    searchCompletionTitles = [titles copy];
}

// the field editor replaces the partial word only: give the end of the matching completions from there
- (NSArray<NSString *> *) completionsForText:(NSString *)text partialWordRange:(NSRange)range
{
    if (NSMaxRange(range) > text.length) return @[];
    NSString *typed = [text substringToIndex:NSMaxRange(range)];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *t in searchCompletionTitles) {
        if (t.length <= range.location) continue;
        if ([t rangeOfString:typed options:NSAnchoredSearch | NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == 0) {
            [out addObject:[t substringFromIndex:range.location]];
        }
    }
    return out;
}

- (NSArray<NSString *> *) control:(NSControl *)control textView:(NSTextView *)textView completions:(NSArray<NSString *> *)words
              forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index
{
    if (control != searchField) return words;
    if (index) *index = -1; // nothing preselected: Return keeps what was typed
    return [self completionsForText:textView.string partialWordRange:charRange];
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
    if ((0) && !inclPOI) {
        return _gpxData;
    }
    return [self gpxData:_gpxData withPOIs:inclPOI ? self.exportablePOIs : @[] trackName:trackName];
}

// custom POIs, then fetched ones, without the excluded ones (#5)
- (NSArray<POILocation *> *) exportablePOIs
{
    NSMutableArray<POILocation *> *pois = [NSMutableArray array];
    for (POILocation *poi in [_document.plan.customPoiloc arrayByAddingObjectsFromArray:_document.plan.poiloc ?: @[]]) {
        if (![_document.plan isPOIExcluded:poi]) [pois addObject:poi];
    }
    return pois;
}

// one GPX per stage (#31) in dir: "<baseName> - stage <n>.gpx", with the POIs of the stage (nearest route point)
- (BOOL) exportStagesToDirectory:(NSURL *)dir baseName:(NSString *)baseName withPOI:(BOOL)inclPOI error:(NSError **)error
{
    NSArray<NSArray<CLLocation *> *> *stages = _document.plan.stagesRoutePoints;
    NSMutableArray<NSMutableArray<POILocation *> *> *pois = [NSMutableArray array];
    for (NSUInteger i = 0; i < stages.count; i++) [pois addObject:[NSMutableArray array]];
    if (inclPOI) {
        for (POILocation *poi in self.exportablePOIs) {
            NSUInteger s = MIN([_document.plan stageOfCoordinate:poi.coordinate], stages.count - 1);
            [pois[s] addObject:poi];
        }
    }
    for (NSUInteger i = 0; i < stages.count; i++) {
        NSString *name = [NSString stringWithFormat:NSLocalizedString(@"%@ - stage %lu", @"GPX file of a stage"), baseName, (unsigned long)(i + 1)];
        NSData *gpx = [self gpxData:[BikePlan gpxDataForPoints:stages[i] name:name] withPOIs:pois[i] trackName:name];
        NSURL *url = [dir URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"gpx"]];
        if (![gpx writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
    }
    return YES;
}

- (NSData *) gpxData:(NSData *)baseGPX withPOIs:(NSArray<POILocation *> *)pois trackName:(nullable NSString *)trackName
{
    if (!trackName) trackName = @"track";
    //NSMutableString *xml = [[NSMutableString alloc]initWithCapacity:4000];
    NSString *gpxstr = [[NSString alloc] initWithData:baseGPX encoding:NSUTF8StringEncoding];
    
    //gpxstr = [gpxstr stringByAppendingString:@"<name>plop</name>"];
    NSRange nameTag = [gpxstr rangeOfString:@"<name>.*</name>" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch];
    if (nameTag.location != NSNotFound) {
        NSString *nname = [NSString stringWithFormat:@"<name>%@</name>", xmlEscaped(trackName)];
        gpxstr = [gpxstr stringByReplacingCharactersInRange:nameTag withString:nname];
    }
    
    NSRange closingTag = [gpxstr rangeOfString:@"</gpx>" options:NSBackwardsSearch|NSCaseInsensitiveSearch];
    if (closingTag.location == NSNotFound) {
        NSLog(@"Invalid GPX: missing </gpx>");
        return baseGPX;
    }
    NSMutableString *xml = [NSMutableString stringWithString:
                               [gpxstr substringToIndex:closingTag.location]];
  
    
    for (POILocation *poi in pois) {
        [xml appendFormat:@"<wpt lat=\"%f\" lon=\"%f\">\n", poi.coordinate.latitude, poi.coordinate.longitude];
        [xml appendFormat:@"  <name>%@</name>\n", xmlEscaped(poi.title ?: poi.gpxType)]; // custom POIs have no title
        //if (poi.subtitle) {
        //    [xml appendFormat:@"  <desc>%@</desc>\n", poi.subtitle];
        //}
        [xml appendFormat:@"  <sym>%@</sym>\n", xmlEscaped(poi.gpxSymbol ?: @"Flag")];
        [xml appendFormat:@"  <type>%@</type>\n", xmlEscaped(poi.gpxType ?: @"Flag")];
        [xml appendString:@"</wpt>\n"];
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
- (BOOL) isDirectory:(NSURL *)url
{
    BOOL dir = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&dir] && dir;
}

// the export panel of a route in stages (#31, #69): a folder name (no extension) for one file per stage in a
// folder; else a .gpx file name (the whole route, or the base name of the stage files)
- (void) applyStagesExportMode:(BPStagesExportMode)mode toPanel:(NSSavePanel *)panel
{
    NSString *base = [panel.nameFieldStringValue stringByDeletingPathExtension];
    if (!base.length) base = @"plan";
    if (mode == BPStagesExportFolder) {
        panel.allowedContentTypes = @[UTTypeFolder];
        panel.nameFieldStringValue = base;
    } else {
        panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"gpx"]];
        panel.nameFieldStringValue = [base stringByAppendingPathExtension:@"gpx"];
    }
}

- (void) exportStagesModeChanged:(NSPopUpButton *)sender
{
    [self.exportDefaults setInteger:sender.selectedTag forKey:BPExportStagesModeKey];
    NSSavePanel *panel = exportPanel;
    if (panel) [self applyStagesExportMode:sender.selectedTag toPanel:panel];
}

// "Stages:" pop-up of the export panel, on the last choice (#69)
- (NSPopUpButton *) stagesExportPopUp
{
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSArray *titles = @[NSLocalizedString(@"One file per stage, in a folder", @"export"),
                        NSLocalizedString(@"Whole route, one file", @"export"),
                        NSLocalizedString(@"One file per stage, no folder", @"export")];
    for (NSUInteger i = 0; i < titles.count; i++) {
        [popup addItemWithTitle:titles[i]];
        popup.lastItem.tag = (NSInteger)i;
    }
    NSInteger mode = [self.exportDefaults integerForKey:BPExportStagesModeKey];
    if (![popup selectItemWithTag:mode]) [popup selectItemWithTag:BPStagesExportFolder];
    popup.target = self;
    popup.action = @selector(exportStagesModeChanged:);
    popup.accessibilityIdentifier = @"exportStages";
    [popup sizeToFit];
    return popup;
}

- (NSUserDefaults *) exportDefaults
{
    return exportDefaults ?: [NSUserDefaults standardUserDefaults];
}

- (void) setExportDefaults:(nullable NSUserDefaults *)defaults
{
    exportDefaults = defaults;
}

// writes the GPX of the route at url: a new folder of stage files, one file, or stage files next to url ("<name> -
// stage <n>.gpx", url itself is not written)
- (BOOL) exportGPXToURL:(NSURL *)url mode:(BPStagesExportMode)mode withPOI:(BOOL)inclPOI error:(NSError **)error
{
    NSString *name = [[url lastPathComponent] stringByDeletingPathExtension];
    switch (mode) {
        case BPStagesExportFolder: {
            NSError *err = nil;
            BOOL ok = [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:&err]
                      || [url hasDirectoryPath] || [self isDirectory:url];
            if (!ok) {
                if (error) *error = err;
                return NO;
            }
            return [self exportStagesToDirectory:url baseName:name withPOI:inclPOI error:error];
        }
        case BPStagesExportFiles:
            return [self exportStagesToDirectory:url.URLByDeletingLastPathComponent baseName:name withPOI:inclPOI error:error];
        case BPStagesExportWhole:
        default:
            return [[self exportGpxDataWithPOI:inclPOI trackName:name] writeToURL:url options:NSDataWritingAtomic error:error];
    }
}

- (BOOL) isNoPermissionError:(nullable NSError *)error
{
    if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileWriteNoPermissionError) return YES;
    NSError *posix = error.userInfo[NSUnderlyingErrorKey];
    return [posix.domain isEqualToString:NSPOSIXErrorDomain] && (posix.code == EPERM || posix.code == EACCES);
}

// folders where the user let the app write stage files (#69): security-scoped bookmarks, by path
- (nullable NSURL *) rememberedFolderAccess:(NSURL *)dir
{
    NSData *bookmark = [self.exportDefaults dictionaryForKey:BPExportFolderBookmarksKey][dir.URLByStandardizingPath.path];
    if (!bookmark) return nil;
    BOOL stale = NO;
    NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope
                                     relativeToURL:nil bookmarkDataIsStale:&stale error:NULL];
    if (stale && url) [self rememberFolderAccess:url];
    return url;
}

- (void) rememberFolderAccess:(NSURL *)dir
{
    NSData *bookmark = [dir bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil
                                      relativeToURL:nil error:NULL];
    if (!bookmark) return;
    NSMutableDictionary *d = [[self.exportDefaults dictionaryForKey:BPExportFolderBookmarksKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    d[dir.URLByStandardizingPath.path] = bookmark;
    [self.exportDefaults setObject:d forKey:BPExportFolderBookmarksKey];
}

// one file per stage, no folder (#69): the save panel only lets the sandboxed app write the file it names, so the
// folder needs its own permission: a folder panel opened on it (one click), remembered for the next exports
- (void) exportStageFilesNextTo:(NSURL *)fileURL withPOI:(BOOL)inclPOI
{
    NSURL *dir = fileURL.URLByDeletingLastPathComponent;
    NSString *name = fileURL.lastPathComponent;
    NSURL *scoped = [self rememberedFolderAccess:dir];
    BOOL accessing = [scoped startAccessingSecurityScopedResource];
    NSError *error = nil;
    BOOL ok = [self exportGPXToURL:fileURL mode:BPStagesExportFiles withPOI:inclPOI error:&error];
    if (accessing) [scoped stopAccessingSecurityScopedResource];
    if (ok) return;
    if (![self isNoPermissionError:error]) {
        [self showExportError:error];
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.directoryURL = dir;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    panel.prompt = NSLocalizedString(@"Export Here", @"folder panel of the stage files");
    panel.message = NSLocalizedString(@"Allow BikePlanner to write one GPX file per stage in this folder (asked once per folder).",
                                      @"folder panel of the stage files");
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        NSURL *chosen = panel.URL;
        [self rememberFolderAccess:chosen];
        NSError *err = nil;
        if (![self exportGPXToURL:[chosen URLByAppendingPathComponent:name] mode:BPStagesExportFiles withPOI:inclPOI error:&err]) {
            [self showExportError:err];
        }
    }];
}

- (void) showExportError:(nullable NSError *)error
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Export failed";
    alert.informativeText = error.localizedDescription ?: @"";
    [alert runModal];
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
    // a route in stages (#31, #69): one GPX per stage in a folder named in the panel, the whole route, or one GPX per
    // stage next to each other; the last choice is kept
    NSPopUpButton *stagesMode = nil;
    if (_document.plan.stagesRoutePoints.count > 1) {
        NSView *acc = accessoryVC.view;
        stagesMode = [self stagesExportPopUp];
        NSTextField *label = [NSTextField labelWithString:NSLocalizedString(@"Stages:", @"export")];
        CGFloat h = MAX(NSHeight(stagesMode.frame), NSHeight(label.frame)) + 8;
        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(acc.frame), NSHeight(acc.frame) + h)];
        acc.frame = NSMakeRect(0, h, NSWidth(acc.frame), NSHeight(acc.frame));
        label.frameOrigin = NSMakePoint(20, 4 + (NSHeight(stagesMode.frame) - NSHeight(label.frame)) / 2);
        stagesMode.frameOrigin = NSMakePoint(NSMaxX(label.frame) + 6, 4);
        [box addSubview:acc];
        [box addSubview:label];
        [box addSubview:stagesMode];
        savePanel.accessoryView = box;
        exportPanel = savePanel;
        [self applyStagesExportMode:stagesMode.selectedTag toPanel:savePanel];
    }
    
    [savePanel beginWithCompletionHandler:^(NSModalResponse result) {
        self->exportPanel = nil;
        if (result != NSModalResponseOK) return;
        NSURL *destinationURL = savePanel.URL;
        BOOL includePOI = (accessoryVC.poiCheckbox.state == NSControlStateValueOn);
        BPStagesExportMode mode = stagesMode ? stagesMode.selectedTag : BPStagesExportWhole;
        if (mode == BPStagesExportFiles) {
            // after the save panel is closed: it may open a folder panel
            dispatch_async(dispatch_get_main_queue(), ^{ [self exportStageFilesNextTo:destinationURL withPOI:includePOI]; });
            return;
        }
        NSError *error = nil;
        if (![self exportGPXToURL:destinationURL mode:mode withPOI:includePOI error:&error]) [self showExportError:error];
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
    
    CGPoint proj; // projection may be NULL
    if (t < 0) {
        proj = a;
    } else if (t > 1) {
        proj = b;
    } else {
        proj = CGPointMake(a.x + t * dx, a.y + t * dy);
    }
    if (projection) *projection = proj;
    
    CGFloat px = p.x - proj.x;
    CGFloat py = p.y - proj.y;
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
        view.menu = [self waypointMenuForAnnotation:ra];
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
            POICalloutView *detailView = [[POICalloutView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
            view.detailCalloutAccessoryView = detailView;
            detailView.actionTarget = self; // #72; its content is built when it opens (#78)
            view.leftCalloutAccessoryView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 28, 28)];
            detailView.annotview = view;
        } else {
            view.annotation = annotation;
        }
        
        POIAnnotation *poi = (POIAnnotation *)annotation;
        [poi configureAnnotViewIcon:view];
        // the callout content is filled when it opens (didSelectAnnotationView:): filling it here, for every marker,
        // computed the position on the route each time (#78)
        POICalloutView *callout = (POICalloutView *)view.detailCalloutAccessoryView;
        callout.infodic = poi.info;
        callout.included = !poi.excluded;
        ((NSImageView *)view.leftCalloutAccessoryView).image = [self calloutIconForPOIType:poi.poiType];
        // custom POIs: Edit / Remove on right-click (#3); views are reused: always set
        if ([poi.poiKey hasPrefix:@"custom:"]) {
            NSMenu *menu = [[NSMenu alloc] initWithTitle:@"POI"];
            NSMenuItem *edit = [menu addItemWithTitle:NSLocalizedString(@"Edit POI…", @"custom POI menu")
                                               action:@selector(editCustomPOIMenuAction:) keyEquivalent:@""];
            NSMenuItem *remove = [menu addItemWithTitle:NSLocalizedString(@"Remove POI", @"custom POI menu")
                                                 action:@selector(removeCustomPOIMenuAction:) keyEquivalent:@""];
            for (NSMenuItem *item in @[edit, remove]) {
                item.target = self;
                item.representedObject = poi.poiKey;
            }
            view.menu = menu;
        } else {
            view.menu = nil;
        }
        
        return view;
    }
        
    return nil;
}

#pragma mark - POI callout (#72)

- (void) configurePOICallout:(POICalloutView *)callout forAnnotation:(POIAnnotation *)poi
{
    callout.infodic = poi.info;
    callout.included = !poi.excluded;
    BPPOIDescription *d = [[BPPOIDescription alloc] initWithType:poi.poiType info:poi.info custom:[poi.poiKey hasPrefix:@"custom:"]];
    [callout configureWithDescription:d position:[self routePositionStringForCoordinate:poi.coordinate]];
}

// "km 12.4 (stage 2) · 180 m off route", nil without route
- (nullable NSString *) routePositionStringForCoordinate:(CLLocationCoordinate2D)coord
{
    BikePlan *plan = _document.plan;
    if (plan.routePoints.count < 2) return nil;
    NSUInteger segstart = 0;
    double along = [self distanceAtCoordinate:coord segstart:&segstart];
    CLLocationCoordinate2D onRoute = [self coordinateAtDistance:along];
    CLLocation *a = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
    CLLocation *b = [[CLLocation alloc] initWithLatitude:onRoute.latitude longitude:onRoute.longitude];
    NSInteger stage = plan.stagesRoutePoints.count > 1 ? (NSInteger)[plan stageOfCoordinate:onRoute] : -1;
    return [BPPOIDescription positionStringForDistance:along offset:[a distanceFromLocation:b] stage:stage];
}

// the marker of the type: its glyph in white on a disc of its color
- (NSImage *) calloutIconForPOIType:(PoiType_t)type
{
    NSImage *glyph = [POIAnnotation glyphImageForType:type];
    NSColor *tint = [POIAnnotation tintColorForType:type] ?: [NSColor systemGrayColor];
    return [NSImage imageWithSize:NSMakeSize(28, 28) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [[tint colorWithAlphaComponent:fmax(tint.alphaComponent, 0.6)] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(r, 1, 1)] fill];
        if (glyph) {
            NSImage *white = [NSImage imageWithSize:glyph.size flipped:NO drawingHandler:^BOOL(NSRect gr) {
                [glyph drawInRect:gr];
                [[NSColor whiteColor] set];
                NSRectFillUsingOperation(gr, NSCompositingOperationSourceAtop);
                return YES;
            }];
            [white drawInRect:NSInsetRect(r, 7, 7)];
        }
        return YES;
    }];
}

// the POI whose callout holds this control
- (nullable POIAnnotation *) poiAnnotationOfCalloutControl:(NSView *)control
{
    NSView *v = control;
    while (v && ![v isKindOfClass:[POICalloutView class]]) v = v.superview;
    id<MKAnnotation> annotation = ((POICalloutView *)v).annotview.annotation;
    return [annotation isKindOfClass:[POIAnnotation class]] ? (POIAnnotation *)annotation : nil;
}

- (void) openPOIInOSM:(NSButton *)sender
{
    POIAnnotation *poi = [self poiAnnotationOfCalloutControl:sender];
    if (!poi) return;
    NSURL *url = [[BPPOIDescription alloc] initWithType:poi.poiType info:poi.info custom:[poi.poiKey hasPrefix:@"custom:"]].osmURL;
    if (!url) return;
    if (poiURLOpener) poiURLOpener(url);
    else [[NSWorkspace sharedWorkspace] openURL:url];
}

// tests
- (void) setPoiPasteboard:(nullable NSPasteboard *)pb
{
    poiPasteboard = pb;
}

- (void) setPoiURLOpener:(nullable void (^)(NSURL *url))opener
{
    poiURLOpener = opener;
}

// Street View from the nearest point of the route, looking at the POI; the profile cursor goes there
- (void) streetViewAtPOI:(NSButton *)sender
{
    POIAnnotation *poi = [self poiAnnotationOfCalloutControl:sender];
    if (!poi) return;
    CLLocationCoordinate2D target = poi.coordinate;
    if (_document.plan.routePoints.count < 2) {
        [self.svCtrl viewCoord:target lookingAt:0 coalesce:NO];
        return;
    }
    NSUInteger segstart = 0;
    double along = [self distanceAtCoordinate:target segstart:&segstart];
    CLLocationCoordinate2D onRoute = [self coordinateAtDistance:along];
    CLLocation *a = [[CLLocation alloc] initWithLatitude:target.latitude longitude:target.longitude];
    CLLocation *b = [[CLLocation alloc] initWithLatitude:onRoute.latitude longitude:onRoute.longitude];
    // on the route: no direction to the POI, look along the route
    double bearing = [a distanceFromLocation:b] < 10 ? [self bearingAtDistance:along] : [self bearingFrom:onRoute to:target];
    scrubberMarker.coordinate = onRoute;
    self.elevationView.highlightDistance = along;
    [self.elevationView setNeedsDisplay:YES];
    [self.svCtrl viewCoord:onRoute lookingAt:bearing coalesce:NO];
}

- (void) copyPOICoordinates:(NSButton *)sender
{
    POIAnnotation *poi = [self poiAnnotationOfCalloutControl:sender];
    if (!poi) return;
    NSPasteboard *pb = poiPasteboard ?: [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[BPPOIDescription coordinateString:poi.coordinate] forType:NSPasteboardTypeString];
}

- (void) editPOIFromCallout:(NSButton *)sender
{
    POIAnnotation *poi = [self poiAnnotationOfCalloutControl:sender];
    if (!poi.poiKey) return;
    [self.mapView deselectAnnotation:poi animated:NO];
    [self editCustomPOIWithKey:poi.poiKey];
}

// "Include in track" in the POI callout (#5, checkbox #72): an excluded POI is not exported, and shown greyed
- (void)includeCheckboxChanged:(NSButton *)sender
{
    POIAnnotation *annotation = [self poiAnnotationOfCalloutControl:sender];
    if (!annotation) return;
    NSString *key = annotation.poiKey;
    if (!key) return;
    [self setPOIKey:key excluded:(sender.state != NSControlStateValueOn)];
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
        
        if (![annotView.annotation isKindOfClass:[RouteAnnotation class]]) return;
        NSMenu *menu = [self waypointMenuForAnnotation:(RouteAnnotation *)annotView.annotation];
        
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

// the profile was zoomed or moved (#62): the map shows the same part of the route
- (void)elevationProfileView:(id)view didShowRangeFrom:(double)from to:(double)to
{
    NSArray<CLLocation *> *pts = _document.plan.routePoints;
    if (pts.count < 2) return;
    MKMapPoint a = MKMapPointForCoordinate([self coordinateAtDistance:from]);
    MKMapPoint b = MKMapPointForCoordinate([self coordinateAtDistance:to]);
    MKMapRect r = MKMapRectMake(fmin(a.x, b.x), fmin(a.y, b.y), fabs(a.x - b.x), fabs(a.y - b.y));
    double d = 0;
    for (NSUInteger i = 1; i < pts.count && d < to; i++) {
        d += [pts[i] distanceFromLocation:pts[i - 1]];
        if (d <= from || d >= to) continue;
        MKMapPoint p = MKMapPointForCoordinate(pts[i].coordinate);
        r = MKMapRectUnion(r, MKMapRectMake(p.x, p.y, 0, 0));
    }
    [self.mapView setVisibleMapRect:r edgePadding:NSEdgeInsetsMake(40, 40, 40, 40) animated:NO];
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


// Remove Waypoint; on an intermediate waypoint, End Stage Here (checked when it ends a stage, #31)
- (NSMenu *)waypointMenuForAnnotation:(RouteAnnotation *)annotation
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Waypoint Menu"];
    menu.delegate = self; // rebuilt when opened: the waypoint indexes change with insertions (menuNeedsUpdate:)
    [self fillWaypointMenu:menu annotation:annotation];
    return menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    RouteAnnotation *annotation = menu.itemArray.firstObject.representedObject;
    if (![menu.title isEqualToString:@"Waypoint Menu"] || ![annotation isKindOfClass:[RouteAnnotation class]]) return;
    [menu removeAllItems];
    [self fillWaypointMenu:menu annotation:annotation];
}

- (void)fillWaypointMenu:(NSMenu *)menu annotation:(RouteAnnotation *)annotation
{
    NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Remove Waypoint", @"waypoint menu")
                                                        action:@selector(removeWaypointMenuAction:)
                                                 keyEquivalent:@""];
    removeItem.target = self;
    removeItem.representedObject = annotation; // store the annotation reference
    [menu addItem:removeItem];
    NSUInteger idx = annotation.idx;
    if (idx > 0 && idx + 1 < _document.plan.waypointsLocations.count) {
        NSMenuItem *stageItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"End Stage Here", @"waypoint menu")
                                                           action:@selector(toggleStageEndMenuAction:)
                                                    keyEquivalent:@""];
        stageItem.target = self;
        stageItem.representedObject = annotation;
        stageItem.state = [_document.plan isStageEndAtWaypointIndex:idx] ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:stageItem];
    }
}

// the route is not requested again: same waypoints, only cut differently
- (void)toggleStageEndMenuAction:(id)sender
{
    RouteAnnotation *annotation = [(NSMenuItem *)sender representedObject];
    NSUInteger idx = annotation.idx;
    if (idx == 0 || idx + 1 >= _document.plan.waypointsLocations.count) return;
    BOOL end = ![_document.plan isStageEndAtWaypointIndex:idx];
    NSArray *old = [_document.plan setStageEnd:end atWaypointIndex:idx];
    NSUndoManager *um = _document.undoManager;
    [um registerUndoWithTarget:self selector:@selector(undoStages:) object:old];
    [um setActionName:end ? @"end stage" : @"remove stage end"];
    [self fullRefresh:NO];
}

- (void)undoStages:(NSArray<CLLocation *> *)oldwp
{
    [_document.undoManager registerUndoWithTarget:self selector:@selector(undoStages:) object:_document.plan.waypointsLocations];
    [_document.plan undoSetWayPt:oldwp];
    [self fullRefresh:NO];
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

// the same waypoints sent again to BRouter (#55): route of a document saved before a feature that needs the
// BRouter answer (#53, #54), of an imported trace, or after a failed request
- (BOOL) canRecalculateRoute
{
    return [_document.plan.waypointsLocations count] >= 2;
}

- (IBAction) recalculateRoute:(id)sender
{
    if (![self canRecalculateRoute]) return;
    [self requestRouteUndoable:@"recalculate route"];
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
    NSMutableArray<POILocation *> *pois = [NSMutableArray array];
    if (![pgpx.traceSource isEqualToString:@"wpt"]) {
        NSSet *fetchedTypes = [NSSet setWithObjects:@"WATER", @"TOILET", @"SERVICE", @"GENERIC", nil];
        [pgpx.waypoints enumerateObjectsUsingBlock:^(CLLocation *w, NSUInteger i, BOOL *stop) {
            if ([fetchedTypes containsObject:pgpx.waypointTypes[i]]) return;
            // the GPX type is kept (#74)
            PoiType_t type = [POILocation customPoiTypeForGPXType:pgpx.waypointTypes[i]];
            [pois addObject:[[POILocation alloc] initWithLatitude:w.coordinate.latitude longitude:w.coordinate.longitude
                                                           ofType:type info:@{} custom:YES]];
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

- (void) setRouteFromTrace:(NSArray<CLLocation *> *)trace waypoints:(NSArray<CLLocation *> *)wps pois:(NSArray<POILocation *> *)pois
{
    NSUndoManager *um = _document.undoManager;
    [um beginUndoGrouping];
    [self setRouteState:nil desc:nil]; // undo restores the whole previous route
    [_document.plan undoSetWayPt:wps];
    for (POILocation *p in pois) (void)[_document.plan addCustomPoiAt:p.coordinate type:p.poiType name:nil];
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
    if ((1) || _document.undoManager.isUndoing) {
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
    [self addCustomPoiAt:coord type:[POILocation defaultCustomPoiType] name:nil];
}

- (void) addCustomPoiAt:(CLLocationCoordinate2D)coord type:(PoiType_t)type name:(nullable NSString *)name
{
    [self undoableCustomPoi:[_document.plan.customPoiloc copy] desc:@"add POI"];
    (void)[_document.plan addCustomPoiAt:coord type:type name:name];
    [self refreshPOI];
}

- (nullable POILocation *) customPoiWithKey:(NSString *)key
{
    for (POILocation *p in _document.plan.customPoiloc) if ([p.poiKey isEqualToString:key]) return p;
    return nil;
}

// right-click menu of a custom POI (#3)
- (void) editCustomPOIMenuAction:(NSMenuItem *)sender
{
    [self editCustomPOIWithKey:sender.representedObject];
}

// also the Edit… button of the callout (#72)
- (void) editCustomPOIWithKey:(NSString *)key
{
    POILocation *poi = [self customPoiWithKey:key];
    if (!poi) return;
    [BPPOIEditor editType:poi.poiType name:poi.name
                    title:NSLocalizedString(@"Edit the point of interest", @"custom POI editor")
                 okButton:NSLocalizedString(@"OK", @"custom POI editor") window:self.mapView.window
               completion:^(PoiType_t type, NSString *name) {
        POILocation *current = [self customPoiWithKey:poi.poiKey];
        if (!current) return;
        [self undoableCustomPoi:[self.document.plan.customPoiloc copy] desc:@"edit POI"];
        (void)[self.document.plan replaceCustomPoi:current type:type name:name];
        [self refreshPOI];
    }];
}

- (void) removeCustomPOIMenuAction:(NSMenuItem *)sender
{
    POILocation *poi = [self customPoiWithKey:sender.representedObject];
    if (!poi) return;
    [self undoableCustomPoi:[_document.plan.customPoiloc copy] desc:@"remove POI"];
    [_document.plan removeCustomPoi:poi];
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

- (void) setGpxDisplayed:(nullable NSArray <CLLocation *>*)points desc:(nullable NSString *)d
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
