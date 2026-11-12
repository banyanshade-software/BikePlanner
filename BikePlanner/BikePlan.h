//
//  BikePlan.h
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "RouteAnnotation.h"
#import "TaggedPoly.h"
#import "POILocation.h"


NS_ASSUME_NONNULL_BEGIN

extern const CLLocationDistance kBPImportTolerance;   // m, distance to the track below which a point is dropped
extern const CLLocationDistance kBPImportMaxSpacing;  // m, along the track
extern const NSUInteger kBPImportMaxWaypoints;        // before spacing: the tolerance grows to stay below

/// keys of the rows of BrouterInfo.roadTypesRows (#66)
extern NSString *const BPRoadTypeKindKey;      // "road:<road class>" or "surface:<surface class>" (BRouterGeoJSON.h),
                                               // as -[MapController highlightKind:] takes it
extern NSString *const BPRoadTypeNameKey;      // "Small roads", "Paved"
extern NSString *const BPRoadTypeDistanceKey;  // "18.0 km"
extern NSString *const BPRoadTypePercentKey;   // "50 %"

@interface BrouterInfo : NSObject <NSSecureCoding> {
}

@property NSInteger kmlen;
@property NSInteger mup;
@property NSInteger meters;   // route length, 0 in documents saved before #30 (kmlen is then used)
@property NSInteger seconds;  // riding time estimated by BRouter (kinematic model of the profile), 0 if unknown

// for the Info tab (#30)
@property (readonly) double averageSpeed;           // km/h, 0 if unknown
@property (readonly) NSString *durationText;        // "2 h 39", "45 min", "–"
@property (readonly) NSString *averageSpeedText;    // "18.4" (localized), "–"

// distance (m) by road class / surface class, from the BRouter way tags (#53; keys: see BRouterGeoJSON.h)
@property (copy, nullable) NSDictionary<NSString *, NSNumber *> *roadStats;
@property (copy, nullable) NSDictionary<NSString *, NSNumber *> *surfaceStats;
/// road class along the route (#54): runs of route points, @[class, index of the last point] (see BRouterGeoJSON)
@property (copy, nullable) NSArray<NSArray *> *roadRuns;
/// same for the surface class
@property (copy, nullable) NSArray<NSArray *> *surfaceRuns;
/// road classes in the order of the rows of roadTypesRows (longest first)
@property (readonly) NSArray<NSString *> *roadTypesClasses;
/// Info section (#53, #66): one row per road class, longest first, then one per surface class (paved, unpaved,
/// unknown), without the empty ones; keys BPRoadType…Key; empty without statistics
@property (readonly) NSArray<NSDictionary<NSString *, NSString *> *> *roadTypesRows;

@end


#pragma mark -

/// a waypoint where a stage ends (#31): the next stage starts there. Only an intermediate waypoint ends a stage
/// (on the start or the end, the class has no effect). Archived as a plain CLLocation + the "stageEnds" index set
@interface BPStageEndLocation : CLLocation
+ (instancetype) locationFrom:(CLLocation *)loc;
@end


@interface BikePlan : NSObject <NSSecureCoding> {
    
}

//@property (weak,nonatomic) NSUndoManager *docUndoMgr;
@property (readonly,nonatomic) NSArray <CLLocation *>*waypointsLocations;
@property (strong,nonatomic) NSArray<CLLocation *> *routePoints;
// raw GPX returned by BRouter for routePoints, saved with the document for the export (#10); nil in documents
// saved before, or without route
@property (strong,nonatomic,nullable) NSData *routeGPX;
// GPX to export: routeGPX, else one generated from routePoints (older documents); nil without route
@property (readonly,nonatomic,nullable) NSData *exportableGPX;
+ (NSData *) gpxDataForPoints:(NSArray<CLLocation *> *)points name:(NSString *)name;
@property (strong,nonatomic,nullable) NSArray<CLLocation *> *gpxDisplayed; // reference trace, nil: none
@property (strong,nonatomic) BrouterInfo *brouterInfo;
@property (readonly,nonatomic) NSString *profileName;   // BRouter profile: "trekking" (choice of the profile: #1)
// BRouter profile parameters (Params tab, name → value, sent as profile:<name>=<value>), saved in the document;
// empty = the profile defaults (also for documents saved before #44)
@property (copy,nonatomic,null_resettable) NSDictionary<NSString *, NSString *> *profileOverrides;

