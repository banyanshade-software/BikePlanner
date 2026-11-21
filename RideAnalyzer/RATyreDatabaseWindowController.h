//
//  RATyreDatabaseWindowController.h
//  RideAnalyzer
//
//  The tyre database (#82, R13), in a window opened from the equipment window: brand, model, width, Crr, test
//  pressure, category; a search field; the note on where the values come from. "Use for Selected Part" (or a
//  double-click) gives the tyre to the part chosen in the equipment window. Built in code.
//

#import <Cocoa/Cocoa.h>

@class RATyre, RATyreDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface RATyreDatabaseWindowController : NSWindowController

- (instancetype)initWithDatabase:(RATyreDatabase *)database;
/// called with the tyre chosen (Use for Selected Part, double-click); nil: the button is disabled
@property (copy, nonatomic, nullable) void (^useHandler)(RATyre *tyre);

// for tests
@property (readonly, nonatomic) NSTableView *table;
@property (readonly, nonatomic) NSSearchField *search;
@property (readonly, nonatomic) NSArray<RATyre *> *shownTyres;
- (IBAction)useSelectedTyre:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
