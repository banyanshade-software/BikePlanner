//
//  BikeMapView.h
//  BikePlanner
//
//  Created by Daniel Braun on 17/08/2025.
//

#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

/// gives the context menu of the map (#80)
@protocol BikeMapViewMenuProvider <NSObject>
/// p: in the map view's coordinates; nil: no menu
- (nullable NSMenu *)contextMenuForMapPoint:(NSPoint)p;
@end

@interface BikeMapView : MKMapView

/// right-click / ctrl-click on the map (not on an annotation view with its own menu): the provider's menu
@property (weak, nullable) id<BikeMapViewMenuProvider> menuProvider;

@end

NS_ASSUME_NONNULL_END
