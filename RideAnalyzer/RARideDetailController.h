//
//  RARideDetailController.h
//  RideAnalyzer
//
//  The detail of the selected ride (#82, R3 notes and tags, R4): title, notes and tags (editable, undoable),
//  summary, the track on the map colored by speed, slope, heart rate or power, the elevation profile (shared with
//  BikePlanner: ElevationProfileView) and the curves; one cursor for the map, the profile and the curves. The ride
//  is analysed from its original file in the background. Built in code.
//

#import <Cocoa/Cocoa.h>
#import "RARideAnalysis.h"

@class RARide, RALibraryDocument;

NS_ASSUME_NONNULL_BEGIN

@interface RARideDetailController : NSViewController

@property (weak, nonatomic, nullable) RALibraryDocument *library;
/// nil, or several rides: a message instead of the detail
- (void)showRides:(NSArray<RARide *> *)rides;
/// the ride's figures, notes and tags changed (not its track)
- (void)refreshRideInfo;

// for tests
@property (readonly, nonatomic, nullable) RARide *ride;
@property (readonly, nonatomic, nullable) RARideAnalysis *analysis;
@property (nonatomic) RAColorMode colorMode;
/// the index of the point under the cursor, NSNotFound when none
@property (readonly, nonatomic) NSUInteger cursorIndex;
- (void)moveCursorToDistance:(double)distance;

@end

NS_ASSUME_NONNULL_END
