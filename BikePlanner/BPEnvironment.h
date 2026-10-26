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

@interface BPEnvironment : NSObject

/// BRouter server base URL (default https://brouter.de) — key BPBRouterServer
+ (NSURL *) brouterServerURL;
/// URL of a BRouter profile (.brf) on the BRouter server
+ (NSURL *) brouterProfileURLForName:(NSString *)profileName;
/// Overpass interpreter URL (default https://overpass-api.de/api/interpreter) — key BPOverpassURL
+ (NSURL *) overpassURL;
/// YES to never load Google Street View — key BPDisableStreetView
+ (BOOL) streetViewDisabled;
/// YES to not use remote map tiles (OSM / Thunderforest) — key BPDisableTiles
+ (BOOL) tilesDisabled;
/// Region shown for a plan without route, instead of the user location — key BPInitialRegion, "lat,lon,span"
/// (span in degrees). Returns NO when not set.
+ (BOOL) getInitialRegion:(MKCoordinateRegion * _Nullable)region;
/// YES when the app is the host of unit tests (XCTest injected)
+ (BOOL) isUnitTestHost;

@end

NS_ASSUME_NONNULL_END
