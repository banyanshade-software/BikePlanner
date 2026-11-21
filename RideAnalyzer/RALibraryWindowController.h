//
//  RALibraryWindowController.h
//  RideAnalyzer
//
//  The window of a library (#82): sidebar with the filter (search field, period, device, distance, tag, More…, Clear,
//  Save…) and the saved filters and devices (R3; names editable), the list of rides with the progress of an import
//  (R1, R2), and four tabs: the detail of the selected ride (RARideDetailController, R4), the trends (R6,
//  RATrendsViewController), the map (R10, RARidesMapViewController) and the climbs (R7, RAClimbsViewController)
//  of the selected rides, or of the list.
//  Built in code, no XIB.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RALibraryWindowController : NSWindowController

/// File ▸ Import Files… (R2): several files or folders
- (IBAction)importFiles:(id)sender;
/// File ▸ Import from Device… (R2): the Garmin/Activity folder of a device connected as a disk
- (IBAction)importFromDevice:(id)sender;
/// File ▸ Fetch from Garmin Connect… (R1): new rides, or all rides since a date
- (IBAction)fetchFromGarminConnect:(id)sender;
/// stops the running import or fetch (what was read is kept)
- (IBAction)cancelImport:(nullable id)sender;
/// Window ▸ Trends (⇧⌘T): the Trends tab (R6), or back to the Ride tab
- (IBAction)showTrends:(nullable id)sender;
/// Window ▸ Climbs (⇧⌘K): the Climbs tab (R7), or back to the Ride tab
- (IBAction)showClimbs:(nullable id)sender;
/// Window ▸ Equipment (⇧⌘E): the equipment window of the library (R13)
- (IBAction)showEquipment:(nullable id)sender;
/// the bike of the rides of the contextual menu of the list (R13); representedObject: the bike identifier
- (IBAction)setBikeOfSelectedRides:(NSMenuItem *)sender;
/// Window ▸ Map of the Rides (⇧⌘M): the Map tab (R10), or back to the Ride tab
- (IBAction)showRidesMap:(nullable id)sender;
/// Edit ▸ Find… (⌘F): the search field (name, notes, tags; R3)
- (IBAction)focusSearch:(nullable id)sender;
/// Edit ▸ Filter… / Clear Filter / Save Filter…: the criteria of the list (R3)
- (IBAction)editFilter:(nullable id)sender;
- (IBAction)clearFilter:(nullable id)sender;
- (IBAction)saveFilter:(nullable id)sender;
/// the saved filter clicked in the sidebar (contextual menu)
- (IBAction)deleteSavedFilter:(nullable id)sender;
/// Edit ▸ Delete: the selected rides
- (IBAction)delete:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
