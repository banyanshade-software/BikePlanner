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

NS_ASSUME_NONNULL_BEGIN


@interface MapController : NSObject <MKMapViewDelegate>

@property (weak) IBOutlet MKMapView *mapView;
@property (weak) IBOutlet StreetViewController *svCtrl;
@property (strong) BRouterClient *brouter;
@property (assign) CLLocationCoordinate2D startCoord;
@property (assign) CLLocationCoordinate2D endCoord;
@property (assign) BOOL hasStart;
@property (assign) BOOL hasEnd;

@property (strong, nullable) NSData *gpxData;


- (IBAction) exportGPX:(id)sender;


- (void) initializeMapview;

@end

NS_ASSUME_NONNULL_END
