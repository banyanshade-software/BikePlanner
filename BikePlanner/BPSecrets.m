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

// A key is encoded at compile time into byte arrays: the string literal of Secret.h is only used in constant
// expressions, so it is not emitted in the binary (checked by SecretsTests and make_dmg.sh). This is the only file
// that may include Secret.h. Stronger than the fixed XOR of #51 (#57), though anyone running the app in a debugger
// still gets the key (and it travels in clear in the requests):
// - the mask is a non-linear keystream (32-bit hash of seed + index) seeded by the time of the compilation of this
//   file, so it changes from one build to the next and appears nowhere as such;
// - the bytes are stored out of order (position 37 i + 11 mod 96), the unused ones filled with noise, the length
//   masked too;
// - each key is split in two arrays (shares) that must be XOR-ed together.
#define BP_KEY_MAX 96
#define BP_LEN(K) (sizeof(K) - 1)
#define BP_U(x) ((unsigned)(x))
#define BP_SEED (BP_U(__TIME__[0]) * 0x01000193u ^ BP_U(__TIME__[1]) * 0x2545F491u ^ BP_U(__TIME__[3]) * 0x9E3779B1u \
               ^ BP_U(__TIME__[4]) * 0x85EBCA77u ^ BP_U(__TIME__[6]) * 0xC2B2AE3Du ^ BP_U(__TIME__[7]) * 0x27D4EB2Fu \
               ^ BP_U(__DATE__[4]) * 0x165667B1u ^ BP_U(__DATE__[5]) * 0xD3A2646Bu ^ BP_U(__DATE__[0]) * 0x61C88647u)
#define BP_M1(x) (BP_U(BP_U(x) ^ (BP_U(x) >> 15)) * 0x2C1B3C6Du)
#define BP_M2(x) (BP_U(BP_U(x) ^ (BP_U(x) >> 12)) * 0x297A2D39u)
#define BP_HASH(x) (BP_M2(BP_M1(x)) ^ (BP_M2(BP_M1(x)) >> 15))
#define BP_BYTE(s, i) ((unsigned char)(BP_HASH(BP_U(s) + BP_U(i) * 0x9E3779B9u) >> 11))
#define BP_SHARE_SALT 0xA5A5A5A5u
#define BP_NOISE_SALT 0x77777777u
#define BP_LEN_INDEX 1000
#define BP_SLOT(i) ((37 * (i) + 11) % BP_KEY_MAX)              // where key byte i is stored
#define BP_INDEX(j) ((13 * (j) + 49) % BP_KEY_MAX)             // which key byte is stored at j (inverse of BP_SLOT)
// key byte i (noise after the end of the key), masked
#define BP_CODE(K, s, i) ((unsigned char)(((i) < BP_LEN(K) ? K[(i) < BP_LEN(K) ? (i) : 0] : BP_BYTE((s) ^ BP_NOISE_SALT, i)) \
                                          ^ BP_BYTE(s, i)))
#define BP_A(K, s, j) BP_BYTE((s) ^ BP_SHARE_SALT, j)
#define BP_B(K, s, j) ((unsigned char)(BP_CODE(K, s, BP_INDEX(j)) ^ BP_A(K, s, j)))
#define BP_8(F, K, s, j) F(K, s, j), F(K, s, j + 1), F(K, s, j + 2), F(K, s, j + 3), \
                         F(K, s, j + 4), F(K, s, j + 5), F(K, s, j + 6), F(K, s, j + 7)
#define BP_ARRAY(F, K, s) { BP_8(F, K, s, 0), BP_8(F, K, s, 8), BP_8(F, K, s, 16), BP_8(F, K, s, 24), \
                            BP_8(F, K, s, 32), BP_8(F, K, s, 40), BP_8(F, K, s, 48), BP_8(F, K, s, 56), \
                            BP_8(F, K, s, 64), BP_8(F, K, s, 72), BP_8(F, K, s, 80), BP_8(F, K, s, 88) }
#define BP_SALT_THUNDERFOREST 0x5A17C3E1u
#define BP_SALT_GOOGLE 0x3C6EF372u

_Static_assert(BP_LEN(THUNDERFOREST_API_KEY) <= BP_KEY_MAX, "Thunderforest key too long for BPSecrets");
_Static_assert(BP_LEN(GOOGLE_MAPS_API_KEY) <= BP_KEY_MAX, "Google Maps key too long for BPSecrets");

typedef struct {
    unsigned salt;
    unsigned char length;                   // masked
    unsigned char a[BP_KEY_MAX], b[BP_KEY_MAX];
} BPEncodedKey;

#define BP_ENCODED(K, salt) { salt, (unsigned char)(BP_LEN(K) ^ BP_BYTE(BP_SEED ^ (salt), BP_LEN_INDEX)), \
                              BP_ARRAY(BP_A, K, BP_SEED ^ (salt)), BP_ARRAY(BP_B, K, BP_SEED ^ (salt)) }

static const unsigned kSeed = BP_SEED;
static const BPEncodedKey kThunderforestKey = BP_ENCODED(THUNDERFOREST_API_KEY, BP_SALT_THUNDERFOREST);
static const BPEncodedKey kGoogleMapsKey = BP_ENCODED(GOOGLE_MAPS_API_KEY, BP_SALT_GOOGLE);

// BP_BYTE at run time
static unsigned char BPByte(unsigned s, unsigned i)
{
    unsigned x = s + i * 0x9E3779B9u;
    x = (x ^ (x >> 15)) * 0x2C1B3C6Du;
    x = (x ^ (x >> 12)) * 0x297A2D39u;
    x ^= x >> 15;
    return (unsigned char)(x >> 11);
}

static NSString *BPDecode(const BPEncodedKey *encoded)
{
    // read through volatile pointers: otherwise the optimizer (Release) decodes the constants at compile time and
    // writes the key in clear in the binary
    const volatile BPEncodedKey *e = encoded;
    const volatile unsigned *seed = &kSeed;
    unsigned s = *seed ^ e->salt;
    size_t len = (unsigned char)(e->length ^ BPByte(s, BP_LEN_INDEX));
    if (len > BP_KEY_MAX) return @"";
    char key[BP_KEY_MAX + 1];
    for (size_t i = 0; i < len; i++) {
        size_t j = BP_SLOT(i);
        key[i] = (char)(e->a[j] ^ e->b[j] ^ BPByte(s, (unsigned)i));
    }
    key[len] = 0;
    NSString *str = [NSString stringWithUTF8String:key];
    memset(key, 0, sizeof(key));
    return str ?: @"";
}

@implementation BPSecrets

+ (NSString *)thunderforestAPIKey
{
    return BPDecode(&kThunderforestKey);
}

+ (NSString *)googleMapsAPIKey
{
    return BPDecode(&kGoogleMapsKey);
}

+ (NSString *)thunderforestTileURLTemplate
{
    return [@"https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=" stringByAppendingString:[self thunderforestAPIKey]];
}

@end
