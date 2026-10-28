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
@property (nonatomic,strong) NSDictionary *info;
@property (nonatomic,copy,nullable) NSString *poiKey;   // -[POILocation poiKey]
@property (nonatomic) BOOL excluded;                    // excluded from the export (#5): greyed

- (void) configureAnnotViewIcon:(MKMarkerAnnotationView *)view;
@end

@interface POICustomAnnotation : POIAnnotation

@end

NS_ASSUME_NONNULL_END
