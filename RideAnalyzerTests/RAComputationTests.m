//
//  RAComputationTests.m
//  RideAnalyzerTests
//
//  The asynchronous computations of the views (#82, owner's request 2026-11-22): in the background, cancelled when
//  the parameters or the selection change, only the latest result shown.
//

#import <XCTest/XCTest.h>
#import "RAComputation.h"
#import "RALibraryDocument.h"
#import "RAEquipment.h"
#import "RARide.h"
#import "RARideAnalysis.h"
#import "RARideDetailController.h"
#import "RATestSupport.h"

@interface RAComputationTests : XCTestCase
@end

@implementation RAComputationTests

- (void)testOnlyTheLatestShows
{
    RAComputation *computation = [[RAComputation alloc] initWithLabel:@"test"];
    NSMutableArray<NSNumber *> *states = [NSMutableArray array];
    computation.runningHandler = ^(BOOL running) { [states addObject:@(running)]; };
    NSMutableArray *shown = [NSMutableArray array];
    __block BOOL firstSawCancel = NO;
    [computation start:^id(RACancellation *c) {
        // a long work that checks its cancellation
        for (int i = 0; i < 500 && !c.cancelled; i++) [NSThread sleepForTimeInterval:0.01];
        firstSawCancel = c.cancelled;
        return @1;
    } completion:^(id result) { [shown addObject:result]; }];
    XCTAssertTrue(computation.running);
    RAWaitUntil(0.1, ^BOOL { return NO; });
    [computation start:^id(RACancellation *c) { return @2; } completion:^(id result) { [shown addObject:result]; }];
    XCTAssertTrue(RAWaitUntil(5, ^BOOL { return !computation.running; }));
    XCTAssertEqualObjects(shown, @[ @2 ], @"the first one cancelled: never shown");
    XCTAssertTrue(firstSawCancel, @"the work was told to stop");
    XCTAssertEqualObjects(states, (@[ @YES, @NO ]), @"one spinner for both");
    XCTAssertEqual(computation.cancelledCount, 1u);
    XCTAssertEqual(computation.finishedCount, 1u);

    // cancelled: no completion
    [computation start:^id(RACancellation *c) { return @3; } completion:^(id result) { [shown addObject:result]; }];
    [computation cancel];
    XCTAssertFalse(computation.running);
    RAWaitUntil(0.3, ^BOOL { return NO; });
    XCTAssertEqualObjects(shown, @[ @2 ]);
}

// quick successive changes (typing, a slider): with a delay, only the last one is computed
- (void)testDelayComputesOnce
{
    RAComputation *computation = [[RAComputation alloc] initWithLabel:@"delay"];
    computation.delay = 0.2;
    __block NSUInteger worked = 0;
    __block id last = nil;
    for (int i = 0; i < 5; i++) {
        [computation start:^id(RACancellation *c) { worked++; return @(i); } completion:^(id result) { last = result; }];
    }
    XCTAssertTrue(RAWaitUntil(5, ^BOOL { return !computation.running; }));
    XCTAssertEqualObjects(last, @4);
    XCTAssertEqual(worked, 1u, @"the others were replaced before starting");
}

// the detail: another ride cancels the analysis in progress; other equipment computes the estimated power again
- (void)testDetailFollowsSelectionAndEquipment
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc importData:RATCX(@[ @100, @150, @130, @180 ], 0, nil, nil) fileName:@"a.tcx" error:NULL];
    [doc importData:RATCX(@[ @100, @110 ], 86400, nil, nil) fileName:@"b.tcx" error:NULL];
    RARide *a = doc.rides[0], *b = doc.rides[1];
    RARideDetailController *detail = [[RARideDetailController alloc] init];
    detail.library = doc;
    [detail showRides:@[ a ]];
    [detail showRides:@[ b ]];
    XCTAssertTrue(RAWaitUntil(10, ^BOOL { return detail.analysis != nil && !detail.computing; }));
    XCTAssertEqual(detail.ride, b);
    XCTAssertEqual(detail.analysis.count, b.distance > a.distance ? 4u : 2u, @"the analysis of the last ride shown");
    XCTAssertTrue(detail.analysis.powerIsEstimated);
    double before = detail.analysis.averagePower;

    [doc changeEquipment:^(RAEquipment *x) { x.riderWeight = 110; } actionName:@"x"];
    [detail refreshRideInfo];
    XCTAssertTrue(detail.computing, @"heavier: the estimated power again");
    XCTAssertTrue(RAWaitUntil(10, ^BOOL { return !detail.computing; }));
    XCTAssertGreaterThan(detail.analysis.averagePower, before);
}

@end
