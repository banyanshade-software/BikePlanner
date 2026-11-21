//
//  RATimeChartView.h
//  RideAnalyzer
//
//  A chart against the date (#82, R6): points (one per ride or period) with an optional trend line, or bars (totals
//  per period). A click picks the nearest point. Drawn in code.
//

#import <Cocoa/Cocoa.h>

@class RATrendPoint, RATimeChartView;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RATimeChartStyle) {
    RATimeChartPoints,
    RATimeChartBars,
};

@protocol RATimeChartViewDelegate <NSObject>
- (void)timeChartView:(RATimeChartView *)chart didSelectPoint:(nullable RATrendPoint *)point;
@end

@interface RATimeChartView : NSView

@property (nonatomic) RATimeChartStyle style;
@property (copy, nonatomic) NSArray<RATrendPoint *> *points;
/// value at the first and at the last point (RATrends trendLineOfPoints:), nil for none
@property (copy, nonatomic, nullable) NSArray<NSNumber *> *trendLine;
@property (strong, nonatomic) NSColor *color;
/// shown when there are no points
@property (copy, nonatomic) NSString *emptyMessage;
/// date format of the bars' labels (e.g. "MMM", "yyyy"); points: automatic
@property (copy, nonatomic) NSString *barLabelFormat;
@property (weak, nonatomic, nullable) id<RATimeChartViewDelegate> delegate;
@property (readonly, nonatomic, nullable) RATrendPoint *selectedPoint;

/// the vertical range drawn (min, max), for tests
@property (readonly, nonatomic) double lowValue, highValue;

@end

NS_ASSUME_NONNULL_END
