//
//  RAEquipmentWindowController.h
//  RideAnalyzer
//
//  The equipment of a library (#82, R13), in a window of its own (Window ▸ Equipment, ⇧⌘E): the rider's weight,
//  the default bike, the bikes (list on the left) and the sheet of the selected bike: name, model, kind, weight
//  (typical of the kind when empty), riding position, CdA, usual roads (surface factor of the Crr), front and rear
//  tyre (tyre database or any model, width, pressure, the Crr used and where it comes from), "Change Tyre…" (a new
//  tyre from a date, the old one kept in the history) and the tyres over time; below, all the parts (kind, model,
//  width and wheel of a tyre, Crr — its default shown —, bike and dates it is mounted, distance, wear limit).
//  Changing the bike of a part that has been ridden moves it from today (the old mounting ends yesterday). The bikes
//  are entered here: the Garmin Connect Personal API does not give the gear (HTTP 404, 2026-11-21). Every change is
//  undoable (RALibraryDocument changeEquipment:).
//  Built in code.
//

#import <Cocoa/Cocoa.h>
#import "RAEquipment.h"

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
/// the factors of the rolling resistance by surface (R8, configurable): RASurfaceFactorsWindowController
- (IBAction)showSurfaceFactors:(nullable id)sender;
/// gives a tyre of the database to the selected part (a new tyre part when none is selected)
- (void)useTyre:(RATyre *)tyre;
/// shows the sheet of that bike
- (void)selectBikeWithID:(NSString *)bikeID;
/// a new tyre on a wheel (front or rear) of the selected bike from a day (what Change Tyre… does)
- (void)changeTyreOnWheel:(RAWheel)wheel model:(NSString *)model width:(double)width date:(NSDate *)date;
- (IBAction)changeTyre:(nullable id)sender;

// for tests
@property (readonly, nonatomic) NSTableView *bikesTable;
@property (readonly, nonatomic) NSTableView *partsTable;
@property (readonly, nonatomic) NSTextField *riderWeightField;
@property (readonly, nonatomic) NSPopUpButton *defaultBikePopup;
/// what an edit of a cell does (the action of its control)
- (void)setValue:(id)value forColumn:(NSString *)column ofBikeAtRow:(NSInteger)row;
- (void)setValue:(nullable id)value forColumn:(NSString *)column ofPartAtRow:(NSInteger)row;
/// what an edit of the sheet does: bike fields name, model, kind, weight, position, cda, surface; tyre fields model,
/// width, pressure, crr — on the tyre now on that wheel (a first tyre entered counts since always)
- (void)setValue:(id)value forBikeField:(NSString *)field;
- (void)setValue:(nullable id)value forTyreField:(NSString *)field wheel:(RAWheel)wheel;
@property (readonly, nonatomic) NSTableView *tyreHistoryTable;
/// the controls of the sheet by identifier (bikeName, frontTyreModel, rearTyrePressure…), and the figures line
@property (readonly, nonatomic) NSDictionary<NSString *, NSControl *> *sheetControls;
@property (readonly, nonatomic) NSTextField *sheetFigures;

@end

NS_ASSUME_NONNULL_END
