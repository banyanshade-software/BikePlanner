//
//  SecretEncodingExample.h
//  BikePlanner
//
//  Encoding of the API keys compiled in the app (#51, #57): this committed EXAMPLE is used only when the private
//  BikePlanner/SecretEncoding.h is missing (fresh clone). It is a plain XOR with one byte that changes at each build:
//  enough to keep the key out of `strings`, nothing more. scripts/make_dmg.sh refuses to package an app built with it.
//
//  The real mechanism is in SecretEncoding.h (git-ignored, private: the sources are public, so a committed
//  mechanism protects nothing). It must provide what this file provides, included only by BPSecrets.m:
//  - BP_KEY_MAX: the longest key;
//  - BP_SECRET_ENCODING_PRIVATE: 1 in the private file, 0 here;
//  - BP_SECRET_SALT_THUNDERFOREST, BP_SECRET_SALT_GOOGLE: one value per key, passed to BP_SECRET_ENCODE;
//  - the type BPSecretEncodedKey and BP_SECRET_ENCODE(K, salt): a constant initializer of it from the string literal
//    K (only used in constant expressions, so that the literal is not emitted in the binary);
//  - static NSString *BPSecretDecode(const BPSecretEncodedKey *): the key at run time.
//

#define BP_KEY_MAX 96
#define BP_SECRET_ENCODING_PRIVATE 0
#define BP_SECRET_SALT_THUNDERFOREST 1u // unused by this encoding
#define BP_SECRET_SALT_GOOGLE 2u

#define BP_LEN(K) (sizeof(K) - 1)
// one byte per build (never 0)
#define BP_X ((unsigned char)((__TIME__[7] * 31u + __TIME__[6] * 7u + __TIME__[4] * 3u) | 0x01u))
#define BP_E(K, i) ((unsigned char)(((i) < BP_LEN(K) ? K[(i) < BP_LEN(K) ? (i) : 0] : 0) ^ BP_X))
#define BP_8(K, j) BP_E(K, j), BP_E(K, j + 1), BP_E(K, j + 2), BP_E(K, j + 3), \
                   BP_E(K, j + 4), BP_E(K, j + 5), BP_E(K, j + 6), BP_E(K, j + 7)

typedef struct {
    unsigned char mask, length;
    unsigned char bytes[BP_KEY_MAX];
} BPSecretEncodedKey;

#define BP_SECRET_ENCODE(K, salt) { BP_X, (unsigned char)BP_LEN(K), \
    { BP_8(K, 0), BP_8(K, 8), BP_8(K, 16), BP_8(K, 24), BP_8(K, 32), BP_8(K, 40), \
      BP_8(K, 48), BP_8(K, 56), BP_8(K, 64), BP_8(K, 72), BP_8(K, 80), BP_8(K, 88) } }

static NSString *BPSecretDecode(const BPSecretEncodedKey *encoded)
{
    // volatile: otherwise the optimizer (Release) decodes at compile time and writes the key in clear
    const volatile BPSecretEncodedKey *e = encoded;
    size_t len = e->length;
    if (len > BP_KEY_MAX) return @"";
    char key[BP_KEY_MAX + 1];
    for (size_t i = 0; i < len; i++) key[i] = (char)(e->bytes[i] ^ e->mask);
    key[len] = 0;
    NSString *str = [NSString stringWithUTF8String:key];
    memset(key, 0, sizeof(key));
    return str ?: @"";
}
