//
//  MapController.h
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "BRouterClient.h"

NS_ASSUME_NONNULL_BEGIN


@interface MapController : NSObject <MKMapViewDelegate>

@property (weak) IBOutlet MKMapView *mapView;
@property (strong) BRouterClient *brouter;
@property (assign) CLLocationCoordinate2D startCoord;
@property (assign) CLLocationCoordinate2D endCoord;
@property (assign) BOOL hasStart;
@property (assign) BOOL hasEnd;



- (void) initializeMapview;

@end

NS_ASSUME_NONNULL_END
