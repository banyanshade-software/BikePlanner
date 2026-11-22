//
//  RAHeatmap.h
//  RideAnalyzer
//
//  The map of all rides (#82, R10): the tracks of a set of rides on one map, the roads ridden most often standing
//  out. The map is divided in cells (40 m by default); a cell counts the rides that cross it; each piece of track
//  gets the level of its cell: 1 ride, 2–3, 4–9, 10 or more.
//  The tracks come from the stats of the rides (RARideStats.track): simplified when the stats are computed, so the
//  original files are not read again. Computed off the main thread (the result is immutable).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

@class RARide, RACancellation;

NS_ASSUME_NONNULL_BEGIN

/// number of levels (1 ride, 2–3, 4–9, 10+)
extern const NSUInteger RAHeatLevelCount;

@interface RAHeatmap : NSObject

// packed tracks: float32 latitude, longitude pairs
/// the trace simplified (Douglas–Peucker, tolerance in meters), packed
+ (NSData *)packedTrackOfTrace:(NSArray<CLLocation *> *)trace tolerance:(double)tolerance;
+ (NSUInteger)pointCountOfPackedTrack:(NSData *)track;
+ (CLLocationCoordinate2D)coordinateAtIndex:(NSUInteger)index ofPackedTrack:(NSData *)track;

/// the level of a number of rides (0 for 1 ride … RAHeatLevelCount - 1)
+ (NSUInteger)levelOfCount:(NSUInteger)count;
/// "1 ride", "2–3", "4–9", "10+"
+ (NSString *)legendOfLevel:(NSUInteger)level;

/// any thread; rides without track are left out
- (instancetype)initWithRides:(NSArray<RARide *> *)rides cellSize:(double)meters;
- (instancetype)initWithRides:(NSArray<RARide *> *)rides;   // 40 m
/// the same, stopped early (nil) when the cancellation is set (RAComputation)
- (nullable instancetype)initWithRides:(NSArray<RARide *> *)rides cellSize:(double)meters
                          cancellation:(nullable RACancellation *)cancellation;
/// the same, with intermediate heatmaps of the first rides (a long computation shows as it goes): partial is called
/// on the computing thread with the heatmap of the rides done so far — the first one after partialDelay, then each
/// time their number has doubled and at least 0.5 s later (so all the intermediate ones cost less than the final
/// one); none when it finishes sooner
- (nullable instancetype)initWithRides:(NSArray<RARide *> *)rides cellSize:(double)meters
                          cancellation:(nullable RACancellation *)cancellation
                               partial:(nullable void (^)(RAHeatmap *partial))partial;
/// before the first intermediate heatmap, s (0.25; 0 in tests: after the first ride, then at 2, 4, 8… rides)
@property (class, nonatomic) NSTimeInterval partialDelay;

/// rides that have a track
@property (readonly, nonatomic) NSUInteger rideCount;
/// the most rides in one cell
@property (readonly, nonatomic) NSUInteger maxCount;
/// the pieces of track of a level, joined in polylines; their title is the level ("0"…)
- (NSArray<MKPolyline *> *)polylinesOfLevel:(NSUInteger)level;
/// all the tracks, MKMapRectNull when none
@property (readonly, nonatomic) MKMapRect boundingRect;
/// rides crossing the cell of that point
- (NSUInteger)countAtCoordinate:(CLLocationCoordinate2D)coordinate;

@end

NS_ASSUME_NONNULL_END
