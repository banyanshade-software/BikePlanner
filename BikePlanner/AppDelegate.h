//
//  AppDelegate.h
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>
#import <WebKit/WebKit.h>
#import "BRouterClient.h"


@interface AppDelegate : NSObject <NSApplicationDelegate, MKMapViewDelegate>

@property (strong) IBOutlet NSWindow *window;
@property (weak) IBOutlet MKMapView *mapView;
@property (weak) IBOutlet WKWebView *webView;

@property (strong) BRouterClient *brouter;
@property (assign) CLLocationCoordinate2D startCoord;
@property (assign) CLLocationCoordinate2D endCoord;
@property (assign) BOOL hasStart;
@property (assign) BOOL hasEnd;

@end

