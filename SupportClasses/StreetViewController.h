//
//  StreetViewController.h
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface StreetViewController : NSObject
@property (weak) IBOutlet WKWebView *webView;

- (void) initializeStreetView;
- (void) viewCoord:(CLLocationCoordinate2D)coord lookingAt:(double)bearing coalesce:(BOOL)coal;
/// coordinate of the last viewCoord:… (also when Street View is disabled: tests)
@property (readonly) CLLocationCoordinate2D lastCoord;

@end

NS_ASSUME_NONNULL_END
