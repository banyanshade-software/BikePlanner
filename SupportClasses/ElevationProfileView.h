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

@property (nonatomic) double highlightDistance; // meters
- (void)setHighlightDistance:(double)highlightDistance animated:(BOOL)animated;

@property (nonatomic, strong) NSArray<NSNumber *> *distances;
@property (nonatomic, strong) NSArray<NSNumber *> *elevations;
@property (nonatomic, strong) NSArray<NSNumber *> *slopes;
@property (nonatomic, weak) id<ElevationProfileViewDelegate> delegate;

- (void) setGpxPoints:(NSArray<CLLocation *> *)points;

/// elevation (m) at a distance along the route, interpolated
- (double) elevationAtDistance:(double)distance;
/// slope (%, positive uphill in the route direction) around a distance, over ±50 m (elevations are noisy); nil
/// without route (#48)
- (nullable NSNumber *) slopeAtDistance:(double)distance;
/// "12.3 km · 145 m · +6.5 %" at the highlighted distance, shown next to the cursor; nil when nothing is selected
@property (nonatomic, readonly, nullable) NSString *highlightText;
@end

NS_ASSUME_NONNULL_END
