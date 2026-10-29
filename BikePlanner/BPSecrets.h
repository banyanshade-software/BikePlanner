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

@end

NS_ASSUME_NONNULL_END
