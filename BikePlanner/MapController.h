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
NS_ASSUME_NONNULL_BEGIN

// what a click on the map does; values are the segment indexes of the clickMode control
typedef NS_ENUM(int, BPClickMode) {
    BPClickModeEdit = 0,    // add start/end waypoints, click on route inserts one
    BPClickModeInterm = 1,  // click on route inserts an intermediate waypoint
    BPClickModeAddPOI = 2,  // click on route adds a custom POI
    BPClickModeView = 3,    // click on route moves Street View / elevation cursor
};

// pin of the location search result (one at a time, #40)
@interface BPSearchPinAnnotation : MKPointAnnotation
@end

@interface MapController : NSObject <MKMapViewDelegate, ElevationProfileViewDelegate, NSGestureRecognizerDelegate, NSToolbarItemValidation,
                                     NSSearchFieldDelegate, MKLocalSearchCompleterDelegate>

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
- (IBAction) clearRoute:(id)sender;
- (BOOL) canClearRoute;
- (IBAction) sendersearchFieldAction:(id)sender;
- (void) shouldRecalcRoute;
- (void) fullRefresh:(BOOL)fromLoad; // called after load

- (void) initializeMapview;
- (void) planReplaced; // document.plan was replaced (Revert to Saved)


- (IBAction) setClickModeToEdit:(id)sender;
- (IBAction) setClickModeToInterm:(id)sender;
- (IBAction) setClickModeToView:(id)sender;
- (IBAction) setClickModeToAddPoi:(id)sender;


//@property unsigned int kmlen;
//@property unsigned int mup;
@end

NS_ASSUME_NONNULL_END
