//
//  RATrendsWindowController.h
//  RideAnalyzer
//
//  The progression (#82, R6), in a window of its own per library: a measure over time per ride, week or month on a
//  kind of terrain (e.g. W/bpm in the climbs of 4–8 %, on the rides of a saved filter), with its trend line;
//  totals per week, month or year; records. Uses the stats of the rides, computing in the background those of the
//  rides imported before the stats existed. Built in code.
//

#import <Cocoa/Cocoa.h>
#import "RATrends.h"

@class RALibraryDocument, RATimeChartView;

NS_ASSUME_NONNULL_BEGIN

@interface RATrendsWindowController : NSWindowController

- (instancetype)initWithLibrary:(RALibraryDocument *)library;

// for tests
@property (nonatomic) RATrendMeasure measure;
@property (nonatomic) RATerrain terrain;
@property (nonatomic) RATrendGrouping grouping;
@property (nonatomic) RATotalMeasure totalMeasure;
@property (nonatomic) RAPeriod period;
/// 0: all rides; i > 0: the saved filter i - 1
@property (nonatomic) NSInteger filterIndex;
@property (readonly, nonatomic) RATimeChartView *trendChart;
@property (readonly, nonatomic) RATimeChartView *totalsChart;
@property (readonly, nonatomic) NSArray<RARecord *> *records;
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
