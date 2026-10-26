//
//  BikePlannerUITestsLaunchTests.m
//  BikePlannerUITests
//
//  Launch screenshot, for each UI configuration (light / dark appearance), offline.
//

#import "BPUITestCase.h"

@interface BikePlannerUITestsLaunchTests : BPUITestCase
@end

@implementation BikePlannerUITestsLaunchTests

+ (BOOL)runsForEachTargetApplicationUIConfiguration
{
    return YES;
}

- (void)testLaunch
{
    XCTAttachment *attachment = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    attachment.name = @"Launch Screen";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}

@end
