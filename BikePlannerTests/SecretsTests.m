//
//  SecretsTests.m
//  BikePlannerTests
//
//  The Thunderforest and Google Maps keys of Secret.h must not appear in clear in the app binaries (#51), nor under a
//  simple decoding (#57).
//  The assertion messages never print the key.
//

#import <XCTest/XCTest.h>
#import "BPSecrets.h"
#import "../BikePlanner/Secret.h" // git-ignored, not in the project
#if !defined(GOOGLE_MAPS_API_KEY) && defined(GOOGLE_API_KEY) // same alias as BPSecrets.m
#define GOOGLE_MAPS_API_KEY GOOGLE_API_KEY
#endif
#ifndef GOOGLE_MAPS_API_KEY // optional (#49)
#define GOOGLE_MAPS_API_KEY ""
#endif

@interface SecretsTests : XCTestCase
@end

@implementation SecretsTests

- (NSString *)key
{
    return @THUNDERFOREST_API_KEY;
}

- (void)testDecodedKey
{
    XCTAssertTrue([[BPSecrets thunderforestAPIKey] isEqualToString:[self key]], @"decoded key differs from Secret.h");
    NSString *t = [BPSecrets thunderforestTileURLTemplate];
    XCTAssertTrue([t hasPrefix:@"https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey="]);
    XCTAssertTrue([t hasSuffix:[self key]], @"template does not end with the key");
}

- (void)testDecodedGoogleMapsKey
{
    XCTAssertTrue([[BPSecrets googleMapsAPIKey] isEqualToString:@GOOGLE_MAPS_API_KEY], @"decoded key differs from Secret.h");
}

// every Mach-O of Contents/MacOS (in Debug, the code is in BikePlanner.debug.dylib)
- (void)testKeyNotInClearInBinaries
{
    [self assertNotInClear:[self key] name:@"Thunderforest"];
    if (strlen(GOOGLE_MAPS_API_KEY) > 0) [self assertNotInClear:@GOOGLE_MAPS_API_KEY name:@"Google Maps"];
}

// stronger obfuscation (#57): the key is not found either with simple decodings of the binaries — a constant byte
// XOR, the reversed key, or the fixed mask of #51 (0xA7 ^ 29 i, in the order of the key)
- (void)testKeyNotFoundWithSimpleDecodings
{
    [self assertNotEncoded:[self key] name:@"Thunderforest"];
    if (strlen(GOOGLE_MAPS_API_KEY) > 0) [self assertNotEncoded:@GOOGLE_MAPS_API_KEY name:@"Google Maps"];
}

- (void)assertNotEncoded:(NSString *)keyString name:(NSString *)name
{
    NSData *key = [keyString dataUsingEncoding:NSUTF8StringEncoding];
    const unsigned char *k = key.bytes;
    NSUInteger n = key.length;
    NSMutableArray<NSData *> *encodings = [NSMutableArray array];
    NSMutableData *e = [NSMutableData dataWithLength:n];
    unsigned char *b = e.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) b[i] = k[i] ^ (unsigned char)(0xA7 ^ (i * 29));
    [encodings addObject:[e copy]];
    for (NSUInteger i = 0; i < n; i++) b[i] = k[n - 1 - i];
    [encodings addObject:[e copy]];
    for (unsigned x = 1; x < 256; x++) {
        for (NSUInteger i = 0; i < n; i++) b[i] = k[i] ^ (unsigned char)x;
        [encodings addObject:[e copy]];
    }
    NSString *dir = [NSBundle mainBundle].executablePath.stringByDeletingLastPathComponent;
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        NSData *bin = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
        [encodings enumerateObjectsUsingBlock:^(NSData *enc, NSUInteger idx, BOOL *stop) {
            BOOL found = [bin rangeOfData:enc options:0 range:NSMakeRange(0, bin.length)].location != NSNotFound;
            XCTAssertFalse(found, @"%@ key found in %@ with simple decoding #%lu (#57)", name, f, (unsigned long)idx);
            if (found) *stop = YES;
        }];
    }
}

- (void)assertNotInClear:(NSString *)keyString name:(NSString *)name
{
    NSData *key = [keyString dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertGreaterThan(key.length, 8u);
    NSString *dir = [NSBundle mainBundle].executablePath.stringByDeletingLastPathComponent;
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    XCTAssertGreaterThan(files.count, 0u);
    for (NSString *f in files) {
        NSData *bin = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
        NSRange r = [bin rangeOfData:key options:0 range:NSMakeRange(0, bin.length)];
        XCTAssertEqual(r.location, (NSUInteger)NSNotFound, @"%@ key in clear in %@ (#51)", name, f);
    }
}

@end
