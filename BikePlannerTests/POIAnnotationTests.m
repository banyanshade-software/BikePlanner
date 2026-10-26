//
//  POIAnnotationTests.m
//  BikePlannerTests
//
//  Ownership of the POI info dictionary (issue #7).
//

#import <XCTest/XCTest.h>
#import "POIAnnotation.h"
#import "POICalloutView.h"

@interface POIAnnotationTests : XCTestCase
@end

@implementation POIAnnotationTests

static NSDictionary *BPHeapDictionary(void)
{
    // mutable + non-constant content: a real heap object that can be deallocated
    return [NSMutableDictionary dictionaryWithObject:[NSUUID UUID].UUIDString forKey:@"amenity"];
}

- (void)testAnnotationKeepsInfo
{
    POIAnnotation *ann = [[POIAnnotation alloc] init];
    __weak NSDictionary *weakInfo = nil;
    @autoreleasepool {
        NSDictionary *info = BPHeapDictionary();
        weakInfo = info;
        ann.info = info;
    }
    XCTAssertNotNil(weakInfo);
    XCTAssertNotNil(ann.info[@"amenity"]);
}

- (void)testCalloutKeepsInfo
{
    POICalloutView *v = [[POICalloutView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    __weak NSDictionary *weakInfo = nil;
    @autoreleasepool {
        NSDictionary *info = BPHeapDictionary();
        weakInfo = info;
        v.infodic = info;
    }
    XCTAssertNotNil(weakInfo);
    XCTAssertNotNil(v.infodic[@"amenity"]);
}

@end
