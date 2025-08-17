//
//  POIAnnotation.h
//  BikePlanner
//
//  Created by Daniel Braun on 17/08/2025.
//

#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface POIAnnotation : MKPointAnnotation
@property (nonatomic, copy) NSString *poiType;
@end

NS_ASSUME_NONNULL_END
