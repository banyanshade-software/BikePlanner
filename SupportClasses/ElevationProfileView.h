//
//  ElevationProfileView.h
//  BikePlanner
//
//  Created by Daniel on 13/08/2025.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ElevationProfileViewDelegate <NSObject>
- (void)elevationProfileView:(id)view didSelectDistance:(double)distance;
@optional
/// the user zoomed or moved the profile (#62): it shows the route from..to (m); the map shows the same part
- (void)elevationProfileView:(id)view didShowRangeFrom:(double)from to:(double)to;
@end


@interface ElevationProfileView : NSView

@property (nonatomic) double highlightDistance; // meters; outside the visible part: the profile moves to show it
- (void)setHighlightDistance:(double)highlightDistance animated:(BOOL)animated;

@property (nonatomic, strong) NSArray<NSNumber *> *distances;
@property (nonatomic, strong) NSArray<NSNumber *> *elevations;
@property (nonatomic, strong) NSArray<NSNumber *> *slopes;
@property (nonatomic, weak) id<ElevationProfileViewDelegate> delegate;
/// indexes of the points (of setGpxPoints:) where a stage ends (#31): a vertical line with the number of the next stage
@property (nonatomic, copy) NSArray<NSNumber *> *stageEndIndexes;
/// color of the stage-end markers (#71: from the color scheme); purple by default
@property (nonatomic, strong) NSColor *stageEndColor;
/// distances (m) of the stage ends, from stageEndIndexes and the points
@property (nonatomic, readonly) NSArray<NSNumber *> *stageEndDistances;

- (void) setGpxPoints:(NSArray<CLLocation *> *)points; // shows the whole route (#62)

// zoom on the distance axis (#62): pinch, ⌘-scroll, ⌥-drag on a range, buttons (accessibility identifiers
// profileZoomIn / profileZoomOut / profileZoomFit), click on a stage number; double-click: the whole route.
// Scroll horizontally, or use the overview strip under the plot, to move a zoomed profile.
/// visible part of the route (m): 0…length when not zoomed
@property (nonatomic, readonly) double visibleFrom;
@property (nonatomic, readonly) double visibleTo;
@property (nonatomic, readonly, getter=isZoomed) BOOL zoomed;
/// shows from..to, at least 1 km (around its middle), moved inside the route; notify: tell the delegate
- (void) showRangeFrom:(double)from to:(double)to notify:(BOOL)notify;
/// zoom in (factor > 1) or out, the distance staying at the same place in the view; the delegate is told
- (void) zoomBy:(double)factor around:(double)distance;
- (IBAction) zoomProfileIn:(id)sender;
- (IBAction) zoomProfileOut:(id)sender;
- (IBAction) zoomProfileToFit:(id)sender;

/// elevation (m) at a distance along the route, interpolated
- (double) elevationAtDistance:(double)distance;
/// slope (%, positive uphill in the route direction) around a distance, over ±50 m (elevations are noisy); nil
/// without route (#48)
- (nullable NSNumber *) slopeAtDistance:(double)distance;
/// "12.3 km · 145 m · +6.5 %" at the highlighted distance, shown next to the cursor; nil when nothing is selected
@property (nonatomic, readonly, nullable) NSString *highlightText;
@end

NS_ASSUME_NONNULL_END
