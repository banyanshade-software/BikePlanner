//
//  POIAnnotation.h
//  BikePlanner
//
//  Created by Daniel Braun on 17/08/2025.
//

#import <MapKit/MapKit.h>
#import "POILocation.h"

NS_ASSUME_NONNULL_BEGIN

@interface POIAnnotation : MKPointAnnotation
//@property (nonatomic, copy) NSString *xxpoiType;
@property (nonatomic) PoiType_t poiType;
@property (nonatomic,assign) NSDictionary *info;

- (void) configureAnnotViewIcon:(MKMarkerAnnotationView *)view;
@end

@interface POICustomAnnotation : POIAnnotation

@end

NS_ASSUME_NONNULL_END
