//
//  RALibraryWindowController.h
//  RideAnalyzer
//
//  The window of a library (#82): sidebar (sections, saved filters — R3, R6, R10, R13), the list of rides (R3) and
//  the selected ride (R4). Built in code, no XIB.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RALibraryWindowController : NSWindowController

/// File ▸ Import Files… (R2): several files or folders
- (IBAction)importFiles:(id)sender;
/// File ▸ Fetch from Garmin Connect… (R1), not implemented yet
- (IBAction)fetchFromGarminConnect:(id)sender;
/// Edit ▸ Delete: the selected rides
- (IBAction)delete:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
