//
//  BPSecrets.m
//  BikePlanner
//

#import "BPSecrets.h"
#import "Secret.h" // git-ignored, see Secret.h.example

// The key is XOR-ed at compile time, character by character, into a byte array: the string literal of Secret.h is
// only used in constant expressions, so it is not emitted in the binary (checked by SecretsTests). This is the only
// file that may include Secret.h.
#define BP_KEY_LEN (sizeof(THUNDERFOREST_API_KEY) - 1)
#define BP_KEY_MAX 96
#define BP_MASK(i) ((unsigned char)(0xA7 ^ ((i) * 29)))
#define BP_E(i) ((unsigned char)((i) < BP_KEY_LEN ? (THUNDERFOREST_API_KEY[(i) < BP_KEY_LEN ? (i) : 0] ^ BP_MASK(i)) : 0))
#define BP_E8(i) BP_E(i), BP_E(i + 1), BP_E(i + 2), BP_E(i + 3), BP_E(i + 4), BP_E(i + 5), BP_E(i + 6), BP_E(i + 7)

_Static_assert(BP_KEY_LEN <= BP_KEY_MAX, "Thunderforest key too long for BPSecrets");

static const unsigned char kThunderforestKey[BP_KEY_MAX] = {
    BP_E8(0), BP_E8(8), BP_E8(16), BP_E8(24), BP_E8(32), BP_E8(40),
    BP_E8(48), BP_E8(56), BP_E8(64), BP_E8(72), BP_E8(80), BP_E8(88),
};

@implementation BPSecrets

+ (NSString *)thunderforestAPIKey
{
    // read through a volatile pointer: otherwise the optimizer (Release) decodes the constant array at compile time
    // and writes the key in clear in the binary
    const volatile unsigned char *obf = kThunderforestKey;
    char key[BP_KEY_MAX + 1];
    for (size_t i = 0; i < BP_KEY_LEN; i++) key[i] = (char)(obf[i] ^ BP_MASK(i));
    key[BP_KEY_LEN] = 0;
    NSString *s = [NSString stringWithUTF8String:key];
    memset(key, 0, sizeof(key));
    return s ?: @"";
}

+ (NSString *)thunderforestTileURLTemplate
{
    return [@"https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=" stringByAppendingString:[self thunderforestAPIKey]];
}

@end
