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
/// Info section: one line per road class, longest first ("Small roads  18.0 km  50 %"), then the surface line;
/// "" without statistics
@property (readonly) NSString *roadTypesText;
/// same, with a title and aligned columns, bound to the Info section label
@property (readonly) NSAttributedString *roadTypesAttributedText;

@end


#pragma mark -


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
@property (strong,nonatomic) NSArray<CLLocation *> *gpxDisplayed;
@property (strong,nonatomic) BrouterInfo *brouterInfo;
@property (readonly,nonatomic) NSString *profileName;   // BRouter profile: "trekking" (choice of the profile: #1)
// BRouter profile parameters (Params tab, name → value, sent as profile:<name>=<value>), saved in the document;
// empty = the profile defaults (also for documents saved before #44)
@property (copy,nonatomic,null_resettable) NSDictionary<NSString *, NSString *> *profileOverrides;

@property (readonly,nonatomic) NSArray<POILocation *> *poiloc;
@property (readonly,nonatomic) NSMutableArray<POILocation *> *customPoiloc;
@property (nonatomic, copy) void (^poiAvailableCallback)(void);
- (void) addCustomPoiAt:(CLLocationCoordinate2D)coord;   // POI_warning, no name
// typed custom POIs (#3); an empty name is no name
- (POILocation *) addCustomPoiAt:(CLLocationCoordinate2D)coord type:(PoiType_t)type name:(nullable NSString *)name;
- (POILocation *) replaceCustomPoi:(POILocation *)poi type:(PoiType_t)type name:(nullable NSString *)name;
- (void) removeCustomPoi:(POILocation *)poi;
- (void) restoreCustomPoi:(NSArray<POILocation *> *)pois; // for undo

// returns old waypointsLocations for undo
- (NSArray <CLLocation *>*) removeWaypoints NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) removeWaypointAtIndex:(NSUInteger)idx NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) appendWaypoint:(CLLocation *)loc NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) insertWaypoint:(CLLocation *)loc atIndex:(NSUInteger)idx NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) replaceWaypointAtIndex:(NSUInteger)idx by:(CLLocation *)loc NS_WARN_UNUSED_RESULT;
- (NSArray <CLLocation *>*) reverseWaypoints NS_WARN_UNUSED_RESULT; // start <-> end

- (void) undoSetWayPt:() wp;

// erases waypoints, route, length/ascent, fetched and custom POIs; keeps the reference trace (#33).
// Returns the previous state, to give back to restoreRoute: (undo)
- (NSDictionary *) clearRoute NS_WARN_UNUSED_RESULT;
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
