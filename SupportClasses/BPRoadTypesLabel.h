//
//  BPRoadTypesLabel.h
//  BikePlanner
//
//  Distance by road type of the Info section (#53). Reports the part of the text under the mouse (#54): the value of
//  its BPRouteKindAttributeName attribute, "road:<class>" or "surface:<class>", to highlight it on the map.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPRoadTypesLabel : NSTextField

/// called when the hovered kind changes (nil: none, e.g. the mouse left the label)
@property (copy, nullable) void (^hoverHandler)(NSString * _Nullable kind);
@property (readonly, nullable) NSString *hoveredKind;

/// kind of the text at this point (label coordinates), nil for the title, between the parts, or outside
- (nullable NSString *)kindAtPoint:(NSPoint)point;
/// the mouse is at this point (label coordinates): updates hoveredKind, calls hoverHandler on a change
- (void)hoverAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END
