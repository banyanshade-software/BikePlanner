//
//  StreetViewControllerTests.m
//  BikePlannerTests
//
//  Pages sent to the web view (a WKWebView subclass records them instead of loading): the Maps Embed API in an
//  iframe when there is a Google Maps key accepted by Google (#49), the Google Maps web app otherwise. The key check
//  goes to BPStubServer, which rejects keys starting with "invalid".
//

#import <XCTest/XCTest.h>
#import "StreetViewController.h"
#import "TestFixtures.h"
#import "BPSecrets.h"
#import "BPStubServer.h"

@interface BPRecordingWebView : WKWebView
@property (nonatomic, strong) NSMutableArray<NSURL *> *loaded;
@property (nonatomic, strong) NSMutableArray<NSString *> *html;
@property (nonatomic, strong) NSMutableArray<NSURL *> *baseURLs;
@end

@implementation BPRecordingWebView
- (WKNavigation *)loadRequest:(NSURLRequest *)request
{
    if (!_loaded) _loaded = [NSMutableArray array];
    [_loaded addObject:request.URL];
    return nil;
}
- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL
{
    if (!_html) _html = [NSMutableArray array];
    if (!_baseURLs) _baseURLs = [NSMutableArray array];
    [_html addObject:string];
    [_baseURLs addObject:baseURL];
    return nil;
}
@end

// the key normally comes from Secret.h (BPSecrets); tests set it, whatever the owner's Secret.h contains
@interface StreetViewController (Testing)
@property (nonatomic, copy, nullable) NSString *apiKey;
+ (NSURL *)embedURLForCoord:(CLLocationCoordinate2D)coord heading:(double)heading key:(NSString *)key;
@end


@interface StreetViewControllerTests : XCTestCase
@end

@implementation StreetViewControllerTests {
    StreetViewController *sv;
    BPRecordingWebView *web;
    BPStubServer *server;
}

