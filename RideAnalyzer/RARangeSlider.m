//
//  RARangeSlider.m
//  RideAnalyzer
//

#import "RARangeSlider.h"

static const CGFloat RAKnobRadius = 8;
static const CGFloat RATrackHeight = 4;

@implementation RARangeSlider
{
    BOOL _draggingUpper;    // the knob being dragged, or the one last used (keyboard)
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _minValue = 0;
        _maxValue = 100;
        _upperValue = 100;
        _step = 1;
    }
    return self;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(NSViewNoIntrinsicMetric, 2 * RAKnobRadius + 6);
}

- (BOOL)acceptsFirstResponder
{
    return self.enabled;
}

- (BOOL)isFlipped
{
    return YES;
}

#pragma mark - values

- (double)rounded:(double)v
{
    if (_step > 0) v = _minValue + round((v - _minValue) / _step) * _step;
    return MIN(MAX(v, _minValue), _maxValue);
}

- (void)setMinValue:(double)minValue
{
    _minValue = minValue;
    if (_maxValue < _minValue) _maxValue = _minValue;
    [self setLowerValue:_lowerValue upperValue:_upperValue sendAction:NO];
}

- (void)setMaxValue:(double)maxValue
{
    _maxValue = MAX(maxValue, _minValue);
    [self setLowerValue:_lowerValue upperValue:_upperValue sendAction:NO];
}

- (void)setLowerValue:(double)lowerValue
{
    [self setLowerValue:lowerValue upperValue:_upperValue sendAction:NO];
}

- (void)setUpperValue:(double)upperValue
{
    [self setLowerValue:_lowerValue upperValue:upperValue sendAction:NO];
}

- (void)setLowerValue:(double)lower upperValue:(double)upper sendAction:(BOOL)send
{
    lower = [self rounded:lower];
    upper = [self rounded:upper];
    if (lower > upper) {
        if (_draggingUpper) lower = upper; else upper = lower;
    }
    _lowerValue = lower;
    _upperValue = upper;
    self.needsDisplay = YES;
    if (send) [self sendAction:self.action to:self.target];
}

#pragma mark - geometry

- (NSRect)trackRect
{
    NSRect b = self.bounds;
    return NSMakeRect(NSMinX(b) + RAKnobRadius + 1, NSMidY(b) - RATrackHeight / 2,
                      MAX(1, NSWidth(b) - 2 * RAKnobRadius - 2), RATrackHeight);
}

- (CGFloat)xOfValue:(double)v
{
    NSRect t = [self trackRect];
    double span = _maxValue - _minValue;
    return NSMinX(t) + (span > 0 ? (v - _minValue) / span : 0) * NSWidth(t);
}

- (double)valueOfX:(CGFloat)x
{
    NSRect t = [self trackRect];
    return _minValue + (x - NSMinX(t)) / NSWidth(t) * (_maxValue - _minValue);
}

#pragma mark - drawing

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect t = [self trackRect];
    [[NSColor tertiaryLabelColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:t xRadius:2 yRadius:2] fill];
    CGFloat lx = [self xOfValue:_lowerValue], ux = [self xOfValue:_upperValue];
    [(self.enabled ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor]) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(lx, NSMinY(t), ux - lx, NSHeight(t)) xRadius:2 yRadius:2] fill];
    for (NSNumber *x in @[ @(lx), @(ux) ]) {
        NSRect k = NSMakeRect(x.doubleValue - RAKnobRadius, NSMidY(t) - RAKnobRadius, 2 * RAKnobRadius, 2 * RAKnobRadius);
        NSBezierPath *knob = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(k, 0.5, 0.5)];
        [[NSColor whiteColor] setFill];
        [knob fill];
        [[NSColor separatorColor] setStroke];
        knob.lineWidth = 1;
        [knob stroke];
    }
}

#pragma mark - mouse and keyboard

- (void)mouseDown:(NSEvent *)event
{
    if (!self.enabled) return;
    [self.window makeFirstResponder:self];
    CGFloat x = [self convertPoint:event.locationInWindow fromView:nil].x;
    CGFloat lx = [self xOfValue:_lowerValue], ux = [self xOfValue:_upperValue];
    // the nearer knob; when they overlap, the one that can move toward the click
    if (fabs(lx - ux) < 1) _draggingUpper = x > ux;
    else _draggingUpper = fabs(x - ux) < fabs(x - lx);
    _tracking = YES;
    [self dragToX:x];
    while (YES) {
        NSEvent *e = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
        if (!e || e.type == NSEventTypeLeftMouseUp) break;
        [self dragToX:[self convertPoint:e.locationInWindow fromView:nil].x];
    }
    _tracking = NO;
    [self sendAction:self.action to:self.target];
}

- (void)dragToX:(CGFloat)x
{
    double v = [self valueOfX:x];
    if (_draggingUpper) {
        [self setLowerValue:_lowerValue upperValue:MAX(v, _lowerValue) sendAction:YES];
    } else {
        [self setLowerValue:MIN(v, _upperValue) upperValue:_upperValue sendAction:YES];
    }
}

- (void)keyDown:(NSEvent *)event
{
    NSString *c = event.charactersIgnoringModifiers;
    unichar k = c.length ? [c characterAtIndex:0] : 0;
    double step = _step > 0 ? _step : (_maxValue - _minValue) / 100;
    if (k == NSTabCharacter) {
        [super keyDown:event];
    } else if (k == NSLeftArrowFunctionKey || k == NSRightArrowFunctionKey) {
        double d = k == NSLeftArrowFunctionKey ? -step : step;
        if (_draggingUpper) [self setLowerValue:_lowerValue upperValue:MAX(_upperValue + d, _lowerValue) sendAction:YES];
        else [self setLowerValue:MIN(_lowerValue + d, _upperValue) upperValue:_upperValue sendAction:YES];
    } else if (k == NSUpArrowFunctionKey || k == NSDownArrowFunctionKey) {
        _draggingUpper = k == NSUpArrowFunctionKey;     // up: the upper knob, down: the lower one
        self.needsDisplay = YES;
    } else {
        [super keyDown:event];
    }
}

#pragma mark - accessibility

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilitySliderRole;
}

- (nullable id)accessibilityValue
{
    return [NSString stringWithFormat:@"%g–%g", _lowerValue, _upperValue];
}

@end
