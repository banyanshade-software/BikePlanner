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


- (void)routeWithWaypoints:(NSArray <CLLocation *>*)waypoints
          profile:(NSString *)profile
         extraUrl:(NSString *)extraUrl  
       completion:(void(^)(NSArray<CLLocation *> *points,   // parsed points
                           NSData *gpx,                     // raw gpx file, as received
                           NSDictionary *brouterInfo,       // info brouter found in coments
                           NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
