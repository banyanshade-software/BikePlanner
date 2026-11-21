//
//  RARangeSlider.h
//  RideAnalyzer
//
//  A horizontal slider with two knobs, for a range (#82, R3: the distance of the filter, owner's request). Values
//  are rounded to `step`. The action is sent while a knob is dragged (`tracking` YES: the target may only update a
//  label) and once more when the mouse is released (`tracking` NO: apply). The arrow keys move the knob last used.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RARangeSlider : NSControl

@property (nonatomic) double minValue;
@property (nonatomic) double maxValue;
@property (nonatomic) double step;               // 0: no rounding
/// minValue ≤ lowerValue ≤ upperValue ≤ maxValue (clamped when set)
@property (nonatomic) double lowerValue;
@property (nonatomic) double upperValue;
/// a knob is being dragged
@property (readonly, nonatomic, getter=isTracking) BOOL tracking;

/// for tests and the keyboard: moves a knob as a drag would, then sends the action as on release
- (void)setLowerValue:(double)lower upperValue:(double)upper sendAction:(BOOL)send;

@end

NS_ASSUME_NONNULL_END
