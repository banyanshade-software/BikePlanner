//
//  BPSecrets.m
//  BikePlanner
//

#import "BPSecrets.h"
#import "Secret.h" // git-ignored, see Secret.h.example

// Optional (#49): without it, Street View falls back to the Google Maps web app
#ifndef GOOGLE_MAPS_API_KEY
#define GOOGLE_MAPS_API_KEY ""
#endif

// A key is XOR-ed at compile time, character by character, into a byte array: the string literal of Secret.h is
// only used in constant expressions, so it is not emitted in the binary (checked by SecretsTests). This is the only
// file that may include Secret.h.
#define BP_KEY_MAX 96
#define BP_LEN(K) (sizeof(K) - 1)
#define BP_MASK(i) ((unsigned char)(0xA7 ^ ((i) * 29)))
#define BP_E(K, i) ((unsigned char)((i) < BP_LEN(K) ? (K[(i) < BP_LEN(K) ? (i) : 0] ^ BP_MASK(i)) : 0))
#define BP_E8(K, i) BP_E(K, i), BP_E(K, i + 1), BP_E(K, i + 2), BP_E(K, i + 3), \
                    BP_E(K, i + 4), BP_E(K, i + 5), BP_E(K, i + 6), BP_E(K, i + 7)
#define BP_OBFUSCATE(K) { BP_E8(K, 0), BP_E8(K, 8), BP_E8(K, 16), BP_E8(K, 24), BP_E8(K, 32), BP_E8(K, 40), \
                          BP_E8(K, 48), BP_E8(K, 56), BP_E8(K, 64), BP_E8(K, 72), BP_E8(K, 80), BP_E8(K, 88) }

_Static_assert(BP_LEN(THUNDERFOREST_API_KEY) <= BP_KEY_MAX, "Thunderforest key too long for BPSecrets");
_Static_assert(BP_LEN(GOOGLE_MAPS_API_KEY) <= BP_KEY_MAX, "Google Maps key too long for BPSecrets");

static const unsigned char kThunderforestKey[BP_KEY_MAX] = BP_OBFUSCATE(THUNDERFOREST_API_KEY);
static const unsigned char kGoogleMapsKey[BP_KEY_MAX] = BP_OBFUSCATE(GOOGLE_MAPS_API_KEY);

static NSString *BPDecode(const unsigned char *obfuscated, size_t len)
{
    // read through a volatile pointer: otherwise the optimizer (Release) decodes the constant array at compile time
    // and writes the key in clear in the binary
    const volatile unsigned char *obf = obfuscated;
    char key[BP_KEY_MAX + 1];
    for (size_t i = 0; i < len; i++) key[i] = (char)(obf[i] ^ BP_MASK(i));
    key[len] = 0;
    NSString *s = [NSString stringWithUTF8String:key];
    memset(key, 0, sizeof(key));
    return s ?: @"";
}

@implementation BPSecrets

+ (NSString *)thunderforestAPIKey
{
    return BPDecode(kThunderforestKey, BP_LEN(THUNDERFOREST_API_KEY));
}

+ (NSString *)googleMapsAPIKey
{
    return BPDecode(kGoogleMapsKey, BP_LEN(GOOGLE_MAPS_API_KEY));
}

+ (NSString *)thunderforestTileURLTemplate
{
    return [@"https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=" stringByAppendingString:[self thunderforestAPIKey]];
}

@end