@property (readonly,nonatomic) NSArray<POILocation *> *poiloc;
@property (readonly,nonatomic) NSMutableArray<POILocation *> *customPoiloc;
@property (nonatomic, copy) void (^poiAvailableCallback)(void);
- (void) addCustomPoiAt:(CLLocationCoordinate2D)coord;   // default type (Information, #74), no name
// typed custom POIs (#3); an empty name is no name
- (POILocation *) addCustomPoiAt:(CLLocationCoordinate2D)coord type:(PoiType_t)type name:(nullable NSString *)name;
- (POILocation *) replaceCustomPoi:(POILocation *)poi type:(PoiType_t)type name:(nullable NSString *)name;
- (void) removeCustomPoi:(POILocation *)poi;
- (void) restoreCustomPoi:(nullable NSArray<POILocation *> *)pois; // for undo; nil: none

// returns old waypointsLocations for undo
- (NSArray <CLLocation *>*) removeWaypoints NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) removeWaypointAtIndex:(NSUInteger)idx NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) appendWaypoint:(CLLocation *)loc NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) insertWaypoint:(CLLocation *)loc atIndex:(NSUInteger)idx NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) replaceWaypointAtIndex:(NSUInteger)idx by:(CLLocation *)loc NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) reverseWaypoints NS_WARN_UNUSED_RESULT; // start <-> end
// replaceWaypointAtIndex:by: keeps the stage end of the replaced waypoint (a moved waypoint still ends its stage)

// stages (#31): a route is cut in stages at the waypoints marked as stage ends (one BRouter request for the whole
// route). The waypoint keeps its coordinates. Returns old waypointsLocations for undo
- (NSArray <CLLocation *>*) setStageEnd:(BOOL)stageEnd atWaypointIndex:(NSUInteger)idx NS_WARN_UNUSED_RESULT;
/// an intermediate waypoint marked as a stage end (NO for the start and the end)
- (BOOL) isStageEndAtWaypointIndex:(NSUInteger)idx;
/// indexes in routePoints where a stage ends, ascending, without 0 and the last point; empty without route or stages
@property (readonly,nonatomic) NSArray<NSNumber *> *stageEndRouteIndexes;
/// route points of each stage (a stage end belongs to both stages); one stage without stage ends, none without route
@property (readonly,nonatomic) NSArray<NSArray<CLLocation *> *> *stagesRoutePoints;
/// index in routePoints of the route point nearest to each waypoint, in order (the route goes through them): the
/// nearest point after the previous waypoint's, the first one within 30 m of the minimum when the route passes twice
+ (NSArray<NSNumber *> *) routeIndexesOfWaypoints:(NSArray<CLLocation *> *)waypoints inRoute:(NSArray<CLLocation *> *)route;
/// stage (0-based) of a location: the one of the nearest route point; 0 without stages
- (NSUInteger) stageOfCoordinate:(CLLocationCoordinate2D)coord;

- (void) undoSetWayPt:() wp;

// erases waypoints, route, length/ascent, fetched and custom POIs; keeps the reference trace (#33).
// Returns the previous state, to give back to restoreRoute: (undo)
- (NSDictionary *) clearRoute NS_WARN_UNUSED_RESULT;
// the same state, without erasing anything
- (NSDictionary *) routeState;
- (void) restoreRoute:(NSDictionary *)state;

// Import GPX as route (#29): waypoints for a track, simplified (Douglas–Peucker, kBPImportTolerance) and with at
// most kBPImportMaxSpacing between two waypoints along the track, so BRouter follows it. First/last points kept.
+ (NSArray <CLLocation *>*) waypointsForTrace:(NSArray <CLLocation *>*)trace;

@property (readonly,nonatomic) TaggedPoly *routePoly;    // MKPolyLine with a tag, 0
@property (readonly,nonatomic) TaggedPoly *waypointPoly; // MKPolyLine with a tag, 1
@property (readonly,nonatomic) TaggedPoly *gpxDisplayedPoly; // MKPolyLine with a tag, 2

@property (nonatomic) BOOL fetchPOI;

// POIs excluded by the user (POI callout, #5): shown greyed, not exported; saved with the document
@property (copy,nonatomic,null_resettable) NSSet<NSString *> *excludedPOIKeys;
- (BOOL) isPOIExcluded:(POILocation *)poi;
- (void) setPOI:(POILocation *)poi excluded:(BOOL)excluded;
- (void) setPOIKey:(NSString *)key excluded:(BOOL)excluded;
@end

NS_ASSUME_NONNULL_END
