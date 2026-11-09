//
//  BPEnvironment.h
//  BikePlanner
//
//  External endpoints and test hooks, read from NSUserDefaults.
//  Values can be overridden with launch arguments, e.g.
//      -BPBRouterServer http://127.0.0.1:8123 -BPDisableStreetView YES
//  (used by UI tests to run offline against a local stub server).
//  Without overrides, the defaults are the production endpoints.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

/// where a new document starts (#65) — key BPStartPosition (Preferences)
typedef NS_ENUM(NSInteger, BPStartPosition) {
    BPStartPositionLocation = 0,        // the user location; the default position until it comes, or if refused
    BPStartPositionDefault = 1,         // the default position (BPDefaultPosition), the location is not asked
    BPStartPositionRemarkableSite = 2,  // a remarkable site at random (BPRemarkableSites), the location is not asked
};

@interface BPEnvironment : NSObject

/// BRouter server base URL (default https://brouter.de) — key BPBRouterServer
+ (NSURL *) brouterServerURL;
/// URL of a BRouter profile (.brf) on the BRouter server
+ (NSURL *) brouterProfileURLForName:(NSString *)profileName;
/// Overpass interpreter URL (default https://overpass-api.de/api/interpreter) — key BPOverpassURL
+ (NSURL *) overpassURL;
/// Base URL of the Google Maps Embed API (default https://www.google.com/maps/embed/v1/) — key BPGoogleMapsEmbedURL
+ (NSURL *) googleMapsEmbedURL;
/// YES to never load Google Street View — key BPDisableStreetView
+ (BOOL) streetViewDisabled;
/// YES to not use remote map tiles (OSM / Thunderforest) — key BPDisableTiles
+ (BOOL) tilesDisabled;
/// Region shown for a plan without route, instead of the user location — key BPInitialRegion, "lat,lon,span"
/// (span in degrees). Returns NO when not set.
+ (BOOL) getInitialRegion:(MKCoordinateRegion * _Nullable)region;
/// Center of the initial map region when the user location is unknown or refused — key BPDefaultPosition,
/// "lat,lon" (default: Laplume, Lot-et-Garonne; to be set in the Preferences, #27)
+ (CLLocationCoordinate2D) defaultPosition;
/// Radius of the initial map region, km (default 80) — key BPInitialRadiusKm
+ (double) initialRadiusKm;
/// Where a new document starts — key BPStartPosition (default: a remarkable site)
+ (BPStartPosition) startPosition;
/// Index of the remarkable site to start on instead of a random one (tests) — key BPRemarkableSiteIndex; -1 when
/// not set
+ (NSInteger) remarkableSiteIndex;
/// YES to never ask for / use the user location (tests) — key BPDisableLocation
+ (BOOL) locationDisabled;
/// YES when the app is the host of unit tests (XCTest injected)
+ (BOOL) isUnitTestHost;
/// User-Agent of every request of the app: "BikePlanner/<version> (build <n>; +<project URL>)" — the OSM tile and
/// Overpass usage policies ask for an identifying User-Agent with a contact
+ (NSString *) userAgent;
/// GET request with the app's User-Agent
+ (NSMutableURLRequest *) requestWithURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
