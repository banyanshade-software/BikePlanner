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
// glyph and color of the marker of a POI type (also the icon of the callout, #72)
+ (nullable NSImage *) glyphImageForType:(PoiType_t)type;
+ (nullable NSColor *) tintColorForType:(PoiType_t)type;
@end

@interface POICustomAnnotation : POIAnnotation

@end

NS_ASSUME_NONNULL_END
