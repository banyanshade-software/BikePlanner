//
//  RAEquipmentWindowController.h
//  RideAnalyzer
//
//  The equipment of a library (#82, R13), in a window of its own (Window ▸ Equipment, ⇧⌘E): the rider's weight,
//  the default bike, the bikes (kind, weight, riding position, CdA, distance ridden) and the parts (kind, model,
//  width and wheel of a tyre, Crr — its default shown —, bike and dates it is mounted, distance, wear limit).
//  Changing the bike of a part that has been ridden moves it from today (the old mounting ends yesterday). Bikes can
//  be imported from the Garmin Connect gear. Every change is undoable (RALibraryDocument changeEquipment:).
//  Built in code.
//

#import <Cocoa/Cocoa.h>

@class RALibraryDocument;

NS_ASSUME_NONNULL_BEGIN

@interface RAEquipmentWindowController : NSWindowController

- (instancetype)initWithLibrary:(RALibraryDocument *)library;

- (IBAction)addBike:(nullable id)sender;
- (IBAction)removeBike:(nullable id)sender;
- (IBAction)addPart:(nullable id)sender;
- (IBAction)removePart:(nullable id)sender;
- (IBAction)importGarminBikes:(nullable id)sender;

// for tests
@property (readonly, nonatomic) NSTableView *bikesTable;
@property (readonly, nonatomic) NSTableView *partsTable;
@property (readonly, nonatomic) NSTextField *riderWeightField;
@property (readonly, nonatomic) NSPopUpButton *defaultBikePopup;
/// what an edit of a cell does (the action of its control)
- (void)setValue:(id)value forColumn:(NSString *)column ofBikeAtRow:(NSInteger)row;
- (void)setValue:(nullable id)value forColumn:(NSString *)column ofPartAtRow:(NSInteger)row;
/// imports the bikes of a gear list (not yet in the library: same gear identifier)
- (NSUInteger)importGear:(NSArray *)gear;

@end

NS_ASSUME_NONNULL_END
