//
//  PlannerWindowController.h
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import <Cocoa/Cocoa.h>

@class BRFProfileEditor, BPGuidedTour, BPSightsView;

NS_ASSUME_NONNULL_BEGIN

@interface PlannerWindowController : NSWindowController
@property (strong, nonatomic) BRFProfileEditor *brfEditor;
/// sights near the route, in the Info section (#81)
@property (strong, nonatomic, nullable) BPSightsView *sightsView;
/// the guided tour of this window (#63), created when first shown
@property (strong, nonatomic, nullable) BPGuidedTour *guidedTour;

/// starts the guided tour in this window (#63), pointing at the elements of its route
- (void)startGuidedTour;
/// Help ▸ Guided Tour and the first launch (#63): opens the sample route in its own window and starts the tour there;
/// completion (tests): the window controller, nil on error
+ (void)showGuidedTourOnSampleWithCompletion:(nullable void (^)(PlannerWindowController * _Nullable controller))completion;

// the document's plan was replaced (Revert to Saved): shows its BRouter parameters in the Params tab
- (void)planReplaced;

@end

NS_ASSUME_NONNULL_END
