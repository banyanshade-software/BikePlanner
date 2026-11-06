//
//  BPRoadTypesLabel.m
//  BikePlanner
//

#import "BPRoadTypesLabel.h"
#import "BikePlan.h"

@implementation BPRoadTypesLabel {
    NSTrackingArea *_tracking;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                                     NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)mouseMoved:(NSEvent *)event
{
    [self hoverAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseEntered:(NSEvent *)event
{
    [self hoverAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)event
{
    [self setHovered:nil];
}

- (void)setHovered:(nullable NSString *)kind
{
    if (kind == _hoveredKind || [kind isEqualToString:_hoveredKind]) return;
    _hoveredKind = [kind copy];
    if (self.hoverHandler) self.hoverHandler(_hoveredKind);
}

- (void)hoverAtPoint:(NSPoint)point
{
    [self setHovered:[self kindAtPoint:point]];
}

// character under the point: the text laid out as the cell draws it (title rect, width of the label); NSNotFound
// outside the text, after the end of a line, or in the gap between two parts
- (NSUInteger)characterIndexAtPoint:(NSPoint)point
{
    NSAttributedString *s = self.attributedStringValue;
    if (!s.length || !NSPointInRect(point, self.bounds)) return NSNotFound;
    NSRect r = [self.cell titleRectForBounds:self.bounds];
    NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:s];
    NSLayoutManager *layout = [[NSLayoutManager alloc] init];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(NSWidth(r), CGFLOAT_MAX)];
    [layout addTextContainer:container];
    [storage addLayoutManager:layout];
    [layout ensureLayoutForTextContainer:container]; // usedRect is empty before
    NSPoint q = NSMakePoint(point.x - NSMinX(r), self.isFlipped ? point.y - NSMinY(r) : NSMaxY(r) - point.y);
    if (q.y < 0 || q.y >= NSHeight([layout usedRectForTextContainer:container])) return NSNotFound;
    CGFloat fraction = 0;
    NSUInteger glyph = [layout glyphIndexForPoint:q inTextContainer:container fractionOfDistanceThroughGlyph:&fraction];
    NSRect glyphRect = [layout boundingRectForGlyphRange:NSMakeRange(glyph, 1) inTextContainer:container];
    if (q.x > NSMaxX(glyphRect)) return NSNotFound; // right of the last glyph of the line
    return [layout characterIndexForGlyphAtIndex:glyph];
}

- (nullable NSString *)kindAtPoint:(NSPoint)point
{
    NSUInteger ch = [self characterIndexAtPoint:point];
    if (ch == NSNotFound || ch >= self.attributedStringValue.length) return nil;
    return [self.attributedStringValue attribute:BPRouteKindAttributeName atIndex:ch effectiveRange:NULL];
}

@end
