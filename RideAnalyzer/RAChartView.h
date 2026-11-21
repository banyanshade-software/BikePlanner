//
//  RAChartView.h
//  RideAnalyzer
//
//  A curve of the ride detail (#82, R4): one value per point against the distance (speed, heart rate, cadence,
//  power, temperature), with the cursor shared with the map and the elevation profile, and the same visible range
//  as the profile when it is zoomed. A click or a drag moves the cursor.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class RAChartView;

@protocol RAChartViewDelegate <NSObject>
- (void)chartView:(RAChartView *)chart didSelectDistance:(double)distance;
@end

@interface RAChartView : NSView

@property (copy, nonatomic) NSString *title;
@property (strong, nonatomic) NSColor *color;
@property (nonatomic) BOOL dashed;
/// one value per point (NaN: no value), and the distance of each point (meters)
- (void)setValues:(NSArray<NSNumber *> *)values distances:(NSArray<NSNumber *> *)distances;
/// meters; the whole ride by default
- (void)setVisibleFrom:(double)from to:(double)to;
@property (nonatomic) double cursorDistance;   // NaN: no cursor
@property (weak, nonatomic, nullable) id<RAChartViewDelegate> delegate;

/// the lowest and highest values (NaN when none), for tests
@property (readonly, nonatomic) double minimum, maximum;

@end

NS_ASSUME_NONNULL_END
