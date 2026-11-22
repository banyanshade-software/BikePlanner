//
//  RARoads.h
//  RideAnalyzer
//
//  Road types and surfaces of a ride (#82, R8), from OpenStreetMap: the ways around the track are fetched from
//  Overpass (cells of 0.01°, kept in a cache folder: the roads ridden often are fetched once), then each point of
//  the track is matched to the nearest way going the same way (within 30 m; a way kept while it stays close, so
//  that crossings do not make it flicker). The result, RARoadMatch, is kept with the ride: runs of points of the
//  file's trace with their road class (the classes of BikePlanner's Road types, #66), surface class and the factor
//  of the Crr of the tyres on that surface (R11: the estimated power uses it instead of the bike's usual roads).
//
//  Endpoints (user defaults, as RAEnvironment): RAOverpassServers (array of interpreter URLs, tried in turn),
//  RAWaysCacheDirectory (tests). Requests carry the app's User-Agent (OSM / Overpass policies).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@class RARideAnalysis, RACancellation;

NS_ASSUME_NONNULL_BEGIN

/// road classes: those of BikePlanner (BRouterGeoJSON) — cycleway, path, track, small, tertiary, secondary,
/// primary, other — and "none" for the points matched to no way
extern NSString *const RARoadNone;
/// surface classes: paved, unpaved, unknown (as BikePlanner)
extern NSString *const RASurfaceClassPaved, *const RASurfaceClassUnpaved, *const RASurfaceClassUnknown;
/// the version of the matching: a match of an older version is done again
extern const NSInteger RARoadMatchVersion;

/// the factor of the Crr measured on a drum for a way of these OSM tags (surface, smoothness, tracktype, highway):
/// smooth asphalt 1.15, asphalt 1.3, paving stones 1.5, compacted 1.8, fine gravel 2.0, cobbles 2.2, gravel 2.5,
/// dirt / grass 3.0; without surface tag, from the highway (a track by its tracktype, 2.5 without; a path 2.0;
/// roads and cycleways taken as asphalt)
double RARollingFactorOfTags(NSDictionary<NSString *, NSString *> *tags);

/// the roads of a ride: runs of points of its file's trace
@interface RARoadMatch : NSObject
@property (nonatomic) NSInteger version;
@property (copy, nonatomic) NSDate *date;
/// points of the file's trace
@property (nonatomic) NSUInteger pointCount;
/// [road class, surface class, rolling factor (0: no way), index of the last point], in order
@property (copy, nonatomic) NSArray<NSArray *> *runs;
- (NSDictionary *)propertyList;
+ (nullable RARoadMatch *)matchWithPropertyList:(nullable id)plist;
/// the runs of these points: one value per point
+ (RARoadMatch *)matchWithRoadClasses:(NSArray<NSString *> *)roads surfaces:(NSArray<NSString *> *)surfaces
                              factors:(NSArray<NSNumber *> *)factors;
/// the rolling factor of `count` points from the file's point `first` (0 where no way)
- (NSArray<NSNumber *> *)rollingFactorsFrom:(NSUInteger)first count:(NSUInteger)count;
- (NSString *)roadClassAtIndex:(NSUInteger)fileIndex;
- (NSString *)surfaceClassAtIndex:(NSUInteger)fileIndex;
/// the share of the points matched to a way
@property (readonly, nonatomic) double matchedFraction;
@end

/// a row of the road types of a ride (R8): a road class or a surface class
@interface RARoadRow : NSObject
@property (copy, nonatomic) NSString *kind;        // "road:<class>" or "surface:<class>"
@property (copy, nonatomic) NSString *name;
@property (nonatomic) double distance;             // m
@property (nonatomic) NSTimeInterval time;         // s moving
@property (readonly, nonatomic) double speed;      // km/h, NaN without time
@end

@interface RARoadMatch (Rows)
/// distance, time and speed per road class (longest first) then per surface class, over the points of the analysis
- (NSArray<RARoadRow *> *)rowsForAnalysis:(RARideAnalysis *)analysis;
+ (NSString *)nameOfRoadClass:(NSString *)roadClass;
+ (NSString *)nameOfSurfaceClass:(NSString *)surfaceClass;
@end

@interface RARoadMatcher : NSObject

/// matches a trace (the file's whole trace) to the roads of OpenStreetMap; synchronous (call it in the background):
/// fetches the missing cells from Overpass. nil with an error when Overpass could not be reached, or when cancelled
+ (nullable RARoadMatch *)matchTrace:(NSArray<CLLocation *> *)trace cancellation:(nullable RACancellation *)cancellation
                               error:(NSError **)error;
/// matches a trace to given ways (no network): ways as [tags, NSData of float latitude, longitude pairs]
+ (RARoadMatch *)matchTrace:(NSArray<CLLocation *> *)trace toWays:(NSArray<NSArray *> *)ways;

/// the session of the Overpass requests (tests: RAStubURLProtocol's); nil: a default one
@property (class, nonatomic, nullable) NSURLSession *session;
/// the detail finds the roads of the ride it shows (unless the user default RANoAutomaticRoads is set; in the unit
/// tests only with a stub session: they never reach the real service)
+ (BOOL)findsRoadsAutomatically;
/// the Overpass servers (RAOverpassServers, else overpass-api.de and overpass.kumi.systems)
+ (NSArray<NSURL *> *)overpassServers;
/// the cache of the ways (RAWaysCacheDirectory, else Caches/RideAnalyzer/OSMWays)
+ (NSURL *)cacheDirectory;
/// the Overpass query of these cells (keys "lat_lon" in hundredths of a degree)
+ (NSString *)queryForCells:(NSArray<NSString *> *)cells;
/// the cells of a trace (and their neighbors when a point is within 60 m of the border)
+ (NSArray<NSString *> *)cellsOfTrace:(NSArray<CLLocation *> *)trace;

@end

NS_ASSUME_NONNULL_END
