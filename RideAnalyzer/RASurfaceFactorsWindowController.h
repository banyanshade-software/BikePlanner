//
//  RASurfaceFactorsWindowController.h
//  RideAnalyzer
//
//  The factors of the rolling resistance by surface (#82, R8, R11; owner's request 2026-11-22: configurable):
//  a table of the surface categories (RASurfaceFactors) with their OSM tags, default and the value used — editable,
//  empty for the default —, Restore Defaults, and the sources of the defaults (links). Changes go to the
//  equipment of the library (undoable) and apply at once: the stats keep the rolling work per category.
//  From the Equipment window (Surface Factors…). Built in code.
//

#import <Cocoa/Cocoa.h>

@class RALibraryDocument;

NS_ASSUME_NONNULL_BEGIN

@interface RASurfaceFactorsWindowController : NSWindowController

- (instancetype)initWithLibrary:(RALibraryDocument *)library;

/// nil or ≤ 0: back to the default; bounded to RASurfaceFactors minimum / maximum
- (void)setFactor:(nullable NSNumber *)factor ofCategory:(NSString *)category;
- (IBAction)restoreDefaults:(nullable id)sender;

// for tests
@property (readonly, nonatomic) NSTableView *tableView;

@end

NS_ASSUME_NONNULL_END
