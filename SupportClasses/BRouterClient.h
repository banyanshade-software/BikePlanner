//
//  BRouterClient.h
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//


#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>

/* initial version by chatgpt
 */

NS_ASSUME_NONNULL_BEGIN

@interface BRouterClient : NSObject
@property (nonatomic, strong) NSURL *serverURL; // e.g. http://127.0.0.1:17777


- (instancetype)initWithServerURL:(NSURL *)url;


// GET <server>/brouter?lonlats=…&profile=…&alternativeidx=0&format=gpx&profile:<name>=<value>…
// overrides: profile parameters (name → value, without the "profile:" prefix), one query parameter each,
// percent-encoded (#15, #35)
+ (nullable NSURL *)routeURLForServer:(NSURL *)server
                            waypoints:(NSArray <CLLocation *>*)waypoints
                              profile:(nullable NSString *)profile
                            overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides;

- (void)routeWithWaypoints:(NSArray <CLLocation *>*)waypoints
          profile:(NSString *)profile
        overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides
       completion:(void(^)(NSArray<CLLocation *> *points,   // parsed points
                           NSData *gpx,                     // raw gpx file, as received
                           NSDictionary *brouterInfo,       // info brouter found in coments
                           NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
