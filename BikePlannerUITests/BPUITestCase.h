//
//  BPUITestCase.h
//  BikePlannerUITests
//
//  Base class for UI tests: starts the local stub server (BRouter + Overpass), launches the app
//  offline against it (no tiles, no Street View, fixed initial region around 44.05N 0.55E),
//  and provides helpers. The stub server request log is the main oracle for app behavior.
//

#import <XCTest/XCTest.h>
#import "BPStubServer.h"

NS_ASSUME_NONNULL_BEGIN

@interface BPUITestCase : XCTestCase

@property (nonatomic, strong) XCUIApplication *app;
@property (nonatomic, strong) BPStubServer *server;

/// launch arguments added to the offline ones (override in subclasses before -setUp)
- (NSArray<NSString *> *) extraLaunchArguments;

- (XCUIElement *) window;
- (XCUIElement *) map;
- (XCUIElement *) elementWithIdentifier:(NSString *)ident;

/// click on the map at a normalized position (0,0 = top left); keep away from the bottom-left controls
- (void) clickMapAt:(CGVector)offset;
- (void) rightClickMapAt:(CGVector)offset dy:(CGFloat)dy;
/// click a segment of a segmented control by label
- (void) clickSegment:(NSString *)label of:(NSString *)controlIdentifier;
/// click a menu item of the main menu bar
- (void) clickMenu:(NSString *)menu item:(NSString *)item;
- (BOOL) menu:(NSString *)menu hasItem:(NSString *)item;

/// waits until the stub server received `count` requests on `path`
- (BOOL) waitForRequests:(NSString *)path count:(NSUInteger)count timeout:(NSTimeInterval)timeout;
/// waits until the element's value differs from `value`
- (BOOL) waitForElement:(XCUIElement *)e valueNot:(NSString *)value timeout:(NSTimeInterval)timeout;

/// two waypoints (start, destination) and the computed route; returns after the route is displayed
- (void) buildRoute;
/// number of waypoints in the last /brouter request
- (NSUInteger) lastRouteWaypointCount;

@end

NS_ASSUME_NONNULL_END
