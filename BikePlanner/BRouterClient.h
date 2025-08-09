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


- (void)routeFrom:(CLLocationCoordinate2D)from
                to:(CLLocationCoordinate2D)to
          profile:(NSString *)profile
       completion:(void(^)(NSArray<CLLocation *> *points, NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
