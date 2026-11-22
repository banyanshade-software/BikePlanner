//
//  RARideDetailController.h
//  RideAnalyzer
//
//  The detail of the selected ride (#82, R3 notes and tags, R4): title, notes and tags (editable, undoable),
//  summary, the track on the map colored by speed, slope, heart rate or power, the elevation profile (shared with
//  BikePlanner: ElevationProfileView) and the curves; one cursor for the map, the profile and the curves. The ride
//  is analysed from its original file in the background. Its equipment (R13) and its climbs (R7: shaded on the
//  profile and the map, a table with their figures and the rank among the passages of the library; a click zooms
//  on one, a double-click compares its passages). Built in code.
//

#import <Cocoa/Cocoa.h>
#import "RARideAnalysis.h"

@class RARide, RALibraryDocument, RAClimb;

NS_ASSUME_NONNULL_BEGIN

@interface RARideDetailController : NSViewController

@property (weak, nonatomic, nullable) RALibraryDocument *library;
/// nil, or several rides: a message instead of the detail
- (void)showRides:(NSArray<RARide *> *)rides;
/// the ride's figures, notes and tags changed (not its track)
- (void)refreshRideInfo;
/// a double-click on a climb of the ride (R7): compare its passages (the window shows the Climbs tab)
@property (copy, nonatomic, nullable) void (^compareClimbHandler)(RAClimb *climb);
/// "Edit Bike…" in the bike pop-up: the sheet of the ride's bike (@"": none yet, a new bike)
@property (copy, nonatomic, nullable) void (^editBikeHandler)(NSString *bikeID);

// for tests
@property (readonly, nonatomic, nullable) RARide *ride;
@property (readonly, nonatomic, nullable) RARideAnalysis *analysis;
@property (nonatomic) RAColorMode colorMode;
/// the index of the point under the cursor, NSNotFound when none
@property (readonly, nonatomic) NSUInteger cursorIndex;
- (void)moveCursorToDistance:(double)distance;

@end

NS_ASSUME_NONNULL_END
