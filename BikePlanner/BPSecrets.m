//
//  BPSecrets.m
//  BikePlanner
//

#import "BPSecrets.h"
#import "Secret.h" // git-ignored, see Secret.h.example

// Optional (#49): without it, Street View falls back to the Google Maps web app. GOOGLE_API_KEY is accepted too.
#if !defined(GOOGLE_MAPS_API_KEY) && defined(GOOGLE_API_KEY)
#define GOOGLE_MAPS_API_KEY GOOGLE_API_KEY
#endif
#ifndef GOOGLE_MAPS_API_KEY
#define GOOGLE_MAPS_API_KEY ""
#endif

// The encoding mechanism is private (#57: the sources are public): BikePlanner/SecretEncoding.h, git-ignored; a fresh
// clone uses the committed SecretEncodingExample.h (plain XOR, refused by make_dmg.sh), which documents what the
// private file provides. The string literals of Secret.h are only used in constant expressions, so they are not
// emitted in the binary (checked by SecretsTests and make_dmg.sh). This is the only file that may include Secret.h.
#if __has_include("SecretEncoding.h")
#import "SecretEncoding.h"
#else
#import "SecretEncodingExample.h"
#endif

_Static_assert(sizeof(THUNDERFOREST_API_KEY) - 1 <= BP_KEY_MAX, "Thunderforest key too long for BPSecrets");
_Static_assert(sizeof(GOOGLE_MAPS_API_KEY) - 1 <= BP_KEY_MAX, "Google Maps key too long for BPSecrets");

static const BPSecretEncodedKey kThunderforestKey = BP_SECRET_ENCODE(THUNDERFOREST_API_KEY, BP_SECRET_SALT_THUNDERFOREST);
static const BPSecretEncodedKey kGoogleMapsKey = BP_SECRET_ENCODE(GOOGLE_MAPS_API_KEY, BP_SECRET_SALT_GOOGLE);

@implementation BPSecrets

+ (NSString *)thunderforestAPIKey
{
    return BPSecretDecode(&kThunderforestKey);
}

+ (NSString *)googleMapsAPIKey
{
    return BPSecretDecode(&kGoogleMapsKey);
}

+ (BOOL)usesPrivateEncoding
{
    return BP_SECRET_ENCODING_PRIVATE;
}

+ (NSString *)thunderforestTileURLTemplate
{
    return [@"https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=" stringByAppendingString:[self thunderforestAPIKey]];
}

@end
