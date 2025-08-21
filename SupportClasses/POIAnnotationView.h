//
//  POIAnnotationView.h
//  BikePlanner
//
//  Created by Daniel Braun on 20/08/2025.
//

#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface POIAnnotationView : MKMarkerAnnotationView
@property (strong,nonatomic) NSColor *savedColor;
@end

NS_ASSUME_NONNULL_END