- (void)setUp
{
    server = [BPStubServer new];
    XCTAssertTrue([server startInProcess]);
    BPOverrideDefaults(@{ @"BPGoogleMapsEmbedURL": server.googleMapsEmbedURL.absoluteString });
    web = [[BPRecordingWebView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    sv = [[StreetViewController alloc] init];
    sv.webView = web;
    sv.apiKey = @"";
}

- (void)tearDown
{
    [server stop];
    BPRestoreDefaults();
}

- (NSArray<BPStubRequest *> *)keyChecks
{
    return [server requestsWithPath:@"/maps/embed/v1/streetview"];
}

- (BOOL)waitForPages:(NSUInteger)count
{
    return BPWaitUntil(5, ^BOOL{ return self->web.loaded.count + self->web.html.count >= count; });
}

// the initial page is the panorama at the default position, not a hard-coded Google Maps URL (#18)
- (void)testInitialPage
{
    BPOverrideDefaults(@{ @"BPDefaultPosition": @"45.5,1.25" });
    [sv initializeStreetView];
    XCTAssertEqual(web.loaded.count, 1u);
    XCTAssertEqualObjects(web.loaded[0].absoluteString,
        @"https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=45.500000,1.250000&heading=0.000000");
}

- (void)testViewCoordURL
{
    [sv viewCoord:CLLocationCoordinate2DMake(44.104288, 0.523907) lookingAt:166.5 coalesce:NO];
    XCTAssertEqual(web.loaded.count, 1u);
    XCTAssertEqualObjects(web.loaded[0].absoluteString,
        @"https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=44.104288,0.523907&heading=166.500000");
}

// with a valid key: the Maps Embed API in an iframe filling the pane, no Google Maps web app (and no big info box, #49)
- (void)testEmbedPage
{
    sv.apiKey = @"KEY";
    [sv viewCoord:CLLocationCoordinate2DMake(44.104288, 0.523907) lookingAt:166.5 coalesce:NO];
    XCTAssertTrue([self waitForPages:1]);
    XCTAssertEqual(web.loaded.count, 0u, @"no Google Maps web app");
    XCTAssertEqual(web.html.count, 1u);
    NSString *html = web.html.firstObject;
    NSString *src = [NSString stringWithFormat:@"src=\"%@streetview?key=KEY&amp;location=44.104288,0.523907"
                     "&amp;heading=166.50&amp;pitch=0&amp;fov=90\"", server.googleMapsEmbedURL.absoluteString];
    XCTAssertTrue([html containsString:src], @"%@", html);
    XCTAssertTrue([html containsString:@"<iframe"]);
    XCTAssertTrue([html containsString:@"width:100%"]);
    XCTAssertTrue([html containsString:@"height:100%"]);
    // the base URL is the referrer seen by Google: the key can be restricted to it
    XCTAssertEqualObjects(web.baseURLs.firstObject.absoluteString, @"https://bikeplanner.invalid/");
}

- (void)testEmbedInitialPage
{
    // BPOverrideDefaults replaces the overrides of setUp
    BPOverrideDefaults(@{ @"BPDefaultPosition": @"45.5,1.25",
                          @"BPGoogleMapsEmbedURL": server.googleMapsEmbedURL.absoluteString });
    sv.apiKey = @"KEY";
    [sv initializeStreetView];
    XCTAssertTrue([self waitForPages:1]);
    XCTAssertEqual(web.html.count, 1u);
    XCTAssertTrue([web.html.firstObject containsString:@"location=45.500000,1.250000&amp;heading=0.00&amp;"]);
}

// the key is checked once, with the referrer of the iframe (a key restricted to other websites is rejected)
- (void)testKeyCheckedOnceWithReferrer
{
    sv.apiKey = @"KEY";
    [sv viewCoord:CLLocationCoordinate2DMake(44, 0.5) lookingAt:0 coalesce:NO];
    XCTAssertTrue([self waitForPages:1]);
    [sv viewCoord:CLLocationCoordinate2DMake(44.1, 0.6) lookingAt:90 coalesce:NO];
    [sv viewCoord:CLLocationCoordinate2DMake(44.2, 0.7) lookingAt:180 coalesce:NO];
    XCTAssertEqual(web.html.count, 3u, @"no wait once the key is accepted");
    NSArray<BPStubRequest *> *checks = [self keyChecks];
    XCTAssertEqual(checks.count, 1u);
    XCTAssertEqualObjects(checks.firstObject.query[@"key"], @"KEY");
    XCTAssertEqualObjects(checks.firstObject.referer, @"https://bikeplanner.invalid/");
}

// nothing is shown while the key is checked; then only the last requested view
- (void)testViewsDuringCheck
{
    server.responseDelay = 0.3;
    sv.apiKey = @"KEY";
    [sv viewCoord:CLLocationCoordinate2DMake(44, 0.5) lookingAt:0 coalesce:NO];
    [sv viewCoord:CLLocationCoordinate2DMake(44.2, 0.7) lookingAt:45 coalesce:NO];
    XCTAssertEqual(web.loaded.count + web.html.count, 0u);
    XCTAssertTrue([self waitForPages:1]);
    BPSpin(0.1);
    XCTAssertEqual(web.html.count, 1u);
    XCTAssertTrue([web.html.firstObject containsString:@"location=44.200000,0.700000&amp;heading=45.00&amp;"]);
    XCTAssertEqual([self keyChecks].count, 1u);
}

// a key rejected by Google: the Google Maps web app, and the key is not checked again
- (void)testRejectedKeyFallsBackToMapsURL
{
    sv.apiKey = @"invalid-KEY";
    [sv viewCoord:CLLocationCoordinate2DMake(44.104288, 0.523907) lookingAt:166.5 coalesce:NO];
    XCTAssertTrue([self waitForPages:1]);
    XCTAssertEqual(web.html.count, 0u, @"no Embed API");
    XCTAssertEqual(web.loaded.count, 1u);
    XCTAssertEqualObjects(web.loaded[0].absoluteString,
        @"https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=44.104288,0.523907&heading=166.500000");
    [sv viewCoord:CLLocationCoordinate2DMake(44, 0.5) lookingAt:0 coalesce:NO];
    XCTAssertEqual(web.loaded.count, 2u, @"no wait once the key is rejected");
    XCTAssertEqual([self keyChecks].count, 1u);
}

// Google not reached: the Google Maps web app for this view, the key is checked again at the next one and the
// Embed API is used as soon as it is accepted
- (void)testUnreachableGoogleRetriesCheck
{
    server.failCount = 1;
    server.failStatus = 503;
    sv.apiKey = @"KEY";
    [sv viewCoord:CLLocationCoordinate2DMake(44, 0.5) lookingAt:0 coalesce:NO];
    XCTAssertTrue([self waitForPages:1]);
    XCTAssertEqual(web.loaded.count, 1u);
    XCTAssertEqual(web.html.count, 0u);
    [sv viewCoord:CLLocationCoordinate2DMake(44.1, 0.6) lookingAt:0 coalesce:NO];
    XCTAssertTrue([self waitForPages:2]);
    XCTAssertEqual(web.loaded.count, 1u);
    XCTAssertEqual(web.html.count, 1u, @"Embed API once the key is accepted");
    XCTAssertEqual([self keyChecks].count, 2u);
}

// a new key (tests; Secret.h at the next build) is checked again
- (void)testNewKeyCheckedAgain
{
    sv.apiKey = @"invalid-KEY";
    [sv viewCoord:CLLocationCoordinate2DMake(44, 0.5) lookingAt:0 coalesce:NO];
    XCTAssertTrue([self waitForPages:1]);
    sv.apiKey = @"KEY";
    [sv viewCoord:CLLocationCoordinate2DMake(44, 0.5) lookingAt:0 coalesce:NO];
    XCTAssertTrue([self waitForPages:2]);
    XCTAssertEqual(web.html.count, 1u);
    XCTAssertEqual([self keyChecks].count, 2u);
}

// headings are normalized to [0, 360), the key is URL-encoded
- (void)testEmbedURL
{
    BPRestoreDefaults(); // the production endpoint
    NSURL *u = [StreetViewController embedURLForCoord:CLLocationCoordinate2DMake(-33.5, -70.25) heading:-90 key:@"a+b/c"];
    XCTAssertEqualObjects(u.absoluteString, @"https://www.google.com/maps/embed/v1/streetview?key=a%2Bb%2Fc"
                          "&location=-33.500000,-70.250000&heading=270.00&pitch=0&fov=90");
    u = [StreetViewController embedURLForCoord:CLLocationCoordinate2DMake(1, 2) heading:725 key:@"K"];
    XCTAssertTrue([u.absoluteString containsString:@"&heading=5.00&"]);
}

// no key in Secret.h: falls back to the Google Maps web app
- (void)testNoKeyFallsBackToMapsURL
{
    sv.apiKey = nil;
    if ([BPSecrets googleMapsAPIKey].length) return; // the owner's Secret.h has a key: covered by testEmbedPage
    [sv viewCoord:CLLocationCoordinate2DMake(44, 0.5) lookingAt:0 coalesce:NO];
    XCTAssertEqual(web.loaded.count, 1u);
    XCTAssertEqual(web.html.count, 0u);
    XCTAssertEqual([self keyChecks].count, 0u, @"no key, no check");
}

- (void)testDisabled
{
    BPOverrideDefaults(@{ @"BPDisableStreetView": @YES });
    sv.apiKey = @"KEY";
    [sv initializeStreetView];
    [sv viewCoord:CLLocationCoordinate2DMake(44, 0.5) lookingAt:0 coalesce:YES];
    BPSpin(0.2);
    XCTAssertEqual(web.loaded.count, 0u);
    XCTAssertEqual(web.html.count, 0u);
    XCTAssertEqual([self keyChecks].count, 0u);
}

@end
