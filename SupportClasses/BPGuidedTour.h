//
//  BPGuidedTour.h
//  BikePlanner
//
//  Guided tour (#63): a series of bubbles (popovers) pointing at the main controls of a document window and at the
//  elements of its route, read with Previous / Next / End. It runs on a sample route bundled with the app
//  (TourSample.bikeplan, opened from a temporary copy). Offered once by itself (first document window) and from
//  Help ▸ Guided Tour.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPGuidedTour : NSObject

/// YES when the tour was never offered (user default BPGuidedTourShown)
+ (BOOL)shouldOfferAutomaticallyWithDefaults:(NSUserDefaults *)defaults;
+ (void)markOfferedInDefaults:(NSUserDefaults *)defaults;
/// Help ▸ Guided Tour (action showGuidedTour:, handled by the application delegate)
+ (void)installMenuItem;
/// the sample route of the app bundle
+ (nullable NSURL *)sampleURL;
/// opens the sample route (a temporary copy, "BikePlanner Tour.bikeplan"; the open one if already open) in its own
/// window; completion: the document, nil on error
+ (void)openSampleWithCompletion:(void (^)(NSDocument * _Nullable document, NSError * _Nullable error))completion;

- (instancetype)initWithWindow:(NSWindow *)window;

/// the elements of the route the steps point at ("waypoint", "routeLine", "waterPOI"): view and rect in it; nil:
/// the center of the map instead
@property (copy, nullable) NSView * _Nullable (^routeAnchorProvider)(NSString *key, NSRect *rect);

@property (readonly, nonatomic) NSUInteger stepCount;
@property (readonly, nonatomic) NSUInteger currentStep;
@property (readonly, nonatomic) BOOL isShowing;
/// the bubble of the current step
@property (readonly, nonatomic, nullable) NSPopover *popover;

/// the control a step points at (found in the window by accessibility identifier, or given by the route anchor
/// provider; the map or the window content otherwise)
- (nullable NSView *)anchorViewForStep:(NSUInteger)step;
/// the anchor key of a step (accessibility identifier, "search", "toolbar", or a route anchor key)
- (NSString *)anchorKeyForStep:(NSUInteger)step;

- (void)start;
- (void)next;     // Done on the last step: ends the tour
- (void)previous;
- (void)end;

@end

NS_ASSUME_NONNULL_END
