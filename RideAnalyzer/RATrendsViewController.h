//
//  RATrendsViewController.h
//  RideAnalyzer
//
//  The progression (#82, R6), the Trends tab beside the list of a library window: a measure over time per ride,
//  week or month on a kind of terrain (e.g. W/bpm in the climbs of 4–8 %), with its trend line; totals per week,
//  month or year; records. Of the selected rides when several are selected, else of the rides of the list (those
//  of the filter). The measures are taken on the parts of the rides of that terrain (RARideStats), not on whole
//  rides. Uses the stats of the rides, computing in the background those of the rides imported before the stats
//  existed. Built in code.
//

#import <Cocoa/Cocoa.h>
#import "RATrends.h"

@class RALibraryDocument, RATimeChartView, RARide;

NS_ASSUME_NONNULL_BEGIN

@interface RATrendsViewController : NSViewController

@property (weak, nonatomic, nullable) RALibraryDocument *library;
/// the rides to chart; selected: they are the selection of the list (else the whole list), for the status line
- (void)showRides:(NSArray<RARide *> *)rides selected:(BOOL)selected;

// for tests
@property (nonatomic) RATrendMeasure measure;
@property (nonatomic) RATerrain terrain;
@property (nonatomic) RATrendGrouping grouping;
@property (nonatomic) RATotalMeasure totalMeasure;
@property (nonatomic) RAPeriod period;
@property (readonly, nonatomic) NSArray<RARide *> *rides;
@property (readonly, nonatomic) RATimeChartView *trendChart;
@property (readonly, nonatomic) RATimeChartView *totalsChart;
@property (readonly, nonatomic) NSArray<RARecord *> *records;
@property (readonly, nonatomic) NSTextField *status;
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
