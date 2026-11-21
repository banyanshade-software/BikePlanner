//
//  RAEquipmentWindowController.h
//  RideAnalyzer
//
//  The equipment of a library (#82, R13), in a window of its own (Window ▸ Equipment, ⇧⌘E): the rider's weight,
//  the default bike, the bikes (kind, weight, riding position, CdA, distance ridden) and the parts (kind, model,
//  width and wheel of a tyre, Crr — its default shown —, bike and dates it is mounted, distance, wear limit).
//  Changing the bike of a part that has been ridden moves it from today (the old mounting ends yesterday). The bikes
//  are entered here: the Garmin Connect Personal API does not give the gear (HTTP 404, 2026-11-21). Every change is
//  undoable (RALibraryDocument changeEquipment:).
//  Built in code.
//

#import <Cocoa/Cocoa.h>

@class RALibraryDocument, RATyre;

NS_ASSUME_NONNULL_BEGIN

@interface RAEquipmentWindowController : NSWindowController

- (instancetype)initWithLibrary:(RALibraryDocument *)library;

- (IBAction)addBike:(nullable id)sender;
- (IBAction)removeBike:(nullable id)sender;
- (IBAction)addPart:(nullable id)sender;
- (IBAction)removePart:(nullable id)sender;
/// the tyre database (published Crr): its window, whose "Use" gives a tyre to the selected part
- (IBAction)showTyreDatabase:(nullable id)sender;
/// gives a tyre of the database to the selected part (a new tyre part when none is selected)
- (void)useTyre:(RATyre *)tyre;

// for tests
@property (readonly, nonatomic) NSTableView *bikesTable;
@property (readonly, nonatomic) NSTableView *partsTable;
@property (readonly, nonatomic) NSTextField *riderWeightField;
@property (readonly, nonatomic) NSPopUpButton *defaultBikePopup;
/// what an edit of a cell does (the action of its control)
- (void)setValue:(id)value forColumn:(NSString *)column ofBikeAtRow:(NSInteger)row;
- (void)setValue:(nullable id)value forColumn:(NSString *)column ofPartAtRow:(NSInteger)row;

@end

NS_ASSUME_NONNULL_END
