//
//  BPSecrets.h
//  BikePlanner
//
//  API keys of Secret.h, stored obfuscated in the binary (#51; stronger encoding #57: keystream seeded at compile
//  time, bytes out of order, split in two shares). It raises the cost of extraction only: the key is still in the
//  binary for anyone with a debugger, and sent in clear in the tile and Street View requests. Never log the key.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPSecrets : NSObject

+ (NSString *)thunderforestAPIKey;
/// OSM+cycle tiles (Thunderforest), with the key
+ (NSString *)thunderforestTileURLTemplate;
/// Maps Embed API key for Street View (#49); empty when Secret.h has no GOOGLE_MAPS_API_KEY
+ (NSString *)googleMapsAPIKey;

@end

NS_ASSUME_NONNULL_END
