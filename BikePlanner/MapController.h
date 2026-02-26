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


@interface MapController : NSObject <MKMapViewDelegate, ElevationProfileViewDelegate, NSGestureRecognizerDelegate>

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
@property (strong) NSString *extraUrl;


@property (strong, nullable) NSData *gpxData;
@property (nonatomic) BOOL viewPOI;


- (IBAction) exportGPX:(id)sender;
- (IBAction) importGPXTraceForDisplay:(id)sender;
- (IBAction) sendersearchFieldAction:(id)sender;
- (void) shouldRecalcRoute;
- (void) fullRefresh:(BOOL)fromLoad; // called after load

- (void) initializeMapview;


- (IBAction) setClickModeToEdit:(id)sender;
- (IBAction) setClickModeToInterm:(id)sender;
- (IBAction) setClickModeToView:(id)sender;
- (IBAction) setClickModeToAddPoi:(id)sender;


//@property unsigned int kmlen;
//@property unsigned int mup;
@end

NS_ASSUME_NONNULL_END
