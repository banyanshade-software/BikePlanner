//
//  RALibraryWindowController.h
//  RideAnalyzer
//
//  The window of a library (#82): sidebar (all rides, the devices — R3; device names editable), the list of rides
//  (R3) with the progress of an import (R1, R2), and the selected ride (R4). Built in code, no XIB.
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
/// Edit ▸ Delete: the selected rides
- (IBAction)delete:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
