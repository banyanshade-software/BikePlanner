//
//  BPUITestCase.m
//  BikePlannerUITests
//

#import "BPUITestCase.h"

@implementation BPUITestCase

- (NSArray<NSString *> *) extraLaunchArguments
{
    return @[];
}

- (void) setUp
{
    self.continueAfterFailure = NO;
    self.server = [[BPStubServer alloc] init];
    XCTAssertTrue([self.server start]);

    self.app = [[XCUIApplication alloc] init];
    NSMutableArray *args = [@[
        @"-BPBRouterServer", self.server.baseURL.absoluteString,
        @"-BPOverpassURL", self.server.overpassURL.absoluteString,
        @"-BPDisableStreetView", @"YES",
        @"-BPDisableTiles", @"YES",
        @"-BPInitialRegion", @"44.05,0.55,0.2",
        @"-ApplePersistenceIgnoreState", @"YES",
    ] mutableCopy];
    [args addObjectsFromArray:[self extraLaunchArguments]];
    self.app.launchArguments = args;
    [self.app launch];

    if (![self.map waitForExistenceWithTimeout:5]) {
        // no untitled document opened at launch: create one
        [self.app typeKey:@"n" modifierFlags:XCUIKeyModifierCommand];
    }
    XCTAssertTrue([self.map waitForExistenceWithTimeout:10]);
}

- (void) tearDown
{
    [self.app terminate];
    [self.server stop];
}

#pragma mark - elements

- (XCUIElement *) window
{
    return self.app.windows.firstMatch;
}

- (XCUIElement *) elementWithIdentifier:(NSString *)ident
{
    return [[self.app descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:ident].firstMatch;
}

- (XCUIElement *) map
{
    return [self elementWithIdentifier:@"map"];
}

#pragma mark - actions

- (void) clickMapAt:(CGVector)offset
{
    [[self.map coordinateWithNormalizedOffset:offset] click];
    // let MapKit settle so that two clicks are not taken as a double click
    [NSThread sleepForTimeInterval:0.6];
}

- (void) rightClickMapAt:(CGVector)offset dy:(CGFloat)dy
{
    [[[self.map coordinateWithNormalizedOffset:offset] coordinateWithOffset:CGVectorMake(0, dy)] rightClick];
}

- (void) clickSegment:(NSString *)label of:(NSString *)controlIdentifier
{
    XCUIElement *seg = [self elementWithIdentifier:controlIdentifier];
    XCTAssertTrue([seg waitForExistenceWithTimeout:5], @"%@", controlIdentifier);
    XCUIElement *b = seg.buttons[label];
    if (!b.exists) b = seg.radioButtons[label];
    XCTAssertTrue(b.exists, @"segment %@", label);
    [b click];
}

- (void) clickMenu:(NSString *)menu item:(NSString *)item
{
    [self.app.menuBars.menuBarItems[menu] click];
    XCUIElement *mi = self.app.menuBars.menuItems[item];
    XCTAssertTrue([mi waitForExistenceWithTimeout:3], @"menu item %@", item);
    [mi click];
}

- (BOOL) menu:(NSString *)menu hasItem:(NSString *)item
{
    [self.app.menuBars.menuBarItems[menu] click];
    BOOL found = [self.app.menuBars.menuItems[item] waitForExistenceWithTimeout:2];
    [self.app typeKey:XCUIKeyboardKeyEscape modifierFlags:0];
    return found;
}

#pragma mark - waiting

- (BOOL) waitForRequests:(NSString *)path count:(NSUInteger)count timeout:(NSTimeInterval)timeout
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([self.server requestsWithPath:path].count < count) {
        if ([limit timeIntervalSinceNow] < 0) return NO;
        [NSThread sleepForTimeInterval:0.1];
    }
    return YES;
}

- (BOOL) waitForElement:(XCUIElement *)e valueNot:(NSString *)value timeout:(NSTimeInterval)timeout
{
    NSPredicate *p = [NSPredicate predicateWithFormat:@"exists == YES AND value != %@", value];
    XCTNSPredicateExpectation *x = [[XCTNSPredicateExpectation alloc] initWithPredicate:p object:e];
    return [XCTWaiter waitForExpectations:@[x] timeout:timeout] == XCTWaiterResultCompleted;
}

#pragma mark - scenarios

- (void) buildRoute
{
    [self clickMapAt:CGVectorMake(0.30, 0.30)];
    [self clickMapAt:CGVectorMake(0.70, 0.45)];
    XCTAssertTrue([self waitForRequests:@"/brouter" count:1 timeout:10]);
    XCTAssertTrue([self waitForElement:[self elementWithIdentifier:@"routeLength"] valueNot:@"...." timeout:10]);
}

- (NSUInteger) lastRouteWaypointCount
{
    NSString *lonlats = [self.server requestsWithPath:@"/brouter"].lastObject.query[@"lonlats"];
    return lonlats ? [lonlats componentsSeparatedByString:@"|"].count : 0;
}

@end
