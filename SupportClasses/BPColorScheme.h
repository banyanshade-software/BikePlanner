//
//  BPColorScheme.h
//  BikePlanner
//
//  Colors of the route on the map (#71): a fixed list of schemes, chosen in the Preferences (global, not stored in
//  the document), used for every map type. Each scheme gives the colors of the stages (alternating), of the
//  stage ends (waypoint pin, marker in the elevation profile), of the reference trace and of the road type /
//  surface highlight (#54).
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// user default: identifier of the scheme
extern NSString *const BPColorSchemeKey;
/// posted (object: the new scheme) when the scheme is changed in the Preferences
extern NSNotificationName const BPColorSchemeDidChangeNotification;

@interface BPColorScheme : NSObject

@property (readonly, nonatomic) NSString *identifier;
@property (readonly, nonatomic) NSString *localizedName;
/// colors of the successive stages (stage i: stageColors[i % count]); also the route without stages (first one)
@property (readonly, nonatomic) NSArray<NSColor *> *stageColors;
/// opacity and width of the route line (width 8 except in the Compare scheme)
@property (readonly, nonatomic) CGFloat routeAlpha;
@property (readonly, nonatomic) CGFloat routeWidth;
@property (readonly, nonatomic) NSColor *stageEndColor;
@property (readonly, nonatomic) NSColor *referenceTraceColor;
/// opacity and width of the reference trace, always drawn under the route (0.5 and 6 except in the Compare scheme)
@property (readonly, nonatomic) CGFloat traceAlpha;
@property (readonly, nonatomic) CGFloat traceWidth;
@property (readonly, nonatomic) NSColor *highlightColor;

- (NSColor *)colorForStage:(NSUInteger)stage;

/// Classic, Vivid, Dark, Satellite, Compare
+ (NSArray<BPColorScheme *> *)allSchemes;
/// Classic: the colors before #71
+ (BPColorScheme *)defaultScheme;
/// the default scheme for an unknown identifier
+ (BPColorScheme *)schemeWithIdentifier:(nullable NSString *)identifier;
/// the scheme of the user defaults
+ (BPColorScheme *)currentScheme;

/// a small image of the scheme (stage colors, stage end, trace, highlight), for the Preferences pop-up
- (NSImage *)swatchImage;

@end

NS_ASSUME_NONNULL_END
