//
//  TaggedPoly.h
//  BikePlanner
//
//  Created by Daniel on 16/08/2025.
//

#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TaggedPoly : MKPolyline
@property (nonatomic, assign) NSUInteger tag;
@end

NS_ASSUME_NONNULL_END
