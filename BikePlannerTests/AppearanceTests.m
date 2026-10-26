//
//  AppearanceTests.m
//  BikePlannerTests
//
//  Light / dark appearance: what the app draws must stay readable in both (issue #17).
//

#import <XCTest/XCTest.h>
#import <MapKit/MapKit.h>
#import "ElevationProfileView.h"
#import "Document.h"
#import "MapController.h"
#import "BikePlan.h"
#import "BPStubServer.h"
#import "TestFixtures.h"

static NSAppearance *BPAqua(void) { return [NSAppearance appearanceNamed:NSAppearanceNameAqua]; }
static NSAppearance *BPDark(void) { return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; }

// brightness of a color as seen in an appearance (dynamic colors resolved), 0 = black, 1 = white
static CGFloat BPBrightness(NSColor *c, NSAppearance *appearance)
{
    __block CGFloat b = -1;
    [appearance performAsCurrentDrawingAppearance:^{
        NSColor *rgb = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        b = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent;
    }];
    return b;
}

@interface AppearanceTests : XCTestCase
@end

@implementation AppearanceTests

#pragma mark - elevation profile

// Renders the profile in `appearance` and returns the brightest/darkest opaque pixel of the vertical axis (x = 40).
- (void)renderProfileIn:(NSAppearance *)appearance maxBrightness:(CGFloat *)maxB minBrightness:(CGFloat *)minB
{
    ElevationProfileView *v = [[ElevationProfileView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    v.appearance = appearance;
    [v setGpxPoints:@[BPLocAlt(0, 0, 100), BPLocAlt(0, 0.01, 150), BPLocAlt(0, 0.02, 120)]];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    CGFloat scale = rep.pixelsWide / v.bounds.size.width;
    *maxB = 0; *minB = 1;
    NSInteger x0 = (NSInteger)(40 * scale);
    for (NSInteger x = x0 - 1; x <= x0 + 1; x++) {
        for (NSInteger y = (NSInteger)(60 * scale); y < (NSInteger)(140 * scale); y += 4) {
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            if (c.alphaComponent < 0.5) continue;
            CGFloat b = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent;
            *maxB = MAX(*maxB, b);
            *minB = MIN(*minB, b);
        }
    }
}

- (void)testProfileAxisIsDarkInLightMode
{
    CGFloat maxB, minB;
    [self renderProfileIn:BPAqua() maxBrightness:&maxB minBrightness:&minB];
    XCTAssertLessThan(minB, 0.4, @"axis must be drawn dark in light mode");
}

- (void)testProfileAxisIsLightInDarkMode
{
    CGFloat maxB, minB;
    [self renderProfileIn:BPDark() maxBrightness:&maxB minBrightness:&minB];
    XCTAssertGreaterThan(maxB, 0.6, @"axis must be drawn light in dark mode");
}

#pragma mark - document window controls

- (MapController *)openWindow:(Document **)docOut server:(BPStubServer *)server
{
    BPOverrideDefaults(@{ @"BPBRouterServer": server.baseURL.absoluteString,
                          @"BPDisableStreetView": @YES, @"BPDisableTiles": @YES,
                          @"BPInitialRegion": @"44.05,0.55,0.2" });
    Document *doc = [[Document alloc] init];
    doc.plan.fetchPOI = NO;
    [doc makeWindowControllers];
    (void)doc.windowControllers.firstObject.window;
    *docOut = doc;
    return doc.mapController;
}

- (NSView *)viewWithIdentifier:(NSString *)ident in:(NSView *)root
{
    if ([root.accessibilityIdentifier isEqualToString:ident]) return root;
    for (NSView *v in root.subviews) {
        NSView *f = [self viewWithIdentifier:ident in:v];
        if (f) return f;
    }
    return nil;
}

- (void)testMapControlsInBothAppearances
{
    BPStubServer *server = [[BPStubServer alloc] init];
    XCTAssertTrue([server startInProcess]);
    Document *doc = nil;
    MapController *mc = [self openWindow:&doc server:server];
    NSView *content = mc.mapView.superview;

    for (NSString *ident in @[@"clickMode", @"mapType"]) {
        NSSegmentedControl *seg = (NSSegmentedControl *)[self viewWithIdentifier:ident in:content];
        NSColor *sel = seg.selectedSegmentBezelColor;
        // unchanged look in light mode (light gray), dark in dark mode so that the white label stays readable
        XCTAssertGreaterThan(BPBrightness(sel, BPAqua()), 0.6, @"%@ light", ident);
        XCTAssertLessThan(BPBrightness(sel, BPDark()), 0.4, @"%@ dark", ident);
    }

    // the help text is drawn over the map (OSM tiles are always light): it needs its own background
    NSTextField *help = (NSTextField *)[self viewWithIdentifier:@"clickModeHelp" in:content];
    XCTAssertTrue(help.drawsBackground);
    XCTAssertGreaterThan(help.backgroundColor.alphaComponent, 0.3);
    XCTAssertGreaterThan(BPBrightness(help.backgroundColor, BPAqua()), 0.6);
    XCTAssertLessThan(BPBrightness(help.backgroundColor, BPDark()), 0.4);

    [doc close];
    [server stop];
    BPRestoreDefaults();
}

@end
