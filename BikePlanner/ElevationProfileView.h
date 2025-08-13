//
//  ElevationProfileView.h
//  BikePlanner
//
//  Created by Daniel on 13/08/2025.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ElevationProfileViewDelegate <NSObject>
- (void)elevationProfileView:(id)view didSelectDistance:(double)distance;
@end


@interface ElevationProfileView : NSView
@property (nonatomic, strong) NSArray<NSNumber *> *distances;
@property (nonatomic, strong) NSArray<NSNumber *> *elevations;
@property (nonatomic, strong) NSArray<NSNumber *> *slopes;
@property (nonatomic, weak) id<ElevationProfileViewDelegate> delegate;

- (void) setGpxPoints:(NSArray<CLLocation *> *)points;
@end

NS_ASSUME_NONNULL_END
