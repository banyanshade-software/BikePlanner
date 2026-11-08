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
/// route (tag 0) cut in stages (#31): index of the stage, for its color
@property (nonatomic, assign) NSUInteger stage;
@end

NS_ASSUME_NONNULL_END
