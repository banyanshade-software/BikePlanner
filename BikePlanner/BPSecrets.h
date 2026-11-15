//
//  BPSecrets.h
//  BikePlanner
//
//  API keys of Secret.h, stored obfuscated in the binary (#51, #57). The encoding mechanism is private
//  (SecretEncoding.h, git-ignored, as the sources are public; SecretEncodingExample.h otherwise). It raises the cost of
//  extraction only: the key is still in the binary for anyone with a debugger, and sent in clear in the tile and
//  Street View requests. Never log the key.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPSecrets : NSObject

+ (NSString *)thunderforestAPIKey;
/// OSM+cycle tiles (Thunderforest), with the key
+ (NSString *)thunderforestTileURLTemplate;
/// Maps Embed API key for Street View (#49); empty when Secret.h has no GOOGLE_MAPS_API_KEY
+ (NSString *)googleMapsAPIKey;
/// NO when the app is built with the committed example encoding (no private SecretEncoding.h): not for distribution
+ (BOOL)usesPrivateEncoding;

@end

NS_ASSUME_NONNULL_END
