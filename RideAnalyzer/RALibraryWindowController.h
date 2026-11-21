//
//  RALibraryWindowController.h
//  RideAnalyzer
//
//  The window of a library (#82): sidebar (all rides, saved filters, devices — R3; names editable), the list of
//  rides with its search field and filter (R3) and the progress of an import (R1, R2), and the detail of the
//  selected ride (RARideDetailController, R4). Built in code, no XIB.
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
/// Window ▸ Trends (⇧⌘T): the progression window of the library (R6)
- (IBAction)showTrends:(nullable id)sender;
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
