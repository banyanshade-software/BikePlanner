//
//  StreetViewControllerTests.m
//  BikePlannerTests
//
//  URLs sent to the web view (a WKWebView subclass records them instead of loading).
//

#import <XCTest/XCTest.h>
#import "StreetViewController.h"
#import "TestFixtures.h"

@interface BPRecordingWebView : WKWebView
@property (nonatomic, strong) NSMutableArray<NSURL *> *loaded;
@end

@implementation BPRecordingWebView
- (WKNavigation *)loadRequest:(NSURLRequest *)request
{
    if (!_loaded) _loaded = [NSMutableArray array];
    [_loaded addObject:request.URL];
    return nil;
}
@end


@interface StreetViewControllerTests : XCTestCase
@end

@implementation StreetViewControllerTests {
    StreetViewController *sv;
    BPRecordingWebView *web;
}

- (void)setUp
{
    web = [[BPRecordingWebView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    sv = [[StreetViewController alloc] init];
    sv.webView = web;
}

- (void)tearDown
{
    BPRestoreDefaults();
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

- (void)testDisabled
{
    BPOverrideDefaults(@{ @"BPDisableStreetView": @YES });
    [sv initializeStreetView];
    [sv viewCoord:CLLocationCoordinate2DMake(44, 0.5) lookingAt:0 coalesce:YES];
    XCTAssertEqual(web.loaded.count, 0u);
}

@end
