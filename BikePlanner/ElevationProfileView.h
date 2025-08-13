//
//  ElevationProfileView.h
//  BikePlanner
//
//  Created by Daniel on 13/08/2025.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface ElevationProfileView : NSView
@property (nonatomic, strong) NSArray<NSNumber *> *distances;
@property (nonatomic, strong) NSArray<NSNumber *> *elevations;
@property (nonatomic, strong) NSArray<NSNumber *> *slopes;

- (void) setGpxPoints:(NSArray<CLLocation *> *)points;
@end

NS_ASSUME_NONNULL_END
