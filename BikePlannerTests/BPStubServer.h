//
//  BPStubServer.h
//  BikePlannerTests (shared with BikePlannerUITests)
//
//  Minimal local HTTP server imitating the external services, so that tests run offline:
//    GET  /brouter?lonlats=lon,lat|lon,lat…&profile=…   → GPX (straight lines, synthetic elevation,
//                                                         BRouter statistics comment)
//    GET  /brouter/profiles2/<name>.brf                  → small BRouter profile
//    POST /api/interpreter                               → Overpass JSON (3 POIs ~1 km from the first
//                                                         "around" point of the query)
//    GET  /maps/embed/v1/streetview?key=…                → Google Maps Embed API: a small page, or HTTP 403
//                                                         when the key is empty or starts with "invalid"
//  Every request is recorded. Use with BPEnvironment overrides
//  (-BPBRouterServer <baseURL> -BPOverpassURL <baseURL>/api/interpreter
//   -BPGoogleMapsEmbedURL <baseURL>/maps/embed/v1/).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPStubRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *query;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy, nullable) NSString *referer;  // Referer header
@property (nonatomic, copy, nullable) NSString *userAgent; // User-Agent header
@end

@interface BPStubServer : NSObject

/// Starts listening on 127.0.0.1, on a free port. Returns NO on failure.
/// For UI tests (the app runs in another process). Needs the network.server entitlement.
- (BOOL) start;
/// Serves http://bpstub.test/… inside the current process through an NSURLProtocol (no socket).
/// For unit tests: works even when the host app is sandboxed without network.server.
/// Only one in-process server at a time.
- (BOOL) startInProcess;
- (void) stop;

@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) NSURL *baseURL;          // http://127.0.0.1:<port> or http://bpstub.test
@property (nonatomic, readonly) NSURL *overpassURL;      // <baseURL>/api/interpreter
@property (nonatomic, readonly) NSURL *googleMapsEmbedURL; // <baseURL>/maps/embed/v1/

/// Requests received so far (thread safe snapshot)
@property (nonatomic, readonly) NSArray<BPStubRequest *> *requests;
- (NSArray<BPStubRequest *> *) requestsWithPath:(NSString *)path;
- (void) clearRequests;

/// The next `failCount` requests get HTTP `failStatus` (default 500).
@property (atomic) NSInteger failCount;
@property (atomic) NSInteger failStatus;
/// Retry-After header of these failures (default none)
@property (atomic, copy, nullable) NSString *failRetryAfter;
/// Delay before answering, in seconds (default 0).
@property (atomic) double responseDelay;

/// GPX that the /brouter endpoint returns for these "lon,lat|lon,lat" waypoints (exposed for assertions)
+ (NSString *) gpxForLonLats:(NSString *)lonlats;

@end

NS_ASSUME_NONNULL_END
