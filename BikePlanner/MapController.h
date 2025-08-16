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


@interface MapController : NSObject <MKMapViewDelegate, ElevationProfileViewDelegate>

@property (weak) IBOutlet MKMapView *mapView;
@property (weak) IBOutlet Document *document;
@property (weak) IBOutlet StreetViewController *svCtrl;
@property (weak) IBOutlet ElevationProfileView *elevationView;

@property (strong) BRouterClient *brouter;
//@property (assign) CLLocationCoordinate2D startCoord;
//@property (assign) CLLocationCoordinate2D endCoord;
//@property (assign) BOOL hasStart;
//@property (assign) BOOL hasEnd;
@property (strong) NSString *extraUrl;


@property (strong, nullable) NSData *gpxData;


- (IBAction) exportGPX:(id)sender;
- (IBAction) importGPXTraceForDisplay:(id)sender;
- (IBAction) sendersearchFieldAction:(id)sender;
- (void) shouldRecalcRoute;
- (void) fullRefresh; // called after load

- (void) initializeMapview;

@property unsigned int kmlen;
@property unsigned int mup;
@end

NS_ASSUME_NONNULL_END
