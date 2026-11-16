//
//  MapController.h
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "BRouterClient.h"
#import "StreetViewController.h"
#import "ElevationProfileView.h"
#import "Document.h"
#import "BPRemarkableSites.h"
NS_ASSUME_NONNULL_BEGIN

// what a click on the map does; values are the segment indexes of the clickMode control
typedef NS_ENUM(int, BPClickMode) {
    BPClickModeEdit = 0,    // add start/end waypoints, click on route inserts one
    BPClickModeInterm = 1,  // click on route inserts an intermediate waypoint
    BPClickModeView = 2,    // click on route moves Street View / elevation cursor
    // custom POIs: right-click menu of the map, in every mode (#80; Add POI was a mode before)
};

// pin of the location search result (one at a time, #40)
@interface BPSearchPinAnnotation : MKPointAnnotation
@end

@interface MapController : NSObject <MKMapViewDelegate, ElevationProfileViewDelegate, NSGestureRecognizerDelegate, NSToolbarItemValidation,
                                     NSSearchFieldDelegate, MKLocalSearchCompleterDelegate, NSMenuDelegate>

@property (weak) IBOutlet MKMapView *mapView;
@property (weak) IBOutlet Document *document;
@property (weak) IBOutlet StreetViewController *svCtrl;
@property (weak) IBOutlet ElevationProfileView *elevationView;
@property (weak) NSView *activeCalloutView;   // your POICalloutView

@property (strong) BRouterClient *brouter;
//@property (assign) CLLocationCoordinate2D startCoord;
//@property (assign) CLLocationCoordinate2D endCoord;
//@property (assign) BOOL hasStart;
//@property (assign) BOOL hasEnd;


@property (strong, nullable) NSData *gpxData;
@property (nonatomic) BOOL viewPOI;
@property (readonly, nonatomic) BPClickMode clickMode;
/// shows the menu of search results under the search field (default: pop-up menu; replaced by tests) (#40)
@property (copy) void (^presentSearchResultsMenu)(NSMenu *menu, NSView *view);


- (IBAction) exportGPX:(id)sender;
- (IBAction) importGPXTraceForDisplay:(id)sender;
- (IBAction) importGPXAsRoute:(id)sender;
- (IBAction) removeGPXTraceForDisplay:(id)sender;
- (BOOL) canRemoveGPXTraceForDisplay;
- (IBAction) reverseRoute:(id)sender;
- (BOOL) canReverseRoute;
- (IBAction) recalculateRoute:(id)sender;
- (BOOL) canRecalculateRoute;
- (IBAction) clearRoute:(id)sender;
- (BOOL) canClearRoute;
- (IBAction) sendersearchFieldAction:(id)sender;
- (void) shouldRecalcRoute;
- (void) fullRefresh:(BOOL)fromLoad; // called after load

- (void) initializeMapview;
/// shows a remarkable site as a new document starts on it (#65; also the start sites editor, #67)
- (void) showSite:(BPRemarkableSite *)site;
- (void) planReplaced; // document.plan was replaced (Revert to Saved)
/// the parts of the route of this kind, highlighted over the route (#54): "road:<road class>" or
/// "surface:<surface class>" (classes: BRouterGeoJSON.h; see BPRoadTypeKindKey); nil: none. Drawn again on each
/// new route (#66)
- (void) highlightKind:(nullable NSString *)kind;


/// called after the POIs are drawn again (refreshPOI): the Info section updates its list of sights (#81)
@property (copy, nullable) void (^poisChangedHandler)(void);
/// sights (#81), undoable: the categories (the POIs are fetched again), the inclusion distance (meters, 0: none)
- (void) setSightCategories:(NSArray<NSString *> *)categories;
- (void) setSightIncludeDistance:(NSInteger)meters;
/// includes / excludes a POI in the track, undoable (#5; a sight, #81)
- (void) setPOIKey:(NSString *)key excluded:(BOOL)excluded;
/// centers the map on a POI and opens its callout (#81, list of the sights)
- (void) showPOIWithKey:(NSString *)key;

/// what a guided tour step points at (#63): "waypoint" (an intermediate waypoint pin, else the last one),
/// "routeLine" (a point of the route, a third of the way), "waterPOI" (a visible drinking water POI); nil if none
/// (no route, nothing visible). *rect: in the returned view's coordinates
- (nullable NSView *) tourAnchorForKey:(NSString *)key rect:(NSRect *)rect;

- (IBAction) setClickModeToEdit:(id)sender;
- (IBAction) setClickModeToInterm:(id)sender;
- (IBAction) setClickModeToView:(id)sender;


//@property unsigned int kmlen;
//@property unsigned int mup;
@end

NS_ASSUME_NONNULL_END
