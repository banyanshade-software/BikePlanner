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

// The completion is called on a background queue: points, GPX and info, or an error (network, cancelled, HTTP
// error status or no route: BRouter's message as localizedDescription, #9). Returns the task (to cancel it), nil
// when the URL is invalid (the completion is then called at once with an error).
- (nullable NSURLSessionDataTask *)routeWithWaypoints:(NSArray <CLLocation *>*)waypoints
          profile:(NSString *)profile
        overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides
       completion:(void(^)(NSArray<CLLocation *> * _Nullable points, // parsed points
                           NSData * _Nullable gpx,                    // GPX built from the points
                           NSDictionary * _Nullable brouterInfo,      // BRouter statistics
                           NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
