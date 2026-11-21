//
//  RAClimbsViewController.h
//  RideAnalyzer
//
//  The Climbs tab beside the list (#82, R7): the climbs ridden (RAClimbGroup) — of the selected rides when two or
//  more are selected, else of the rides of the list; with one ride selected, the climbs of that ride, compared with
//  their other passages in the list. For the chosen climb: its passages by date (time, VAM, heart rate, power —
//  measured, or estimated with the equipment, R11 —, rank) and the time of each passage against the date, with
//  its trend. Climbs can be named (the name goes to every passage). Built in code.
//

#import <Cocoa/Cocoa.h>

@class RALibraryDocument, RARide, RAClimbGroup, RATimeChartView;

NS_ASSUME_NONNULL_BEGIN

@interface RAClimbsViewController : NSViewController

@property (weak, nonatomic, nullable) RALibraryDocument *library;
/// rides: where the climbs are looked for; focus: a single selected ride whose climbs are shown, or nil
- (void)showRides:(NSArray<RARide *> *)rides focus:(nullable RARide *)focus selected:(BOOL)selected;

// for tests
@property (readonly, nonatomic) NSArray<RAClimbGroup *> *groups;
@property (readonly, nonatomic) NSTableView *climbsTable;
@property (readonly, nonatomic) NSTableView *passagesTable;
@property (readonly, nonatomic) RATimeChartView *timeChart;
- (void)refresh;
- (void)renameClimbAtRow:(NSInteger)row to:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
