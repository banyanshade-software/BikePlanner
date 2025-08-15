//
//  RouteAnnotation.h
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RouteAnnotation : MKPointAnnotation

@property (nonatomic,assign) NSUInteger idx;

@end

NS_ASSUME_NONNULL_END
