//
//  BPOverpassServers.h
//  BikePlanner
//
//  Overpass servers (#84): several public instances in round robin, to share the load; a server that fails (no
//  connection, timeout, HTTP 5xx / 429 / 406) or answers slowly leaves the rotation for a while (10 min, doubled at
//  each new failure, at most 2 h). A regional server (Europe…) is a candidate only for a route whose bounding box is
//  inside one of its zones. No UI (also in the Quick Look extension, with BikePlan).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// a rectangle in degrees
typedef struct {
    double south, west, north, east;
} BPGeoBox;

static inline BPGeoBox BPGeoBoxMake(double south, double west, double north, double east)
{
    BPGeoBox b = { south, west, north, east };
    return b;
}

@interface BPOverpassServer : NSObject

/// zones: NSValue of BPGeoBox; none: worldwide
- (instancetype)initWithURL:(NSURL *)url zones:(NSArray<NSValue *> *)zones;
/// "https://…/interpreter" or "https://…/interpreter s,w,n,e;s,w,n,e" (zones), as in the user default
/// BPOverpassServers; nil if invalid
+ (nullable instancetype)serverWithSpec:(NSString *)spec;

@property (readonly, nonatomic) NSURL *url;
@property (readonly, nonatomic) NSArray<NSValue *> *zones;
@property (readonly, nonatomic) BOOL worldwide;
/// worldwide, or one of the zones contains the whole box
- (BOOL)covers:(BPGeoBox)box;

@end

@interface BPOverpassServerPool : NSObject

/// the servers of BPEnvironment (+overpassServerSpecs); a new pool when they change (tests). Its demotions are kept in
/// the standard user defaults (memory only in the unit test host)
+ (instancetype)shared;
/// forgets the demotions (tests)
+ (void)resetShared;
- (instancetype)initWithServers:(NSArray<BPOverpassServer *> *)servers;
/// the demotions kept in these defaults from one launch to the next (key BPOverpassServerState); nil: memory only
- (instancetype)initWithServers:(NSArray<BPOverpassServer *> *)servers defaults:(nullable NSUserDefaults *)defaults;
@property (readonly, nonatomic) NSArray<BPOverpassServer *> *servers;

/// the clock (tests)
@property (copy, nonatomic) NSDate *(^clock)(void);
/// first demotion, doubled at each consecutive failure, at most maxDemotion (seconds)
@property (nonatomic) NSTimeInterval baseDemotion;   // 600
@property (nonatomic) NSTimeInterval maxDemotion;    // 7200
/// an answer slower than this demotes the server (its answer is still used)
@property (nonatomic) NSTimeInterval slowAnswer;     // 20

/// the server for the next request of a route of this bounding box: the next one in round robin among the
/// candidates not demoted and not tried; if they are all demoted, the one that answered last (even with an error:
/// it is reachable), else the one whose demotion ends first; nil when every candidate was tried
- (nullable BPOverpassServer *)nextServerFor:(BPGeoBox)box excluding:(NSSet<NSURL *> *)tried;
- (void)serverFailed:(BPOverpassServer *)server retryAfter:(NSTimeInterval)retryAfter;
/// an HTTP answer came back (whatever its status)
- (void)serverResponded:(BPOverpassServer *)server;
- (void)server:(BPOverpassServer *)server answeredAfter:(NSTimeInterval)seconds;
- (BOOL)isDemoted:(BPOverpassServer *)server;

@end

NS_ASSUME_NONNULL_END
