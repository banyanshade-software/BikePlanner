//
//  SecretsTests.m
//  BikePlannerTests
//
//  The Thunderforest and Google Maps keys of Secret.h must not appear in clear in the app binaries (#51).
//  The assertion messages never print the key.
//

#import <XCTest/XCTest.h>
#import "BPSecrets.h"
#import "../BikePlanner/Secret.h" // git-ignored, not in the project
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
