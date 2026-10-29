//
//  BPSecrets.h
//  BikePlanner
//
//  API keys of Secret.h, stored obfuscated in the binary (#51): not visible with `strings`. A rough protection only
//  (the key is also sent in clear in the tile requests); never log the key.
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
